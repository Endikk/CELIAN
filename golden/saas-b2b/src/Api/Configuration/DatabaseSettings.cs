using System.Globalization;
using Npgsql;

namespace Api.Configuration;

/// <summary>A database setting is missing or invalid. The message names it, never its value.</summary>
public sealed class DatabaseSettingsException(string message) : Exception(message);

/// <summary>
/// How the API reaches PostgreSQL: host, port, database and TLS mode from
/// app-config, user and password from the files of the mounted Secret db-auth
/// (contracts/secrets.md). Nothing comes from an argument or a versioned file.
/// </summary>
public sealed class DatabaseSettings
{
    private const int MaxPort = 65535;

    private readonly string _password;

    private DatabaseSettings(string host, int port, string database, SslMode sslMode, string username, string password)
    {
        Host = host;
        Port = port;
        Database = database;
        SslMode = sslMode;
        Username = username;
        _password = password;
    }

    public string Host { get; }

    public int Port { get; }

    public string Database { get; }

    public SslMode SslMode { get; }

    public string Username { get; }

    public static DatabaseSettings Load(IConfiguration appConfig, string dbAuthDirectory)
    {
        var host = Required(appConfig, AppConfigKeys.DatabaseHost);
        var port = ParsePort(Required(appConfig, AppConfigKeys.DatabasePort));
        var database = Required(appConfig, AppConfigKeys.DatabaseName);
        var sslMode = ParseSslMode(Required(appConfig, AppConfigKeys.DatabaseSslMode));
        var username = ReadSecretFile(dbAuthDirectory, "username");
        var password = ReadSecretFile(dbAuthDirectory, "password");
        return new DatabaseSettings(host, port, database, sslMode, username, password);
    }

    public NpgsqlConnectionStringBuilder ToConnectionStringBuilder() => new()
    {
        Host = Host,
        Port = Port,
        Database = Database,
        SslMode = SslMode,
        Username = Username,
        Password = _password,
        ApplicationName = "saas-b2b-api",
    };

    public override string ToString() =>
        $"Host={Host}; Port={Port}; Database={Database}; SslMode={SslMode}; Username={Username}";

    private static string Required(IConfiguration appConfig, string key)
    {
        var value = appConfig[key];
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new DatabaseSettingsException($"app-config has no value for {key}.");
        }

        return value.Trim();
    }

    private static int ParsePort(string value)
    {
        if (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var port) || port < 1 || port > MaxPort)
        {
            throw new DatabaseSettingsException($"{AppConfigKeys.DatabasePort} in app-config must be a port number from 1 to {MaxPort}.");
        }

        return port;
    }

    private static SslMode ParseSslMode(string value)
    {
        var names = Enum.GetNames<SslMode>();
        var name = names.FirstOrDefault(n => string.Equals(n, value, StringComparison.OrdinalIgnoreCase));
        if (name is null)
        {
            throw new DatabaseSettingsException(
                $"{AppConfigKeys.DatabaseSslMode} in app-config must be one of {string.Join(", ", names)}.");
        }

        return Enum.Parse<SslMode>(name);
    }

    private static string ReadSecretFile(string directory, string key)
    {
        var path = Path.Combine(directory, key);
        if (!File.Exists(path))
        {
            throw new DatabaseSettingsException($"The Secret db-auth has no file {path}.");
        }

        var value = File.ReadAllText(path).TrimEnd('\r', '\n');
        if (value.Length == 0)
        {
            throw new DatabaseSettingsException($"The file {path} of the Secret db-auth is empty.");
        }

        return value;
    }
}
