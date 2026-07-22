defmodule LoanActor.ServerPropertyTest do
  @moduledoc """
  FT-034 — property-based proof that `LoanActor.Server`'s FULL pipeline
  (PIIGuard → idempotency → transition → diary, plus the periodic/planning
  loops' own tool invocations) replays byte-identically after a crash,
  across many random legal walks through `LoanActor.State.Model`. Extends
  `replay_test.exs` (FT-009 — a pure `State.transition/2` fold, no live
  Server, no tool invocations) to the live GenServer + real diary store +
  real tool-invocation diary entries, exactly as that file's own moduledoc
  says this task would.

  Taxonomy: happy / boundary / replay.

  ## Run count

  The task's own deliverable text asks for "10,000 sequences in CI". Each
  run here spawns a REAL supervised actor, waits for at least one
  heartbeat-driven tool invocation (`heartbeat_ms: 100` in
  `config/test.exs`), kills it, and polls for supervisor restart +
  rehydration — genuinely slower than a pure-function property (FT-009's
  own, `max_runs: 100`, has none of this). Running 10,000 of these on
  every local `mix test` would make the inner dev loop minutes slower for
  no local benefit, so `max_runs` is 10,000 only under `CI=true`; 25
  otherwise — enough to catch a real regression locally without
  punishing every test run (mirrors the `mix test.load`/`:load` tag
  precedent of keeping genuinely expensive proof separate from the fast
  default loop, without needing a whole separate Mix task for one property).
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias LoanActor.Diary.File, as: FileStore
  alias LoanActor.Diary.Mnesia, as: MnesiaStore
  alias LoanActor.Factory
  alias LoanActor.FileTestSupport
  alias LoanActor.MnesiaTestSupport
  alias LoanActor.ServerTestSupport

  @dir FileTestSupport.dir()
  @max_runs if System.get_env("CI"), do: 10_000, else: 25
  @tool_entry_types [:tool_invoked, :tool_completed, :tool_failed]

  setup_all do
    :ok = FileStore.init(dir: @dir)
    # LoanActor.Idempotency's loan_idem table is always Mnesia (data-model.md),
    # independent of which DiaryStore backs the actual entries.
    :ok = MnesiaStore.init(dir: MnesiaTestSupport.dir())
    :ok
  end

  setup do
    # Deliberately the REAL default skill pack (demo-document-request), not
    # an empty dir — this property specifically proves replay stays
    # identical WITH genuine tool-invocation entries in the diary, not
    # vacuously without any.
    previous_skills_dir = Application.get_env(:loan_actor, :skills_dir)
    Application.delete_env(:loan_actor, :skills_dir)

    on_exit(fn ->
      case previous_skills_dir do
        nil -> Application.delete_env(:loan_actor, :skills_dir)
        value -> Application.put_env(:loan_actor, :skills_dir, value)
      end
    end)

    :ok
  end

  defp eventually(fun, attempts) do
    Enum.reduce_while(1..attempts, nil, fn _, _ ->
      case fun.() do
        nil ->
          Process.sleep(10)
          {:cont, nil}

        value ->
          {:halt, value}
      end
    end)
  end

  defp entries(loan_id), do: Enum.to_list(FileStore.stream(loan_id, []))

  defp tool_entry_type_sequence(loan_id) do
    loan_id |> entries() |> Enum.filter(&(&1.type in @tool_entry_types)) |> Enum.map(& &1.type)
  end

  defp wait_for_tool_invocation(loan_id) do
    eventually(
      fn ->
        case tool_entry_type_sequence(loan_id) do
          [] -> nil
          found -> found
        end
      end,
      30
    )
  end

  property "every legal walk through a real Server survives a crash + rehydration with identical state, tool-invocation entries included" do
    check all(event_types <- Factory.legal_event_walk_gen(), max_runs: @max_runs) do
      loan_id = Factory.unique_loan_id()
      {:ok, pid} = ServerTestSupport.spawn_and_track(loan_id)

      Enum.each(event_types, fn event_type ->
        assert {:ok, _seq} = LoanActor.send_event(loan_id, Factory.event(%{type: event_type}))
      end)

      # Give the periodic loop a chance to invoke a tool at least once —
      # proving this WITH tool-invocation entries genuinely present, not
      # vacuously with an empty diary tail.
      assert wait_for_tool_invocation(loan_id) != nil

      {:ok, pre_crash_state} = LoanActor.state(loan_id)
      pre_crash_tool_sequence = tool_entry_type_sequence(loan_id)

      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 2_000

      new_pid =
        eventually(
          fn ->
            case LoanActor.whereis(loan_id) do
              nil -> nil
              ^pid -> nil
              other -> other
            end
          end,
          100
        )

      assert is_pid(new_pid)
      assert {:ok, rehydrated_state} = LoanActor.state(loan_id)

      # `last_heartbeat_at` is excluded from the identical-state claim: its
      # live value comes from a `DateTime.utc_now()` call at heartbeat time,
      # never stored verbatim in the diary (only a hash of the state it was
      # set on) — the closest reconstruction rehydrate/2 can do is the
      # `:heartbeat` entry's OWN timestamp, a few microseconds off from the
      # live value by construction, not a bug. Both sides having been set
      # at all (non-nil) is what's actually provable here.
      assert %{rehydrated_state | last_heartbeat_at: nil} == %{pre_crash_state | last_heartbeat_at: nil}
      rehydrated_has_heartbeat? = match?(%DateTime{}, rehydrated_state.last_heartbeat_at)
      pre_crash_has_heartbeat? = match?(%DateTime{}, pre_crash_state.last_heartbeat_at)
      assert rehydrated_has_heartbeat? == pre_crash_has_heartbeat?

      # The tool-invocation sequence itself is replay-stable: rehydration
      # doesn't touch the store, so the diary read back after the crash
      # still carries the exact same administrative entries in the same
      # order as before it.
      assert tool_entry_type_sequence(loan_id) == pre_crash_tool_sequence

      # Hygiene: this property can run thousands of iterations under CI,
      # each leaving a live, heartbeating actor behind if not stopped here
      # (ServerTestSupport's own moduledoc documents exactly this
      # accumulation risk) — terminate now rather than deferring every
      # iteration's cleanup to the outer test's on_exit.
      DynamicSupervisor.terminate_child(LoanActor.Supervisor, new_pid)
    end
  end
end
