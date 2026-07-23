import { describe, expect, it, vi } from "vitest";
import { consumeAGUIStream, isAGUIEvent, parseSSEDataLines } from "../src/lib/ag-ui-client";
import type { AGUIEvent } from "../src/types";

/**
 * FT-030 — `ag-ui-client.ts`. Taxonomy: happy / error / contract.
 *
 * "A recorded stream" (per the task's own deliverable text) is built here
 * as a synthetic SSE byte stream from canned event objects — the same
 * `data: <json>\n\n` wire format the real backend produces
 * (`contracts/ag-ui-events.md`), fed through a real `ReadableStream` so the
 * parser is exercised exactly as it would be against a live response body.
 *
 * "A live backend" test is gated behind `AG_UI_LIVE_BACKEND_URL` — running
 * a real `LoanActor.Web.Endpoint` from a Vitest process isn't something
 * this test file can orchestrate cross-language; it's skipped by default
 * and documented, mirroring `mix test.load`'s own opt-in-only pattern for
 * tests needing infrastructure beyond the default fast loop.
 */

function sseBody(dataLines: string[]): string {
  return dataLines.map((line) => `data: ${line}\n\n`).join("");
}

function streamFromText(text: string): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  const bytes = encoder.encode(text);

  return new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(bytes);
      controller.close();
    },
  });
}

/** Splits one SSE body into several enqueue()s, to prove frames spanning chunk boundaries still parse. */
function chunkedStreamFromText(text: string, chunkSize: number): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  const bytes = encoder.encode(text);

  return new ReadableStream<Uint8Array>({
    start(controller) {
      for (let i = 0; i < bytes.length; i += chunkSize) {
        controller.enqueue(bytes.slice(i, i + chunkSize));
      }
      controller.close();
    },
  });
}

interface MockResponse {
  ok: boolean;
  status: number;
  body: ReadableStream<Uint8Array> | null;
}

function fetchReturning(response: MockResponse): typeof fetch {
  return vi.fn().mockResolvedValue(response) as unknown as typeof fetch;
}

const recordedRunStarted = { type: "RunStarted", run_id: "run-1", thread_id: null, loan_id: "L-1" };
const recordedStateSnapshot = {
  type: "StateSnapshot",
  loan_id: "L-1",
  state: {
    loan_id: "L-1",
    status: "spawned",
    goals: [],
    context: {},
    version: 0,
    last_heartbeat_at: null,
  },
};
const recordedDiaryEntry = {
  type: "CustomEvent",
  name: "diary_entry",
  loan_id: "L-1",
  entry: {
    loan_id: "L-1",
    sequence: 1,
    timestamp: "2026-01-01T00:00:00Z",
    type: "goal_set",
    actor: "test",
    payload_hash: "aa",
    payload_ref: null,
    prev_hash: "bb",
  },
};
const recordedStateDelta = {
  type: "StateDelta",
  loan_id: "L-1",
  patch: [{ op: "replace", path: "", value: { status: "awaiting_documents" } }],
};
const recordedToolCallStart = { type: "ToolCallStart", tool_call_id: "inv-1", tool_call_name: "request_document", loan_id: "L-1" };
const recordedToolCallArgs = { type: "ToolCallArgs", tool_call_id: "inv-1", delta: '{"doc_type":"income"}' };
const recordedToolCallEnd = { type: "ToolCallEnd", tool_call_id: "inv-1" };
const recordedToolCallResult = {
  type: "ToolCallResult",
  message_id: "msg-1",
  tool_call_id: "inv-1",
  content: '{"request":{"doc_type":"income"}}',
};
const recordedRunFinished = { type: "RunFinished", run_id: "run-1" };

const recordedHappyPathStream = [
  recordedRunStarted,
  recordedStateSnapshot,
  recordedDiaryEntry,
  recordedStateDelta,
  recordedToolCallStart,
  recordedToolCallArgs,
  recordedToolCallEnd,
  recordedToolCallResult,
  recordedRunFinished,
];

