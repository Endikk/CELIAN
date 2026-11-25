using System.Net;
using Api.Caching;
using Api.Configuration;
using Microsoft.Extensions.Configuration;
using StackExchange.Redis;

namespace Api.Tests;

/// <summary>
/// Cache settings: host, port, TLS mode and CA bundle from app-config, the
/// password from the mounted file of cache-auth (contracts/secrets.md,
/// layers.md; ADR-015, condition 17), and the client options built from them.
/// </summary>
public sealed class CacheSettingsTests : IDisposable
{
    private const string Password = "cacheSecretFromTheMountedFile0123456789AB";

    private readonly string _secrets = Directory.CreateTempSubdirectory("cache-auth-").FullName;

    private readonly string _ca = Path.Combine(Path.GetTempPath(), $"cache-ca-{Guid.NewGuid():N}.pem");

    private readonly Dictionary<string, string?> _appConfig = new()
    {
        [AppConfigKeys.CacheHost] = "cache.saas-b2b.svc",
        [AppConfigKeys.CachePort] = "6379",
        [AppConfigKeys.CacheTlsMode] = "Disable",
        [AppConfigKeys.CacheTlsCaFile] = "",
    };

    public CacheSettingsTests()
    {
        File.WriteAllText(Path.Combine(_secrets, "password"), Password);
        File.WriteAllText(_ca, TestCertificates.Authority().ExportCertificatePem());
    }

    public void Dispose()
    {
        Directory.Delete(_secrets, recursive: true);
        File.Delete(_ca);
    }

    private CacheSettings Load() =>
        CacheSettings.Load(new ConfigurationBuilder().AddInMemoryCollection(_appConfig).Build(), _secrets);

    private void UseTls(string mode)
    {
        _appConfig[AppConfigKeys.CacheTlsMode] = mode;
        _appConfig[AppConfigKeys.CacheTlsCaFile] = _ca;
    }

    [Fact]
    public void The_cache_keys_of_app_config_keep_their_names()
    {
        Assert.Equal("CACHE_HOST", AppConfigKeys.CacheHost);
        Assert.Equal("CACHE_PORT", AppConfigKeys.CachePort);
        Assert.Equal("CACHE_TLS_MODE", AppConfigKeys.CacheTlsMode);
        Assert.Equal("CACHE_TLS_CA_FILE", AppConfigKeys.CacheTlsCaFile);
    }

    [Fact]
    public void Settings_read_app_config_and_cache_auth()
    {
        var settings = Load();

        Assert.Equal("cache.saas-b2b.svc", settings.Host);
        Assert.Equal(6379, settings.Port);
        Assert.Equal(CacheTlsMode.Disable, settings.TlsMode);
        Assert.Equal(Password, settings.ToConfigurationOptions().Password);
    }

    [Fact]
    public void A_trailing_line_break_of_the_password_file_is_dropped()
    {
        File.WriteAllText(Path.Combine(_secrets, "password"), Password + "\r\n");

        Assert.Equal(Password, Load().ToConfigurationOptions().Password);
    }

    [Theory]
    [InlineData("disable", CacheTlsMode.Disable)]
    [InlineData("verifyca", CacheTlsMode.VerifyCA)]
    [InlineData("VerifyFull", CacheTlsMode.VerifyFull)]
    public void The_TLS_mode_is_read_without_regard_to_case(string value, CacheTlsMode expected)
    {
        UseTls(value);

        Assert.Equal(expected, Load().TlsMode);
    }

