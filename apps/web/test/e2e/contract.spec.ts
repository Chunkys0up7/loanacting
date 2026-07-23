import { expect, test } from "@playwright/test";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * FT-038 — cross-stack contract test: captures the LIVE AG-UI wire stream
 * from a real running backend (not through the React app — this is about
 * the wire contract, not the UI; FT-032/033/045's own specs already prove
 * the UI wiring) and diff-checks every observed frame's exact key set
 * against `apps/loan_actor/test/ag_ui/encoder_test.exs`'s own pinned
 * shapes (`EXPECTED_KEYS` below is a hand-kept mirror of those
 * assertions — `contracts/ag-ui-events.md` is the shared source of truth
 * both sides pin against).
 *
 * Scope note: only 10 of the contract's 13 wire `type` values (11 of 15
 * counting `CustomEvent`'s three named variants separately) are reachable
 * from a live run at all. `TextMessageStart`/`TextMessageContent`/
 * `TextMessageEnd` are never emitted by any code path in this
 * deterministic-first foundation (constitution: zero LLM calls); `RunError`
 * is never emitted either (a tool failure completes its ToolCallResult
 * with an error shape instead, per `ag-ui-events.md`'s own tool-call
 * semantics — `RunError` has no caller in `lib/`); `RunFinished` has no
 * caller either, since a loan's AG-UI subscription is a long-lived,
 * intentionally-unbounded connection (`router.ex`'s own moduledoc), not a
 * bounded "run" that closes normally. All five are already exhaustively
 * covered by `encoder_test.exs`'s unit-level snapshots — a cross-stack
 * test can only diff what genuinely crosses the stack.
 *
 * Uses the same temporary-skill-pack technique as `hitl.spec.ts` (a
 * distinct pack id, so the two specs can run in the same suite without
 * colliding) to reach the HITL deferred-result sequence and the
 * hitl_conflict path, so this test also proves the ordering guarantees
 * `ag-ui-events.md` documents: `RunStarted` -> `StateSnapshot` first;
 * every `StateDelta` immediately preceded by its `CustomEvent
 * diary_entry`; `ToolCallEnd` for `request_operator_approval` followed
 * (with other events interleaved, per contract) by `CustomEvent
 * hitl_request`, then — only after this test's own HTTP response — its
 * `ToolCallResult`, with a second response producing `hitl_conflict`
 * instead of a second `ToolCallResult`.
 *
 * Requires `LoanActor.Web.Endpoint` running at http://localhost:4000
 * (same precondition as every other file in this directory).
 */

const BASE_URL = "http://localhost:5173";

const sourceSkillPackDir = path.join(__dirname, "..", "..", "..", "loan_actor", "priv", "skills", "0098-e2e-contract-temp");
const buildSkillPackDir = path.join(
  __dirname,
  "..",
  "..",
  "..",
  "..",
  "_build",
  "dev",
  "lib",
  "loan_actor",
  "priv",
  "skills",
  "0098-e2e-contract-temp",
);

const skillMd = [
  "---",
  "name: e2e-contract-temp",
  "version: 1.0.0",
  "description: During plan review, ask the operator to approve or reject this loan.",
  "tools_required: [request_operator_approval]",
  "---",
  "",
  "Body.",
  "",
].join("\n");

test.beforeAll(() => {
  for (const dir of [sourceSkillPackDir, buildSkillPackDir]) {
    mkdirSync(dir, { recursive: true });
    writeFileSync(path.join(dir, "SKILL.md"), skillMd);
  }
});

test.afterAll(() => {
  for (const dir of [sourceSkillPackDir, buildSkillPackDir]) {
    rmSync(dir, { recursive: true, force: true });
  }
});

type Frame = Record<string, unknown>;

// Mirrors apps/loan_actor/test/ag_ui/encoder_test.exs's own snapshot
// assertions, one entry per reachable wire shape (see moduledoc above for
// the five that are structurally unreachable live and excluded here).
const EXPECTED_KEYS: Record<string, string[]> = {
  RunStarted: ["loan_id", "run_id", "thread_id", "type"],
  StateSnapshot: ["loan_id", "state", "type"],
  StateDelta: ["loan_id", "patch", "type"],
  "CustomEvent:diary_entry": ["entry", "loan_id", "name", "type"],
  "CustomEvent:hitl_request": ["loan_id", "name", "request", "type"],
  "CustomEvent:hitl_conflict": ["loan_id", "name", "request_id", "type"],
  ToolCallStart: ["loan_id", "tool_call_id", "tool_call_name", "type"],
  ToolCallArgs: ["delta", "tool_call_id", "type"],
  ToolCallEnd: ["tool_call_id", "type"],
  ToolCallResult: ["content", "message_id", "tool_call_id", "type"],
};

const EXPECTED_STATE_KEYS = ["context", "goals", "last_heartbeat_at", "loan_id", "status", "version"];
const EXPECTED_DIARY_ENTRY_KEYS = ["actor", "loan_id", "payload_hash", "payload_ref", "prev_hash", "sequence", "timestamp", "type"];
const EXPECTED_HITL_REQUEST_KEYS = ["created_at", "loan_id", "options", "prompt", "request_id"];

function frameKind(frame: Frame): string {
  return frame.type === "CustomEvent" ? `CustomEvent:${frame.name as string}` : (frame.type as string);
}

function assertShape(frame: Frame) {
  const kind = frameKind(frame);
  const expected = EXPECTED_KEYS[kind];
  expect(expected, `no expected key set registered for observed frame kind ${kind}`).toBeDefined();
  expect(Object.keys(frame).sort()).toEqual(expected);

  if (frame.type === "StateSnapshot") {
    expect(Object.keys(frame.state as Frame).sort()).toEqual(EXPECTED_STATE_KEYS);
  } else if (kind === "CustomEvent:diary_entry") {
    expect(Object.keys(frame.entry as Frame).sort()).toEqual(EXPECTED_DIARY_ENTRY_KEYS);
  } else if (kind === "CustomEvent:hitl_request") {
    expect(Object.keys(frame.request as Frame).sort()).toEqual(EXPECTED_HITL_REQUEST_KEYS);
  }
}

async function openStream(loanId: string) {
  const controller = new AbortController();

  const response = await fetch(`${BASE_URL}/loans/${encodeURIComponent(loanId)}/ag-ui`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
    body: JSON.stringify({ thread_id: null, since_sequence: null }),
    signal: controller.signal,
  });

  if (!response.ok || !response.body) {
    throw new Error(`ag-ui stream request failed: HTTP ${response.status}`);
  }

  return { reader: response.body.getReader(), controller };
}