describe("parseSSEDataLines — happy", () => {
  it("yields one data line per SSE frame, in order", async () => {
    const text = sseBody(['{"a":1}', '{"a":2}', '{"a":3}']);
    const reader = streamFromText(text).getReader();

    const lines: string[] = [];
    for await (const line of parseSSEDataLines(reader)) {
      lines.push(line);
    }

    expect(lines).toEqual(['{"a":1}', '{"a":2}', '{"a":3}']);
  });

  it("reassembles a frame split across multiple stream chunks", async () => {
    const text = sseBody(['{"a":1}', '{"a":2}']);
    const reader = chunkedStreamFromText(text, 3).getReader();

    const lines: string[] = [];
    for await (const line of parseSSEDataLines(reader)) {
      lines.push(line);
    }

    expect(lines).toEqual(['{"a":1}', '{"a":2}']);
  });
});

describe("isAGUIEvent — contract (every documented shape accepted)", () => {
  it.each(recordedHappyPathStream)("accepts a recorded %j", (event) => {
    expect(isAGUIEvent(event)).toBe(true);
  });

  it("accepts the hitl_request and hitl_conflict CustomEvent variants", () => {
    expect(
      isAGUIEvent({
        type: "CustomEvent",
        name: "hitl_request",
        loan_id: "L-1",
        request: { request_id: "r1", loan_id: "L-1", prompt: "Approve?", options: ["approve", "reject"], created_at: null },
      }),
    ).toBe(true);

    expect(isAGUIEvent({ type: "CustomEvent", name: "hitl_conflict", loan_id: "L-1", request_id: "r1" })).toBe(true);
  });

  it("accepts RunError and the three TextMessage* events", () => {
    expect(isAGUIEvent({ type: "RunError", run_id: "run-1", message: "boom", code: "internal" })).toBe(true);
    expect(isAGUIEvent({ type: "TextMessageStart", message_id: "m1", role: "assistant" })).toBe(true);
    expect(isAGUIEvent({ type: "TextMessageContent", message_id: "m1", delta: "hi" })).toBe(true);
    expect(isAGUIEvent({ type: "TextMessageEnd", message_id: "m1" })).toBe(true);
  });
});

describe("isAGUIEvent — error (strict rejection)", () => {
  it("rejects an unknown type value", () => {
    expect(isAGUIEvent({ type: "StepStarted" })).toBe(false);
    expect(isAGUIEvent({ type: "MessagesSnapshot" })).toBe(false);
    expect(isAGUIEvent({ type: "SomethingMadeUp" })).toBe(false);
  });

  it("rejects a payload with no type field, or a non-object payload", () => {
    expect(isAGUIEvent({})).toBe(false);
    expect(isAGUIEvent("a string")).toBe(false);
    expect(isAGUIEvent(42)).toBe(false);
    expect(isAGUIEvent(null)).toBe(false);
  });
});

describe("consumeAGUIStream — happy", () => {
  it("dispatches every event in a recorded stream to onEvent, in order, then resolves", async () => {
    const body = streamFromText(sseBody(recordedHappyPathStream.map((e) => JSON.stringify(e))));
    const fetchImpl = fetchReturning({ ok: true, status: 200, body });

    const received: AGUIEvent[] = [];
    const onUnknownEvent = vi.fn();
    const onError = vi.fn();

    await consumeAGUIStream(
      { loanId: "L-1", fetchImpl },
      { onEvent: (event) => received.push(event), onUnknownEvent, onError },
    );

    expect(received).toEqual(recordedHappyPathStream);
    expect(onUnknownEvent).not.toHaveBeenCalled();
    expect(onError).not.toHaveBeenCalled();
  });

  it("POSTs to /loans/:loan_id/ag-ui with thread_id and since_sequence in the body", async () => {
    const body = streamFromText("");
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true, status: 200, body }) as unknown as typeof fetch;

    await consumeAGUIStream(
      { loanId: "L-42", threadId: "t-1", sinceSequence: 7, baseUrl: "http://localhost:4000", fetchImpl },
      { onEvent: vi.fn(), onUnknownEvent: vi.fn() },
    );

    expect(fetchImpl).toHaveBeenCalledWith(
      "http://localhost:4000/loans/L-42/ag-ui",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ thread_id: "t-1", since_sequence: 7 }),
      }),
    );
  });
});

