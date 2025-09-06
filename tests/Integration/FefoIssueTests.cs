using Xunit;
using Npgsql;
public class FefoIssueTests
{
    private static string Conn => System.Environment.GetEnvironmentVariable("ConnectionStrings__Default")
        ?? "Host=localhost;Username=postgres;Password=postgres;Database=catering";
    [Fact]
    public async Task Issue_DoesNotGoBelowZero()
    {
        await using var con = new NpgsqlConnection(Conn); await con.OpenAsync();
        await using var tx = await con.BeginTransactionAsync(System.Data.IsolationLevel.Serializable);

        var cmd = new NpgsqlCommand(@"
          SELECT batch_id, qty_on_hand FROM batches
          WHERE status='available' AND expiry_date>=current_date
          ORDER BY expiry_date, received_at, batch_id LIMIT 1", con, tx);
        await using var r = await cmd.ExecuteReaderAsync();
        Assert.True(await r.ReadAsync());
        var batchId = r.GetGuid(0); var onHand = r.GetDecimal(1);
        await r.DisposeAsync();

        var upd = new NpgsqlCommand(@"
          UPDATE batches SET qty_on_hand = qty_on_hand - @q
          WHERE batch_id=@b AND qty_on_hand >= @q RETURNING 1", con, tx);
        upd.Parameters.AddWithValue("q", onHand + 0.001m);
        upd.Parameters.AddWithValue("b", batchId);
        var res = await upd.ExecuteScalarAsync();
        Assert.Null(res);
        await tx.RollbackAsync();
    }
}
