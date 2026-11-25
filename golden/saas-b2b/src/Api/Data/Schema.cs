namespace Api.Data;

/// <summary>
/// Idempotent SQL script of the notes table (spec 001, data-model, "Note"),
/// run at every start under the role of db-auth, owner of the database app
/// (research RS-04). id is drawn by the API, created_at set by the database.
/// The CHECK repeats the rule of the API: 1 to 500 characters, counted as
/// char_length does.
/// </summary>
public static class Schema
{
    /// <summary>Key of the transaction advisory lock that keeps two starting replicas from racing.</summary>
    public const long AdvisoryLockKey = 0x5aa5_b2b0_0001;

    public static readonly IReadOnlyList<string> Statements =
    [
        """
        CREATE TABLE IF NOT EXISTS notes (
            id uuid PRIMARY KEY,
            body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 500),
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS notes_created_at_idx ON notes (created_at DESC, id DESC)
        """,
    ];
}
