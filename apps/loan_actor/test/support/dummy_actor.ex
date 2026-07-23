defmodule LoanActor.DummyActor do
  @moduledoc """
  Fixture GenServer standing in for `LoanActor.Server` (not yet built —
  FT-017). Used ONLY to test `LoanActor.Supervisor` + `LoanActor.Registry`
  mechanics (spawn / lookup / one_for_one restart on crash) in isolation
  from the real per-loan actor logic — mirrors the `LoanActor.TestTools`
  fixture-module precedent from FT-042 (test-data-forge).
  """

  use GenServer

  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(loan_id) do
    GenServer.start_link(__MODULE__, loan_id, name: LoanActor.Registry.via(loan_id))
  end

  @doc "Ask the actor to crash, to exercise supervisor restart."
  @spec crash(pid()) :: :ok
  def crash(pid), do: GenServer.cast(pid, :crash)

  @impl GenServer
  def init(loan_id), do: {:ok, %{loan_id: loan_id}}

  # Deliberately never returns normally — the whole point is to crash the
  # process so LoanActor.Supervisor's restart mechanics have something
  # real to prove. Dialyzer correctly reports this as a genuine no_return
  # finding since GenServer's own @callback claims a returning shape;
  # unlike an actual bug, this is the fixture's entire purpose, so it's
  # suppressed by name rather than silencing dialyzer more broadly. Found
  # via the first CI run with a real MIX_ENV=test dialyzer pass — local
  # runs throughout this project's development never set MIX_ENV
  # explicitly for `mix dialyzer`, which defaults to :dev and therefore
  # never compiled (or analyzed) test/support/*.ex at all.
  @dialyzer {:nowarn_function, handle_cast: 2}
  @impl GenServer
  def handle_cast(:crash, _state), do: raise("simulated crash (LoanActor.DummyActor)")
end
