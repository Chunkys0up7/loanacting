defmodule LoanActor.ServerTestSupport do
  @moduledoc """
  Test-only teardown for `LoanActor.spawn/1` (FT-018 follow-up).

  Every spawned loan actor is a `:permanent` `DynamicSupervisor` child (the
  default `use GenServer` child spec) with a live `:timer.send_interval`
  heartbeat that fires for the rest of the BEAM's lifetime — nothing in
  the test suite ever stops one. Left unchecked, spawned actors accumulate
  across the ENTIRE suite run (300+ tests, many of which spawn), each
  doing real disk I/O (diary appends, tool invocation, skill loading)
  every `heartbeat_ms`. That cumulative background load is exactly what
  made `test/server_heartbeat_test.exs`'s cadence assertion intermittently
  flaky under a full-suite run even after fixing the two structural bugs
  (drift from self-rescheduling timers; the shared File/Mnesia test-dir
  collisions) — later tests' actors compete for scheduler time with the
  one actively being measured.

  `spawn_and_track/1` wraps `LoanActor.spawn/1` and registers an
  `on_exit` that properly removes the child via
  `DynamicSupervisor.terminate_child/2` — NOT `GenServer.stop/1`, which a
  `:permanent` child's supervisor would simply restart (a `:normal` exit
  still counts as an exit warranting restart under `:permanent`), leaving
  the accumulation problem exactly as bad.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias LoanActor.Supervisor, as: LoanSupervisor

  @doc """
  Spawn `loan_id` via `LoanActor.spawn/1` and register cleanup so the
  actor (and its heartbeat timer) stops when the calling test ends.

  Looks up the CURRENT pid for `loan_id` at cleanup time (via
  `LoanActor.whereis/1`), not the pid captured at spawn time — a test that
  deliberately kills the actor to prove crash-recovery restart leaves a
  DIFFERENT (supervisor-restarted) pid running under the same loan_id by
  the time the test ends, and that is the one that actually needs tearing
  down.
  """
  @spec spawn_and_track(String.t()) :: {:ok, pid()} | {:error, term()}
  def spawn_and_track(loan_id) do
    result = LoanActor.spawn(loan_id)

    on_exit(fn ->
      case LoanActor.whereis(loan_id) do
        nil -> :ok
        pid -> DynamicSupervisor.terminate_child(LoanSupervisor, pid)
      end
    end)

    result
  end
end
