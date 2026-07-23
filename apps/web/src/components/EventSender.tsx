import { useState, type FormEvent } from "react";

export interface EventSentResult {
  result: "ok" | "duplicate";
  sequence: number;
}

export interface EventSenderProps {
  loanId: string;
  baseUrl?: string;
  onSent?: (result: EventSentResult) => void;
  onError?: (message: string) => void;
}

/**
 * The closed event-type enum (`LoanActor.Event.event_types/0`,
 * `contracts/loan-actor-api.md`) — kept in sync manually since the
 * backend doesn't publish it as a fetchable resource.
 */
const EVENT_TYPES = [
  "goal_set",
  "document_uploaded",
  "document_review_requested",
  "operator_approval_required",
  "operator_approval_granted",
  "operator_approval_denied",
  "goal_satisfied",
  "goal_abandoned",
  "complete",
  "abort",
  "heartbeat",
] as const;

/** FT-032 — a form posting `POST /loans/:loan_id/events` directly. */
export function EventSender({ loanId, baseUrl = "", onSent, onError }: EventSenderProps) {
  const [eventType, setEventType] = useState<string>(EVENT_TYPES[0]);
  const [sending, setSending] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSending(true);

    try {
      const response = await fetch(`${baseUrl}/loans/${encodeURIComponent(loanId)}/events`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          event_id: crypto.randomUUID(),
          source: "operator",
          type: eventType,
          payload: {},
          created_at: new Date().toISOString(),
        }),
      });

      const body = (await response.json()) as { result?: string; sequence?: number; error?: string };

      if (response.ok && body.result && typeof body.sequence === "number") {
        onSent?.({ result: body.result as "ok" | "duplicate", sequence: body.sequence });
      } else {
        onError?.(body.error ?? `HTTP ${response.status}`);
      }
    } catch (error) {
      onError?.(error instanceof Error ? error.message : String(error));
    } finally {
      setSending(false);
    }
  }

  return (
    <form aria-label="Send event" onSubmit={handleSubmit}>
      <label htmlFor="event-type-select">Event type</label>
      <select id="event-type-select" value={eventType} onChange={(event) => setEventType(event.target.value)}>
        {EVENT_TYPES.map((type) => (
          <option key={type} value={type}>
            {type}
          </option>
        ))}
      </select>
      <button type="submit" disabled={sending}>
        {sending ? "Sending…" : "Send event"}
      </button>
    </form>
  );
}
