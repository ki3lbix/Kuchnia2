namespace Catering.Domain;
public static class Bom
{
    public static decimal ComputeRequired(decimal portions, decimal qtyPerPortion, decimal lossPct)
        => Math.Round(portions * (qtyPerPortion * (1 + (lossPct/100m))), 3, MidpointRounding.AwayFromZero);
}
