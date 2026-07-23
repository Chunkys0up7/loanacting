defmodule LoanActor.AGUI.Stream do
  @moduledoc """
  `DynamicSupervisor` for `LoanActor.AGUI.Subscriber` processes (FT-024).
  Analogous to `LoanActor.Supervisor` for loan actors — each subscriber is
  its own supervised, independently-crashable process, so one client's
  failure can never affect the loan actor or any other subscriber.
  """

  use DynamicSupervisor

  alias LoanActor.AGUI.Subscriber

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DynamicSupervisor
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a new supervised subscriber delivering to `owner`, correlated by `ref`."
  @spec start_subscriber(pid(), reference(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_subscriber(owner, ref, opts \\ []) do
    child_spec = {Subscriber, Keyword.merge([owner: owner, ref: ref], opts)}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end
