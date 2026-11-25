using System.Net;
using Api.Notes;
using static Api.Tests.Http;

namespace Api.Tests;

/// <summary>GET /api/notes?limit=: the most recent notes, from the database only (contracts/http-api.md).</summary>
public sealed class ListNotesTests
{
    [Fact]
    public async Task List_reads_20_notes_by_default()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await client.GetAsync("/api/notes", Token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal([20], api.Store.ListLimits);
    }

    [Theory]
    [InlineData("1", 1)]
    [InlineData("50", 50)]
    [InlineData("07", 7)]
    public async Task List_accepts_a_limit_from_1_to_50(string limit, int expected)
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await client.GetAsync($"/api/notes?limit={limit}", Token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal([expected], api.Store.ListLimits);
    }

    [Theory]
    [InlineData("0")]
    [InlineData("51")]
    [InlineData("-1")]
    [InlineData("+5")]
    [InlineData("1.5")]
    [InlineData("abc")]
    [InlineData("")]
    [InlineData("%205")]
    [InlineData("99999999999999999999")]
    [InlineData("1&limit=2")]
    public async Task List_refuses_any_other_limit_and_names_limit(string limit)
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await client.GetAsync($"/api/notes?limit={limit}", Token);

        var errors = await ReadValidationProblem(response);
        Assert.Equal(["limit"], PropertyNames(errors));
        Assert.Empty(api.Store.ListLimits);
    }

    [Fact]
    public async Task List_returns_the_notes_from_the_newest_without_the_cache()
    {
        await using var api = new ApiFactory();
        var older = new Note(Guid.NewGuid(), "older", new DateTimeOffset(2026, 11, 20, 8, 0, 0, TimeSpan.Zero));
        var newer = new Note(Guid.NewGuid(), "newer", new DateTimeOffset(2026, 11, 21, 8, 0, 0, TimeSpan.Zero));
        api.Store.Add(older);
        api.Store.Add(newer);
        using var client = api.CreateClient();

        using var response = await client.GetAsync("/api/notes?limit=10", Token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await ReadJson(response);
        Assert.Equal(["items"], PropertyNames(body));
        var items = body.GetProperty("items").EnumerateArray().ToArray();
        Assert.Equal(2, items.Length);
        Assert.All(items, item => Assert.Equal(["body", "createdAt", "id"], PropertyNames(item)));
        Assert.Equal(["newer", "older"], items.Select(i => i.GetProperty("body").GetString()));
        Assert.Equal(0, api.Cache.Gets);
        Assert.Empty(api.Cache.Sets);
    }
}
