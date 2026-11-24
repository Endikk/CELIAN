using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;

namespace Api.Notes;

/// <summary>Shape of the request of POST /api/notes, for the OpenAPI document; the API reads the body itself.</summary>
public sealed record CreateNoteRequest(string Body);

public sealed record NoteResponse(Guid Id, string Body, DateTimeOffset CreatedAt)
{
    public static NoteResponse From(Note note) => new(note.Id, note.Body, note.CreatedAt);
}

public sealed record NoteReadResponse(Guid Id, string Body, DateTimeOffset CreatedAt, string ServedFrom);

public sealed record NoteListResponse(IReadOnlyList<NoteResponse> Items);

/// <summary>
/// POST /api/notes, GET /api/notes/{id} and GET /api/notes (contracts/http-api.md).
/// Answers carry the fields of the contract only, in camelCase.
/// </summary>
public static class NotesEndpoints
{
    private const string Tag = "notes";

    public static IEndpointRouteBuilder MapNotesEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/notes", CreateAsync)
            .Accepts<CreateNoteRequest>("application/json")
            .ProducesProblem(StatusCodes.Status413PayloadTooLarge)
            .ProducesProblem(StatusCodes.Status415UnsupportedMediaType)
            .WithTags(Tag);
        app.MapGet("/api/notes/{id}", ReadAsync)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .WithTags(Tag);
        app.MapGet("/api/notes", ListAsync)
            .WithTags(Tag);
        return app;
    }

    private static async Task<Results<Created<NoteResponse>, ValidationProblem, ProblemHttpResult>> CreateAsync(
        HttpRequest request,
        INoteStore store,
        CancellationToken cancellationToken)
    {
        if (!request.HasJsonContentType())
        {
            return TypedResults.Problem(
                detail: "Send the note as application/json.",
                statusCode: StatusCodes.Status415UnsupportedMediaType);
        }

        var json = await ReadBoundedAsync(request, cancellationToken);
        if (json is null)
        {
            return TypedResults.Problem(
                detail: $"The request body is limited to {NoteValidation.MaxRequestBytes} bytes.",
                statusCode: StatusCodes.Status413PayloadTooLarge);
        }

        var input = NoteValidation.ParseCreateRequest(json.Value);
        if (!input.IsValid)
        {
            return TypedResults.ValidationProblem(input.Errors);
        }

        var note = await store.InsertAsync(Guid.NewGuid(), input.Value!, cancellationToken);
        return TypedResults.Created($"/api/notes/{note.Id:D}", NoteResponse.From(note));
    }

    private static async Task<Results<Ok<NoteReadResponse>, ValidationProblem, ProblemHttpResult>> ReadAsync(
        string id,
        NoteReader reader,
        CancellationToken cancellationToken)
    {
        var noteId = NoteValidation.ParseId(id);
        if (!noteId.IsValid)
        {
            return TypedResults.ValidationProblem(noteId.Errors);
        }

        var read = await reader.ReadAsync(noteId.Value, cancellationToken);
        if (read is null)
        {
            return TypedResults.Problem(detail: "No note has this id.", statusCode: StatusCodes.Status404NotFound);
        }

        var source = read.Source == NoteSource.Cache ? "cache" : "database";
        return TypedResults.Ok(new NoteReadResponse(read.Note.Id, read.Note.Body, read.Note.CreatedAt, source));
    }

    private static async Task<Results<Ok<NoteListResponse>, ValidationProblem>> ListAsync(
        [FromQuery] string? limit,
        HttpRequest request,
        INoteStore store,
        CancellationToken cancellationToken)
    {
        // limit is declared for the OpenAPI document. The raw query values tell
        // "?limit=" from no limit at all, and catch a limit given twice.
        var count = NoteValidation.ParseLimit(request.Query[NoteValidation.LimitField].ToArray());
        if (!count.IsValid)
        {
            return TypedResults.ValidationProblem(count.Errors);
        }

        var notes = await store.ListRecentAsync(count.Value, cancellationToken);
        return TypedResults.Ok(new NoteListResponse(notes.Select(NoteResponse.From).ToList()));
    }

    /// <summary>The request body, or null when it exceeds the limit.</summary>
    private static async Task<ReadOnlyMemory<byte>?> ReadBoundedAsync(HttpRequest request, CancellationToken cancellationToken)
    {
        if (request.ContentLength > NoteValidation.MaxRequestBytes)
        {
            return null;
        }

        var buffer = new byte[NoteValidation.MaxRequestBytes + 1];
        var total = 0;
        int read;
        while ((read = await request.Body.ReadAsync(buffer.AsMemory(total), cancellationToken)) > 0)
        {
            total += read;
            if (total > NoteValidation.MaxRequestBytes)
            {
                return null;
            }
        }

        return buffer.AsMemory(0, total);
    }
}
