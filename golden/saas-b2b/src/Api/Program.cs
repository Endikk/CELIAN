// Example API of the SaaS B2B golden repo (spec 001, contracts/http-api.md).
// Errors leave as problem details, without stack trace nor database message:
// the image runs in the Production environment, where ASP.NET Core shows no
// exception detail (research RS-03).
using Api;
using Api.Health;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddProblemDetails();
builder.Services.AddExampleApi();

var app = builder.Build();
app.UseExceptionHandler();
app.UseStatusCodePages();
app.MapHealthEndpoints();
app.Run();

/// <summary>Entry point, public for the tests (WebApplicationFactory).</summary>
public partial class Program;
