namespace Catering.Domain;
public static class Rop
{
    public static (decimal rop, decimal safety) Compute(decimal dbar, decimal sigmaD, decimal lMean, decimal lStd, decimal z=1.65m)
    {
        var sigmaL = lStd == 0
            ? Math.Sqrt((double)lMean) * (double)sigmaD
            : Math.Sqrt((double)(lMean * sigmaD*sigmaD + dbar*dbar * lStd*lStd));
        var safety = (decimal)sigmaL * z;
        var rop = dbar * lMean + safety;
        return (Math.Round(rop,3, MidpointRounding.AwayFromZero), Math.Round(safety,3, MidpointRounding.AwayFromZero));
    }
}
