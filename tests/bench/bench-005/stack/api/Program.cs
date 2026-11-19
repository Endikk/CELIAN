// BENCH-005 test API. /healthz answers with the marker that the benchmark
// rewrites in Marker.cs to time a rebuild. No business code.
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/healthz", () => Results.Text($"ok {Api.Marker.Value}\n"));

app.Run();
