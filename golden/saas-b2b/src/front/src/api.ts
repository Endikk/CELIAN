// Client of the API routes the front calls (spec 001, contracts/http-api.md).
// The front and the API share one origin behind the gateway (plan, "Routage
// et adresses"): paths are relative, and no address is configured. Each
// route is a literal "<METHOD> <path>", the form control S20 reads, and this
// file is the only one that calls fetch.

export type Note = {
  readonly id: string;
  readonly body: string;
  readonly createdAt: string;
};

export type ServedFrom = "cache" | "database";

export type NoteRead = Note & { readonly servedFrom: ServedFrom };

export type FieldErrors = Readonly<Record<string, readonly string[]>>;

export type ApiFailure = {
  readonly ok: false;
  readonly message: string;
  readonly fieldErrors: FieldErrors;
};

export type ApiResult<T> = { readonly ok: true; readonly value: T } | ApiFailure;

export const UNREACHABLE_MESSAGE =
  "The server could not be reached. Check that the environment is running, then try again.";

export const UNEXPECTED_ANSWER_MESSAGE = "The server sent an answer that this page does not understand.";

const LIST_NOTES = "GET /api/notes";
const READ_NOTE = "GET /api/notes/{id}";
const CREATE_NOTE = "POST /api/notes";

const NO_FIELD_ERRORS: FieldErrors = {};

type Request = {
  readonly route: string;
  readonly params?: Readonly<Record<string, string>>;
  readonly body?: unknown;
  readonly signal?: AbortSignal;
};

export function listNotes(signal?: AbortSignal): Promise<ApiResult<readonly Note[]>> {
  return send({ route: LIST_NOTES, signal }, toNoteList);
}

export function readNote(id: string, signal?: AbortSignal): Promise<ApiResult<NoteRead>> {
  return send({ route: READ_NOTE, params: { id }, signal }, toNoteRead);
}

export function createNote(body: string, signal?: AbortSignal): Promise<ApiResult<Note>> {
  return send({ route: CREATE_NOTE, body: { body }, signal }, toNote);
}

async function send<T>(request: Request, parse: (data: unknown) => T | undefined): Promise<ApiResult<T>> {
  const [method, template] = request.route.split(" ");
  const headers: Record<string, string> =
    request.body === undefined
      ? { Accept: "application/json" }
      : { Accept: "application/json", "Content-Type": "application/json" };
  let response: Response;
  try {
    response = await fetch(fillPath(template, request.params ?? {}), {
      method,
      headers,
      body: request.body === undefined ? undefined : JSON.stringify(request.body),
      signal: request.signal,
    });
  } catch {
    return failure(UNREACHABLE_MESSAGE);
  }
  const data = await readJson(response);
  if (response.ok) {
    const value = parse(data);
    return value === undefined ? failure(UNEXPECTED_ANSWER_MESSAGE) : { ok: true, value };
  }
  return problemFailure(response.status, data);
}

// Replaces each {name} of the template with its encoded value.
function fillPath(template: string, params: Readonly<Record<string, string>>): string {
  return template.replace(/\{([a-z]+)\}/g, (_, name: string) => {
    const value = params[name];
    if (value === undefined) {
      throw new Error(`No value for {${name}} in ${template}`);
    }
    return encodeURIComponent(value);
  });
}

async function readJson(response: Response): Promise<unknown> {
  try {
    const text = await response.text();
    return text === "" ? undefined : (JSON.parse(text) as unknown);
  } catch {
    return undefined;
  }
}

function failure(message: string, fieldErrors: FieldErrors = NO_FIELD_ERRORS): ApiFailure {
  return { ok: false, message, fieldErrors };
}

// Problem details (RFC 9457) as the API writes them: `errors` names each
// field and its rules on a validation error, `detail` explains the others.
function problemFailure(status: number, data: unknown): ApiFailure {
  const detail = isRecord(data) && typeof data.detail === "string" ? data.detail : undefined;
  const fieldErrors = isRecord(data) && isRecord(data.errors) ? toFieldErrors(data.errors) : NO_FIELD_ERRORS;
  return failure(detail ?? `The server answered with an error (HTTP ${status}).`, fieldErrors);
}

function toFieldErrors(errors: Readonly<Record<string, unknown>>): FieldErrors {
  return Object.fromEntries(
    Object.entries(errors)
      .map(([field, messages]): [string, readonly string[]] => [
        field,
        Array.isArray(messages) ? messages.filter((message): message is string => typeof message === "string") : [],
      ])
      .filter(([, messages]) => messages.length > 0),
  );
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// Answers are checked, then copied field by field: the page keeps the fields
// of the contract only.
function toNote(value: unknown): Note | undefined {
  if (
    !isRecord(value) ||
    typeof value.id !== "string" ||
    typeof value.body !== "string" ||
    typeof value.createdAt !== "string"
  ) {
    return undefined;
  }
  return { id: value.id, body: value.body, createdAt: value.createdAt };
}

function toNoteRead(value: unknown): NoteRead | undefined {
  const note = toNote(value);
  if (note === undefined || !isRecord(value)) {
    return undefined;
  }
  const servedFrom = value.servedFrom;
  return servedFrom === "cache" || servedFrom === "database" ? { ...note, servedFrom } : undefined;
}

function toNoteList(value: unknown): readonly Note[] | undefined {
  if (!isRecord(value) || !Array.isArray(value.items)) {
    return undefined;
  }
  const notes = value.items.map(toNote);
  return notes.every((note): note is Note => note !== undefined) ? notes : undefined;
}
