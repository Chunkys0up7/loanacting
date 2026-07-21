# Contract — `LoanActor.Tool` behaviour

*(Added by intent 0004.)* Every self-initiated actor function is a tool: a compiled module
implementing this behaviour, enumerated by the config-driven registry. Test-pinned by a
shared behaviour suite run against **every** registered tool (mirrors
`diary-store-behaviour.md` / `shared_behaviour_test.exs`).

```elixir
defmodule LoanActor.Tool do
  @moduledoc "A typed, individually invokable, deterministic actor function."

  @callback spec() :: LoanActor.Tool.Spec.t()
  # %Tool.Spec{name: String.t, description: String.t, parameters: map()}
  # `parameters` is a JSON-Schema map restricted to the foundation subset below.

  @callback execute(args :: map(), ctx :: LoanActor.Tool.Context.t()) ::
              {:ok, effects :: map()}
              | {:pending, correlation_id :: String.t()}
              | {:error, term()}
  # `{:pending, id}` is reserved for tools whose result arrives later (foundation:
  # only `request_operator_approval`). Everything else returns synchronously.
end
```

`%LoanActor.Tool.Context{}` carries: `loan_id`, `state` (current `%LoanActor.State{}`),
`loop` (`:periodic | :planning`), `actor` (operator id or `"system"`),
`invocation_id` (UUIDv7 — becomes the AG-UI `tool_call_id`).

## JSON-schema subset (HARD CAP)

`parameters` may use **only**: `type` (`"object" | "string" | "integer" | "boolean" |
"array"`), `properties`, `required`, `enum`. `LoanActor.Tool.Spec.validate_args/2`
implements exactly this subset. Extending the subset (formats, refs, nested combinators)
requires an amendment intent — this cap is the same discipline as intent 0003's rule-DSL cap.

## Invariants every tool and the registry MUST uphold

1. **Determinism** — `execute/2` is a pure function of `(args, ctx)`. Effects are *returned*
   (e.g. `%{transition: event, goals: [...], emit: [...]}`), never applied inside the tool.
   The Server applies effects through `State.transition/2` and the diary pipeline. This is
   what makes tool invocations replay-stable and keeps the `NoDirectStateMutation` Credo
   check meaningful.
2. **Zero LLM** — foundation tools are deterministic code (SC-009 grep covers
   `lib/loan_actor/tools/`). The first non-deterministic tool arrives with intent 0003
   behind the escalation gate.
3. **PII order of operations** — the registry passes args through `PIIGuard` **before**
   (a) hashing for the diary payload and (b) inclusion in `ToolCallArgs`. Tools receive the
   redacted form.
4. **Diary discipline** — every invocation appends `:tool_invoked` before execution and
   `:tool_completed` (or `:tool_failed`) after; payload carries tool name, invocation_id,
   redacted-args hash, and (on completion) result hash.
5. **Args validation** — `Registry.invoke/3` validates args against `spec().parameters`
   BEFORE execution; invalid args → `{:error, {:invalid_args, details}}`, diary
   `:tool_failed`, full ToolCall sequence still emitted (result carries the error).
6. **No routing in code** — neither the registry nor any tool module contains
   trigger/matching/selection logic. When-to-use lives in skill content (Principle VI/VIII).

## Registry

`LoanActor.Tool.Registry` reads the tool module list from `config :loan_actor, :tools`.
API: `list/0 :: [Tool.Spec.t]`, `fetch/1 :: {:ok, module} | {:error, :unknown_tool}`,
`invoke/3 (name, args, ctx)`. Telemetry: `[:loan_actor, :tool, :start | :stop | :exception]`.
Tool invocation is **internal-only** — there is no public `invoke_tool` API on
`LoanActor` (see `loan-actor-api.md`).

## Foundation tool set (deterministic only)

| Tool name | Loop | Effect (returned, Server-applied) |
|---|---|---|
| `set_goal` | periodic | add `%Goal{}`; diary `:goal_set` |
| `satisfy_goal` | planning | mark goal `:satisfied`; diary `:goal_satisfied` |
| `request_document` | planning | outbound document request; payload in `ToolCallResult` |
| `transition_state` | loops | state change routed through `State.transition/2` |
| `append_note` | any | human-readable note → `TextMessage*` triplet |
| `request_operator_approval` | planning | `%HITLRequest{}` emission; returns `{:pending, request_id}`; `ToolCallResult` deferred to `respond_hitl` |
| `verify_diary_chain` | periodic | wraps `DiaryStore.verify_chain/1`; result in diary |

## Test pins

- Shared suite: `apps/loan_actor/test/support/tool_shared.ex`, instantiated per registered
  tool — spec shape, args validation (each subset keyword), determinism (same args+ctx →
  same result), effects-not-applied purity, diary pair, four ToolCall frames.
- Registry: `apps/loan_actor/test/tool/registry_test.exs` — unknown tool, config-driven
  list, telemetry, PII order of operations (synthetic PII in args → absent from frames and
  diary).
