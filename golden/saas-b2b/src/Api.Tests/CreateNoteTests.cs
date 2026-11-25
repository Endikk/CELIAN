using System.Globalization;
using System.Net;
using System.Text;
using Api.Notes;
using static Api.Tests.Http;

namespace Api.Tests;

/// <summary>POST /api/notes: validation on the server, 201 or 400 (contracts/http-api.md).</summary>
public sealed class CreateNoteTests
{
    /// <summary>
    /// Largest answer to a request full of unknown fields. Naming each of them
    /// drew about 145 KB from a 16 KiB request (review [SECU] of step 3).
    /// </summary>
    private const int MaxProblemBytes = 1024;

    [Fact]
    public async Task Post_writes_the_note_and_answers_201_with_its_location()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await PostJson(client, "/api/notes", """{"body": "  Buy milk  "}""");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await ReadJson(response);
        Assert.Equal(["body", "createdAt", "id"], PropertyNames(body));
        var id = Guid.ParseExact(body.GetProperty("id").GetString()!, "D");
        Assert.Equal("Buy milk", body.GetProperty("body").GetString());
        Assert.Equal(FakeNoteStore.Now, body.GetProperty("createdAt").GetDateTimeOffset());
        Assert.Equal($"/api/notes/{id}", response.Headers.Location?.OriginalString);
        Assert.Equal([(id, "Buy milk")], api.Store.Inserted);
    }

    [Fact]
    public async Task Post_does_not_touch_the_cache()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await PostJson(client, "/api/notes", """{"body": "x"}""");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Empty(api.Cache.Sets);
        Assert.Equal(0, api.Cache.Gets);
    }

    [Fact]
    public async Task Post_draws_a_new_id_for_each_note()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var first = await PostJson(client, "/api/notes", """{"body": "one"}""");
        using var second = await PostJson(client, "/api/notes", """{"body": "two"}""");

        Assert.Equal(2, api.Store.Inserted.Select(n => n.Id).Distinct().Count());
        Assert.DoesNotContain(Guid.Empty, api.Store.Inserted.Select(n => n.Id));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(500)]
    public async Task Post_accepts_a_body_of_1_to_500_characters(int length)
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();
        var text = new string('a', length);

        using var response = await PostJson(client, "/api/notes", $$"""{"body": " {{text}} "}""");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(text, api.Store.Inserted.Single().Body);
    }

    [Fact]
    public async Task Post_counts_characters_and_not_UTF16_code_units()
    {
        // 500 emoji: 500 characters, 1000 UTF-16 code units; char_length in PostgreSQL says 500.
        await using var api = new ApiFactory();
        using var client = api.CreateClient();
        var text = string.Concat(Enumerable.Repeat("\U0001F600", 500));

        using var response = await PostJson(client, "/api/notes", $$"""{"body": "{{text}}"}""");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Fact]
    public async Task Post_refuses_501_characters_and_names_body()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await PostJson(client, "/api/notes", $$"""{"body": "{{new string('a', 501)}}"}""");

        var errors = await ReadValidationProblem(response);
        Assert.Equal(["body"], PropertyNames(errors));
        Assert.Contains("500", Assert.Single(ErrorsFor(errors, "body")));
        Assert.Empty(api.Store.Inserted);
    }

    [Theory]
    [InlineData("""{}""")]
    [InlineData("""{"body": ""}""")]
    [InlineData("""{"body": "   \t\n  "}""")]
    [InlineData("""{"body": null}""")]
    [InlineData("""{"body": 42}""")]
    [InlineData("""{"body": true}""")]
    [InlineData("""{"body": ["a"]}""")]
    [InlineData("""{"body": {"text": "a"}}""")]
    public async Task Post_refuses_a_missing_blank_or_non_text_body_and_names_body(string json)
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await PostJson(client, "/api/notes", json);

        var errors = await ReadValidationProblem(response);
        Assert.Equal(["body"], PropertyNames(errors));
        Assert.NotEmpty(Assert.Single(ErrorsFor(errors, "body")));
        Assert.Empty(api.Store.Inserted);
    }

    [Theory]
    [InlineData("""{"body": "x", "id": "8d4f2c1e-0000-4000-8000-000000000000"}""", "id")]
    [InlineData("""{"body": "x", "createdAt": "2026-11-24T00:00:00Z"}""", "createdAt")]
    [InlineData("""{"body": "x", "servedFrom": "cache"}""", "servedFrom")]
    [InlineData("""{"Body": "x"}""", "Body")]
    public async Task Post_refuses_any_other_field_and_names_it(string json, string field)
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await PostJson(client, "/api/notes", json);

        var errors = await ReadValidationProblem(response);
        Assert.Contains(field, PropertyNames(errors));
        Assert.NotEmpty(ErrorsFor(errors, field));
        Assert.Empty(api.Store.Inserted);
    }

    [Fact]
    public async Task Post_answers_a_small_problem_to_a_body_full_of_unknown_fields()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await PostJson(client, "/api/notes", ManyUnknownFields());

        var errors = await ReadValidationProblem(response);
        AssertSmall(await response.Content.ReadAsByteArrayAsync(Token));
        Assert.Contains("f0", PropertyNames(errors));
        Assert.Empty(api.Store.Inserted);
    }

    [Fact]
    public async Task Post_answers_a_small_problem_to_a_long_unknown_field_name()
    {
        // 4000 emoji: a name of 16000 bytes, cut on a character boundary if at all.
        await using var api = new ApiFactory();
        using var client = api.CreateClient();
        var name = string.Concat(Enumerable.Repeat("\U0001F600", 4000));

        using var response = await PostJson(client, "/api/notes", $$"""{"body": "x", "{{name}}": 0}""");

        var errors = await ReadValidationProblem(response);
        AssertSmall(await response.Content.ReadAsByteArrayAsync(Token));
        Assert.StartsWith("\U0001F600", Assert.Single(PropertyNames(errors)), StringComparison.Ordinal);
        Assert.Empty(api.Store.Inserted);
    }

    [Fact]
    public async Task Post_refuses_a_field_name_that_is_not_valid_Unicode()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await PostJson(client, "/api/notes", """{"body": "x", "a\ud800b": 0}""");

        var errors = await ReadValidationProblem(response);
        Assert.NotEmpty(ErrorsFor(errors, Assert.Single(PropertyNames(errors))));
        Assert.Empty(api.Store.Inserted);
    }

    [Fact]
    public async Task Post_refuses_body_given_twice()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await PostJson(client, "/api/notes", """{"body": "a", "body": "b"}""");

        var errors = await ReadValidationProblem(response);
        Assert.Equal(["body"], PropertyNames(errors));
        Assert.Empty(api.Store.Inserted);
    }

    [Theory]
    [InlineData("""{"body": "x" """)]
    [InlineData("""not json""")]
    [InlineData("""["body"]""")]
    [InlineData("""  "body"  """)]
    [InlineData("")]
    public async Task Post_refuses_a_payload_that_is_not_a_JSON_object_and_names_body(string json)
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await PostJson(client, "/api/notes", json);

        var errors = await ReadValidationProblem(response);
        Assert.Equal(["body"], PropertyNames(errors));
        Assert.Empty(api.Store.Inserted);
    }

    [Theory]
    [InlineData("""{"body": "a\u0000b"}""")]
    [InlineData("""{"body": "a\ud800b"}""")]
    public async Task Post_refuses_text_that_the_database_cannot_store_and_names_body(string json)
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();

        using var response = await PostJson(client, "/api/notes", json);

        var errors = await ReadValidationProblem(response);
        Assert.Equal(["body"], PropertyNames(errors));
        Assert.Empty(api.Store.Inserted);
    }

    [Fact]
    public async Task Post_refuses_a_payload_that_is_not_declared_as_JSON()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();
        using var content = new StringContent("""{"body": "x"}""", Encoding.UTF8, "text/plain");

        using var response = await client.PostAsync("/api/notes", content, Token);

        Assert.Equal(HttpStatusCode.UnsupportedMediaType, response.StatusCode);
        Assert.Equal("application/problem+json", ContentType(response)?.MediaType);
        Assert.Empty(api.Store.Inserted);
    }

    [Fact]
    public async Task Post_refuses_an_oversized_payload()
    {
        await using var api = new ApiFactory();
        using var client = api.CreateClient();
        var padding = new string(' ', 64 * 1024);

        using var response = await PostJson(client, "/api/notes", $$"""{"body": "x{{padding}}"}""");

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
        Assert.Equal("application/problem+json", ContentType(response)?.MediaType);
        Assert.Empty(api.Store.Inserted);
    }

    /// <summary>{"body":"x","f0":0,"f1":0,...}: as many distinct fields as the 16 KiB limit holds.</summary>
    private static string ManyUnknownFields()
    {
        const int roomForOneMoreField = 16;
        var json = new StringBuilder("{\"body\":\"x\"");
        for (var i = 0; json.Length + roomForOneMoreField <= NoteValidation.MaxRequestBytes; i++)
        {
            json.Append(",\"f").Append(i.ToString(CultureInfo.InvariantCulture)).Append("\":0");
        }

        return json.Append('}').ToString();
    }

    private static void AssertSmall(byte[] answer) =>
        Assert.True(
            answer.Length <= MaxProblemBytes,
            $"The answer holds {answer.Length} bytes; at most {MaxProblemBytes} expected.");
}
