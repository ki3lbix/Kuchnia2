using Xunit;
using Catering.Domain;
public class BomTests
{
    [Theory]
    [InlineData(120, 0.200, 2.5, 24.600)]
    public void Bom_Computation(decimal portions, decimal perPortion, decimal lossPct, decimal expected)
    {
        var need = Bom.ComputeRequired(portions, perPortion, lossPct);
        Assert.Equal(expected, need);
    }
}
