using System.Net;
using static Api.Tests.Http;

namespace Api.Tests;

/// <summary>GET /api/healthz: the process is alive (contracts/http-api.md).</summary>
public sealed class HealthTests
{
    [Fact]
    public async Task Healthz_answers_200_with_status_ok()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await client.GetAsync("/api/healthz", Token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", ContentType(response)?.MediaType);
        var body = await ReadJson(response);
        Assert.Equal(["status"], PropertyNames(body));
        Assert.Equal("ok", body.GetProperty("status").GetString());
    }

    [Fact]
    public async Task Healthz_touches_neither_the_database_nor_the_cache()
    {
        await using var api = new ApiFactory();
        api.Store.Failure = new InvalidOperationException("the database must not be called");
        api.Database.Failure = new InvalidOperationException("the database must not be called");
        api.Cache.PingFailure = new InvalidOperationException("the cache must not be called");
        api.Cache.GetFailure = new InvalidOperationException("the cache must not be called");
        using var client = api.CreateClient();

        using var response = await client.GetAsync("/api/healthz", Token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(0, api.Database.Calls);
        Assert.Equal(0, api.Cache.Gets);
    }
}
