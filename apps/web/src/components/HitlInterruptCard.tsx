import { useState } from "react";
import type { HITLRequest } from "../types";

export interface HitlInterruptCardProps {
  request: HITLRequest;
  loanId: string;
  baseUrl?: string;
  onResolved?: (decision: string) => void;
  onError?: (message: string) => void;
}

/**
 * FT-033 — renders one pending `%HITLRequest{}` (from the
 * `CustomEvent name="hitl_request"` frame, `contracts/ag-ui-events.md`)
 * as a prompt with one button per option, POSTing the operator's
 * decision directly to `POST /loans/:loan_id/hitl/:request_id`
 * (`contracts/http-endpoints.md`) — not through `respond()`, since
 * there is no real CopilotKit runtime/chat-tool call to resume (see
 * this file's own `useHumanInTheLoop` registration in `LoanView.tsx`
 * for why).
 */
export function HitlInterruptCard({ request, loanId, baseUrl = "", onResolved, onError }: HitlInterruptCardProps) {
  const [submitting, setSubmitting] = useState(false);

  async function respond(decision: string) {
    setSubmitting(true);

    try {
      const response = await fetch(
        `${baseUrl}/loans/${encodeURIComponent(loanId)}/hitl/${encodeURIComponent(request.request_id)}`,
        {
          method: "POST",
          // No real operator-auth system yet (out of scope) — identifies
          // responses as coming from this web UI rather than leaving
          // operator_id unset, which LoanActor.HITLResponse.new/1 requires
          // non-empty (config/dev.exs's require_operator_id: false means
          // OperatorPlug wouldn't otherwise supply one).
          headers: { "Content-Type": "application/json", "x-operator-id": "web-ui-operator" },
          body: JSON.stringify({ decision }),
        },
      );

      const body = (await response.json()) as { result?: string; error?: string };

      if (response.ok) {
        onResolved?.(decision);
      } else {
        onError?.(body.error ?? body.result ?? `HTTP ${response.status}`);
      }
    } catch (error) {
      onError?.(error instanceof Error ? error.message : String(error));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <li aria-label={`HITL request ${request.request_id}`}>
      <p>{request.prompt}</p>
      {request.options.map((option) => (
        <button key={option} type="button" disabled={submitting} onClick={() => respond(option)}>
          {option}
        </button>
      ))}
    </li>
  );
}
