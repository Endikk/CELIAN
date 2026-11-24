// Test doubles of the API for U02: a fetch that answers "<METHOD> <path>"
// from a list of handlers, one per expected call, in order.
import { vi } from "vitest";

export type Handler = (init: RequestInit | undefined) => Response | Promise<Response>;

export const firstNote = {
  id: "3f2b8c1e-5d4a-4e6b-9a7c-1d2e3f4a5b6c",
  body: "Call the supplier back",
  createdAt: "2026-11-24T09:15:00+00:00",
} as const;

export const secondNote = {
  id: "9b1f0c2d-7e3a-4c5b-8d6e-0f1a2b3c4d5e",
  body: "Send the quote to Lyon",
  createdAt: "2026-11-24T10:30:00+00:00",
} as const;

export function json(status: number, body: unknown, contentType = "application/json"): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": contentType } });
}

export function validationProblem(field: string, message: string): Response {
  return json(
    400,
    {
      type: "https://tools.ietf.org/html/rfc9110#section-15.5.1",
      title: "One or more validation errors occurred.",
      status: 400,
      errors: { [field]: [message] },
    },
    "application/problem+json",
  );
}

export function problem(status: number, detail: string): Response {
  return json(status, { title: "Error", status, detail }, "application/problem+json");
}

export function unreachable(): Promise<Response> {
  return Promise.reject(new TypeError("Failed to fetch"));
}

export type Deferred<T> = {
  readonly promise: Promise<T>;
  readonly resolve: (value: T) => void;
};

export function deferred<T>(): Deferred<T> {
  let resolve: (value: T) => void = () => undefined;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

// Replaces the global fetch. A call that no handler expects fails the test
// through the error the front then shows, and is listed in the message.
export function stubFetch(routes: Readonly<Record<string, readonly Handler[]>>) {
  const used = new Map<string, number>();
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    if (typeof input !== "string") {
      throw new Error("the front calls fetch with a path string");
    }
    const key = `${init?.method ?? "GET"} ${input}`;
    const index = used.get(key) ?? 0;
    const handler = routes[key]?.[index];
    if (handler === undefined) {
      throw new Error(`unexpected request: ${key}`);
    }
    used.set(key, index + 1);
    return handler(init);
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}
