defmodule LoanActor.IllegalTransitionError do
  @moduledoc """
  Raised by `LoanActor.State.transition/2` when `{from, event_type}` has no
  edge in `LoanActor.State.Model` (FT-011).

  Carries `from` and `event_type` so the Server (FT-017) can wrap it into
  the documented `{:error, {:illegal_transition, from, event_type}}` shape
  (`contracts/loan-actor-api.md`) and append the `:illegal_transition_attempted`
  diary entry (`data-model.md`).
  """

  defexception [:from, :event_type]

  @impl true
  def message(%{from: from, event_type: event_type}) do
    "illegal transition: no edge for status #{inspect(from)} + event #{inspect(event_type)}"
  end
end
