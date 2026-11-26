using Api.Caching;
using Api.Configuration;
using Api.Data;
using Api.Health;
using Api.Notes;
using Npgsql;

namespace Api;

public static class ExampleApiServices
{
    /// <summary>Directory where the pod mounts the Secret db-auth (contracts/secrets.md).</summary>
    public const string DbAuthDirectory = "/run/secrets/db-auth";

    /// <summary>Directory where the pod mounts the Secret cache-auth (contracts/secrets.md).</summary>
    public const string CacheAuthDirectory = "/run/secrets/cache-auth";

    /// <summary>
    /// Registers the services of the API. The data source is built on first
    /// use, and so are the cache settings, so a missing setting fails the
    /// readiness check and is logged, instead of stopping the process.
    /// </summary>
    public static IServiceCollection AddExampleApi(this IServiceCollection services)
    {
        services.AddSingleton(provider =>
        {
            var configuration = provider.GetRequiredService<IConfiguration>();
            var settings = DatabaseSettings.Load(configuration, DbAuthDirectory);
            return NpgsqlDataSource.Create(settings.ToConnectionStringBuilder());
        });
        services.AddSingleton<SchemaState>();
        services.AddHostedService<SchemaInitializer>();
        services.AddSingleton<INoteStore, PostgresNoteStore>();
        services.AddSingleton<IDatabaseProbe, PostgresDatabaseProbe>();

        // One cache client for both targets (ADR-015, condition 17; research RS-11).
        services.AddSingleton<ICache>(provider =>
        {
            var configuration = provider.GetRequiredService<IConfiguration>();
            return new RespCache(
                () => CacheSettings.Load(configuration, CacheAuthDirectory),
                provider.GetRequiredService<ILogger<RespCache>>());
        });
        services.AddSingleton<NoteReader>();
        services.AddOptions<ReadinessOptions>();
        return services;
    }
}
