using System.Text.Json;
using Api.Caching;

namespace Api.Notes;

/// <summary>Key scheme and lifetime of the cached notes (data-model, "Note").</summary>
public static class NoteCache
{
    /// <summary>Fixed lifetime of a cached note, set at step 3 (T023).</summary>
    public static readonly TimeSpan TimeToLive = TimeSpan.FromMinutes(5);

    public static string KeyFor(Guid id) => $"note:{id:D}";
}

public enum NoteSource
{
    Database,
    Cache,
}

public sealed record NoteRead(Note Note, NoteSource Source);

/// <summary>
/// Lazy read through the cache: the cache answers when it holds the note;
/// otherwise the database answers and the note enters the cache. A missing
/// note never enters the cache. A cache that fails, or holds something else
/// than the note, never fails the read: the database answers.
/// </summary>
public sealed class NoteReader(INoteStore store, ICache cache, ILogger<NoteReader> logger)
{
    private static readonly JsonSerializerOptions CacheJson = new(JsonSerializerDefaults.Web);

    public async Task<NoteRead?> ReadAsync(Guid id, CancellationToken cancellationToken)
    {
        var key = NoteCache.KeyFor(id);
        var cached = await TryGetAsync(key, id, cancellationToken);
        if (cached is not null)
        {
            return new NoteRead(cached, NoteSource.Cache);
        }

        var note = await store.FindAsync(id, cancellationToken);
        if (note is null)
        {
            return null;
        }

        await TrySetAsync(key, note, cancellationToken);
        return new NoteRead(note, NoteSource.Database);
    }

    private async Task<Note?> TryGetAsync(string key, Guid id, CancellationToken cancellationToken)
    {
        try
        {
            var value = await cache.GetAsync(key, cancellationToken);
            if (value is null)
            {
                return null;
            }

            var note = JsonSerializer.Deserialize<CachedNote>(value, CacheJson);
            if (note is { Body: not null, CreatedAt: { } createdAt } && note.Id == id)
            {
                return new Note(note.Id, note.Body, createdAt);
            }

            logger.LogWarning("Cache entry {Key} does not hold the note; reading the database.", key);
            return null;
        }
        catch (Exception error) when (error is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning(error, "Cache read of {Key} failed; reading the database.", key);
            return null;
        }
    }

    private async Task TrySetAsync(string key, Note note, CancellationToken cancellationToken)
    {
        try
        {
            var value = JsonSerializer.Serialize(new CachedNote(note.Id, note.Body, note.CreatedAt), CacheJson);
            await cache.SetAsync(key, value, NoteCache.TimeToLive, cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning(error, "Cache write of {Key} failed; the note is served from the database.", key);
        }
    }

    /// <summary>The three fields of a note, as stored in the cache.</summary>
    private sealed record CachedNote(Guid Id, string? Body, DateTimeOffset? CreatedAt);
}
