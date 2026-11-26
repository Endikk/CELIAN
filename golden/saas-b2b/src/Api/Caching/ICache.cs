namespace Api.Caching;

/// <summary>
/// Key-value cache of strings, whatever its engine. The concrete client is
/// RespCache (step 19, research RS-11); the key scheme and the stored value
/// belong to the API, not to the client.
/// </summary>
public interface ICache
{
    /// <summary>Value of the key, or null when the cache does not hold it.</summary>
    Task<string?> GetAsync(string key, CancellationToken cancellationToken);

    Task SetAsync(string key, string value, TimeSpan timeToLive, CancellationToken cancellationToken);

    /// <summary>Whether the cache answers, with the credentials of the target.</summary>
    Task<bool> PingAsync(CancellationToken cancellationToken);
}
