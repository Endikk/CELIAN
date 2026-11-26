// The one screen of the front (spec 001, FR-009): the latest notes, a form
// to add one, and the last note read, with where the API served it from.
// Note bodies are rendered as React text, which escapes them.
import { useEffect, useRef, useState, type ChangeEvent, type FormEvent } from "react";
import { createNote, listNotes, readNote, type Note, type NoteRead } from "../api";

type ListState =
  | { readonly status: "loading" }
  | { readonly status: "ready"; readonly notes: readonly Note[] }
  | { readonly status: "failed"; readonly message: string };

type AddState = {
  readonly pending: boolean;
  readonly fieldError?: string;
  readonly message?: string;
};

type ReadState =
  | { readonly status: "idle" }
  | { readonly status: "loading" }
  | { readonly status: "ready"; readonly note: NoteRead }
  | { readonly status: "failed"; readonly message: string };

const BODY_FIELD_ID = "note-body";
const BODY_ERROR_ID = "note-body-error";

const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });

function formatDate(isoDate: string): string {
  const date = new Date(isoDate);
  return Number.isNaN(date.getTime()) ? isoDate : dateFormat.format(date);
}

export function NotesScreen() {
  const [list, setList] = useState<ListState>({ status: "loading" });
  const [draft, setDraft] = useState("");
  const [add, setAdd] = useState<AddState>({ pending: false });
  const [lastRead, setLastRead] = useState<ReadState>({ status: "idle" });
  const latestRead = useRef(0);

  async function refreshList(isCurrent: () => boolean = () => true) {
    const result = await listNotes();
    if (!isCurrent()) {
      return;
    }
    setList(result.ok ? { status: "ready", notes: result.value } : { status: "failed", message: result.message });
  }

  useEffect(() => {
    let ignore = false;
    void refreshList(() => !ignore);
    return () => {
      ignore = true;
    };
  }, []);

  function onDraftChange(event: ChangeEvent<HTMLTextAreaElement>) {
    setDraft(event.target.value);
    setAdd((current) => ({ pending: current.pending }));
  }

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (add.pending) {
      return;
    }
    setAdd({ pending: true });
    const result = await createNote(draft);
    if (!result.ok) {
      const fieldError = result.fieldErrors.body?.join(" ");
      setAdd(fieldError === undefined ? { pending: false, message: result.message } : { pending: false, fieldError });
      return;
    }
    setDraft("");
    setAdd({ pending: false });
    await refreshList();
  }

  async function onRead(id: string) {
    const request = latestRead.current + 1;
    latestRead.current = request;
    setLastRead({ status: "loading" });
    const result = await readNote(id);
    if (latestRead.current !== request) {
      return;
    }
    setLastRead(result.ok ? { status: "ready", note: result.value } : { status: "failed", message: result.message });
  }

  return (
    <main className="notes">
      <header>
        <h1>Notes</h1>
        <p className="lead">
          Each note is written to the database. Reading one goes through the cache first, and the page shows where the
          answer came from.
        </p>
      </header>

      <section aria-labelledby="new-note-title" className="panel">
        <h2 id="new-note-title">New note</h2>
        <form onSubmit={onSubmit} noValidate>
          <label htmlFor={BODY_FIELD_ID}>Text of the note</label>
          <textarea
            id={BODY_FIELD_ID}
            name="body"
            rows={3}
            value={draft}
            onChange={onDraftChange}
            aria-invalid={add.fieldError !== undefined}
            aria-describedby={add.fieldError === undefined ? undefined : BODY_ERROR_ID}
          />
          {add.fieldError !== undefined && (
            <p id={BODY_ERROR_ID} className="field-error" role="alert">
              {add.fieldError}
            </p>
          )}
          {add.message !== undefined && (
            <p className="error" role="alert">
              {add.message}
            </p>
          )}
          <button type="submit" disabled={add.pending}>
            {add.pending ? "Adding…" : "Add note"}
          </button>
        </form>
      </section>

      <section aria-labelledby="last-read-title" className="panel">
        <h2 id="last-read-title">Last read</h2>
        <LastRead state={lastRead} />
      </section>

      <section aria-labelledby="latest-notes-title" className="panel">
        <h2 id="latest-notes-title">Latest notes</h2>
        <LatestNotes state={list} onRead={onRead} />
      </section>
    </main>
  );
}

function LastRead({ state }: { readonly state: ReadState }) {
  switch (state.status) {
    case "idle":
      return <p className="hint">Choose a note below to read it through the cache.</p>;
    case "loading":
      return <p role="status">Reading…</p>;
    case "failed":
      return (
        <p className="error" role="alert">
          {state.message}
        </p>
      );
    case "ready":
      return (
        <article className="read">
          <p className="note-body">{state.note.body}</p>
          <p className="served-from">
            {state.note.servedFrom === "cache" ? "Served from the cache" : "Served from the database"}
          </p>
          <p className="meta">
            <time dateTime={state.note.createdAt}>{formatDate(state.note.createdAt)}</time>
            {" · "}
            <code>{state.note.id}</code>
          </p>
        </article>
      );
  }
}

function LatestNotes({ state, onRead }: { readonly state: ListState; readonly onRead: (id: string) => void }) {
  switch (state.status) {
    case "loading":
      return <p role="status">Loading notes…</p>;
    case "failed":
      return (
        <p className="error" role="alert">
          {state.message}
        </p>
      );
    case "ready":
      if (state.notes.length === 0) {
        return <p className="hint">No notes yet. Add the first one above.</p>;
      }
      return (
        <ul className="note-list">
          {state.notes.map((note) => (
            <li key={note.id}>
              <p className="note-body">{note.body}</p>
              <p className="meta">
                <time dateTime={note.createdAt}>{formatDate(note.createdAt)}</time>
              </p>
              <button type="button" className="secondary" onClick={() => onRead(note.id)}>
                Read this note
              </button>
            </li>
          ))}
        </ul>
      );
  }
}
