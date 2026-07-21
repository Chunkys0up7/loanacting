defmodule LoanActor.Tool do
  @moduledoc """
  Behaviour for the loan actor's self-initiated functions (FT-041, constitution
  Principle VIII, `contracts/tool-behaviour.md`).

  A tool is a typed, individually invokable, **deterministic** function:

  - `spec/0` describes it (`%LoanActor.Tool.Spec{}` — name, description,
    JSON-schema'd parameters, restricted subset).
  - `execute/2` is a pure function of `(args, ctx)`. It returns **effects** —
    it never mutates state, writes the diary, or emits events itself. The
    Server applies returned effects through `State.transition/2` and the diary
    pipeline (FT-017), which is what makes tool invocations replay-stable.

  `{:pending, correlation_id}` is reserved for tools whose result arrives
  later; in foundation only `request_operator_approval` (HITL) uses it — its
  AG-UI `ToolCallResult` is deferred until `respond_hitl/3`.

  Tools are enumerated by `LoanActor.Tool.Registry` (config-driven). Inbound
  event ingestion is NOT a tool call (clarifications Q11).
  """

  alias LoanActor.Tool.Context
  alias LoanActor.Tool.Spec

  @callback spec() :: Spec.t()

  @callback execute(args :: map(), ctx :: Context.t()) ::
              {:ok, effects :: map()}
              | {:pending, correlation_id :: String.t()}
              | {:error, term()}
end
