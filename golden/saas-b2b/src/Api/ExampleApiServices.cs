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

    /// <summary>
    /// Registers the services of the API. The data source is built on first
    /// use, so a missing setting fails the readiness check and is logged,
    /// instead of stopping the process.
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

        // No concrete cache client before step 19 and ADR-015 (research RS-11).
        services.AddSingleton<ICache, CacheNotConfigured>();
        services.AddSingleton<NoteReader>();
        services.AddOptions<ReadinessOptions>();
        return services;
    }
}
