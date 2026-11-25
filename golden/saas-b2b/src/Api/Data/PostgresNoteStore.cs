using Api.Notes;
using Npgsql;
using NpgsqlTypes;

namespace Api.Data;

/// <summary>
/// Notes in PostgreSQL, with positional parameters only: no value is ever
/// written into the SQL text (research RS-03). The data source is resolved on
/// use, so a missing setting fails the request, never the start of the API.
/// </summary>
public sealed class PostgresNoteStore(IServiceProvider services) : INoteStore
{
    private NpgsqlDataSource DataSource => services.GetRequiredService<NpgsqlDataSource>();

    public async Task<Note> InsertAsync(Guid id, string body, CancellationToken cancellationToken)
    {
        await using var command = DataSource.CreateCommand(
            "INSERT INTO notes (id, body) VALUES ($1, $2) RETURNING created_at");
        command.Parameters.Add(new NpgsqlParameter<Guid> { TypedValue = id });
        command.Parameters.Add(new NpgsqlParameter<string> { TypedValue = body, NpgsqlDbType = NpgsqlDbType.Text });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException("INSERT ... RETURNING gave no row.");
        }

        return new Note(id, body, reader.GetFieldValue<DateTimeOffset>(0));
    }

    public async Task<Note?> FindAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var command = DataSource.CreateCommand(
            "SELECT id, body, created_at FROM notes WHERE id = $1");
        command.Parameters.Add(new NpgsqlParameter<Guid> { TypedValue = id });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? ReadNote(reader) : null;
    }

    public async Task<IReadOnlyList<Note>> ListRecentAsync(int limit, CancellationToken cancellationToken)
    {
        await using var command = DataSource.CreateCommand(
            "SELECT id, body, created_at FROM notes ORDER BY created_at DESC, id DESC LIMIT $1");
        command.Parameters.Add(new NpgsqlParameter<int> { TypedValue = limit });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var notes = new List<Note>(limit);
        while (await reader.ReadAsync(cancellationToken))
        {
            notes.Add(ReadNote(reader));
        }

        return notes;
    }

    private static Note ReadNote(NpgsqlDataReader reader) => new(
        reader.GetGuid(0),
        reader.GetString(1),
        reader.GetFieldValue<DateTimeOffset>(2));
}
