// U02, the notes screen (spec 001, contracts/http-api.md, "Ce que le front
// attend"): list shown on load, add form with its loading state and its
// errors by field, provenance of the last read, relative calls under /api.
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { UNREACHABLE_MESSAGE } from "../src/api";
import { NotesScreen } from "../src/screens/NotesScreen";
import {
  deferred,
  firstNote,
  json,
  problem,
  secondNote,
  stubFetch,
  unreachable,
  validationProblem,
} from "./fakeApi";

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const blankBodyError =
  "Must hold 1 to 500 characters once leading and trailing white space is removed; it is blank.";

function latestNotes(): HTMLElement {
  return screen.getByRole("region", { name: "Latest notes" });
}

function lastRead(): HTMLElement {
  return screen.getByRole("region", { name: "Last read" });
}

function bodyField(): HTMLTextAreaElement {
  return screen.getByLabelText("Text of the note") as HTMLTextAreaElement;
}

function addButton(name: string): HTMLButtonElement {
  return screen.getByRole("button", { name }) as HTMLButtonElement;
}

describe("NotesScreen", () => {
  it("shows a loading state, then the latest notes, newest first", async () => {
    const list = deferred<Response>();
    stubFetch({ "GET /api/notes": [() => list.promise] });

    render(<NotesScreen />);

    expect(within(latestNotes()).getByRole("status").textContent).toBe("Loading notes…");
    list.resolve(json(200, { items: [secondNote, firstNote] }));
    const items = await within(latestNotes()).findAllByRole("listitem");
    expect(items.map((item) => item.querySelector("p")?.textContent)).toEqual([secondNote.body, firstNote.body]);
    expect(within(latestNotes()).queryByRole("status")).toBeNull();
  });

  it("says when there is no note yet", async () => {
    stubFetch({ "GET /api/notes": [() => json(200, { items: [] })] });

    render(<NotesScreen />);

    expect(await within(latestNotes()).findByText("No notes yet. Add the first one above.")).toBeTruthy();
  });

  it("says when the list cannot be loaded", async () => {
    stubFetch({ "GET /api/notes": [unreachable] });

    render(<NotesScreen />);

    expect((await within(latestNotes()).findByRole("alert")).textContent).toBe(UNREACHABLE_MESSAGE);
  });

  it("adds a note: the button shows a loading state, then the list is read again", async () => {
    const created = deferred<Response>();
    let sent: RequestInit | undefined;
    stubFetch({
      "GET /api/notes": [() => json(200, { items: [] }), () => json(200, { items: [firstNote] })],
      "POST /api/notes": [
        (init) => {
          sent = init;
          return created.promise;
        },
      ],
    });
    render(<NotesScreen />);
    await within(latestNotes()).findByText("No notes yet. Add the first one above.");

    fireEvent.change(bodyField(), { target: { value: firstNote.body } });
    fireEvent.click(addButton("Add note"));

    const busy = (await screen.findByRole("button", { name: "Adding…" })) as HTMLButtonElement;
    expect(busy.disabled).toBe(true);
    expect(JSON.parse(String(sent?.body))).toEqual({ body: firstNote.body });
    created.resolve(json(201, firstNote));
    expect(await within(latestNotes()).findByText(firstNote.body)).toBeTruthy();
    expect(addButton("Add note").disabled).toBe(false);
    expect(bodyField().value).toBe("");
  });

  it("shows the error of the body field under the field, until the text changes", async () => {
    stubFetch({
      "GET /api/notes": [() => json(200, { items: [] })],
      "POST /api/notes": [() => validationProblem("body", blankBodyError)],
    });
    render(<NotesScreen />);
    await within(latestNotes()).findByText("No notes yet. Add the first one above.");

    fireEvent.change(bodyField(), { target: { value: "   " } });
    fireEvent.click(addButton("Add note"));

    const message = await screen.findByText(blankBodyError);
    expect(bodyField().getAttribute("aria-invalid")).toBe("true");
    expect(bodyField().getAttribute("aria-describedby")).toBe(message.id);
    expect(bodyField().compareDocumentPosition(message) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(screen.getAllByRole("alert")).toEqual([message]);

    fireEvent.change(bodyField(), { target: { value: "A real note" } });
    expect(screen.queryByText(blankBodyError)).toBeNull();
    expect(bodyField().getAttribute("aria-invalid")).toBe("false");
  });

  it("shows a message for an error that names no field, and keeps the text", async () => {
    stubFetch({
      "GET /api/notes": [() => json(200, { items: [] })],
      "POST /api/notes": [() => problem(413, "The request body is limited to 16384 bytes.")],
    });
    render(<NotesScreen />);
    await within(latestNotes()).findByText("No notes yet. Add the first one above.");

    fireEvent.change(bodyField(), { target: { value: firstNote.body } });
    fireEvent.click(addButton("Add note"));

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toBe("The request body is limited to 16384 bytes.");
    expect(bodyField().getAttribute("aria-invalid")).toBe("false");
    expect(bodyField().value).toBe(firstNote.body);
  });

  it("shows where the last read came from: the database, then the cache", async () => {
    stubFetch({
      "GET /api/notes": [() => json(200, { items: [firstNote] })],
      [`GET /api/notes/${firstNote.id}`]: [
        () => json(200, { ...firstNote, servedFrom: "database" }),
        () => json(200, { ...firstNote, servedFrom: "cache" }),
      ],
    });
    render(<NotesScreen />);
    const item = await within(latestNotes()).findByRole("listitem");

    expect(within(lastRead()).getByText("Choose a note below to read it through the cache.")).toBeTruthy();
    fireEvent.click(within(item).getByRole("button", { name: "Read this note" }));
    expect(await within(lastRead()).findByText("Served from the database")).toBeTruthy();
    expect(within(lastRead()).getByText(firstNote.body)).toBeTruthy();

    fireEvent.click(within(item).getByRole("button", { name: "Read this note" }));
    expect(await within(lastRead()).findByText("Served from the cache")).toBeTruthy();
  });

  it("shows the reason when a read fails", async () => {
    stubFetch({
      "GET /api/notes": [() => json(200, { items: [firstNote] })],
      [`GET /api/notes/${firstNote.id}`]: [() => problem(404, "No note has this id.")],
    });
    render(<NotesScreen />);
    const item = await within(latestNotes()).findByRole("listitem");

    fireEvent.click(within(item).getByRole("button", { name: "Read this note" }));

    expect((await within(lastRead()).findByRole("alert")).textContent).toBe("No note has this id.");
  });

  it("shows note bodies as text, never as HTML", async () => {
    const markup = '<img src="x" onerror="window.alert(1)"><b>bold</b>';
    stubFetch({ "GET /api/notes": [() => json(200, { items: [{ ...firstNote, body: markup }] })] });

    render(<NotesScreen />);

    expect(await within(latestNotes()).findByText(markup)).toBeTruthy();
    expect(document.querySelector("img")).toBeNull();
    expect(document.querySelector("b")).toBeNull();
  });

  it("calls only relative paths under /api, with no configured address", async () => {
    const fetchMock = stubFetch({
      "GET /api/notes": [() => json(200, { items: [] }), () => json(200, { items: [firstNote] })],
      "POST /api/notes": [() => json(201, firstNote)],
      [`GET /api/notes/${firstNote.id}`]: [() => json(200, { ...firstNote, servedFrom: "database" })],
    });
    render(<NotesScreen />);
    await within(latestNotes()).findByText("No notes yet. Add the first one above.");
    fireEvent.change(bodyField(), { target: { value: firstNote.body } });
    fireEvent.click(addButton("Add note"));
    const item = await within(latestNotes()).findByRole("listitem");
    fireEvent.click(within(item).getByRole("button", { name: "Read this note" }));
    await within(lastRead()).findByText("Served from the database");

    const calls = fetchMock.mock.calls.map(([input, init]) => `${init?.method ?? "GET"} ${String(input)}`);
    expect(calls).toEqual([
      "GET /api/notes",
      "POST /api/notes",
      "GET /api/notes",
      `GET /api/notes/${firstNote.id}`,
    ]);
    expect(calls.every((call) => !call.includes("://"))).toBe(true);
  });
});
