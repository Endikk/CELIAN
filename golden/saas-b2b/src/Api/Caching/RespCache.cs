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
/// A command that fails on a connection that is down drops that connection:
/// the next call reads the settings again, the password file included, and
/// connects anew. That is how the API follows a cache-auth that was created
/// again, whose old password the cache now refuses (tasks.md, gap 107); the
/// kubelet refreshes the mounted file within about a minute. A connection
/// that is up after a failure stays: the failure came from the command.
/// </summary>
public sealed class RespCache : ICache, IAsyncDisposable
{
    private readonly Func<CacheSettings> _loadSettings;

    private readonly ILogger<RespCache> _logger;

    private readonly Func<CacheSettings, Task<IConnectionMultiplexer>> _connect;

    private readonly TimeProvider _time;

    private readonly SemaphoreSlim _gate = new(1, 1);

    private long _lastAttempt;

    private bool _hasAttempted;

    /// <summary>
    /// Least time between two attempts to open a connection, once one was made:
    /// while the kubelet refreshes the password file, a call that finds the
    /// connection dropped must not build a new multiplexer each time.
    /// </summary>
    public static readonly TimeSpan ReconnectInterval = TimeSpan.FromSeconds(5);

    private IConnectionMultiplexer? _connection;

    public RespCache(
        Func<CacheSettings> loadSettings,
        ILogger<RespCache> logger,
        Func<CacheSettings, Task<IConnectionMultiplexer>>? connect = null,
        TimeProvider? time = null)
    {
        _loadSettings = loadSettings;
        _logger = logger;
        _connect = connect ?? ConnectAsync;
        _time = time ?? TimeProvider.System;
    }

    public Task<string?> GetAsync(string key, CancellationToken cancellationToken) =>
        RunAsync(
            async database =>
            {
                var value = await database.StringGetAsync(key).WaitAsync(cancellationToken);
                return value.IsNull ? null : value.ToString();
            },
            cancellationToken);

    public Task SetAsync(string key, string value, TimeSpan timeToLive, CancellationToken cancellationToken) =>
        RunAsync(
            async database =>
            {
                // A relative lifetime: Expiration(TimeSpan), the form of the client from
                // its 3.x line (src/StackExchange.Redis/Expiration.cs, 3.4.35).
                await database.StringSetAsync(key, value, new Expiration(timeToLive)).WaitAsync(cancellationToken);
                return true;
            },
            cancellationToken);

    public Task<bool> PingAsync(CancellationToken cancellationToken) =>
        RunAsync(
            async database =>
            {
                await database.PingAsync().WaitAsync(cancellationToken);
                return true;
            },
            cancellationToken);

    public async ValueTask DisposeAsync()
    {
        if (_connection is not null)
        {
            await _connection.DisposeAsync();
        }

        _gate.Dispose();
    }

    private static Task<IConnectionMultiplexer> ConnectAsync(CacheSettings settings) => settings.ConnectAsync();

    /// <summary>Runs the operation on the connection; a failure on a connection that is down drops it.</summary>
    private async Task<T> RunAsync<T>(Func<IDatabase, Task<T>> operation, CancellationToken cancellationToken)
    {
        var connection = await ConnectionAsync(cancellationToken);
        try
        {
            return await operation(connection.GetDatabase());
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            await DropIfDownAsync(connection);
            throw;
        }
    }

    private async Task DropIfDownAsync(IConnectionMultiplexer connection)
    {
        if (connection.IsConnected)
        {
            return;
        }

        var dropped = false;
        await _gate.WaitAsync();
        try
        {
            if (ReferenceEquals(_connection, connection))
            {
                _connection = null;
                dropped = true;
            }
        }
        finally
        {
            _gate.Release();
        }

        if (dropped)
        {
            _logger.LogWarning("Cache connection dropped after a failure; the settings and the password file are read again on the next call.");
            await connection.DisposeAsync();
        }
    }

    private async Task<IConnectionMultiplexer> ConnectionAsync(CancellationToken cancellationToken)
    {
        var connection = Volatile.Read(ref _connection);
        if (connection is not null)
        {
            return connection;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            connection = _connection;
            if (connection is null)
            {
                if (_hasAttempted && _time.GetElapsedTime(_lastAttempt) < ReconnectInterval)
                {
                    throw new InvalidOperationException("The cache connection was dropped a moment ago; the next attempt waits for its interval.");
                }

                var settings = _loadSettings();

                // Not cancelled: a connect left half-way would be lost without
                // being disposed. ConnectTimeout bounds it, and the caller
                // stops waiting at its own deadline.
                _lastAttempt = _time.GetTimestamp();
                _hasAttempted = true;
                connection = await _connect(settings);
                Volatile.Write(ref _connection, connection);
                _logger.LogInformation("Cache client created: {Settings}.", settings);
            }
        }
        finally
        {
            _gate.Release();
        }

        return connection;
    }
}
