using Xunit;
using Catering.Domain;
public class FefoTests
{
    [Fact]
    public void Fefo_Sorting_Deterministic()
    {
        var b1 = new Batch(Guid.NewGuid(), new DateOnly(2025,9,10), new DateTime(2025,9,1,8,0,0), 10);
        var b2 = new Batch(Guid.NewGuid(), new DateOnly(2025,9,12), new DateTime(2025,9,1,7,0,0), 10);
        var b3 = new Batch(Guid.NewGuid(), new DateOnly(2025,9,12), new DateTime(2025,9,1,9,0,0), 10);
        var sorted = Fefo.SortFefo(new[]{b3,b2,b1}).ToArray();
        Assert.Equal(b1, sorted[0]);
        Assert.Equal(b2, sorted[1]);
        Assert.Equal(b3, sorted[2]);
    }
}
