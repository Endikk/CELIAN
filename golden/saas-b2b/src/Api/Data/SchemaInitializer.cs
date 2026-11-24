using Npgsql;

namespace Api.Data;

/// <summary>Whether the schema script has run since the process started.</summary>
public sealed class SchemaState
{
    private volatile bool _isReady;

    public bool IsReady => _isReady;

    public void MarkReady() => _isReady = true;
}

/// <summary>
/// Runs the schema script in the background at start, under an advisory lock,
/// until it succeeds: the database may start after the API. Until then the
/// readiness check reports the database in error; liveness stays up.
/// </summary>
public sealed class SchemaInitializer(IServiceProvider services, SchemaState state, ILogger<SchemaInitializer> logger)
    : BackgroundService
{
    private static readonly TimeSpan FirstRetryDelay = TimeSpan.FromSeconds(1);

    private static readonly TimeSpan MaxRetryDelay = TimeSpan.FromSeconds(30);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var delay = FirstRetryDelay;
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RunScriptAsync(stoppingToken);
                state.MarkReady();
                logger.LogInformation("Schema of the notes table is ready.");
                return;
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception error)
            {
                logger.LogWarning(error, "Schema script failed; next attempt in {Delay}.", delay);
            }

            await Task.Delay(delay, stoppingToken).ConfigureAwait(ConfigureAwaitOptions.SuppressThrowing);
            delay = TimeSpan.FromTicks(Math.Min(delay.Ticks * 2, MaxRetryDelay.Ticks));
        }
    }

    private async Task RunScriptAsync(CancellationToken cancellationToken)
    {
        var dataSource = services.GetRequiredService<NpgsqlDataSource>();
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using (var lockCommand = new NpgsqlCommand("SELECT pg_advisory_xact_lock($1)", connection, transaction))
        {
            lockCommand.Parameters.Add(new NpgsqlParameter<long> { TypedValue = Schema.AdvisoryLockKey });
            await lockCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        foreach (var statement in Schema.Statements)
        {
            await using var command = new NpgsqlCommand(statement, connection, transaction);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
    }
}
