using System.Net;
using System.Text.Json;
using Api.Notes;
using static Api.Tests.Http;

namespace Api.Tests;

/// <summary>GET /api/notes/{id}: lazy read through the cache, with its source (contracts/http-api.md, data-model).</summary>
public sealed class ReadNoteTests
{
    private static readonly Note Stored = new(
        Guid.Parse("3f2b8c1e-5d4a-4e6b-9a7c-1d2e3f4a5b6c"),
        "Ship the golden repo",
        new DateTimeOffset(2026, 11, 20, 8, 0, 0, TimeSpan.Zero));

    [Theory]
    [InlineData("not-a-uuid")]
    [InlineData("42")]
    [InlineData("3f2b8c1e5d4a4e6b9a7c1d2e3f4a5b6c")]
    [InlineData("{3f2b8c1e-5d4a-4e6b-9a7c-1d2e3f4a5b6c}")]
    [InlineData("3f2b8c1e-5d4a-4e6b-9a7c-1d2e3f4a5b6")]
    public async Task Get_refuses_an_id_that_is_not_a_UUID_and_names_id(string id)
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await client.GetAsync($"/api/notes/{id}", Token);

        var errors = await ReadValidationProblem(response);
        Assert.Equal(["id"], PropertyNames(errors));
        Assert.Equal(0, api.Store.FindCalls);
        Assert.Equal(0, api.Cache.Gets);
    }

    [Fact]
    public async Task Get_answers_404_for_a_missing_note_and_caches_nothing()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await client.GetAsync($"/api/notes/{Guid.NewGuid()}", Token);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("application/problem+json", ContentType(response)?.MediaType);
        Assert.Empty(api.Cache.Sets);
        Assert.Empty(api.Cache.Values);
    }

    [Fact]
    public async Task Get_reads_the_database_first_then_the_cache()
    {
        await using var api = new ApiFactory();
        api.Store.Add(Stored);
        using var client = api.CreateClient();

        using var first = await client.GetAsync($"/api/notes/{Stored.Id}", Token);
        using var second = await client.GetAsync($"/api/notes/{Stored.Id}", Token);

        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        var firstBody = await ReadJson(first);
        var secondBody = await ReadJson(second);
        Assert.Equal(["body", "createdAt", "id", "servedFrom"], PropertyNames(firstBody));
        Assert.Equal("database", firstBody.GetProperty("servedFrom").GetString());
        Assert.Equal("cache", secondBody.GetProperty("servedFrom").GetString());
        foreach (var body in new[] { firstBody, secondBody })
        {
            Assert.Equal(Stored.Id, Guid.ParseExact(body.GetProperty("id").GetString()!, "D"));
            Assert.Equal(Stored.Body, body.GetProperty("body").GetString());
            Assert.Equal(Stored.CreatedAt, body.GetProperty("createdAt").GetDateTimeOffset());
        }

        Assert.Equal(1, api.Store.FindCalls);
    }

    [Fact]
    public async Task Get_puts_the_three_fields_in_the_cache_under_note_id_with_the_fixed_time_to_live()
    {
        await using var api = new ApiFactory();
        api.Store.Add(Stored);
        using var client = api.CreateClient();

        using var response = await client.GetAsync($"/api/notes/{Stored.Id}", Token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var (key, value, timeToLive) = Assert.Single(api.Cache.Sets);
        Assert.Equal($"note:{Stored.Id:D}", key);
        Assert.Equal(NoteCache.TimeToLive, timeToLive);
        Assert.True(timeToLive > TimeSpan.Zero);
        using var cached = JsonDocument.Parse(value);
        Assert.Equal(["body", "createdAt", "id"], PropertyNames(cached.RootElement));
        Assert.Equal(Stored.Body, cached.RootElement.GetProperty("body").GetString());
    }

    [Fact]
    public async Task Get_accepts_a_UUID_in_upper_case()
    {
        await using var api = new ApiFactory();
        api.Store.Add(Stored);
        using var client = api.CreateClient();

        using var response = await client.GetAsync($"/api/notes/{Stored.Id.ToString("D").ToUpperInvariant()}", Token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Get_falls_back_to_the_database_when_the_cache_fails()
    {
        await using var api = new ApiFactory();
        api.Store.Add(Stored);
        api.Cache.GetFailure = new InvalidOperationException("cache down");
        api.Cache.SetFailure = new InvalidOperationException("cache down");
        using var client = api.CreateClient();

        using var response = await client.GetAsync($"/api/notes/{Stored.Id}", Token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await ReadJson(response);
        Assert.Equal("database", body.GetProperty("servedFrom").GetString());
    }

    [Theory]
    [InlineData("not json")]
    [InlineData("""{"id": "00000000-0000-0000-0000-000000000001", "body": "other", "createdAt": "2026-11-20T08:00:00+00:00"}""")]
    [InlineData("""{"id": "3f2b8c1e-5d4a-4e6b-9a7c-1d2e3f4a5b6c"}""")]
    public async Task Get_ignores_a_cache_entry_that_does_not_hold_the_note(string entry)
    {
        await using var api = new ApiFactory();
        api.Store.Add(Stored);
        api.Cache.Values[$"note:{Stored.Id:D}"] = entry;
        using var client = api.CreateClient();

        using var response = await client.GetAsync($"/api/notes/{Stored.Id}", Token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await ReadJson(response);
        Assert.Equal("database", body.GetProperty("servedFrom").GetString());
        Assert.Equal(Stored.Body, body.GetProperty("body").GetString());
    }
}
