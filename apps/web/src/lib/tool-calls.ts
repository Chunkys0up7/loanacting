import type { AGUIEvent } from "../types";

export type ToolCallStatus = "pending" | "complete";

/** One tool invocation's frames correlated by `tool_call_id` (FT-045). */
export interface ToolCallState {
  toolCallId: string;
  toolCallName: string;
  loanId: string;
  /** `ToolCallArgs.delta` — PII-redacted args, pre-encoded as a JSON string by the backend. */
  argsDelta: string | null;
  /** Whether `ToolCallEnd` has been received (args are complete). */
  ended: boolean;
  status: ToolCallStatus;
  /** Set once `ToolCallResult` arrives — absent while `status` is `"pending"` (a HITL tool call may stay pending indefinitely, until `respond_hitl/3`). */
  result: { messageId: string; content: string } | null;
}

export type ToolCallsById = Record<string, ToolCallState>;

/**
 * Fold one AG-UI event into the correlated tool-call map. Pure and
 * side-effect-free — a non-ToolCall* event (or a ToolCall* event for an
 * unknown `tool_call_id`, for End/Args/Result) returns `state` unchanged
 * rather than throwing, since the contract explicitly allows other
 * events to interleave between one tool call's own frames (and, for the
 * HITL case, between its `ToolCallEnd` and deferred `ToolCallResult`) —
 * this reducer only ever touches the ONE entry an event names.
 */
export function applyToolCallEvent(state: ToolCallsById, event: AGUIEvent): ToolCallsById {
  switch (event.type) {
    case "ToolCallStart":
      return {
        ...state,
        [event.tool_call_id]: {
          toolCallId: event.tool_call_id,
          toolCallName: event.tool_call_name,
          loanId: event.loan_id,
          argsDelta: null,
          ended: false,
          status: "pending",
          result: null,
        },
      };

    case "ToolCallArgs": {
      const existing = state[event.tool_call_id];
      if (!existing) return state;
      return { ...state, [event.tool_call_id]: { ...existing, argsDelta: event.delta } };
    }

    case "ToolCallEnd": {
      const existing = state[event.tool_call_id];
      if (!existing) return state;
      return { ...state, [event.tool_call_id]: { ...existing, ended: true } };
    }

    case "ToolCallResult": {
      const existing = state[event.tool_call_id];
      if (!existing) return state;
      return {
        ...state,
        [event.tool_call_id]: {
          ...existing,
          status: "complete",
          result: { messageId: event.message_id, content: event.content },
        },
      };
    }

    default:
      return state;
  }
}

/** Whether a completed result's content decodes to an `{"error": ...}` shape. */
export function isErrorResult(content: string): boolean {
  try {
    const parsed: unknown = JSON.parse(content);
    return typeof parsed === "object" && parsed !== null && "error" in parsed;
  } catch {
    return false;
  }
}
