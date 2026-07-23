defmodule LoanActor.Tools.EvaluateGate do
  @moduledoc """
  Gate evaluation (intent 0003, ADH-004; `contracts/gate-behaviour.md`).

  The `%LoanActor.Gate{}` to evaluate arrives via `ctx.gate` — resolved
  and per-loan-version-pinned by the Server BEFORE invocation (FR-011,
  `gate-behaviour.md` invariant 8: "version pinning is a Server-level
  concern, not this tool's"), not derived from `args`. `args["gate_id"]`
  is required and MUST match `ctx.gate.gate_id` — a defensive check
  against the Server ever resolving the wrong gate for this invocation,
  not a normal-path branch.

  The assessment input is derived fresh via
  `LoanActor.Assessment.derive_from_state/1` — the SAME pure function
  `assess_loan` itself wraps — rather than threaded through `args`: both
  calls are deterministic functions of the same state snapshot within one
  loop pass, so they always agree, and this avoids embedding a complex
  nested struct in a tool-args map (`contracts/tool-behaviour.md`'s
  JSON-schema subset is deliberately flat).
  """

  @behaviour LoanActor.Tool

  alias LoanActor.Assessment
  alias LoanActor.Gate
  alias LoanActor.Tool.Spec

  @impl LoanActor.Tool
  def spec do
    Spec.new(%{
      name: "evaluate_gate",
      description: "Evaluate a named gate's rule against the current assessment.",
      parameters: %{
        "type" => "object",
        "properties" => %{"gate_id" => %{"type" => "string"}},
        "required" => ["gate_id"]
      }
    })
  end

  @impl LoanActor.Tool
  def execute(%{"gate_id" => gate_id}, ctx) do
    case ctx.gate do
      %Gate{gate_id: ^gate_id} = gate ->
        assessment = Assessment.derive_from_state(ctx.state)
        {outcome, cause} = Gate.evaluate(gate, %{assessment: assessment, state: ctx.state})

        {:ok,
         %{
           gate_outcome: %{
             gate_id: gate.gate_id,
             gate_version: gate.version,
             outcome: outcome,
             cause: cause
           }
         }}

      _mismatch_or_missing ->
        {:error, {:gate_not_resolved, gate_id}}
    end
  end
end
