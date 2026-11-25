using Api.Data;

namespace Api.Tests;

/// <summary>
/// The schema script runs at every start (research RS-04): each statement
/// must leave an existing schema as it is. Run against PostgreSQL by the
/// tests on kind (step 9, E01 and E02).
/// </summary>
public sealed class SchemaTests
{
    [Fact]
    public void Every_statement_is_idempotent()
    {
        Assert.NotEmpty(Schema.Statements);
        Assert.All(Schema.Statements, statement =>
            Assert.Matches(@"^\s*CREATE (TABLE|INDEX) IF NOT EXISTS ", statement));
    }

    [Fact]
    public void The_notes_table_holds_the_three_fields_of_the_data_model()
    {
        var table = Assert.Single(Schema.Statements, s => s.Contains("CREATE TABLE IF NOT EXISTS notes", StringComparison.Ordinal));

        Assert.Matches(@"\bid uuid PRIMARY KEY\b", table);
        Assert.Matches(@"\bbody text NOT NULL\b", table);
        Assert.Contains("char_length(body) BETWEEN 1 AND 500", table, StringComparison.Ordinal);
        Assert.Matches(@"\bcreated_at timestamptz NOT NULL DEFAULT now\(\)", table);
    }
}
