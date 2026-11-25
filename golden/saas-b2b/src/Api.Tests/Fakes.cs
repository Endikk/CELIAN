using System.Collections.Concurrent;
using Api.Caching;
using Api.Health;
using Api.Notes;

namespace Api.Tests;

/// <summary>Notes kept in memory; records every call.</summary>
public sealed class FakeNoteStore : INoteStore
{
    private readonly ConcurrentDictionary<Guid, Note> _notes = new();

    public static readonly DateTimeOffset Now = new(2026, 11, 24, 9, 30, 0, TimeSpan.Zero);

    public List<(Guid Id, string Body)> Inserted { get; } = [];

    public int FindCalls { get; private set; }

    public List<int> ListLimits { get; } = [];

    public Exception? Failure { get; set; }

    public void Add(Note note) => _notes[note.Id] = note;

    public Task<Note> InsertAsync(Guid id, string body, CancellationToken cancellationToken)
    {
        ThrowIfFailing();
        Inserted.Add((id, body));
        var note = new Note(id, body, Now);
        _notes[id] = note;
        return Task.FromResult(note);
    }

    public Task<Note?> FindAsync(Guid id, CancellationToken cancellationToken)
    {
        ThrowIfFailing();
        FindCalls++;
        return Task.FromResult(_notes.TryGetValue(id, out var note) ? note : null);
    }

    public Task<IReadOnlyList<Note>> ListRecentAsync(int limit, CancellationToken cancellationToken)
    {
        ThrowIfFailing();
        ListLimits.Add(limit);
        IReadOnlyList<Note> notes = _notes.Values
            .OrderByDescending(n => n.CreatedAt)
            .ThenByDescending(n => n.Id)
            .Take(limit)
            .ToList();
        return Task.FromResult(notes);
    }

    private void ThrowIfFailing()
    {
        if (Failure is not null)
        {
            throw Failure;
        }
    }
}

/// <summary>A key-value cache in memory; records every call.</summary>
public sealed class FakeCache : ICache
{
    public ConcurrentDictionary<string, string> Values { get; } = new();

    public List<(string Key, string Value, TimeSpan TimeToLive)> Sets { get; } = [];

    public int Gets { get; private set; }

    public bool PingResult { get; set; } = true;

    public Exception? GetFailure { get; set; }

    public Exception? SetFailure { get; set; }

    public Exception? PingFailure { get; set; }

    public bool PingHangs { get; set; }

    public Task<string?> GetAsync(string key, CancellationToken cancellationToken)
    {
        Gets++;
        if (GetFailure is not null)
        {
            throw GetFailure;
        }

        return Task.FromResult(Values.TryGetValue(key, out var value) ? value : null);
    }

    public Task SetAsync(string key, string value, TimeSpan timeToLive, CancellationToken cancellationToken)
    {
        if (SetFailure is not null)
        {
            throw SetFailure;
        }

        Sets.Add((key, value, timeToLive));
        Values[key] = value;
        return Task.CompletedTask;
    }

    public async Task<bool> PingAsync(CancellationToken cancellationToken)
    {
        if (PingHangs)
        {
            await Task.Delay(Timeout.Infinite, cancellationToken);
        }

        if (PingFailure is not null)
        {
            throw PingFailure;
        }

        return PingResult;
    }
}

/// <summary>Answers the readiness question of the database as told.</summary>
public sealed class FakeDatabaseProbe : IDatabaseProbe
{
    public bool Result { get; set; } = true;

    public Exception? Failure { get; set; }

    public bool Hangs { get; set; }

    public int Calls { get; private set; }

    public async Task<bool> IsReadyAsync(CancellationToken cancellationToken)
    {
        Calls++;
        if (Hangs)
        {
            await Task.Delay(Timeout.Infinite, cancellationToken);
        }

        if (Failure is not null)
        {
            throw Failure;
        }

        return Result;
    }
}
