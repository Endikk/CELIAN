// U02, client of the API (spec 001, contracts/http-api.md): relative paths
// under /api, contract fields only, errors by field.
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  UNEXPECTED_ANSWER_MESSAGE,
  UNREACHABLE_MESSAGE,
  createNote,
  listNotes,
  readNote,
} from "../src/api";
import { firstNote, json, problem, stubFetch, unreachable, validationProblem } from "./fakeApi";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("listNotes", () => {
  it("calls GET /api/notes and keeps only the fields of the contract", async () => {
    const fetchMock = stubFetch({
      "GET /api/notes": [() => json(200, { items: [{ ...firstNote, owner: "someone else" }], total: 1 })],
    });

    const result = await listNotes();

    expect(result).toEqual({ ok: true, value: [firstNote] });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("refuses a list that does not match the contract", async () => {
    stubFetch({ "GET /api/notes": [() => json(200, { items: [{ id: 1, body: "x" }] })] });

    const result = await listNotes();

    expect(result).toEqual({ ok: false, message: UNEXPECTED_ANSWER_MESSAGE, fieldErrors: {} });
  });

  it("says when the server cannot be reached", async () => {
    stubFetch({ "GET /api/notes": [unreachable] });

    const result = await listNotes();

    expect(result).toEqual({ ok: false, message: UNREACHABLE_MESSAGE, fieldErrors: {} });
  });

  it("names the HTTP status of an error that carries no problem details", async () => {
    stubFetch({
      "GET /api/notes": [() => new Response("<html>Bad gateway</html>", { status: 502, headers: { "Content-Type": "text/html" } })],
    });

    const result = await listNotes();

    expect(result.ok).toBe(false);
    expect(result.ok ? "" : result.message).toContain("HTTP 502");
  });
});

describe("readNote", () => {
  it("calls GET /api/notes/{id} and returns where the note was served from", async () => {
    stubFetch({ [`GET /api/notes/${firstNote.id}`]: [() => json(200, { ...firstNote, servedFrom: "cache" })] });

    const result = await readNote(firstNote.id);

    expect(result).toEqual({ ok: true, value: { ...firstNote, servedFrom: "cache" } });
  });

  it("encodes the id in the path", async () => {
    const fetchMock = stubFetch({ "GET /api/notes/a%2Fb%3Fc": [() => problem(400, "Not a UUID.")] });

    await readNote("a/b?c");

    expect(fetchMock.mock.calls[0]?.[0]).toBe("/api/notes/a%2Fb%3Fc");
  });

  it("refuses a provenance outside the contract", async () => {
    stubFetch({ [`GET /api/notes/${firstNote.id}`]: [() => json(200, { ...firstNote, servedFrom: "disk" })] });

    const result = await readNote(firstNote.id);

    expect(result).toEqual({ ok: false, message: UNEXPECTED_ANSWER_MESSAGE, fieldErrors: {} });
  });

  it("gives the detail of a problem without field errors", async () => {
    stubFetch({ [`GET /api/notes/${firstNote.id}`]: [() => problem(404, "No note has this id.")] });

    const result = await readNote(firstNote.id);

    expect(result).toEqual({ ok: false, message: "No note has this id.", fieldErrors: {} });
  });
});

describe("createNote", () => {
  it("sends POST /api/notes with the body as JSON", async () => {
    let sent: RequestInit | undefined;
    stubFetch({
      "POST /api/notes": [
        (init) => {
          sent = init;
          return json(201, firstNote);
        },
      ],
    });

    const result = await createNote(firstNote.body);

    expect(result).toEqual({ ok: true, value: firstNote });
    expect(new Headers(sent?.headers).get("Content-Type")).toBe("application/json");
    expect(JSON.parse(String(sent?.body))).toEqual({ body: firstNote.body });
  });

  it("turns a validation problem into errors by field", async () => {
    stubFetch({ "POST /api/notes": [() => validationProblem("body", "Required.")] });

    const result = await createNote("");

    expect(result.ok).toBe(false);
    expect(result.ok ? {} : result.fieldErrors).toEqual({ body: ["Required."] });
  });
});
