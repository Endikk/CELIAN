using StackExchange.Redis;

namespace Api.Caching;

/// <summary>
/// The cache client of the API, one path for both targets (ADR-015,
/// condition 17): it speaks RESP to whatever serves CACHE_HOST, with the
/// password of cache-auth, and TLS as CACHE_TLS_MODE says. The settings are
/// read and the connection opened on first use, so that a missing setting
/// fails the readiness check and the reads, never the start of the API.
/// The connection is opened once and reconnects on its own; a command
/// never waits for a cache that is away (research RS-11).
/// </summary>
public sealed class RespCache : ICache, IAsyncDisposable
{
    private readonly Func<CacheSettings> _loadSettings;

    private readonly ILogger<RespCache> _logger;

    private readonly Func<ConfigurationOptions, Task<IConnectionMultiplexer>> _connect;

    private readonly SemaphoreSlim _gate = new(1, 1);

    private IConnectionMultiplexer? _connection;

    public RespCache(
        Func<CacheSettings> loadSettings,
        ILogger<RespCache> logger,
        Func<ConfigurationOptions, Task<IConnectionMultiplexer>>? connect = null)
    {
        _loadSettings = loadSettings;
        _logger = logger;
        _connect = connect ?? ConnectAsync;
    }

    public async Task<string?> GetAsync(string key, CancellationToken cancellationToken)
    {
        var database = await DatabaseAsync(cancellationToken);
        var value = await database.StringGetAsync(key).WaitAsync(cancellationToken);
        return value.IsNull ? null : value.ToString();
    }

    public async Task SetAsync(string key, string value, TimeSpan timeToLive, CancellationToken cancellationToken)
    {
        var database = await DatabaseAsync(cancellationToken);
        // A relative lifetime: Expiration(TimeSpan), the form of the client from
        // its 3.x line (src/StackExchange.Redis/Expiration.cs, 3.4.35).
        await database.StringSetAsync(key, value, new Expiration(timeToLive)).WaitAsync(cancellationToken);
    }

    public async Task<bool> PingAsync(CancellationToken cancellationToken)
    {
        var database = await DatabaseAsync(cancellationToken);
        await database.PingAsync().WaitAsync(cancellationToken);
        return true;
    }

    public async ValueTask DisposeAsync()
    {
        if (_connection is not null)
        {
            await _connection.DisposeAsync();
        }

        _gate.Dispose();
    }

    private static async Task<IConnectionMultiplexer> ConnectAsync(ConfigurationOptions options) =>
        await ConnectionMultiplexer.ConnectAsync(options);

    private async Task<IDatabase> DatabaseAsync(CancellationToken cancellationToken)
    {
        var connection = Volatile.Read(ref _connection);
        if (connection is not null)
        {
            return connection.GetDatabase();
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            connection = _connection;
            if (connection is null)
            {
                var settings = _loadSettings();

                // Not cancelled: a connect left half-way would be lost without
                // being disposed. ConnectTimeout bounds it, and the caller
                // stops waiting at its own deadline.
                connection = await _connect(settings.ToConfigurationOptions());
                Volatile.Write(ref _connection, connection);
                _logger.LogInformation("Cache client created: {Settings}.", settings);
            }
        }
        finally
        {
            _gate.Release();
        }

        return connection.GetDatabase();
    }
}
