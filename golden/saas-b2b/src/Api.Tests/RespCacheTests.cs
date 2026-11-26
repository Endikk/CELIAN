using System.Diagnostics;
using System.Reflection;
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
        CacheSettings? seen = null;
        await using var cache = new RespCache(
            () => Settings("cache.saas-b2b.svc", 6379),
            NullLogger<RespCache>.Instance,
            settings =>
            {
                seen = settings;
                throw new InvalidOperationException("no connection in this test");
            });

        await Assert.ThrowsAsync<InvalidOperationException>(() => cache.GetAsync("note:x", CancellationToken.None));

        Assert.NotNull(seen);
        var options = seen.ToConfigurationOptions();
        Assert.Equal(Password, options.Password);
        Assert.False(options.AbortOnConnectFail);
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

    // --- A password that changes under the API (tasks.md, gap 107) -------------

    private const string NewPassword = "newCachePasswordFromTheRecreatedSecret01234";

    /// <summary>Answers each call of an interface through a function of the called method.</summary>
    public class Stub : DispatchProxy
    {
        public Func<MethodInfo, object?> Answer { get; set; } = _ => null;

        protected override object? Invoke(MethodInfo? targetMethod, object?[]? args) => Answer(targetMethod!);
    }

    private static T Proxy<T>(Func<MethodInfo, object?> answer)
        where T : class
    {
        var proxy = DispatchProxy.Create<T, Stub>();
        ((Stub)(object)proxy).Answer = answer;
        return proxy;
    }

    /// <summary>A task of the return type of the method that fails the way a refused password does.</summary>
    private static object? Failing(MethodInfo method)
    {
        var error = new InvalidOperationException("WRONGPASS invalid username-password pair or user is disabled.");
        var type = method.ReturnType;
        if (type == typeof(Task))
        {
            return Task.FromException(error);
        }

        if (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(Task<>))
        {
            var fromException = typeof(Task).GetMethods()
                .First(m => m.Name == nameof(Task.FromException) && m.IsGenericMethodDefinition);
            return fromException.MakeGenericMethod(type.GetGenericArguments()[0]).Invoke(null, [error]);
        }

        return type.IsValueType && type != typeof(void) ? Activator.CreateInstance(type) : null;
    }

    private static IConnectionMultiplexer Connection(bool connected, Action onDispose)
    {
        var database = Proxy<IDatabase>(Failing);
        return Proxy<IConnectionMultiplexer>(method =>
        {
            switch (method.Name)
            {
                case "get_IsConnected":
                    return connected;
                case "GetDatabase":
                    return database;
                case "DisposeAsync":
                    onDispose();
                    return default(ValueTask);
                default:
                    return method.ReturnType.IsValueType && method.ReturnType != typeof(void)
                        ? Activator.CreateInstance(method.ReturnType)
                        : null;
            }
        });
    }

    [Fact]
    public async Task A_failure_on_a_connection_that_is_down_drops_it_and_the_next_call_reads_the_password_again()
    {
        var passwords = new List<string?>();
        var disposed = 0;
        await using var cache = new RespCache(
            () => Settings("cache.saas-b2b.svc", 6379),
            NullLogger<RespCache>.Instance,
            settings =>
            {
                passwords.Add(settings.ToConfigurationOptions().Password);
                return Task.FromResult(Connection(connected: false, () => disposed++));
            });

        await Assert.ThrowsAnyAsync<Exception>(() => cache.PingAsync(CancellationToken.None));
        File.WriteAllText(Path.Combine(_secrets, "password"), NewPassword);
        await Assert.ThrowsAnyAsync<Exception>(() => cache.PingAsync(CancellationToken.None));

        Assert.Equal([Password, NewPassword], passwords);
        // Each failed call found its connection down and dropped it.
        Assert.Equal(2, disposed);
    }

    [Fact]
    public async Task A_failure_on_a_connection_that_is_up_keeps_it()
    {
        var connects = 0;
        await using var cache = new RespCache(
            () => Settings("cache.saas-b2b.svc", 6379),
            NullLogger<RespCache>.Instance,
            _ =>
            {
                connects++;
                return Task.FromResult(Connection(connected: true, () => { }));
            });

        await Assert.ThrowsAnyAsync<Exception>(() => cache.PingAsync(CancellationToken.None));
        await Assert.ThrowsAnyAsync<Exception>(() => cache.PingAsync(CancellationToken.None));

        Assert.Equal(1, connects);
    }
}
