import { AG_UI_EVENT_TYPES, type AGUIEvent, type AGUIEventType } from "../types";

/**
 * Typed SSE consumer for `POST /loans/:loan_id/ag-ui`
 * (`specs/001-loan-actor-foundation/contracts/ag-ui-events.md`, FT-030).
 * Implements the consumer pattern from
 * `.claude/skills/copilotkit/references/ag-ui-protocol.md`'s "Minimal
 * consumer (TypeScript)" section: buffer bytes, split on the SSE
 * double-newline frame terminator, strip the `data: ` prefix, `JSON.parse`.
 *
 * Strict rejection: any frame whose `type` isn't one of this contract's 13
 * known values is a protocol violation, not something to silently drop —
 * `onUnknownEvent` is REQUIRED precisely so a caller can't accidentally
 * swallow it. Malformed frames (not valid JSON, missing a `type` field) are
 * the same class of violation and go through the same callback.
 *
 * Deferred HITL result: `ToolCallEnd` and its `ToolCallResult` for the
 * `request_operator_approval` tool may have arbitrarily many other events
 * (including other tools' complete Start/Args/End/Result sequences)
 * interleaved between them — this consumer imposes no ordering
 * constraints across different `tool_call_id`s, so that interleaving needs
 * no special handling here.
 */

export interface AGUIClientHandlers {
  /** A structurally valid, known-type event. */
  onEvent(event: AGUIEvent): void;
  /** A frame whose `type` isn't one of the 13 known values, or that isn't a JSON object with a `type` field at all. */
  onUnknownEvent(raw: unknown): void;
  /** Network/stream-level failure (fetch rejected, non-2xx response, reader error). */
  onError?(error: Error): void;
}

export interface AGUIClientOptions {
  loanId: string;
  threadId?: string;
  sinceSequence?: number | null;
  baseUrl?: string;
  fetchImpl?: typeof fetch;
  signal?: AbortSignal;
}

const SSE_FRAME_SEPARATOR = "\n\n";
const SSE_DATA_PREFIX = "data: ";

/**
 * Parse raw SSE bytes into individual `data:` payload strings. Pure and
 * stream-agnostic — the same logic backs both the recorded-stream tests
 * (a synthetic `ReadableStream`) and a live `fetch` response body.
 */
export async function* parseSSEDataLines(
  reader: ReadableStreamDefaultReader<Uint8Array>,
): AsyncGenerator<string> {
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const frames = buffer.split(SSE_FRAME_SEPARATOR);
    buffer = frames.pop() ?? "";

    for (const frame of frames) {
      const line = frame.trim();
      if (line.length === 0) continue;
      if (!line.startsWith(SSE_DATA_PREFIX)) continue;
      yield line.slice(SSE_DATA_PREFIX.length);
    }
  }

  const trailing = buffer.trim();
  if (trailing.startsWith(SSE_DATA_PREFIX)) {
    yield trailing.slice(SSE_DATA_PREFIX.length);
  }
}

function isKnownEventType(value: unknown): value is AGUIEventType {
  return typeof value === "string" && (AG_UI_EVENT_TYPES as readonly string[]).includes(value);
}

/**
 * Validate a single parsed JSON payload against the 13 known `type`
 * values. Only checks the discriminant — per-event field shape is the
 * backend's own contract obligation (pinned by
 * `apps/loan_actor/test/ag_ui/encoder_test.exs`), not re-validated here.
 */
export function isAGUIEvent(payload: unknown): payload is AGUIEvent {
  return (
    typeof payload === "object" &&
    payload !== null &&
    "type" in payload &&
    isKnownEventType((payload as { type: unknown }).type)
  );
}

/**
 * Consume the AG-UI SSE stream for `loanId`, dispatching each parsed
 * frame to `handlers`. Resolves when the stream ends (`RunFinished`/
 * `RunError` or the underlying connection closing); never resolves on
 * its own for a live, still-open subscription — callers drive lifetime
 * via `options.signal`.
 */
export async function consumeAGUIStream(
  options: AGUIClientOptions,
  handlers: AGUIClientHandlers,
): Promise<void> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const baseUrl = options.baseUrl ?? "";
  const url = `${baseUrl}/loans/${encodeURIComponent(options.loanId)}/ag-ui`;

  let response: Response;

  try {
    response = await fetchImpl(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
      body: JSON.stringify({
        thread_id: options.threadId ?? null,
        since_sequence: options.sinceSequence ?? null,
      }),
      signal: options.signal,
    });
  } catch (error) {
    handlers.onError?.(error instanceof Error ? error : new Error(String(error)));
    return;
  }

  if (!response.ok || !response.body) {
    handlers.onError?.(new Error(`AG-UI stream request failed: HTTP ${response.status}`));
    return;
  }

  const reader = response.body.getReader();

  try {
    for await (const dataLine of parseSSEDataLines(reader)) {
      let parsed: unknown;

      try {
        parsed = JSON.parse(dataLine);
      } catch {
        handlers.onUnknownEvent(dataLine);
        continue;
      }

      if (isAGUIEvent(parsed)) {
        handlers.onEvent(parsed);
      } else {
        handlers.onUnknownEvent(parsed);
      }
    }
  } catch (error) {
    handlers.onError?.(error instanceof Error ? error : new Error(String(error)));
  }
}
