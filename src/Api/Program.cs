using Serilog;
using Catering.Domain;

var builder = WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders();
Log.Logger = new LoggerConfiguration()
    .Enrich.FromLogContext()
    .Enrich.WithProperty("service","catering-api")
    .WriteTo.Console(new Serilog.Formatting.Compact.RenderedCompactJsonFormatter())
    .CreateLogger();
builder.Host.UseSerilog();

var app = builder.Build();
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapGet("/bom/test", () => Bom.ComputeRequired(120m, 0.200m, 2.5m));
app.Run();
