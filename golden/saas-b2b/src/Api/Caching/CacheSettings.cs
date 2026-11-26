using System.Globalization;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Api.Configuration;
using StackExchange.Redis;

namespace Api.Caching;

/// <summary>A cache setting is missing or invalid. The message names it, never its value.</summary>
public sealed class CacheSettingsException(string message) : Exception(message);

/// <summary>How the API protects its connection to the cache (CACHE_TLS_MODE of app-config).</summary>
public enum CacheTlsMode
{
    /// <summary>No TLS: the local layer, whose traffic stays inside the node of kind.</summary>
    Disable,

    /// <summary>TLS; the server certificate must chain to the CA bundle of the target, whatever its name.</summary>
    VerifyCA,

    /// <summary>TLS; the server certificate must chain to the CA bundle of the target and name CACHE_HOST.</summary>
    VerifyFull,
}

/// <summary>
/// How the API reaches the cache, the same way on both targets (ADR-015,
/// condition 17): host, port, TLS mode and CA bundle from app-config, the
/// password from the file of the mounted Secret cache-auth
/// (contracts/secrets.md). Nothing comes from an argument or a versioned
/// file, and nothing here names an engine or a target.
/// </summary>
public sealed class CacheSettings
{
    /// <summary>Name of the connection, as the cache shows it in its client list.</summary>
    public const string ClientName = "saas-b2b-api";

    /// <summary>Time given to open a connection; the readiness check gives each check 2 s.</summary>
    public static readonly TimeSpan ConnectTimeout = TimeSpan.FromSeconds(2);

    /// <summary>Time given to each command; past it, a read falls back to the database.</summary>
    public static readonly TimeSpan OperationTimeout = TimeSpan.FromSeconds(1);

    private const int MaxPort = 65535;

    private const string SecretName = "cache-auth";

    private const string PasswordFile = "password";

    private readonly string _password;

    private readonly X509Certificate2Collection? _authorities;

    private CacheSettings(string host, int port, CacheTlsMode tlsMode, string? caFile, X509Certificate2Collection? authorities, string password)
    {
        Host = host;
        Port = port;
        TlsMode = tlsMode;
        CaFile = caFile;
        _authorities = authorities;
        _password = password;
    }

    public string Host { get; }

    public int Port { get; }

    public CacheTlsMode TlsMode { get; }

    /// <summary>Path of the CA bundle, PEM, when the mode verifies the server; null without TLS.</summary>
    public string? CaFile { get; }

    public static CacheSettings Load(IConfiguration appConfig, string cacheAuthDirectory)
    {
        var host = Required(appConfig, AppConfigKeys.CacheHost);
        var port = ParsePort(Required(appConfig, AppConfigKeys.CachePort));
        var tlsMode = ParseTlsMode(Required(appConfig, AppConfigKeys.CacheTlsMode));
        string? caFile = null;
        X509Certificate2Collection? authorities = null;
        if (tlsMode != CacheTlsMode.Disable)
        {
            caFile = Required(appConfig, AppConfigKeys.CacheTlsCaFile);
            authorities = ReadAuthorities(caFile);
        }

        var password = ReadPassword(cacheAuthDirectory);
        return new CacheSettings(host, port, tlsMode, caFile, authorities, password);
    }

    /// <summary>
    /// The options of the client (research RS-11): the default user and the
    /// password of cache-auth; CONFIG out of the command map, since the ACL of
    /// the local layer and the managed cache of GCP both refuse it; no
    /// tie-breaker read and no configuration channel; a client that
    /// reconnects on its own and queues nothing while the cache is away.
    /// </summary>
    public ConfigurationOptions ToConfigurationOptions()
    {
        var options = new ConfigurationOptions
        {
            Password = _password,
            ClientName = ClientName,
            AbortOnConnectFail = false,
            BacklogPolicy = BacklogPolicy.FailFast,
            ConnectTimeout = (int)ConnectTimeout.TotalMilliseconds,
            AsyncTimeout = (int)OperationTimeout.TotalMilliseconds,
            SyncTimeout = (int)OperationTimeout.TotalMilliseconds,
            CommandMap = CommandMap.Create(new HashSet<string> { "CONFIG" }, available: false),
            TieBreaker = "",
            ConfigurationChannel = "",
            Ssl = TlsMode != CacheTlsMode.Disable,
        };
        options.EndPoints.Add(Host, Port);
        if (_authorities is not null)
        {
            options.SslHost = Host;
            options.CertificateValidation += CacheCertificateValidation.Create(_authorities, TlsMode);
        }

        return options;
    }

    /// <summary>
    /// Opens the connection with these settings. The options, which carry the
    /// password, are built and used in this file alone (S11).
    /// </summary>
    public async Task<IConnectionMultiplexer> ConnectAsync() =>
        await ConnectionMultiplexer.ConnectAsync(ToConfigurationOptions());

    public override string ToString() =>
        $"Host={Host}; Port={Port}; TlsMode={TlsMode}; CaFile={CaFile ?? "none"}";

    private static string Required(IConfiguration appConfig, string key)
    {
        var value = appConfig[key];
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new CacheSettingsException($"app-config has no value for {key}.");
        }

        return value.Trim();
    }

    private static int ParsePort(string value)
    {
        if (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var port) || port < 1 || port > MaxPort)
        {
            throw new CacheSettingsException($"{AppConfigKeys.CachePort} in app-config must be a port number from 1 to {MaxPort}.");
        }

        return port;
    }

    private static CacheTlsMode ParseTlsMode(string value)
    {
        var names = Enum.GetNames<CacheTlsMode>();
        var name = names.FirstOrDefault(n => string.Equals(n, value, StringComparison.OrdinalIgnoreCase));
        if (name is null)
        {
            throw new CacheSettingsException(
                $"{AppConfigKeys.CacheTlsMode} in app-config must be one of {string.Join(", ", names)}.");
        }

        return Enum.Parse<CacheTlsMode>(name);
    }

    private static X509Certificate2Collection ReadAuthorities(string caFile)
    {
        if (!File.Exists(caFile))
        {
            throw new CacheSettingsException($"The CA bundle {caFile} named by {AppConfigKeys.CacheTlsCaFile} does not exist.");
        }

        var authorities = new X509Certificate2Collection();
        try
        {
            authorities.ImportFromPemFile(caFile);
        }
        catch (CryptographicException)
        {
            throw new CacheSettingsException($"The CA bundle {caFile} named by {AppConfigKeys.CacheTlsCaFile} is not a PEM bundle of certificates.");
        }

        if (authorities.Count == 0)
        {
            throw new CacheSettingsException($"The CA bundle {caFile} named by {AppConfigKeys.CacheTlsCaFile} holds no certificate.");
        }

        return authorities;
    }

    private static string ReadPassword(string directory)
    {
        var path = Path.Combine(directory, PasswordFile);
        if (!File.Exists(path))
        {
            throw new CacheSettingsException($"The Secret {SecretName} has no file {path}.");
        }

        var value = File.ReadAllText(path).TrimEnd('\r', '\n');
        if (value.Length == 0)
        {
            throw new CacheSettingsException($"The file {path} of the Secret {SecretName} is empty.");
        }

        return value;
    }
}
