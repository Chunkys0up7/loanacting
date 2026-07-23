defmodule LoanActor.Tools.AssessLoan do
  @moduledoc """
  Deterministic assessment derivation (intent 0003, ADH-002; FR-001).

  Thin tool wrapper around `LoanActor.Assessment.derive_from_state/1` —
  see that function for the actual derivation logic and its purity
  invariant (`research.md` R-6). Producing the standalone `:assessment`
  diary entry is this tool's own job; the derivation itself is shared
  with `LoanActor.Tools.EvaluateGate` (ADH-004).
  """

  @behaviour LoanActor.Tool

  alias LoanActor.Assessment
  alias LoanActor.Tool.Spec

  @impl LoanActor.Tool
  def spec do
    Spec.new(%{
      name: "assess_loan",
      description: "Derive a deterministic assessment of the loan's current situation.",
      parameters: %{"type" => "object"}
    })
  end

  @impl LoanActor.Tool
  def execute(_args, ctx) do
    {:ok, %{assessment: Assessment.derive_from_state(ctx.state)}}
  end
end
