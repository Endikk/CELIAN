namespace Api.Notes;

/// <summary>The only business data of the golden repo (spec 001, data-model, "Note").</summary>
public sealed record Note(Guid Id, string Body, DateTimeOffset CreatedAt);

/// <summary>Where notes are written and read; PostgreSQL in the API, a double in the tests.</summary>
public interface INoteStore
{
    /// <summary>Writes a note whose id the API drew; the database sets created_at.</summary>
    Task<Note> InsertAsync(Guid id, string body, CancellationToken cancellationToken);

    Task<Note?> FindAsync(Guid id, CancellationToken cancellationToken);

    /// <summary>The most recent notes first.</summary>
    Task<IReadOnlyList<Note>> ListRecentAsync(int limit, CancellationToken cancellationToken);
}
