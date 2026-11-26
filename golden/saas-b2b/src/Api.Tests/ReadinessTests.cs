using System.Diagnostics;
using System.Net;
using System.Text.Json;
using Api.Caching;
using Microsoft.Extensions.DependencyInjection;
using static Api.Tests.Http;

namespace Api.Tests;

/// <summary>GET /api/readyz: database and cache reachable (contracts/http-api.md).</summary>
public sealed class ReadinessTests
{
    private static async Task<JsonElement> ReadReadiness(HttpResponseMessage response)
    {
        var body = await ReadJson(response);
        Assert.Equal(["cache", "database", "status"], PropertyNames(body));
        return body;
    }

    [Fact]
    public async Task Readyz_answers_200_when_database_and_cache_answer()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await client.GetAsync("/api/readyz", Token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await ReadReadiness(response);
        Assert.Equal("ready", body.GetProperty("status").GetString());
        Assert.Equal("ok", body.GetProperty("database").GetString());
        Assert.Equal("ok", body.GetProperty("cache").GetString());
    }

    [Fact]
    public async Task Readyz_answers_503_and_names_the_database_when_it_is_not_ready()
    {
        await using var api = new ApiFactory();
        api.Database.Result = false;
        using var client = api.CreateClient();

        using var response = await client.GetAsync("/api/readyz", Token);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var body = await ReadReadiness(response);
        Assert.Equal("unavailable", body.GetProperty("status").GetString());
        Assert.Equal("error", body.GetProperty("database").GetString());
        Assert.Equal("ok", body.GetProperty("cache").GetString());
    }

    [Fact]
    public async Task Readyz_answers_503_and_names_the_cache_when_it_does_not_answer()
    {
        await using var api = new ApiFactory();
        api.Cache.PingResult = false;
        using var client = api.CreateClient();

        using var response = await client.GetAsync("/api/readyz", Token);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var body = await ReadReadiness(response);
        Assert.Equal("unavailable", body.GetProperty("status").GetString());
        Assert.Equal("ok", body.GetProperty("database").GetString());
        Assert.Equal("error", body.GetProperty("cache").GetString());
    }

    [Fact]
    public async Task Readyz_gives_no_detail_of_a_failure()
    {
        await using var api = new ApiFactory();
        api.Database.Failure = new InvalidOperationException("password authentication failed for user app");
        api.Cache.PingFailure = new InvalidOperationException("NOAUTH secret-cache-detail");
        using var client = api.CreateClient();

        using var response = await client.GetAsync("/api/readyz", Token);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var text = await response.Content.ReadAsStringAsync(Token);
        Assert.DoesNotContain("password", text, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("secret-cache-detail", text, StringComparison.Ordinal);
        var body = await ReadReadiness(response);
        Assert.Equal("error", body.GetProperty("database").GetString());
        Assert.Equal("error", body.GetProperty("cache").GetString());
    }

    [Fact]
    public async Task Readyz_answers_within_its_timeout_when_a_check_hangs()
    {
        await using var api = new ApiFactory { ReadinessTimeout = TimeSpan.FromMilliseconds(200) };
        api.Database.Hangs = true;
        api.Cache.PingHangs = true;
        using var client = api.CreateClient();
        var clock = Stopwatch.StartNew();

        using var response = await client.GetAsync("/api/readyz", Token);

        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(10), $"readyz took {clock.Elapsed}");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var body = await ReadReadiness(response);
        Assert.Equal("error", body.GetProperty("database").GetString());
        Assert.Equal("error", body.GetProperty("cache").GetString());
    }

    [Fact]
    public async Task Readyz_reports_the_cache_in_error_while_its_settings_are_missing()
    {
        // The concrete client of step 19, with neither CACHE_HOST nor the files
        // of cache-auth: the cache is in error, and the API keeps answering.
        await using var api = new ApiFactory { KeepDefaultCache = true };
        using var client = api.CreateClient();

        using var response = await client.GetAsync("/api/readyz", Token);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var body = await ReadReadiness(response);
        Assert.Equal("ok", body.GetProperty("database").GetString());
        Assert.Equal("error", body.GetProperty("cache").GetString());
    }

    [Fact]
    public void The_API_registers_the_concrete_cache_client()
    {
        using var api = new ApiFactory { KeepDefaultCache = true };

        Assert.IsType<RespCache>(api.Services.GetRequiredService<ICache>());
    }
}
