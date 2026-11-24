using System.Globalization;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.OpenApi;

namespace Api.Tests;

/// <summary>
/// src/Api/openapi.json, the machine description of the routes that S20
/// reads without a SDK, stays equal to the OpenAPI 3.1 document generated
/// from the API (research RS-03). The API itself serves no OpenAPI route:
/// the document service is added here, for the test only.
/// </summary>
public sealed class OpenApiDocumentTests
{
    /// <summary>When set, the test writes the generated document there instead of comparing (tests/unit/u01-api.sh --update-openapi).</summary>
    private const string OutputVariable = "OPENAPI_DOCUMENT_OUTPUT";

    private const string UpdateHint = "Run tests/unit/u01-api.sh --update-openapi, then commit src/Api/openapi.json.";

    private static async Task<string> GenerateAsync()
    {
        await using var api = new ApiFactory { ExtraServices = services => services.AddOpenApi() };
        var provider = api.Services.GetRequiredKeyedService<IOpenApiDocumentProvider>("v1");
        var document = await provider.GetOpenApiDocumentAsync(TestContext.Current.CancellationToken);
        using var text = new StringWriter(CultureInfo.InvariantCulture);
        await document.SerializeAsync(new OpenApiJsonWriter(text), OpenApiSpecVersion.OpenApi3_1, TestContext.Current.CancellationToken);
        return text.ToString();
    }

    [Fact]
    public async Task The_committed_document_matches_the_routes_of_the_API()
    {
        var generated = await GenerateAsync();
        var output = Environment.GetEnvironmentVariable(OutputVariable);
        if (!string.IsNullOrEmpty(output))
        {
            await File.WriteAllTextAsync(output, generated + "\n", TestContext.Current.CancellationToken);
            return;
        }

        var committedPath = Path.Combine(AppContext.BaseDirectory, "openapi.json");
        Assert.True(File.Exists(committedPath), $"src/Api/openapi.json is missing. {UpdateHint}");
        var committed = await File.ReadAllTextAsync(committedPath, TestContext.Current.CancellationToken);

        Assert.True(
            JsonNode.DeepEquals(JsonNode.Parse(generated), JsonNode.Parse(committed)),
            $"src/Api/openapi.json differs from the document generated from the API. {UpdateHint}");
    }

    [Fact]
    public async Task The_document_is_OpenAPI_3_1()
    {
        var document = JsonNode.Parse(await GenerateAsync())!;

        Assert.StartsWith("3.1.", document["openapi"]!.GetValue<string>(), StringComparison.Ordinal);
    }
}
