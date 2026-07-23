defmodule LoanActor.Tools.AppendNote do
  @moduledoc """
  Appends a human-readable note (FT-043; any loop). Returns the effect
  `%{note: text}`; the Server turns this into a `TextMessageStart` →
  `TextMessageContent` → `TextMessageEnd` triplet over AG-UI (FT-023+).
  """

  @behaviour LoanActor.Tool

  alias LoanActor.Tool.Spec

  @impl LoanActor.Tool
  def spec do
    Spec.new(%{
      name: "append_note",
      description: "Append a human-readable note to the loan's activity stream.",
      parameters: %{
        "type" => "object",
        "properties" => %{"text" => %{"type" => "string"}},
        "required" => ["text"]
      }
    })
  end

  @impl LoanActor.Tool
  def execute(%{"text" => text}, _ctx), do: {:ok, %{note: text}}
end
