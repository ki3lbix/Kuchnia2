using Xunit;
using Catering.Domain;
public class RopTests
{
    [Fact]
    public void Rop_ConstantLeadTime()
    {
        var (rop, safety) = Rop.Compute(10m, 2m, 5m, 0m, 1.65m);
        Assert.Equal(57.379m, rop);
        Assert.Equal(7.379m, safety);
    }
}
