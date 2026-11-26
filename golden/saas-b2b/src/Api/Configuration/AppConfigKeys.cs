namespace Api.Configuration;

/// <summary>
/// Keys of the ConfigMap app-config, same names on both targets, read as
/// environment variables (contracts/layers.md, "app-config"). The API reads
/// the cache keys from step 19 (ADR-015, condition 17).
/// </summary>
public static class AppConfigKeys
{
    public const string DatabaseHost = "DATABASE_HOST";

    public const string DatabasePort = "DATABASE_PORT";

    public const string DatabaseName = "DATABASE_NAME";

    /// <summary>One of Disable, Allow, Prefer, Require, VerifyCA, VerifyFull (Npgsql SSL Mode).</summary>
    public const string DatabaseSslMode = "DATABASE_SSL_MODE";

    public const string CacheHost = "CACHE_HOST";

    public const string CachePort = "CACHE_PORT";

    /// <summary>One of Disable, VerifyCA, VerifyFull (research RS-11): Disable on the local layer.</summary>
    public const string CacheTlsMode = "CACHE_TLS_MODE";

    /// <summary>Path of the PEM bundle of the CA of the cache, mounted by the target layer; read under VerifyCA and VerifyFull only.</summary>
    public const string CacheTlsCaFile = "CACHE_TLS_CA_FILE";
}
