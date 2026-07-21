defmodule LoanActor.Supervisor do
  @moduledoc """
  DynamicSupervisor for per-loan actor processes (FT-016; constitution
  Principle I — every loan is a supervised actor; `:one_for_one` so a
  crash never takes down sibling loans).

  A thin, unopinionated wrapper: idempotent "already running?" checks
  belong to the caller (`LoanActor.spawn/1`, FT-017), via
  `LoanActor.Registry.whereis/1`, before calling `start_child/1` here —
  matching the documented contract (`contracts/loan-actor-api.md`:
  "Idempotent. If the loan is already running, returns
  `{:ok, existing_pid}`" is `LoanActor.spawn/1`'s behavior, not this
  module's).
  """

  use DynamicSupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DynamicSupervisor
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start `child_spec` under this supervisor."
  @spec start_child(Supervisor.child_spec() | {module(), term()} | module()) ::
          DynamicSupervisor.on_start_child()
  def start_child(child_spec), do: DynamicSupervisor.start_child(__MODULE__, child_spec)
end
