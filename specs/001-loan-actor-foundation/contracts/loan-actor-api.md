# Contract — `LoanActor.Server` public API

The public API of a loan actor process. Everything else in `LoanActor.*` is implementation detail.

> **Tool invocation is internal-only** *(0004, normative)*: there is NO public
> `invoke_tool/3` (or equivalent). Tools are summoned by the loan's own loops
> (constitution Principle I — capabilities are summoned *by* the loan, never orchestrated
> over it). External callers influence the loan by sending events (`send_event/2`) and
> answering its questions (`respond_hitl/3`); the public surface below is unchanged by
> intent 0004.

## Spawn / lookup

```elixir
@spec spawn(loan_id :: String.t) :: {:ok, pid} | {:error, term}
LoanActor.spawn("L-001")
```

- Idempotent. If the loan is already running, returns `{:ok, existing_pid}`.
- Spawns under `LoanActor.Supervisor` (DynamicSupervisor, one-for-one).
- First diary entry on a fresh loan: `{type: :spawned, payload: %{loan_id: ..., spawned_at: ...}}`.

```elixir
@spec whereis(loan_id :: String.t) :: pid | nil
LoanActor.whereis("L-001")
```

## Send event

```elixir
@spec send_event(loan_id :: String.t, event :: %LoanActor.Event{}) ::
        {:ok, sequence :: non_neg_integer} | {:duplicate, sequence :: non_neg_integer} | {:error, term}
LoanActor.send_event("L-001", %Event{...})
```

- Idempotent on `(loan_id, event_id, source)`.
- `{:ok, sequence}` — accepted; diary entry at the given sequence.
- `{:duplicate, sequence}` — already seen; no append.
- `{:error, reason}` — invalid event (PII guard, illegal transition, validation).

## Inspect state

```elixir
@spec state(loan_id :: String.t) :: {:ok, %LoanActor.State{}} | {:error, :not_running}
LoanActor.state("L-001")
```

## Subscribe to AG-UI stream (Elixir-side)

```elixir
@spec subscribe(loan_id :: String.t, opts :: keyword) :: {:ok, ref} | {:error, term}
LoanActor.subscribe("L-001", since_sequence: nil)
```

- Returns a monitor ref. The caller receives `{:ag_ui_event, ref, event}` messages.
- Used internally by the HTTP layer to build SSE streams.

## HITL response

```elixir
@spec respond_hitl(loan_id, request_id :: String.t, response :: %LoanActor.HITLResponse{}) ::
        :ok | {:conflict, existing_response} | {:error, term}
LoanActor.respond_hitl("L-001", "req-...", %HITLResponse{...})
```

## Lifecycle errors

| Error | Meaning |
|---|---|
| `{:error, :not_running}` | No supervised actor for that `loan_id` (spawn first). |
| `{:error, {:illegal_transition, from, event_type}}` | Event would cause an undefined state transition. |
| `{:error, {:pii_violation, paths}}` | Event payload contained PII not allowed past the guard. |
| `{:error, :invalid_event}` | Event struct invariants violated. |

## Test pins

- `apps/loan_actor/test/server_test.exs` exercises each clause.
- Property-based tests assert idempotency and replay invariants against this API.
