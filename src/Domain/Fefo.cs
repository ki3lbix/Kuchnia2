using System;
using System.Collections.Generic;
using System.Linq;
namespace Catering.Domain;

public record Batch(Guid BatchId, DateOnly Expiry, DateTime ReceivedAt, decimal QtyOnHand);

public static class Fefo
{
    public static IEnumerable<Batch> SortFefo(IEnumerable<Batch> batches) =>
        batches.OrderBy(b=>b.Expiry).ThenBy(b=>b.ReceivedAt).ThenBy(b=>b.BatchId);
}
