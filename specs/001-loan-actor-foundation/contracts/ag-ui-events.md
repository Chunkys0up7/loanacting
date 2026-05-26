# Contract — AG-UI Events Emitted by `loan_actor`

The backend emits a subset of the 17 AG-UI events. **This document is the source of truth**; backend and frontend tests both pin against it. Drift = CI failure.

## Transport

- HTTP endpoint: `POST /loans/:loan_id/ag-ui`
- Request body: `{ "thread_id": "<optional>", "since_sequence": <int|null> }`
- Response: `text/event-stream`, one event per `data:` line per SSE convention; double-newline-terminated.

## Events emitted (foundation subset)

| Event | When | Payload (JSON keys) |
|---|---|---|
| `RunStarted` | On subscription open | `{type, run_id, thread_id, loan_id}` |
| `StateSnapshot` | First event after `RunStarted`; on subscriber resync | `{type, loan_id, state: <full %LoanActor.State{} as JSON>}` |
| `StateDelta` | On every state change | `{type, loan_id, patch: <RFC 6902 JSON Patch array>}` |
| `TextMessageStart` | When the loan emits a human-readable note (rare in foundation) | `{type, message_id, role: "assistant"}` |
| `TextMessageContent` | Streaming chunks | `{type, message_id, delta}` |
| `TextMessageEnd` | End of note | `{type, message_id}` |
| `CustomEvent` | Diary entry append (for live feed) | `{type, name: "diary_entry", loan_id, entry: <%DiaryEntry{} as JSON>}` |
| `CustomEvent` | HITL request | `{type, name: "hitl_request", loan_id, request: <%HITLRequest{}>}` |
| `CustomEvent` | HITL conflict (two responses) | `{type, name: "hitl_conflict", loan_id, request_id}` |
| `RunFinished` | Subscription closed normally | `{type, run_id}` |
| `RunError` | Subscription closed on error | `{type, run_id, message, code}` |

Events not emitted in foundation: `StepStarted`, `StepFinished`, `ToolCallStart`, `ToolCallArgs`, `ToolCallEnd`, `ToolCallResult`, `MessagesSnapshot`, `RawEvent`. Adding any requires an amendment intent.

## Ordering guarantees

- Per subscriber: `RunStarted` → `StateSnapshot` → (`StateDelta` | `CustomEvent` | `TextMessage*`)* → `RunFinished`.
- A `StateDelta` for sequence `N` is always preceded by the `CustomEvent diary_entry` for the same diary append. This lets clients render diary first, state second, without inconsistency.
- On subscriber resync (slow client), the stream restarts with a fresh `StateSnapshot`; previous deltas are not resent.

## Versioning

This contract's version follows the spec's version. Breaking changes to event shapes require a MAJOR bump of the spec.

## Test pins

- Backend: `apps/loan_actor/test/ag_ui/encoder_test.exs` — exhaustive coverage of each event's JSON shape, snapshotted.
- Frontend: `apps/web/test/ag-ui-client.test.ts` — typed consumer rejects any unknown event types (strict).
- Cross-stack: `apps/web/test/e2e/contract.spec.ts` — Playwright captures the live stream and diff-checks against the snapshots.
