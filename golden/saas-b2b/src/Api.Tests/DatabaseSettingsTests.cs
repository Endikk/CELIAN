using Api.Configuration;
using Microsoft.Extensions.Configuration;
using Npgsql;

namespace Api.Tests;

/// <summary>
/// Database settings: host, port, name and TLS mode from app-config, user and
/// password from the mounted files of db-auth (contracts/secrets.md, layers.md).
/// </summary>
public sealed class DatabaseSettingsTests : IDisposable
{
    private const string Password = "s3cretPasswordFromTheMountedFile0123456789";

    private readonly string _secrets = Directory.CreateTempSubdirectory("db-auth-").FullName;

    private readonly Dictionary<string, string?> _appConfig = new()
    {
        [AppConfigKeys.DatabaseHost] = "postgres.saas-b2b.svc",
        [AppConfigKeys.DatabasePort] = "5432",
        [AppConfigKeys.DatabaseName] = "app",
        [AppConfigKeys.DatabaseSslMode] = "Require",
    };

    public DatabaseSettingsTests()
    {
        File.WriteAllText(Path.Combine(_secrets, "username"), "app");
        File.WriteAllText(Path.Combine(_secrets, "password"), Password);
    }

    public void Dispose() => Directory.Delete(_secrets, recursive: true);

    private DatabaseSettings Load() =>
        DatabaseSettings.Load(new ConfigurationBuilder().AddInMemoryCollection(_appConfig).Build(), _secrets);

    [Fact]
    public void The_app_config_keys_keep_their_names()
    {
        // These names are part of the contract of both target layers (layers.md, "app-config").
        Assert.Equal("DATABASE_HOST", AppConfigKeys.DatabaseHost);
        Assert.Equal("DATABASE_PORT", AppConfigKeys.DatabasePort);
        Assert.Equal("DATABASE_NAME", AppConfigKeys.DatabaseName);
        Assert.Equal("DATABASE_SSL_MODE", AppConfigKeys.DatabaseSslMode);
        Assert.Equal("CACHE_HOST", AppConfigKeys.CacheHost);
        Assert.Equal("CACHE_PORT", AppConfigKeys.CachePort);
        Assert.Equal("CACHE_TLS_MODE", AppConfigKeys.CacheTlsMode);
    }

    [Fact]
    public void Settings_build_the_connection_from_app_config_and_db_auth()
    {
        var builder = Load().ToConnectionStringBuilder();

        Assert.Equal("postgres.saas-b2b.svc", builder.Host);
        Assert.Equal(5432, builder.Port);
        Assert.Equal("app", builder.Database);
        Assert.Equal(SslMode.Require, builder.SslMode);
        Assert.Equal("app", builder.Username);
        Assert.Equal(Password, builder.Password);
    }

    [Fact]
    public void A_trailing_line_break_of_a_secret_file_is_dropped()
    {
        File.WriteAllText(Path.Combine(_secrets, "password"), Password + "\n");
        File.WriteAllText(Path.Combine(_secrets, "username"), "app\r\n");

        var builder = Load().ToConnectionStringBuilder();

        Assert.Equal(Password, builder.Password);
        Assert.Equal("app", builder.Username);
    }

    [Theory]
    [InlineData("disable", SslMode.Disable)]
    [InlineData("VerifyFull", SslMode.VerifyFull)]
    public void The_TLS_mode_is_read_without_regard_to_case(string value, SslMode expected)
    {
        _appConfig[AppConfigKeys.DatabaseSslMode] = value;

        Assert.Equal(expected, Load().ToConnectionStringBuilder().SslMode);
    }

    [Theory]
    [InlineData("DATABASE_HOST")]
    [InlineData("DATABASE_PORT")]
    [InlineData("DATABASE_NAME")]
    [InlineData("DATABASE_SSL_MODE")]
    public void A_missing_key_is_named(string key)
    {
        _appConfig.Remove(key);

        var error = Assert.Throws<DatabaseSettingsException>(Load);

        Assert.Contains(key, error.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("DATABASE_PORT", "0")]
    [InlineData("DATABASE_PORT", "65536")]
    [InlineData("DATABASE_PORT", "54x")]
    [InlineData("DATABASE_SSL_MODE", "Sometimes")]
    [InlineData("DATABASE_SSL_MODE", "1")]
    [InlineData("DATABASE_HOST", "   ")]
    public void An_invalid_value_is_named(string key, string value)
    {
        _appConfig[key] = value;

        var error = Assert.Throws<DatabaseSettingsException>(Load);

        Assert.Contains(key, error.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("password")]
    [InlineData("username")]
    public void A_missing_or_empty_secret_file_is_named_without_its_content(string file)
    {
        File.Delete(Path.Combine(_secrets, file));
        var missing = Assert.Throws<DatabaseSettingsException>(Load);
        File.WriteAllText(Path.Combine(_secrets, file), "\n");
        var empty = Assert.Throws<DatabaseSettingsException>(Load);

        foreach (var error in new[] { missing, empty })
        {
            Assert.Contains(file, error.Message, StringComparison.Ordinal);
            Assert.DoesNotContain(Password, error.Message, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void No_error_message_holds_the_password()
    {
        _appConfig[AppConfigKeys.DatabasePort] = "invalid";

        var error = Assert.Throws<DatabaseSettingsException>(Load);

        Assert.DoesNotContain(Password, error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void The_settings_never_print_the_password()
    {
        Assert.DoesNotContain(Password, Load().ToString() ?? "", StringComparison.Ordinal);
    }
}
