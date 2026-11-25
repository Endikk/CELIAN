using Api.Caching;
using Api.Data;
using Api.Health;
using Api.Notes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;

namespace Api.Tests;

/// <summary>
/// The API in memory, in the Production environment of its image, with
/// doubles in place of the database and the cache. The schema initializer
/// never runs: no test reaches a real database.
/// </summary>
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    public FakeNoteStore Store { get; } = new();

    public FakeCache Cache { get; } = new();

    public FakeDatabaseProbe Database { get; } = new();

    /// <summary>Keeps the cache the API registers itself, instead of the double.</summary>
    public bool KeepDefaultCache { get; init; }

    public TimeSpan? ReadinessTimeout { get; init; }

    public Action<IServiceCollection>? ExtraServices { get; init; }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment(Environments.Production);
        builder.ConfigureTestServices(services =>
        {
            var initializers = services
                .Where(d => d.ServiceType == typeof(IHostedService) && d.ImplementationType == typeof(SchemaInitializer))
                .ToList();
            foreach (var initializer in initializers)
            {
                services.Remove(initializer);
            }

            services.RemoveAll<INoteStore>();
            services.AddSingleton<INoteStore>(Store);
            services.RemoveAll<IDatabaseProbe>();
            services.AddSingleton<IDatabaseProbe>(Database);
            if (!KeepDefaultCache)
            {
                services.RemoveAll<ICache>();
                services.AddSingleton<ICache>(Cache);
            }

            if (ReadinessTimeout is { } timeout)
            {
                services.Configure<ReadinessOptions>(options => options.Timeout = timeout);
            }

            ExtraServices?.Invoke(services);
        });
    }
}