    [Theory]
    [InlineData("CACHE_HOST")]
    [InlineData("CACHE_PORT")]
    [InlineData("CACHE_TLS_MODE")]
    public void A_missing_key_is_named(string key)
    {
        _appConfig.Remove(key);

        var error = Assert.Throws<CacheSettingsException>(Load);

        Assert.Contains(key, error.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("CACHE_PORT", "0")]
    [InlineData("CACHE_PORT", "65536")]
    [InlineData("CACHE_PORT", "63 79")]
    [InlineData("CACHE_TLS_MODE", "Require")]
    [InlineData("CACHE_TLS_MODE", "Prefer")]
    [InlineData("CACHE_TLS_MODE", "1")]
    [InlineData("CACHE_HOST", "  ")]
    public void An_invalid_value_is_named(string key, string value)
    {
        _appConfig[key] = value;

        var error = Assert.Throws<CacheSettingsException>(Load);

        Assert.Contains(key, error.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("VerifyCA")]
    [InlineData("VerifyFull")]
    public void A_verifying_mode_needs_a_CA_bundle(string mode)
    {
        _appConfig[AppConfigKeys.CacheTlsMode] = mode;

        var error = Assert.Throws<CacheSettingsException>(Load);

        Assert.Contains(AppConfigKeys.CacheTlsCaFile, error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void A_missing_CA_bundle_is_named()
    {
        UseTls("VerifyFull");
        File.Delete(_ca);

        var error = Assert.Throws<CacheSettingsException>(Load);

        Assert.Contains(_ca, error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void A_CA_bundle_without_certificate_is_refused()
    {
        UseTls("VerifyCA");
        File.WriteAllText(_ca, "not a certificate\n");

        var error = Assert.Throws<CacheSettingsException>(Load);

        Assert.Contains(_ca, error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Without_TLS_the_CA_bundle_is_not_read()
    {
        _appConfig[AppConfigKeys.CacheTlsCaFile] = "/nowhere/ca.pem";

        Assert.Equal(CacheTlsMode.Disable, Load().TlsMode);
    }

    [Fact]
    public void A_missing_or_empty_password_file_is_named_without_its_content()
    {
        File.Delete(Path.Combine(_secrets, "password"));
        var missing = Assert.Throws<CacheSettingsException>(Load);
        File.WriteAllText(Path.Combine(_secrets, "password"), "\n");
        var empty = Assert.Throws<CacheSettingsException>(Load);

        foreach (var error in new[] { missing, empty })
        {
            Assert.Contains("password", error.Message, StringComparison.Ordinal);
            Assert.Contains("cache-auth", error.Message, StringComparison.Ordinal);
            Assert.DoesNotContain(Password, error.ToString(), StringComparison.Ordinal);
        }
    }

    [Fact]
    public void The_settings_never_print_the_password()
    {
        UseTls("VerifyFull");

        var settings = Load();

        Assert.DoesNotContain(Password, settings.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(Password, settings.ToConfigurationOptions().ToString(includePassword: false), StringComparison.Ordinal);
    }

    [Fact]
    public void The_options_reach_the_endpoint_of_app_config_as_the_default_user()
    {
        var options = Load().ToConfigurationOptions();

        var endpoint = Assert.IsType<DnsEndPoint>(Assert.Single(options.EndPoints));
        Assert.Equal("cache.saas-b2b.svc", endpoint.Host);
        Assert.Equal(6379, endpoint.Port);
        Assert.Null(options.User);
        Assert.Equal(CacheSettings.ClientName, options.ClientName);
    }

    [Fact]
    public void The_options_never_block_the_API_on_the_cache()
    {
        var options = Load().ToConfigurationOptions();

        // The client reconnects on its own, and queues nothing while the cache
        // is away: a read falls back to the database, readyz answers at once
        // (research RS-11).
        Assert.False(options.AbortOnConnectFail);
        Assert.Same(BacklogPolicy.FailFast, options.BacklogPolicy);
        Assert.Equal((int)CacheSettings.ConnectTimeout.TotalMilliseconds, options.ConnectTimeout);
        Assert.Equal((int)CacheSettings.OperationTimeout.TotalMilliseconds, options.AsyncTimeout);
        Assert.Equal((int)CacheSettings.OperationTimeout.TotalMilliseconds, options.SyncTimeout);
    }

    [Fact]
    public void The_options_send_only_what_the_ACL_and_the_managed_cache_allow()
    {
        var options = Load().ToConfigurationOptions();

        // CONFIG is in @admin, and the managed cache of the gcp layer blocks it:
        // out of the command map, or the handshake fails. No tie-breaker GET and
        // no SUBSCRIBE to the configuration channel (research RS-11; ADR-015,
        // condition 4).
        Assert.Contains("$CONFIG=", options.ToString(includePassword: false), StringComparison.Ordinal);
        Assert.Equal("", options.TieBreaker);
        Assert.Equal("", options.ConfigurationChannel);
    }

    [Fact]
    public void Without_TLS_the_options_open_a_plain_connection()
    {
        Assert.False(Load().ToConfigurationOptions().Ssl);
    }

    [Theory]
    [InlineData("VerifyCA")]
    [InlineData("VerifyFull")]
    public void A_verifying_mode_opens_a_TLS_connection_to_the_host_of_app_config(string mode)
    {
        UseTls(mode);

        var options = Load().ToConfigurationOptions();

        Assert.True(options.Ssl);
        Assert.Equal("cache.saas-b2b.svc", options.SslHost);
    }
}
