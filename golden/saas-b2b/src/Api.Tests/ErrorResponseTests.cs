using System.Net;
using static Api.Tests.Http;

namespace Api.Tests;

/// <summary>No stack trace and no database message in any error (contracts/http-api.md).</summary>
public sealed class ErrorResponseTests
{
    private const string DatabaseMessage = "42P01: relation \"notes\" does not exist; password=hunter2";

    [Theory]
    [InlineData("GET", "/api/notes")]
    [InlineData("GET", "/api/notes/3f2b8c1e-5d4a-4e6b-9a7c-1d2e3f4a5b6c")]
    [InlineData("POST", "/api/notes")]
    public async Task A_database_failure_answers_500_without_any_detail(string method, string path)
    {
        await using var api = new ApiFactory();
        api.Store.Failure = new InvalidOperationException(DatabaseMessage);
        using var client = api.CreateClient();

        using var response = method == "POST"
            ? await PostJson(client, path, """{"body": "x"}""")
            : await client.GetAsync(path, Token);

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        Assert.Equal("application/problem+json", ContentType(response)?.MediaType);
        var text = await response.Content.ReadAsStringAsync(Token);
        Assert.DoesNotContain("hunter2", text, StringComparison.Ordinal);
        Assert.DoesNotContain("42P01", text, StringComparison.Ordinal);
        Assert.DoesNotContain("InvalidOperationException", text, StringComparison.Ordinal);
        Assert.DoesNotContain(" at ", text, StringComparison.Ordinal);
        var problem = await ReadJson(response);
        Assert.Equal(500, problem.GetProperty("status").GetInt32());
    }

    [Theory]
    [InlineData("/")]
    [InlineData("/api")]
    [InlineData("/api/unknown")]
    [InlineData("/openapi/v1.json")]
    public async Task A_path_outside_the_contract_answers_404(string path)
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await client.GetAsync(path, Token);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task A_method_outside_the_contract_is_refused()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await client.DeleteAsync("/api/notes/3f2b8c1e-5d4a-4e6b-9a7c-1d2e3f4a5b6c", Token);

        Assert.Equal(HttpStatusCode.MethodNotAllowed, response.StatusCode);
    }
}
