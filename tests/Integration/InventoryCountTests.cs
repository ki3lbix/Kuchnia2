using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading.Tasks;
using Npgsql;
using Xunit;

public class InventoryCountTests
{
    private static string Conn =>
        Environment.GetEnvironmentVariable("ConnectionStrings__Default")
        ?? "Host=localhost;Username=postgres;Password=postgres;Database=catering";

    private static readonly Guid CarrotId   = Guid.Parse("55555555-5555-5555-5555-555555555555"); // Marchew
    private static readonly Guid PotatoId   = Guid.Parse("66666666-6666-6666-6666-666666666666"); // Ziemniaki
    private const  decimal CarrotDeltaPlus  = 1.500m; // nadwyżka
    private const  decimal PotatoDeltaMinus = 2.000m; // niedobór

    [Fact]
    public async Task SpotInventory_Post_AdjustsBatchesAndCreatesShrinkageReport()
    {
        await using var con = new NpgsqlConnection(Conn);
        await con.OpenAsync();

        await using var tx = await con.BeginTransactionAsync(System.Data.IsolationLevel.Serializable);

        var countId = Guid.NewGuid();
        var locIdObj = await ExecScalarAsync(con, tx, "SELECT location_id FROM locations LIMIT 1");
        var locId = AsGuid(locIdObj);

        // upewnij się, że mamy partie
        await EnsureBatchExistsAsync(con, tx, CarrotId, 20.000m, 7, "MAR");
        await EnsureBatchExistsAsync(con, tx, PotatoId, 50.000m, 20, "ZIE");

        // start inwentaryzacji
        await ExecNonQueryAsync(con, tx, @"
INSERT INTO inventory_counts (count_id, location_id, scope, status, started_at, created_by)
VALUES (@count_id, @loc_id, 'spot', 'in_progress', now(), 'test');
", new() { { "count_id", countId }, { "loc_id", locId } });

        await ExecNonQueryAsync(con, tx, @"
INSERT INTO inventory_count_lines (count_line_id, count_id, product_id, book_qty)
SELECT gen_random_uuid(), @count_id, p.product_id,
       COALESCE(SUM(b.qty_on_hand),0) AS book_qty
FROM products p
LEFT JOIN batches b
  ON b.product_id = p.product_id
 AND b.status='available'
 AND b.expiry_date >= current_date
WHERE p.product_id = ANY(@prod_ids)
GROUP BY p.product_id;
", new() { { "count_id", countId }, { "prod_ids", new[] { CarrotId, PotatoId } } });

        // wpisanie wyników liczenia
        await ExecNonQueryAsync(con, tx, @"
UPDATE inventory_count_lines
SET counted_qty = book_qty + @plus,
    variance_qty = (book_qty + @plus) - book_qty,
    reason = 'overage',
    notes = 'liczenie – korekta'
WHERE count_id=@count_id AND product_id=@prod_carrot;
", new() { { "count_id", countId }, { "prod_carrot", CarrotId }, { "plus", CarrotDeltaPlus } });

        await ExecNonQueryAsync(con, tx, @"
UPDATE inventory_count_lines
SET counted_qty = GREATEST(book_qty - @minus,0),
    variance_qty = (GREATEST(book_qty - @minus,0) - book_qty),
    reason = 'shrinkage',
    notes = 'ubytki testowe'
WHERE count_id=@count_id AND product_id=@prod_potato;
", new() { { "count_id", countId }, { "prod_potato", PotatoId }, { "minus", PotatoDeltaMinus } });

        // posting różnic (ubytki i nadwyżki)
        await ExecNonQueryAsync(con, tx, @"
-- UBYTKI (variance < 0) – FEFO i transakcje w JEDNEJ instrukcji
WITH neg AS (
  SELECT l.product_id, -l.variance_qty AS qty_to_issue
  FROM inventory_count_lines l
  WHERE l.count_id = @count_id AND l.variance_qty < 0
),
ordered AS (
  SELECT n.product_id, b.batch_id, b.qty_on_hand,
         ROW_NUMBER() OVER (PARTITION BY n.product_id ORDER BY b.expiry_date, b.received_at, b.batch_id) AS rn,
         n.qty_to_issue
  FROM neg n
  JOIN batches b ON b.product_id=n.product_id
  WHERE b.status='available' AND b.expiry_date >= current_date
),
to_issue AS (
  SELECT product_id, batch_id,
         LEAST(qty_on_hand,
               qty_to_issue - COALESCE(SUM(qty_on_hand) OVER (PARTITION BY product_id ORDER BY rn
                 ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0)
              ) AS qty_issue
  FROM ordered
),
updated AS (
  UPDATE batches bb
  SET qty_on_hand = bb.qty_on_hand - ti.qty_issue
  FROM to_issue ti
  WHERE bb.batch_id = ti.batch_id AND ti.qty_issue > 0
  RETURNING ti.batch_id, ti.qty_issue
)
INSERT INTO inventory_transactions(trx_id, batch_id, location_id, trx_type, qty, reason, created_by)
SELECT gen_random_uuid(), u.batch_id, @loc_id, 'ADJUST', -u.qty_issue, 'inventory_shrinkage', 'inventory-post'
FROM updated u;

-- NADWYŻKI (variance > 0)
WITH pos AS (
  SELECT l.product_id, l.variance_qty AS qty_to_add
  FROM inventory_count_lines l
  WHERE l.count_id = @count_id AND l.variance_qty > 0
),
new_batches AS (
  INSERT INTO batches(batch_id, product_id, supplier_id, lot_number, received_at, expiry_date, qty_on_hand, status)
  SELECT gen_random_uuid(), p.product_id, NULL, 'INV-'||to_char(current_date,'YYYYMMDD'),
         now(), current_date, p.qty_to_add, 'available'
  FROM pos p
  RETURNING batch_id, product_id, qty_on_hand
)
INSERT INTO inventory_transactions(trx_id, batch_id, location_id, trx_type, qty, reason, created_by)
SELECT gen_random_uuid(), nb.batch_id, @loc_id, 'ADJUST', nb.qty_on_hand, 'inventory_overage', 'inventory-post'
FROM new_batches nb;

-- Zamknięcie inwentaryzacji
UPDATE inventory_counts
SET status='posted', completed_at=now()
WHERE count_id=@count_id;
", new() { { "count_id", countId }, { "loc_id", locId } });

        // asercje
        var shrinkRows = await ReadRowsAsync(con, tx, @"
SELECT product_id, product_name, variance_qty
FROM vw_inventory_shrinkage
WHERE count_id=@count_id
ORDER BY product_name;", new() { { "count_id", countId } });

        Assert.Contains(shrinkRows, r =>
            AsGuid(r["product_id"]) == PotatoId && AsDecimal(r["variance_qty"]) < 0m);
        Assert.DoesNotContain(shrinkRows, r =>
            AsGuid(r["product_id"]) == CarrotId);

        var countedCarrot = AsDecimal(await ExecScalarAsync(con, tx, @"
SELECT counted_qty FROM inventory_count_lines WHERE count_id=@count_id AND product_id=@pid;", new() { { "count_id", countId }, { "pid", CarrotId } }));

        var countedPotato = AsDecimal(await ExecScalarAsync(con, tx, @"
SELECT counted_qty FROM inventory_count_lines WHERE count_id=@count_id AND product_id=@pid;", new() { { "count_id", countId }, { "pid", PotatoId } }));

        var onHandCarrot = AsDecimal(await ExecScalarAsync(con, tx, @"
SELECT COALESCE(SUM(qty_on_hand),0) FROM batches WHERE product_id=@pid AND status='available';", new() { { "pid", CarrotId } }));

        var onHandPotato = AsDecimal(await ExecScalarAsync(con, tx, @"
SELECT COALESCE(SUM(qty_on_hand),0) FROM batches WHERE product_id=@pid AND status='available';", new() { { "pid", PotatoId } }));

        Assert.Equal(countedCarrot, onHandCarrot);
        Assert.Equal(countedPotato, onHandPotato);

        var adjustCnt = AsLong(await ExecScalarAsync(con, tx, @"
SELECT COUNT(*) FROM inventory_transactions
WHERE trx_type='ADJUST' AND occurred_at >= now() - interval '1 hour';", null));
        Assert.True(adjustCnt >= 1, "Brak transakcji ADJUST po postowaniu inwentaryzacji.");

        await tx.RollbackAsync();
    }

    // helpers
    private static Guid AsGuid(object? o)
    {
        if (o is Guid g) return g;
        if (o is string s && Guid.TryParse(s, out var gs)) return gs;
        throw new InvalidOperationException("Expected Guid, got: " + (o?.GetType().FullName ?? "null"));
    }

    private static decimal AsDecimal(object? o)
    {
        if (o is decimal d) return d;
        if (o is double db) return (decimal)db;
        if (o is float fl) return (decimal)fl;
        if (o is long l) return l;
        if (o is int i) return i;
        if (o is string s && decimal.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var dec)) return dec;
        throw new InvalidOperationException("Expected decimal, got: " + (o?.GetType().FullName ?? "null"));
    }

    private static long AsLong(object? o)
    {
        if (o is long l) return l;
        if (o is int i) return i;
        if (o is decimal d) return (long)d;
        if (o is double db) return (long)db;
        if (o is string s && long.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var val)) return val;
        throw new InvalidOperationException("Expected long, got: " + (o?.GetType().FullName ?? "null"));
    }

    private static async Task EnsureBatchExistsAsync(NpgsqlConnection con, NpgsqlTransaction tx, Guid productId, decimal qty, int expiryDays, string lotPrefix)
    {
        var countObj = await ExecScalarAsync(con, tx, "SELECT COUNT(*) FROM batches WHERE product_id=@pid AND status='available';",
            new() { { "pid", productId } });
        var count = AsLong(countObj);
        if (count == 0)
        {
            await ExecNonQueryAsync(con, tx, @"
INSERT INTO batches (batch_id, product_id, supplier_id, lot_number, received_at, expiry_date, qty_on_hand, status)
VALUES (gen_random_uuid(), @pid, NULL, @lot, now(), current_date + @days, @qty, 'available');",
                new() { { "pid", productId }, { "lot", $"{lotPrefix}-{DateTime.UtcNow:yyyyMMddHHmmss}" }, { "days", expiryDays }, { "qty", qty } });
        }
    }

    private static async Task ExecNonQueryAsync(NpgsqlConnection con, NpgsqlTransaction tx, string sql, Dictionary<string, object?>? p = null)
    {
        await using var cmd = new NpgsqlCommand(sql, con, tx);
        if (p != null) foreach (var kv in p) cmd.Parameters.AddWithValue(kv.Key, kv.Value ?? DBNull.Value);
        _ = await cmd.ExecuteNonQueryAsync();
    }

    private static async Task<object?> ExecScalarAsync(NpgsqlConnection con, NpgsqlTransaction tx, string sql, Dictionary<string, object?>? p = null)
    {
        await using var cmd = new NpgsqlCommand(sql, con, tx);
        if (p != null) foreach (var kv in p) cmd.Parameters.AddWithValue(kv.Key, kv.Value ?? DBNull.Value);
        return await cmd.ExecuteScalarAsync();
    }

    private static async Task<List<Dictionary<string, object?>>> ReadRowsAsync(NpgsqlConnection con, NpgsqlTransaction tx, string sql, Dictionary<string, object?>? p = null)
    {
        await using var cmd = new NpgsqlCommand(sql, con, tx);
        if (p != null) foreach (var kv in p) cmd.Parameters.AddWithValue(kv.Key, kv.Value ?? DBNull.Value);
        var rows = new List<Dictionary<string, object?>>();
        await using var rd = await cmd.ExecuteReaderAsync();
        while (await rd.ReadAsync())
        {
            var row = new Dictionary<string, object?>(rd.FieldCount);
            for (int i = 0; i < rd.FieldCount; i++)
                row[rd.GetName(i)] = rd.IsDBNull(i) ? null : rd.GetValue(i);
            rows.Add(row);
        }
        return rows;
    }
}
