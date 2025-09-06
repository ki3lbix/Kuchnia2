using System.Text.Json;
using Serilog;
using Catering.Domain;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

// --- Serilog (JSON) ---
builder.Logging.ClearProviders();
Log.Logger = new LoggerConfiguration()
    .Enrich.FromLogContext()
    .Enrich.WithProperty("service", "catering-api")
    .WriteTo.Console(new Serilog.Formatting.Compact.RenderedCompactJsonFormatter())
    .CreateLogger();
builder.Host.UseSerilog();

var app = builder.Build();

// --- CorrelationId middleware (X-Correlation-Id -> HttpContext.Items/LogContext) ---
app.Use(async (ctx, next) =>
{
    var cid = ctx.Request.Headers.TryGetValue("X-Correlation-Id", out var val) && !string.IsNullOrWhiteSpace(val)
        ? val.ToString()
        : Guid.NewGuid().ToString();
    ctx.Response.Headers["X-Correlation-Id"] = cid;
    using (Serilog.Context.LogContext.PushProperty("correlationId", cid))
    {
        await next();
    }
});

// --- Health ---
app.MapGet("/health", () => Results.Ok(new { status = "ok" }))
   .WithName("Health");

// --- BOM test (kontrolny wynik 24.600) ---
app.MapGet("/bom/test", () =>
{
    var result = Bom.ComputeRequired(120m, 0.200m, 2.5m);
    return Results.Ok(result);
}).WithName("BomTest");

// --- Raport: niedobory po inwentaryzacji (vw_inventory_shrinkage) ---
app.MapGet("/reports/inventory-shrinkage", async (HttpRequest req) =>
{
    // Query params (opcjonalne): ?from=YYYY-MM-DD&to=YYYY-MM-DD&location_id=<uuid>
    string from = req.Query["from"];
    string to = req.Query["to"];
    string loc = req.Query["location_id"];

    const string sql = """
        SELECT count_id, location_id, location_name, started_at, completed_at, status,
               product_id, product_name, unit, book_qty, counted_qty, variance_qty, reason, notes
        FROM vw_inventory_shrinkage
        WHERE 1=1
          AND (@from::date IS NULL OR completed_at::date >= @from::date)
          AND (@to::date   IS NULL OR completed_at::date <= @to::date)
          AND (@loc::uuid  IS NULL OR location_id = @loc::uuid)
        ORDER BY completed_at DESC, location_name, product_name
    """;

    string cs = Environment.GetEnvironmentVariable("ConnectionStrings__Default")
               ?? "Host=localhost;Username=postgres;Password=postgres;Database=catering";

    await using var con = new NpgsqlConnection(cs);
    await con.OpenAsync();

    await using var cmd = new NpgsqlCommand(sql, con);
    // Uwaga: przekazujemy DBNull, jeśli brak parametru – SQL używa warunku OR IS NULL
    if (string.IsNullOrWhiteSpace(from))
        cmd.Parameters.AddWithValue("from", DBNull.Value);
    else
        cmd.Parameters.AddWithValue("from", DateTime.Parse(from));

    if (string.IsNullOrWhiteSpace(to))
        cmd.Parameters.AddWithValue("to", DBNull.Value);
    else
        cmd.Parameters.AddWithValue("to", DateTime.Parse(to));

    if (string.IsNullOrWhiteSpace(loc))
        cmd.Parameters.AddWithValue("loc", DBNull.Value);
    else
        cmd.Parameters.AddWithValue("loc", Guid.Parse(loc));

    var rows = new List<Dictionary<string, object?>>();
    await using var rd = await cmd.ExecuteReaderAsync();
    while (await rd.ReadAsync())
    {
        var row = new Dictionary<string, object?>(capacity: rd.FieldCount);
        for (int i = 0; i < rd.FieldCount; i++)
            row[rd.GetName(i)] = rd.IsDBNull(i) ? null : rd.GetValue(i);
        rows.Add(row);
    }

    return Results.Json(rows, new JsonSerializerOptions { WriteIndented = false });
}).WithName("InventoryShrinkageReport");

app.Run();