// Reads frames onto `frames` (mutated in place, so callers keep every
// frame seen across multiple calls) until `until(frames)` is satisfied or
// `timeoutMs` elapses.
async function readUntil(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  frames: Frame[],
  until: (frames: Frame[]) => boolean,
  timeoutMs = 15_000,
): Promise<void> {
  const decoder = new TextDecoder();
  let buffer = "";
  const deadline = Date.now() + timeoutMs;

  while (!until(frames)) {
    if (Date.now() >= deadline) {
      throw new Error(`timed out waiting for frames; have kinds: ${frames.map(frameKind).join(", ")}`);
    }

    const { value, done } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const parts = buffer.split("\n\n");
    buffer = parts.pop() ?? "";

    for (const part of parts) {
      const line = part.trim();
      if (!line.startsWith("data: ")) continue;
      frames.push(JSON.parse(line.slice("data: ".length)));
    }
  }
}

async function postJson(pathname: string, body: unknown, headers: Record<string, string> = {}) {
  const response = await fetch(`${BASE_URL}${pathname}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });

  return { status: response.status, body: (await response.json()) as Record<string, unknown> };
}

test("the live AG-UI wire stream matches the backend's own pinned event shapes (contract)", async () => {
  const spawned = await postJson("/loans", {});
  expect(spawned.status).toBe(201);
  const loanId = spawned.body.loan_id as string;

  const { reader, controller } = await openStream(loanId);
  const frames: Frame[] = [];

  try {
    // ---- RunStarted -> StateSnapshot, first two frames, in order ----
    await readUntil(reader, frames, (f) => f.length >= 2);
    expect(frames[0]?.type).toBe("RunStarted");
    expect(frames[1]?.type).toBe("StateSnapshot");

    // ---- goal_set drives the reactive transition AND (maybe_trigger_planning)
    // the planning loop, which matches the temp pack (its description
    // contains "plan", the planning loop's own event_type) and invokes
    // request_operator_approval ----
    const sent = await postJson(`/loans/${encodeURIComponent(loanId)}/events`, {
      event_id: "contract-test-goal-set",
      source: "operator",
      type: "goal_set",
      payload: {},
      created_at: new Date().toISOString(),
    });
    expect(sent.status).toBe(202);

    await readUntil(reader, frames, (f) => f.some((frame) => frameKind(frame) === "CustomEvent:hitl_request"));

    // ---- ordering: every StateDelta is immediately preceded by its own
    // CustomEvent diary_entry (ag-ui-events.md's own ordering guarantee) ----
    frames.forEach((frame, index) => {
      if (frame.type === "StateDelta") {
        expect(index).toBeGreaterThan(0);
        const previous = frames[index - 1];
        expect(previous && frameKind(previous)).toBe("CustomEvent:diary_entry");
      }
    });

    // ---- the request_operator_approval invocation: Start -> Args -> End,
    // then hitl_request, with NO ToolCallResult yet (deferred) ----
    const startIndex = frames.findIndex((f) => f.type === "ToolCallStart" && f.tool_call_name === "request_operator_approval");
    expect(startIndex).toBeGreaterThanOrEqual(0);
    const invocationId = frames[startIndex]?.tool_call_id as string;

    const argsIndex = frames.findIndex((f, i) => i > startIndex && f.type === "ToolCallArgs" && f.tool_call_id === invocationId);
    const endIndex = frames.findIndex((f, i) => i > argsIndex && f.type === "ToolCallEnd" && f.tool_call_id === invocationId);
    const hitlRequestIndex = frames.findIndex(
      (f, i) => i > endIndex && frameKind(f) === "CustomEvent:hitl_request" && (f.request as Frame).request_id === invocationId,
    );

    expect(argsIndex).toBeGreaterThan(startIndex);
    expect(endIndex).toBeGreaterThan(argsIndex);
    expect(hitlRequestIndex).toBeGreaterThan(endIndex);

    const resultBeforeResponse = frames.find((f) => f.type === "ToolCallResult" && f.tool_call_id === invocationId);
    expect(resultBeforeResponse, "ToolCallResult must stay deferred until respond_hitl — contract's own HITL semantics").toBeUndefined();

    // ---- first response resolves the deferred ToolCallResult ----
    const firstResponse = await postJson(
      `/loans/${encodeURIComponent(loanId)}/hitl/${encodeURIComponent(invocationId)}`,
      { decision: "approve" },
      { "x-operator-id": "contract-test-operator-1" },
    );
    expect(firstResponse.status).toBe(200);

    await readUntil(reader, frames, (f) => f.some((frame) => frame.type === "ToolCallResult" && frame.tool_call_id === invocationId));

    const resultIndex = frames.findIndex((f) => f.type === "ToolCallResult" && f.tool_call_id === invocationId);
    expect(resultIndex).toBeGreaterThan(hitlRequestIndex);

    // ---- second response for the SAME request is a conflict, not a
    // second ToolCallResult (ag-ui-events.md's hitl_conflict row) ----
    const secondResponse = await postJson(
      `/loans/${encodeURIComponent(loanId)}/hitl/${encodeURIComponent(invocationId)}`,
      { decision: "reject" },
      { "x-operator-id": "contract-test-operator-2" },
    );
    expect(secondResponse.status).toBe(409);

    await readUntil(
      reader,
      frames,
      (f) => f.some((frame) => frameKind(frame) === "CustomEvent:hitl_conflict" && frame.request_id === invocationId),
    );

    const resultFramesForInvocation = frames.filter((f) => f.type === "ToolCallResult" && f.tool_call_id === invocationId);
    expect(resultFramesForInvocation).toHaveLength(1);

    // ---- every frame observed (scripted + ambient heartbeat activity),
    // of every kind this test knows how to check, matches the backend's
    // own pinned shape exactly ----
    for (const frame of frames) {
      if (frameKind(frame) in EXPECTED_KEYS) {
        assertShape(frame);
      }
    }
  } finally {
    controller.abort();
  }
});
