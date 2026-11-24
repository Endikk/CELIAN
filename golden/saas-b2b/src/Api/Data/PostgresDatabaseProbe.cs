using Api.Health;
using Npgsql;

namespace Api.Data;

/// <summary>
/// The database is ready when the schema script has run and an authenticated
/// SELECT 1 answers (ADR-012, condition 6).
/// </summary>
public sealed class PostgresDatabaseProbe(IServiceProvider services, SchemaState schema) : IDatabaseProbe
{
    public async Task<bool> IsReadyAsync(CancellationToken cancellationToken)
    {
        if (!schema.IsReady)
        {
            return false;
        }

        var dataSource = services.GetRequiredService<NpgsqlDataSource>();
        await using var command = dataSource.CreateCommand("SELECT 1");
        return await command.ExecuteScalarAsync(cancellationToken) is 1;
    }
}
