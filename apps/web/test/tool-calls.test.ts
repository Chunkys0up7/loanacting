import { describe, expect, it } from "vitest";
import { applyToolCallEvent, isErrorResult, type ToolCallsById } from "../src/lib/tool-calls";
import type { AGUIEvent } from "../src/types";

function fold(events: AGUIEvent[]): ToolCallsById {
  return events.reduce(applyToolCallEvent, {} as ToolCallsById);
}

describe("applyToolCallEvent — happy", () => {
  it("correlates a full Start/Args/End/Result sequence by tool_call_id", () => {
    const events: AGUIEvent[] = [
      { type: "ToolCallStart", tool_call_id: "inv-1", tool_call_name: "request_document", loan_id: "L-1" },
      { type: "ToolCallArgs", tool_call_id: "inv-1", delta: '{"doc_type":"income"}' },
      { type: "ToolCallEnd", tool_call_id: "inv-1" },
      { type: "ToolCallResult", message_id: "msg-1", tool_call_id: "inv-1", content: '{"request":{"doc_type":"income"}}' },
    ];

    const result = fold(events);

    expect(result["inv-1"]).toEqual({
      toolCallId: "inv-1",
      toolCallName: "request_document",
      loanId: "L-1",
      argsDelta: '{"doc_type":"income"}',
      ended: true,
      status: "complete",
      result: { messageId: "msg-1", content: '{"request":{"doc_type":"income"}}' },
    });
  });

  it("keeps two different tool_call_ids fully independent when interleaved", () => {
    const events: AGUIEvent[] = [
      { type: "ToolCallStart", tool_call_id: "inv-1", tool_call_name: "verify_diary_chain", loan_id: "L-1" },
      { type: "ToolCallStart", tool_call_id: "inv-2", tool_call_name: "request_operator_approval", loan_id: "L-1" },
      { type: "ToolCallArgs", tool_call_id: "inv-2", delta: '{"prompt":"Approve?","options":["approve","reject"]}' },
      { type: "ToolCallArgs", tool_call_id: "inv-1", delta: "{}" },
      { type: "ToolCallEnd", tool_call_id: "inv-2" },
      { type: "ToolCallEnd", tool_call_id: "inv-1" },
      { type: "ToolCallResult", message_id: "msg-1", tool_call_id: "inv-1", content: '{"verify_chain":true}' },
      // inv-2 (the HITL tool) has no Result yet — still pending.
    ];

    const result = fold(events);

    expect(result["inv-1"]?.status).toBe("complete");
    expect(result["inv-2"]?.status).toBe("pending");
    expect(result["inv-2"]?.ended).toBe(true);
    expect(result["inv-2"]?.result).toBeNull();
  });
});

describe("applyToolCallEvent — boundary", () => {
  it("stays pending (no result) until ToolCallResult arrives — a long-lived HITL tool call", () => {
    const events: AGUIEvent[] = [
      { type: "ToolCallStart", tool_call_id: "inv-1", tool_call_name: "request_operator_approval", loan_id: "L-1" },
      { type: "ToolCallArgs", tool_call_id: "inv-1", delta: '{"prompt":"Approve?","options":["approve","reject"]}' },
      { type: "ToolCallEnd", tool_call_id: "inv-1" },
    ];

    const result = fold(events);

    expect(result["inv-1"]?.status).toBe("pending");
    expect(result["inv-1"]?.ended).toBe(true);
    expect(result["inv-1"]?.result).toBeNull();
  });

  it("is a no-op for a non-ToolCall event", () => {
    const state: ToolCallsById = {};
    const result = applyToolCallEvent(state, { type: "RunFinished", run_id: "run-1" });
    expect(result).toBe(state);
  });

  it("is a no-op for ToolCallArgs/End/Result naming an unknown tool_call_id", () => {
    const state: ToolCallsById = {};
    const afterArgs = applyToolCallEvent(state, { type: "ToolCallArgs", tool_call_id: "ghost", delta: "{}" });
    const afterEnd = applyToolCallEvent(state, { type: "ToolCallEnd", tool_call_id: "ghost" });
    const afterResult = applyToolCallEvent(state, {
      type: "ToolCallResult",
      message_id: "m",
      tool_call_id: "ghost",
      content: "{}",
    });

    expect(afterArgs).toBe(state);
    expect(afterEnd).toBe(state);
    expect(afterResult).toBe(state);
  });
});

describe("isErrorResult", () => {
  it("recognizes an error-shaped result", () => {
    expect(isErrorResult('{"error":"goal_not_found"}')).toBe(true);
  });

  it("recognizes a success-shaped result", () => {
    expect(isErrorResult('{"verify_chain":true}')).toBe(false);
  });

  it("treats malformed content as not error-shaped (boundary)", () => {
    expect(isErrorResult("not json")).toBe(false);
  });
});
