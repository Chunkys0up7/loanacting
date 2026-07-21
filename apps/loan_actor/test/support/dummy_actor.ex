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

  @impl GenServer
  def handle_cast(:crash, _state), do: raise("simulated crash (LoanActor.DummyActor)")
end
