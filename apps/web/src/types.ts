/**
 * TypeScript mirror of `specs/001-loan-actor-foundation/contracts/ag-ui-events.md`
 * (FT-031). This file — not prose — is what `ag-ui-client.ts` (FT-030) and
 * every consumer type-check against; the contract doc is normative, this is
 * its TS shape. 15 event rows, 13 distinct `type` values (`CustomEvent` has
 * three `name`-discriminated variants; the four ToolCall events were added
 * by intent 0004).
 */

export type GoalStatus = "open" | "satisfied" | "abandoned";

export interface Goal {
  goal_id: string;
  description: string;
  status: GoalStatus;
  due_at: string | null;
}

/** Mirrors `LoanActor.AGUI.Encoder.state_as_json/1`'s output shape. */
export interface LoanState {
  loan_id: string;
  status: string;
  goals: Goal[];
  context: Record<string, unknown>;
  version: number;
  last_heartbeat_at: string | null;
}

/** Mirrors `LoanActor.AGUI.Encoder.entry_as_json/1`'s output shape. */
export interface DiaryEntry {
  loan_id: string;
  sequence: number;
  timestamp: string;
  type: string;
  actor: string;
  payload_hash: string;
  payload_ref: string | null;
  prev_hash: string;
}

/** Mirrors `LoanActor.AGUI.Encoder.hitl_request_as_json/1`'s output shape. */
export interface HITLRequest {
  request_id: string;
  loan_id: string;
  prompt: string;
  options: string[];
  created_at: string | null;
}

/** RFC 6902 JSON Patch operation, as emitted by `StateDelta`. */
export interface JSONPatchOp {
  op: string;
  path: string;
  value?: unknown;
}

// ---- Lifecycle ----

export interface RunStartedEvent {
  type: "RunStarted";
  run_id: string;
  thread_id: string | null;
  loan_id: string;
}

export interface RunFinishedEvent {
  type: "RunFinished";
  run_id: string;
}

export interface RunErrorEvent {
  type: "RunError";
  run_id: string;
  message: string;
  code: unknown;
}

// ---- State ----

export interface StateSnapshotEvent {
  type: "StateSnapshot";
  loan_id: string;
  state: LoanState;
}

export interface StateDeltaEvent {
  type: "StateDelta";
  loan_id: string;
  patch: JSONPatchOp[];
}

// ---- Text messages ----

export interface TextMessageStartEvent {
  type: "TextMessageStart";
  message_id: string;
  role: "assistant";
}

export interface TextMessageContentEvent {
  type: "TextMessageContent";
  message_id: string;
  delta: string;
}

export interface TextMessageEndEvent {
  type: "TextMessageEnd";
  message_id: string;
}

// ---- Custom events (name-discriminated) ----

export interface DiaryEntryCustomEvent {
  type: "CustomEvent";
  name: "diary_entry";
  loan_id: string;
  entry: DiaryEntry;
}

export interface HitlRequestCustomEvent {
  type: "CustomEvent";
  name: "hitl_request";
  loan_id: string;
  request: HITLRequest;
}

export interface HitlConflictCustomEvent {
  type: "CustomEvent";
  name: "hitl_conflict";
  loan_id: string;
  request_id: string;
}

export type CustomEvent = DiaryEntryCustomEvent | HitlRequestCustomEvent | HitlConflictCustomEvent;

// ---- Tool calls (0004) ----

export interface ToolCallStartEvent {
  type: "ToolCallStart";
  tool_call_id: string;
  tool_call_name: string;
  loan_id: string;
}

export interface ToolCallArgsEvent {
  type: "ToolCallArgs";
  tool_call_id: string;
  /** PII-redacted args, pre-encoded as a JSON string by the backend. */
  delta: string;
}

export interface ToolCallEndEvent {
  type: "ToolCallEnd";
  tool_call_id: string;
}

export interface ToolCallResultEvent {
  type: "ToolCallResult";
  message_id: string;
  tool_call_id: string;
  /** Result or error shape, pre-encoded as a JSON string by the backend. */
  content: string;
}

/** The full 15-member discriminated union — the foundation AG-UI event set. */
export type AGUIEvent =
  | RunStartedEvent
  | StateSnapshotEvent
  | StateDeltaEvent
  | TextMessageStartEvent
  | TextMessageContentEvent
  | TextMessageEndEvent
  | CustomEvent
  | ToolCallStartEvent
  | ToolCallArgsEvent
  | ToolCallEndEvent
  | ToolCallResultEvent
  | RunFinishedEvent
  | RunErrorEvent;

/** Every `type` value a strict consumer accepts — anything else is rejected. */
export const AG_UI_EVENT_TYPES = [
  "RunStarted",
  "StateSnapshot",
  "StateDelta",
  "TextMessageStart",
  "TextMessageContent",
  "TextMessageEnd",
  "CustomEvent",
  "ToolCallStart",
  "ToolCallArgs",
  "ToolCallEnd",
  "ToolCallResult",
  "RunFinished",
  "RunError",
] as const;

export type AGUIEventType = (typeof AG_UI_EVENT_TYPES)[number];
