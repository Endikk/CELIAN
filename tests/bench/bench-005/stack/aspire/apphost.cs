// BENCH-005, Aspire option: the AppHost of the test stack, in C#.
// `aspire start` runs the API as a .NET process on the host and the other
// resources as containers. Images are pinned by digest (read on 2026-11-19).
// Passwords come from the environment (Parameters__pgpassword and
// Parameters__valkeypassword), set by `task up` with random values.
#:package Aspire.Hosting.AppHost@17.0.0
#:package Aspire.Hosting.Dotnet@17.0.0
#:package Aspire.Hosting.PostgreSQL@17.0.0
#:package Aspire.Hosting.Valkey@17.0.0

var builder = DistributedApplication.CreateBuilder(args);

var pgPassword = builder.AddParameter("pgpassword", secret: true);
var valkeyPassword = builder.AddParameter("valkeypassword", secret: true);

var postgres = builder.AddPostgres("postgres", password: pgPassword)
    .WithImageTag("18.7-alpine")
    .WithImageSHA256("ff64c9e3bdf8e2120107d3559de8db314e8305f7e38c5105903c6295876738ff")
    .WithContainerName("celian-bench-005-postgres");

var valkey = builder.AddValkey("valkey", password: valkeyPassword)
    .WithImageTag("9.1.4-alpine")
    .WithImageSHA256("56729e68bdda139cbd3f6a2538683dc3523325fc5711ea1a379938f1b37893f0")
    .WithContainerName("celian-bench-005-valkey");

var api = builder.AddDotnetProject("api", "../api/Api.csproj")
    .WithHttpEndpoint(name: "http")
    .WithHttpHealthCheck("/healthz");

// The front is the nginx image with the static files mounted: a change is
// served at once, without a rebuild.
var front = builder.AddContainer("front", "library/nginx", "1.30.7-alpine")
    .WithImageSHA256("bef154735288bc38d99fac41ae63730684bcc661503673a04a0f9bc526ba8598")
    .WithBindMount("../front/html", "/usr/share/nginx/html", isReadOnly: true)
    .WithBindMount("../front/nginx.conf", "/etc/nginx/conf.d/default.conf", isReadOnly: true)
    .WithHttpEndpoint(targetPort: 8080, name: "http")
    .WithContainerName("celian-bench-005-front");

// Test harness only: the probe of the other options, in a container.
var pgEndpoint = postgres.GetEndpoint("tcp");
var valkeyEndpoint = valkey.GetEndpoint("tcp");
builder.AddContainer("probe", "library/busybox", "1.37.0")
    .WithImageSHA256("a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec")
    .WithBindMount("../probe.sh", "/probe/probe.sh", isReadOnly: true)
    .WithEntrypoint("sh")
    .WithArgs("/probe/probe.sh")
    .WithEnvironment("API_URL", ReferenceExpression.Create($"{api.GetEndpoint("http")}/healthz"))
    .WithEnvironment("FRONT_URL", ReferenceExpression.Create($"{front.GetEndpoint("http")}/"))
    .WithEnvironment("PG_HOST", pgEndpoint.Property(EndpointProperty.Host))
    .WithEnvironment("PG_PORT", pgEndpoint.Property(EndpointProperty.Port))
    .WithEnvironment("CACHE_HOST", valkeyEndpoint.Property(EndpointProperty.Host))
    .WithEnvironment("CACHE_PORT", valkeyEndpoint.Property(EndpointProperty.Port))
    .WithContainerName("celian-bench-005-probe");

builder.Build().Run();
