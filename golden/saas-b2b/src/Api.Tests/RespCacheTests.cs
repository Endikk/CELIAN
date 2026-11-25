using System.Diagnostics;
using Api.Caching;
using Api.Configuration;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using StackExchange.Redis;

namespace Api.Tests;

/// <summary>
/// The concrete cache client (spec 001, T080): one connection, created on
/// first use from the settings of the target, never in the way of the API
/// when the cache is away. No test reaches a real cache: E13 and E02 do, on
/// kind.
/// </summary>
public sealed class RespCacheTests : IDisposable
{
    private const string Password = "cacheSecretFromTheMountedFile0123456789AB";

    private readonly string _secrets = Directory.CreateTempSubdirectory("cache-auth-").FullName;

    public RespCacheTests()
    {
        File.WriteAllText(Path.Combine(_secrets, "password"), Password);
    }

    public void Dispose() => Directory.Delete(_secrets, recursive: true);

    private CacheSettings Settings(string host, int port) => CacheSettings.Load(
        new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            [AppConfigKeys.CacheHost] = host,
            [AppConfigKeys.CachePort] = port.ToString(System.Globalization.CultureInfo.InvariantCulture),
            [AppConfigKeys.CacheTlsMode] = "Disable",
            [AppConfigKeys.CacheTlsCaFile] = "",
        }).Build(),
        _secrets);

    [Fact]
    public async Task A_settings_failure_reaches_the_caller_and_opens_no_connection()
    {
        var connects = 0;
        await using var cache = new RespCache(
            () => throw new CacheSettingsException("app-config has no value for CACHE_HOST."),
            NullLogger<RespCache>.Instance,
            _ =>
            {
                connects++;
                throw new InvalidOperationException("no connection in this test");
            });

        var error = await Assert.ThrowsAsync<CacheSettingsException>(() => cache.PingAsync(CancellationToken.None));

        Assert.Contains("CACHE_HOST", error.Message, StringComparison.Ordinal);
        Assert.Equal(0, connects);
    }

    [Fact]
    public async Task The_connection_gets_the_options_of_the_settings()
    {
        ConfigurationOptions? seen = null;
        await using var cache = new RespCache(
            () => Settings("cache.saas-b2b.svc", 6379),
            NullLogger<RespCache>.Instance,
            options =>
            {
                seen = options;
                throw new InvalidOperationException("no connection in this test");
            });

        await Assert.ThrowsAsync<InvalidOperationException>(() => cache.GetAsync("note:x", CancellationToken.None));

        Assert.NotNull(seen);
        Assert.Equal(Password, seen.Password);
        Assert.False(seen.AbortOnConnectFail);
    }

    [Fact]
    public async Task A_cache_that_does_not_answer_fails_fast()
    {
        // Port 1 of the loopback: nothing listens, the connection is refused.
        await using var cache = new RespCache(() => Settings("127.0.0.1", 1), NullLogger<RespCache>.Instance);
        var clock = Stopwatch.StartNew();

        await Assert.ThrowsAnyAsync<Exception>(() => cache.PingAsync(CancellationToken.None));
        await Assert.ThrowsAnyAsync<Exception>(() => cache.GetAsync("note:x", CancellationToken.None));

        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(15), $"the cache client took {clock.Elapsed}");
    }

    [Fact]
    public async Task No_error_of_the_client_holds_the_password()
    {
        await using var cache = new RespCache(() => Settings("127.0.0.1", 1), NullLogger<RespCache>.Instance);

        var error = await Assert.ThrowsAnyAsync<Exception>(() => cache.PingAsync(CancellationToken.None));

        Assert.DoesNotContain(Password, error.ToString(), StringComparison.Ordinal);
    }
}
