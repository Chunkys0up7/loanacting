defmodule LoanActor.Registry do
  @moduledoc """
  Via-tuple registry for loan actor pids (FT-016). Wraps Elixir's built-in
  `Registry` (unique keys, one entry per `loan_id`) so
  `LoanActor.Supervisor` and the loan actor process (`LoanActor.Server`,
  FT-017) can look up / register a loan by `loan_id` without a central
  bottleneck process.
  """

  @name __MODULE__

  @doc "Child spec for this registry, for use in a supervision tree."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @name)
  end

  @doc "The `:via` tuple for a loan's registered process name."
  @spec via(String.t()) :: {:via, Registry, {module(), String.t()}}
  def via(loan_id), do: {:via, Registry, {@name, loan_id}}

  @doc "The pid registered for `loan_id`, or `nil` if none is running."
  @spec whereis(String.t()) :: pid() | nil
  def whereis(loan_id) do
    case Registry.lookup(@name, loan_id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end
end
