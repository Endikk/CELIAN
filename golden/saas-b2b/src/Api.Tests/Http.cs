using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Api.Tests;

/// <summary>Helpers to call the API and read its JSON answers.</summary>
public static class Http
{
    public static CancellationToken Token => TestContext.Current.CancellationToken;

    public static Task<HttpResponseMessage> PostJson(HttpClient client, string path, string json) =>
        client.PostAsync(path, new StringContent(json, Encoding.UTF8, "application/json"), Token);

    public static async Task<JsonElement> ReadJson(HttpResponseMessage response)
    {
        var text = await response.Content.ReadAsStringAsync(Token);
        using var document = JsonDocument.Parse(text);
        return document.RootElement.Clone();
    }

    public static string[] PropertyNames(JsonElement element) =>
        element.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal).ToArray();

    /// <summary>Checks a 400 answer in the problem details format and returns its errors.</summary>
    public static async Task<JsonElement> ReadValidationProblem(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var problem = await ReadJson(response);
        Assert.Equal(400, problem.GetProperty("status").GetInt32());
        Assert.False(string.IsNullOrWhiteSpace(problem.GetProperty("title").GetString()));
        return problem.GetProperty("errors");
    }

    /// <summary>Messages that the problem gives for one field.</summary>
    public static string[] ErrorsFor(JsonElement errors, string field) =>
        errors.GetProperty(field).EnumerateArray().Select(e => e.GetString() ?? "").ToArray();

    public static MediaTypeHeaderValue? ContentType(HttpResponseMessage response) =>
        response.Content.Headers.ContentType;
}
