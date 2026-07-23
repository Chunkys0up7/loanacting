defmodule LoanActor.Tools.TransitionState do
  @moduledoc """
  Requests a state transition (FT-043; any loop). Validates legality
  against `LoanActor.State.Model` (a pure read, no mutation) and returns
  the effect `%{transition: event_type}`; the Server applies it by calling
  `LoanActor.State.transition/2` for real. Returns
  `{:error, {:illegal_transition, from, event_type}}` if there is no legal
  edge — matching `contracts/loan-actor-api.md`'s documented error shape —
  so callers get a fast, side-effect-free rejection instead of a raised
  exception.
  """

  @behaviour LoanActor.Tool

  alias LoanActor.State.Model
  alias LoanActor.Tool.Spec

  @impl LoanActor.Tool
  def spec do
    Spec.new(%{
      name: "transition_state",
      description: "Advance the loan's state machine by an event type.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "event_type" => %{
            "type" => "string",
            "enum" => Enum.map(Model.event_types(), &Atom.to_string/1)
          }
        },
        "required" => ["event_type"]
      }
    })
  end

  @impl LoanActor.Tool
  def execute(%{"event_type" => event_type_string}, ctx) do
    # Safe: the schema's enum (validated before execute/2 runs) restricts
    # event_type_string to the 11 documented values, all of which already
    # exist as atoms (compiled into Model.event_types/0).
    event_type = String.to_existing_atom(event_type_string)
    from_status = current_status(ctx.state)

    if Model.legal?(from_status, event_type) do
      {:ok, %{transition: event_type}}
    else
      {:error, {:illegal_transition, from_status, event_type}}
    end
  end

  defp current_status(%{status: status}), do: status
  defp current_status(_state), do: nil
end
