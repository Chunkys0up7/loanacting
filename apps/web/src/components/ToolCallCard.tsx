import { isErrorResult, type ToolCallState } from "../lib/tool-calls";

export interface ToolCallCardProps {
  toolCall: ToolCallState;
}

/**
 * FT-045 — renders one correlated tool invocation (`ToolCallStart` →
 * `ToolCallArgs` → `ToolCallEnd` → `ToolCallResult`, correlated by
 * `tool_call_id` in `src/lib/tool-calls.ts`). Stays in its pending state
 * for as long as `result` is absent — including indefinitely for the
 * HITL tool, whose `ToolCallResult` is deferred until `respond_hitl/3`
 * (no special-casing needed here: "still pending" already covers it).
 */
export function ToolCallCard({ toolCall }: ToolCallCardProps) {
  const { toolCallName, status, result } = toolCall;

  if (status === "pending" || !result) {
    return (
      <li aria-label={`Tool call ${toolCallName}`} data-status="pending">
        <strong>{toolCallName}</strong> — pending…
      </li>
    );
  }

  const errorShaped = isErrorResult(result.content);

  return (
    <li aria-label={`Tool call ${toolCallName}`} data-status={errorShaped ? "error" : "complete"}>
      <strong>{toolCallName}</strong> — {errorShaped ? "failed" : "complete"}
      <pre>{result.content}</pre>
    </li>
  );
}
