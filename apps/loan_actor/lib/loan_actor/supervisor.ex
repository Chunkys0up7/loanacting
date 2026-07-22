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

  **Restart intensity (found via FT-034's property-based crash-recovery
  test, which crashes and restarts many DIFFERENT loans in quick
  succession):** `Supervisor`'s default `max_restarts: 3, max_seconds: 5`
  counts restarts across ALL children of this supervisor COMBINED, not
  per-child. For the intended production shape — potentially thousands of
  independently-running, 30-year-lived loan actors, where crashes are
  isolated single-loan events rather than a symptom of one problem — the
  default would let a handful of UNRELATED loans crashing within the same
  five-second window exhaust the intensity cap and shut down this entire
  supervisor, taking every other currently-running loan down with it: the
  exact cross-loan blast radius `:one_for_one` exists to prevent. Raised
  generously; this does not weaken protection against a single
  crash-looping loan in any way `:one_for_one`'s default already didn't —
  a supervisor-wide counter can't distinguish "one loan looping" from
  "many independent crashes" either way, so there was never a real safety
  property here to preserve, only an accidentally-too-low default.
  """

  use DynamicSupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DynamicSupervisor
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 1_000, max_seconds: 5)
  end

  @doc "Start `child_spec` under this supervisor."
  @spec start_child(Supervisor.child_spec() | {module(), term()} | module()) ::
          DynamicSupervisor.on_start_child()
  def start_child(child_spec), do: DynamicSupervisor.start_child(__MODULE__, child_spec)
end
