defmodule LoanActor.Tools.RequestOperatorApproval do
  @moduledoc """
  Requests operator approval — the HITL tool (FT-043; planning loop).
  Returns `{:pending, ctx.invocation_id}` per `contracts/tool-behaviour.md`
  and constitution Principle VIII: its `ToolCallResult` is deferred until
  `respond_hitl/3` (FT-028) delivers the operator's decision.

  `ctx.invocation_id` doubles as the `%LoanActor.HITLRequest{}.request_id`
  — one id correlates the AG-UI tool_call AND the HITL request, since both
  describe the SAME pending question.
  """

  @behaviour LoanActor.Tool

  alias LoanActor.Tool.Spec

  @impl LoanActor.Tool
  def spec do
    Spec.new(%{
      name: "request_operator_approval",
      description: "Ask the operator to approve or reject, pausing the planning loop.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "prompt" => %{"type" => "string"},
          "options" => %{"type" => "array"}
        },
        "required" => ["prompt", "options"]
      }
    })
  end

  @impl LoanActor.Tool
  def execute(%{"prompt" => _prompt, "options" => options}, ctx) when is_list(options) do
    {:pending, ctx.invocation_id}
  end
end
