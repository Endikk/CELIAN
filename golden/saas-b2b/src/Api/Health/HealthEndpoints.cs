using Api.Caching;
using Microsoft.Extensions.Options;

namespace Api.Health;

/// <summary>Readiness of the database, as the target sees it.</summary>
public interface IDatabaseProbe
{
    Task<bool> IsReadyAsync(CancellationToken cancellationToken);
}

public sealed class ReadinessOptions
{
    /// <summary>Time given to each check of /api/readyz before it counts as an error.</summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(2);

    public TimeSpan Timeout { get; set; } = DefaultTimeout;
}

public sealed record HealthResponse(string Status);

public sealed record ReadinessResponse(string Status, string Database, string Cache);

/// <summary>GET /api/healthz and GET /api/readyz (contracts/http-api.md).</summary>
public static class HealthEndpoints
{
    private const string Tag = "health";

    private const string Ok = "ok";

    private const string Error = "error";

    public static IEndpointRouteBuilder MapHealthEndpoints(this IEndpointRouteBuilder app)
    {
        // Liveness: the process answers; neither the database nor the cache is touched.
        app.MapGet("/api/healthz", () => TypedResults.Ok(new HealthResponse(Ok)))
            .WithTags(Tag);

        app.MapGet("/api/readyz", ReadyAsync)
            .Produces<ReadinessResponse>(StatusCodes.Status200OK)
            .Produces<ReadinessResponse>(StatusCodes.Status503ServiceUnavailable)
            .WithTags(Tag);
        return app;
    }

    private static async Task<IResult> ReadyAsync(
        IDatabaseProbe database,
        ICache cache,
        IOptions<ReadinessOptions> options,
        CancellationToken cancellationToken)
    {
        var timeout = options.Value.Timeout;
        var checks = await Task.WhenAll(
            CheckAsync(database.IsReadyAsync, timeout, cancellationToken),
            CheckAsync(cache.PingAsync, timeout, cancellationToken));
        var databaseOk = checks[0];
        var cacheOk = checks[1];
        var body = new ReadinessResponse(
            databaseOk && cacheOk ? "ready" : "unavailable",
            databaseOk ? Ok : Error,
            cacheOk ? Ok : Error);
        return databaseOk && cacheOk
            ? TypedResults.Ok(body)
            : TypedResults.Json(body, statusCode: StatusCodes.Status503ServiceUnavailable);
    }

    /// <summary>True when the check answers yes within the timeout; any failure is an error, without detail.</summary>
    private static async Task<bool> CheckAsync(
        Func<CancellationToken, Task<bool>> check,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(timeout);
        try
        {
            return await check(deadline.Token).WaitAsync(deadline.Token);
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            return false;
        }
    }
}
