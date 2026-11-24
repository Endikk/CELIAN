using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Api.Notes;

/// <summary>Outcome of a validation: the value, or the errors by field name.</summary>
public sealed record Validated<T>(T? Value, IReadOnlyDictionary<string, string[]> Errors)
{
    public bool IsValid => Errors.Count == 0;
}

/// <summary>
/// Server-side rules of the notes routes (contracts/http-api.md). Each error
/// names its field and the rule it breaks. Characters are Unicode code
/// points, as char_length counts them in PostgreSQL (research RS-03).
/// </summary>
public static class NoteValidation
{
    public const string BodyField = "body";

    public const string IdField = "id";

    public const string LimitField = "limit";

    public const int MaxBodyCharacters = 500;

    public const int DefaultLimit = 20;

    public const int MaxLimit = 50;

    /// <summary>Largest request body read for POST /api/notes; beyond it, 413.</summary>
    public const int MaxRequestBytes = 16 * 1024;

    private const int MaxJsonDepth = 8;

    private const string BodyRule = "Must hold 1 to 500 characters once leading and trailing white space is removed";

    private const string UnknownFieldRule = "Unknown field: the only accepted field is 'body'.";

    /// <summary>
    /// Longest field name that an error repeats, in characters. With this cut
    /// and only the first unknown field named, a request of 16 KiB draws a few
    /// hundred bytes; naming every unknown field drew 107 KB in U01 (review
    /// [SECU] of step 3).
    /// </summary>
    private const int MaxNamedFieldCharacters = 32;

    /// <summary>Stands for the name of an unknown field that is not valid Unicode, and cannot be repeated.</summary>
    private const string UnreadableFieldName = "(field name that is not valid Unicode)";

    private static readonly IReadOnlyDictionary<string, string[]> NoErrors = new Dictionary<string, string[]>();

    /// <summary>Reads {"body": "..."}, the only accepted shape, and returns the trimmed body.</summary>
    public static Validated<string> ParseCreateRequest(ReadOnlyMemory<byte> json)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = MaxJsonDepth });
        }
        catch (JsonException)
        {
            return Invalid<string>(BodyField, "Send a JSON object with a 'body' field.");
        }

        using (document)
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return Invalid<string>(BodyField, "Send a JSON object with a 'body' field.");
            }

            var errors = new Dictionary<string, string[]>(StringComparer.Ordinal);
            var bodies = new List<JsonElement>();
            JsonProperty? firstUnknown = null;
            var unknownCount = 0;
            foreach (var property in document.RootElement.EnumerateObject())
            {
                if (property.NameEquals(BodyField))
                {
                    bodies.Add(property.Value);
                }
                else
                {
                    firstUnknown ??= property;
                    unknownCount++;
                }
            }

            // One unknown field named, whatever their number: the answer stays
            // small, and the client learns that only 'body' is accepted.
            if (firstUnknown is { } unknown)
            {
                errors[NameForErrors(unknown)] = [UnknownFieldsRule(unknownCount)];
            }

            string? body = null;
            var bodyError = bodies.Count switch
            {
                0 => "Required.",
                > 1 => "Give 'body' once.",
                _ => ReadBody(bodies[0], out body),
            };
            if (bodyError is not null)
            {
                errors[BodyField] = [bodyError];
            }

            return errors.Count == 0 ? new Validated<string>(body, NoErrors) : new Validated<string>(null, errors);
        }
    }

    /// <summary>A note id is a UUID in its canonical form, 8-4-4-4-12 hexadecimal digits.</summary>
    public static Validated<Guid> ParseId(string id) =>
        Guid.TryParseExact(id, "D", out var value)
            ? new Validated<Guid>(value, NoErrors)
            : Invalid<Guid>(IdField, "Must be a UUID such as 3f2b8c1e-5d4a-4e6b-9a7c-1d2e3f4a5b6c.");

    /// <summary>limit: an integer from 1 to 50, 20 when absent.</summary>
    public static Validated<int> ParseLimit(IReadOnlyList<string?> values)
    {
        const string rule = "Must be an integer from 1 to 50.";
        if (values.Count == 0)
        {
            return new Validated<int>(DefaultLimit, NoErrors);
        }

        if (values.Count > 1)
        {
            return Invalid<int>(LimitField, "Give limit once. " + rule);
        }

        return int.TryParse(values[0], NumberStyles.None, CultureInfo.InvariantCulture, out var limit)
            && limit is >= 1 and <= MaxLimit
                ? new Validated<int>(limit, NoErrors)
                : Invalid<int>(LimitField, rule);
    }

    private static string? ReadBody(JsonElement element, out string? body)
    {
        body = null;
        if (element.ValueKind != JsonValueKind.String)
        {
            return "Must be a string.";
        }

        string text;
        try
        {
            text = element.GetString() ?? "";
        }
        catch (InvalidOperationException)
        {
            return "Must be valid Unicode text.";
        }

        if (!IsWellFormed(text))
        {
            return "Must be valid Unicode text.";
        }

        if (text.Contains('\0', StringComparison.Ordinal))
        {
            return "Must not contain the NUL character.";
        }

        var trimmed = text.Trim();
        var characters = trimmed.EnumerateRunes().Count();
        if (characters == 0)
        {
            return $"{BodyRule}; it is blank.";
        }

        if (characters > MaxBodyCharacters)
        {
            return $"{BodyRule}; it holds {characters}.";
        }

        body = trimmed;
        return null;
    }

    /// <summary>The name of an unknown field as its error gives it: cut after 32 characters, never split inside a character.</summary>
    private static string NameForErrors(JsonProperty property)
    {
        string name;
        try
        {
            name = property.Name;
        }
        catch (InvalidOperationException)
        {
            return UnreadableFieldName;
        }

        if (!IsWellFormed(name))
        {
            return UnreadableFieldName;
        }

        var characters = 0;
        var end = 0;
        foreach (var rune in name.EnumerateRunes())
        {
            if (characters == MaxNamedFieldCharacters)
            {
                return name[..end] + "...";
            }

            characters++;
            end += rune.Utf16SequenceLength;
        }

        return name;
    }

    private static string UnknownFieldsRule(int count) =>
        count == 1
            ? UnknownFieldRule
            : string.Create(
                CultureInfo.InvariantCulture,
                $"{UnknownFieldRule} The request holds {count} unknown fields; this error names the first.");

    private static bool IsWellFormed(string text)
    {
        var rest = text.AsSpan();
        while (!rest.IsEmpty)
        {
            if (Rune.DecodeFromUtf16(rest, out _, out var used) != System.Buffers.OperationStatus.Done)
            {
                return false;
            }

            rest = rest[used..];
        }

        return true;
    }

    private static Validated<T> Invalid<T>(string field, string message) =>
        new(default, new Dictionary<string, string[]>(StringComparer.Ordinal) { [field] = [message] });
}
