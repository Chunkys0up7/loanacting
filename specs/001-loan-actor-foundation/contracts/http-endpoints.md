# Contract — HTTP Endpoints

Bandit-served Plug.Router. Four endpoints in foundation. All require the `x-operator-id` header in production; tests can disable.

## `POST /loans`

Spawn a loan.

**Request:**
```json
{ "loan_id": "L-001" }            // optional; server generates UUIDv7 if absent
```

**Response (201):**
```json
{ "loan_id": "L-001", "status": "spawned", "version": 0 }
```

Idempotent. Re-POSTing the same `loan_id` returns 200 with the current state.

## `POST /loans/:loan_id/events`

Send an event to a loan.

**Request:**
```json
{
  "event_id": "01HG...",
  "source": "operator",
  "type": "document_uploaded",
  "payload": { ... },
  "created_at": "2026-05-26T14:30:00Z"
}
```

**Response (202):**
```json
{ "result": "ok", "sequence": 42 }
```

Or:
```json
{ "result": "duplicate", "sequence": 42 }
```

**Errors:**
- 400 — invalid event struct.
- 422 — PII guard rejection (body lists redacted paths).
- 409 — illegal transition.

## `POST /loans/:loan_id/hitl/:request_id`

Respond to an HITL request.

**Request:**
```json
{ "decision": "approve", "comment": "looks good" }
```

**Response (200):**
```json
{ "result": "accepted" }
```

**Errors:**
- 409 `{ "result": "conflict", "existing_response": { ... } }` — already responded.

## `GET /loans/:loan_id/ag-ui`  (alias: `POST` with body)

Open the AG-UI SSE stream. See [`ag-ui-events.md`](ag-ui-events.md) for event shapes.

**Query params:** `since_sequence` (int) — replay from this sequence forward before going live.

**Response:** `text/event-stream`.

## Errors (all endpoints)

- 401 — missing `x-operator-id` (production only).
- 404 — loan not running (for `/events`, `/hitl`, `/ag-ui`).
- 500 — unhandled; body has `{ "request_id": "..." }` correlating to a server-side log.

## Test pins

- Backend: `apps/loan_actor/test/web/router_test.exs` (per endpoint).
- Frontend: `apps/web/test/ag-ui-client.test.ts` consumes the AG-UI endpoint against a running server.
- Playwright: end-to-end flows touch all four endpoints.
