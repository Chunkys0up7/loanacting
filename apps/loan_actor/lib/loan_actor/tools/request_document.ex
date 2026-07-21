defmodule LoanActor.Tools.RequestDocument do
  @moduledoc """
  Requests a document from the operator (FT-043; planning loop). Returns
  the effect `%{request: %{"doc_type" => ...}}` — the Server (FT-019) turns
  this into the `ToolCallResult` payload per spec.md SC-012 (0004's
  rewrite of the planning-loop emission onto this tool).
  """

  @behaviour LoanActor.Tool

  alias LoanActor.Tool.Spec

  @impl LoanActor.Tool
  def spec do
    Spec.new(%{
      name: "request_document",
      description: "Request a document from the operator.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "doc_type" => %{"type" => "string", "enum" => ["income", "identity", "appraisal"]}
        },
        "required" => ["doc_type"]
      }
    })
  end

  @impl LoanActor.Tool
  def execute(%{"doc_type" => doc_type}, _ctx) do
    {:ok, %{request: %{"doc_type" => doc_type}}}
  end
end
