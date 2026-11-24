namespace Api.Configuration;

/// <summary>
/// Keys of the ConfigMap app-config, same names on both targets, read as
/// environment variables (contracts/layers.md, "app-config"). The cache keys
/// exist before ADR-015; the API reads them from step 19.
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

    /// <summary>Values fixed with the cache engine, by ADR-015.</summary>
    public const string CacheTlsMode = "CACHE_TLS_MODE";
}