describe("consumeAGUIStream — error", () => {
  it("routes an unknown-type frame to onUnknownEvent, not onEvent, and keeps consuming", async () => {
    const goodBefore = recordedRunStarted;
    const bad = { type: "StepStarted", foo: "bar" };
    const goodAfter = recordedRunFinished;
    const body = streamFromText(sseBody([JSON.stringify(goodBefore), JSON.stringify(bad), JSON.stringify(goodAfter)]));
    const fetchImpl = fetchReturning({ ok: true, status: 200, body });

    const received: AGUIEvent[] = [];
    const unknown: unknown[] = [];

    await consumeAGUIStream(
      { loanId: "L-1", fetchImpl },
      { onEvent: (event) => received.push(event), onUnknownEvent: (raw) => unknown.push(raw) },
    );

    expect(received).toEqual([goodBefore, goodAfter]);
    expect(unknown).toEqual([bad]);
  });

  it("routes malformed (non-JSON) data to onUnknownEvent", async () => {
    const body = streamFromText(sseBody(["not json at all"]));
    const fetchImpl = fetchReturning({ ok: true, status: 200, body });

    const unknown: unknown[] = [];
    await consumeAGUIStream({ loanId: "L-1", fetchImpl }, { onEvent: vi.fn(), onUnknownEvent: (raw) => unknown.push(raw) });

    expect(unknown).toEqual(["not json at all"]);
  });

  it("calls onError when the HTTP response is not ok", async () => {
    const fetchImpl = fetchReturning({ ok: false, status: 404, body: null });
    const onError = vi.fn();

    await consumeAGUIStream({ loanId: "not-a-real-loan", fetchImpl }, { onEvent: vi.fn(), onUnknownEvent: vi.fn(), onError });

    expect(onError).toHaveBeenCalledWith(expect.objectContaining({ message: expect.stringContaining("404") }));
  });

  it("calls onError when fetch itself rejects (network failure)", async () => {
    const fetchImpl = vi.fn().mockRejectedValue(new Error("network down")) as unknown as typeof fetch;
    const onError = vi.fn();

    await consumeAGUIStream({ loanId: "L-1", fetchImpl }, { onEvent: vi.fn(), onUnknownEvent: vi.fn(), onError });

    expect(onError).toHaveBeenCalledWith(expect.objectContaining({ message: "network down" }));
  });
});

// @types/node isn't in plan.md's dependency list; `process` is a real
// Node global under Vitest regardless, so read it through globalThis
// rather than adding a new devDependency just for this one opt-in check.
const liveBackendUrl = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env
  ?.AG_UI_LIVE_BACKEND_URL;

describe.skipIf(!liveBackendUrl)("consumeAGUIStream — live backend (opt-in, AG_UI_LIVE_BACKEND_URL)", () => {
  it("streams RunStarted then StateSnapshot from a real spawned loan", async () => {
    const loanId = `L-live-${Date.now()}`;

    await fetch(`${liveBackendUrl}/loans`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ loan_id: loanId }),
    });

    const received: AGUIEvent[] = [];
    const controller = new AbortController();
    setTimeout(() => controller.abort(), 1000);

    await consumeAGUIStream(
      { loanId, baseUrl: liveBackendUrl, signal: controller.signal },
      { onEvent: (event) => received.push(event), onUnknownEvent: vi.fn() },
    ).catch(() => {
      // Aborting a still-open stream rejects the fetch — expected here,
      // this test only cares that the two setup frames arrived first.
    });

    expect(received[0]).toMatchObject({ type: "RunStarted", loan_id: loanId });
    expect(received[1]).toMatchObject({ type: "StateSnapshot", loan_id: loanId });
  });
});
