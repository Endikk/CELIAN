namespace Api.Caching;

/// <summary>
/// Key-value cache of strings, whatever its engine. The concrete client comes
/// with step 19, after ADR-015 picks the engine (research RS-11); the key
/// scheme and the stored value belong to the API, not to the client.
/// </summary>
public interface ICache
{
    /// <summary>Value of the key, or null when the cache does not hold it.</summary>
    Task<string?> GetAsync(string key, CancellationToken cancellationToken);

    Task SetAsync(string key, string value, TimeSpan timeToLive, CancellationToken cancellationToken);

    /// <summary>Whether the cache answers, with the credentials of the target.</summary>
    Task<bool> PingAsync(CancellationToken cancellationToken);
}

/// <summary>
/// Stand-in until step 19: holds nothing, so every read goes to the database,
/// and never answers, so the readiness check reports the cache in error.
/// </summary>
public sealed class CacheNotConfigured : ICache
{
    public Task<string?> GetAsync(string key, CancellationToken cancellationToken) => Task.FromResult<string?>(null);

    public Task SetAsync(string key, string value, TimeSpan timeToLive, CancellationToken cancellationToken) =>
        Task.CompletedTask;

    public Task<bool> PingAsync(CancellationToken cancellationToken) => Task.FromResult(false);
}
