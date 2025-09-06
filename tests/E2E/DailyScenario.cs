using Xunit;
using Catering.Domain;
using Npgsql;
public class DailyScenario
{
    private static string Conn => System.Environment.GetEnvironmentVariable("ConnectionStrings__Default")
        ?? "Host=localhost;Username=postgres;Password=postgres;Database=catering";

    [Fact]
    public async Task EndToEnd_Smoke()
    {
        var need = Bom.ComputeRequired(120m, 0.200m, 2.5m);
        Assert.Equal(24.600m, need);

        await using var con = new NpgsqlConnection(Conn); await con.OpenAsync();
        var exists = await new NpgsqlCommand("select count(*) from products;", con).ExecuteScalarAsync();
        Assert.NotNull(exists);
    }
}
