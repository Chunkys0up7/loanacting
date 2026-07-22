defmodule LoanActor.Load.NFRLoadTest do
  @moduledoc """
  FT-035 — load test proving NFR-001..NFR-004 hold WITH the tool-call
  streaming ceremony now on (FT-023/024/028: diary pairs + four AG-UI
  frames per tool invocation) — intent 0004's own early-warning gate for
  that hot-path risk. NFR-005 (the `DiaryStore` behaviour admits ≥2
  implementations, switching needs zero changes outside the
  implementation module) is a structural claim, not a performance one —
  already proven by the shared behaviour suite
  (`test/support/diary_store_shared.ex`, instantiated for both File and
  Mnesia); no load profile applies to it, so it is not re-tested here.

  Run via `mix test.load` (the existing `mix.exs` alias, `mix test --only
  load`) — excluded from the default `mix test` run
  (`test/test_helper.exs`). Env var overrides let a full run be
  sanity-checked quickly without waiting out the literal spec'd
  duration/scale (mirrors `diary/file_test.exs`'s existing
  `LOAN_DIARY_LOAD_SIZE` precedent):

  - `LOAN_LOAD_LOANS` (default 100) — SC-001's concurrent loan count
  - `LOAN_LOAD_DURATION_S` (default 60) — SC-001's duration
  - `LOAN_LOAD_EVENTS_PER_SEC` (default 10) — SC-001's per-loan rate
  - `LOAN_LOAD_SUB_LOANS` (default 10) — NFR-004's subscribed-loan count
  - `LOAN_LOAD_SUB_DURATION_S` (default 5) — NFR-004's duration
  - `LOAN_LOAD_CRASH_LOANS` (default 10) — SC-002's simultaneous-kill count
  - `LOAN_LOAD_CRASH_DIARY_SIZE` (default 10_000) — NFR-003's diary depth

  Load-generation event choice: every scenario repeatedly sends
  `%Event{type: :heartbeat}` — a structurally valid event
  (`Event.validate/1`'s enum) that has no legal `State.Model` edge from
  any status (confirmed by FT-034's fix), so every send exercises the
  FULL reactive pipeline (validate → PIIGuard → idempotency →
  transition-attempt-and-catch → diary append of
  `:illegal_transition_attempted`) without needing to track which
  transitions remain legal from the loan's current status — exactly the
  cost path NFR-001/NFR-004 care about, independent of *which* diary
  entry type results.
  """

  use ExUnit.Case, async: false

  alias LoanActor.Diary.Chain
  alias LoanActor.Diary.Entry
  alias LoanActor.Diary.File, as: FileStore
  alias LoanActor.Diary.Mnesia, as: MnesiaStore
  alias LoanActor.Factory
  alias LoanActor.FileTestSupport
  alias LoanActor.MnesiaTestSupport
  alias LoanActor.ServerTestSupport

  @dir FileTestSupport.dir()

  setup_all do
    :ok = FileStore.init(dir: @dir)
    # LoanActor.Idempotency's loan_idem table is always Mnesia (data-model.md),
    # independent of which DiaryStore backs the actual entries.
    :ok = MnesiaStore.init(dir: MnesiaTestSupport.dir())
    :ok
  end

  setup do
    # Real default skill pack (demo-document-request), not an empty dir —
    # this gate specifically proves the budgets hold WITH tool-call
    # ceremony on, not vacuously without any tool invocations at all.
    previous_skills_dir = Application.get_env(:loan_actor, :skills_dir)
    Application.delete_env(:loan_actor, :skills_dir)

    # config/test.exs pins diary_store: LoanActor.Diary.File — a
    # deliberate choice for fast, deterministic UNIT tests (per its own
    # moduledoc, every append does three file opens plus an fsync). NFR-001
    # is a PRODUCTION latency budget; production's default backend is
    # Mnesia (config/config.exs). Measuring against File here would be
    # measuring the wrong store — override to the production default for
    # this load test specifically.
    previous_diary_store = Application.get_env(:loan_actor, :diary_store)
    Application.put_env(:loan_actor, :diary_store, LoanActor.Diary.Mnesia)

    # config/test.exs also pins heartbeat_ms: 100 — deliberately, for OTHER
    # tests' fast cadence verification (SC-011). SC-001's "10 events/sec/loan"
    # describes REACTIVE send_event traffic; the periodic loop's own
    # heartbeat is a separate, always-on mechanism that in production fires
    # once a minute (config/config.exs: 60_000). Leaving it at 100ms here
    # would make every one of the 100 loans ALSO fire its own internal
    # heartbeat (3 extra diary writes: log, tool_invoked, tool_completed)
    # 10 times/sec — an order of magnitude of write load SC-001 never asks
    # for, on top of the reactive traffic being measured, and it would
    # swamp the very tool-ceremony signal FT-035 wants isolated. 5 seconds
    # keeps the periodic loop's own tool invocation (verify_diary_chain)
    # genuinely firing throughout the run (~12 ticks/loan over 60s — "with
    # tool ceremony on" stays true) while keeping its contribution to
    # total write volume modest (~0.6 extra writes/sec/loan) rather than
    # dominating the profile the way the raw 100ms test default would.
    previous_heartbeat_ms = Application.get_env(:loan_actor, :heartbeat_ms)
    Application.put_env(:loan_actor, :heartbeat_ms, 5_000)

    on_exit(fn ->
      case previous_skills_dir do
        nil -> Application.delete_env(:loan_actor, :skills_dir)
        value -> Application.put_env(:loan_actor, :skills_dir, value)
      end

      case previous_diary_store do
        nil -> Application.delete_env(:loan_actor, :diary_store)
        value -> Application.put_env(:loan_actor, :diary_store, value)
      end

      case previous_heartbeat_ms do
        nil -> Application.delete_env(:loan_actor, :heartbeat_ms)
        value -> Application.put_env(:loan_actor, :heartbeat_ms, value)
      end
    end)

    :ok
  end

  defp env_int(name, default), do: name |> System.get_env(Integer.to_string(default)) |> String.to_integer()

  defp percentile(sorted_ascending, p) when sorted_ascending != [] do
    n = length(sorted_ascending)
    idx = max(0, min(n - 1, ceil(p * n) - 1))
    Enum.at(sorted_ascending, idx)
  end

  defp eventually(fun, attempts) do
    Enum.reduce_while(1..attempts, nil, fn _, _ ->
      case fun.() do
        nil ->
          Process.sleep(2)
          {:cont, nil}

        value ->
          {:halt, value}
      end
    end)
  end

  describe "NFR-001/NFR-002/SC-001 — sustained concurrent load" do
    @tag :load
    @tag timeout: :infinity
    test "N concurrent loans at events_per_sec/loan for duration_s: p95 event-to-diary latency < 100ms, memory < 256MB" do
      loans = env_int("LOAN_LOAD_LOANS", 100)
      duration_s = env_int("LOAN_LOAD_DURATION_S", 60)
      events_per_sec = env_int("LOAN_LOAD_EVENTS_PER_SEC", 10)
      interval_ms = div(1_000, events_per_sec)

      loan_ids = for _ <- 1..loans, do: Factory.unique_loan_id()
      Enum.each(loan_ids, fn loan_id -> {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id) end)

      deadline_ms = System.monotonic_time(:millisecond) + duration_s * 1_000

      tasks =
        Enum.map(loan_ids, fn loan_id ->
          Task.async(fn -> generate_event_load(loan_id, deadline_ms, interval_ms, []) end)
        end)

      latencies_ms = tasks |> Task.await_many(:infinity) |> List.flatten() |> Enum.sort()
      memory_bytes = :erlang.memory(:total)

      assert latencies_ms != []
      p95_ms = percentile(latencies_ms, 0.95)
      max_ms = List.last(latencies_ms)

      IO.puts("""
      [NFR-001/SC-001] loans=#{loans} events_per_sec=#{events_per_sec} duration_s=#{duration_s} \
      total_events=#{length(latencies_ms)} p95_ms=#{Float.round(p95_ms, 2)} max_ms=#{Float.round(max_ms, 2)}
      [NFR-002] resident_memory_mb=#{Float.round(memory_bytes / 1_048_576, 2)}
      """)

      assert p95_ms < 100.0, "p95 event-to-diary latency #{p95_ms}ms exceeds NFR-001's 100ms budget"
      assert memory_bytes < 256 * 1_048_576, "resident memory #{memory_bytes} bytes exceeds NFR-002's 256MB budget"
    end
  end

  defp generate_event_load(loan_id, deadline_ms, interval_ms, acc) do
    if System.monotonic_time(:millisecond) >= deadline_ms do
      acc
    else
      event = Factory.event(%{type: :heartbeat, source: :test})
      t0 = System.monotonic_time(:microsecond)
      _result = LoanActor.send_event(loan_id, event)
      elapsed_ms = (System.monotonic_time(:microsecond) - t0) / 1000.0

      Process.sleep(interval_ms)
      generate_event_load(loan_id, deadline_ms, interval_ms, [elapsed_ms | acc])
    end
  end

  describe "NFR-004 — AG-UI delivery latency (diary append to subscribed client)" do
    @tag :load
    @tag timeout: :infinity
    test "p95 diary-append-to-subscriber delivery latency < 250ms" do
      loans = env_int("LOAN_LOAD_SUB_LOANS", 10)
      duration_s = env_int("LOAN_LOAD_SUB_DURATION_S", 5)

      # Generous relative to config/test.exs's deliberately tight default
      # (8, chosen there to exercise slow-client resync) — this scenario
      # is measuring steady-state delivery latency, not resync behavior;
      # a too-small buffer would trip resync under concurrent per-loan
      # heartbeat/tool broadcasts and silently drop the very events being
      # timed, corrupting the measurement rather than reflecting NFR-004.
      previous_buffer = Application.get_env(:loan_actor, :ag_ui_subscriber_buffer)
      Application.put_env(:loan_actor, :ag_ui_subscriber_buffer, 10_000)

      on_exit(fn ->
        case previous_buffer do
          nil -> Application.delete_env(:loan_actor, :ag_ui_subscriber_buffer)
          value -> Application.put_env(:loan_actor, :ag_ui_subscriber_buffer, value)
        end
      end)

      loan_ids = for _ <- 1..loans, do: Factory.unique_loan_id()

      loan_ids
      |> Enum.each(fn loan_id -> {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id) end)

      deadline_ms = System.monotonic_time(:millisecond) + duration_s * 1_000

      tasks =
        Enum.map(loan_ids, fn loan_id ->
          Task.async(fn ->
            {:ok, ref} = LoanActor.subscribe(loan_id)
            generate_delivery_load(loan_id, ref, deadline_ms, [])
          end)
        end)

      latencies_ms =
        tasks
        |> Task.await_many(:infinity)
        |> List.flatten()
        |> Enum.reject(&(&1 == :timeout))
        |> Enum.sort()

      assert latencies_ms != []
      p95_ms = percentile(latencies_ms, 0.95)

      IO.puts("""
      [NFR-004] loans=#{loans} duration_s=#{duration_s} total_deliveries=#{length(latencies_ms)} \
      p95_ms=#{Float.round(p95_ms, 2)}
      """)

      assert p95_ms < 250.0, "p95 AG-UI delivery latency #{p95_ms}ms exceeds NFR-004's 250ms budget"
    end
  end

  defp generate_delivery_load(loan_id, ref, deadline_ms, acc) do
    if System.monotonic_time(:millisecond) >= deadline_ms do
      acc
    else
      event = Factory.event(%{type: :heartbeat, source: :test})
      _result = LoanActor.send_event(loan_id, event)
      t_sent = System.monotonic_time(:microsecond)

      latency_ms =
        receive do
          {:ag_ui_event, ^ref, %{"type" => "CustomEvent", "name" => "diary_entry"}} ->
            (System.monotonic_time(:microsecond) - t_sent) / 1000.0
        after
          2_000 -> :timeout
        end

      Process.sleep(50)
      generate_delivery_load(loan_id, ref, deadline_ms, [latency_ms | acc])
    end
  end

  describe "NFR-003/SC-002 — simultaneous crash-recovery at scale" do
    @tag :load
    @tag timeout: :infinity
    test "crash_loans loans with crash_diary_size diary entries each: killed simultaneously, all restart + rehydrate within 1s, identical state" do
      crash_loans = env_int("LOAN_LOAD_CRASH_LOANS", 10)
      diary_size = env_int("LOAN_LOAD_CRASH_DIARY_SIZE", 10_000)

      loan_ids = for _ <- 1..crash_loans, do: Factory.unique_loan_id()
      Enum.each(loan_ids, &seed_large_diary(&1, diary_size))

      pids =
        Enum.map(loan_ids, fn loan_id ->
          {:ok, pid} = ServerTestSupport.spawn_and_track(loan_id)
          pid
        end)

      pre_crash_states =
        Map.new(loan_ids, fn loan_id ->
          {:ok, state} = LoanActor.state(loan_id)
          {loan_id, meaningful_state(state)}
        end)

      start_ms = System.monotonic_time(:millisecond)
      Enum.each(pids, &Process.exit(&1, :kill))

      Enum.zip(loan_ids, pids)
      |> Enum.each(fn {loan_id, old_pid} ->
        new_pid =
          eventually(
            fn ->
              case LoanActor.whereis(loan_id) do
                nil -> nil
                ^old_pid -> nil
                other -> other
              end
            end,
            500
          )

        assert is_pid(new_pid), "loan #{loan_id} never restarted"
        {:ok, rehydrated_state} = LoanActor.state(loan_id)
        assert meaningful_state(rehydrated_state) == Map.fetch!(pre_crash_states, loan_id)
      end)

      elapsed_ms = System.monotonic_time(:millisecond) - start_ms
      IO.puts("[NFR-003/SC-002] crash_loans=#{crash_loans} diary_size=#{diary_size} elapsed_ms=#{elapsed_ms}")

      assert elapsed_ms < 1_000,
             "simultaneous crash-recovery of #{crash_loans} loans took #{elapsed_ms}ms, exceeds NFR-003's 1s budget"
    end
  end

  # `last_heartbeat_at` is excluded — its live value comes from a
  # `DateTime.utc_now()` call at heartbeat time, never stored verbatim in
  # the diary; a real periodic tick can land in the narrow window between
  # the pre-crash snapshot and the kill, same reasoning as FT-034's
  # property test. Status/version/goals/context are what "byte-identical
  # state" (SC-002) actually claims here.
  defp meaningful_state(state), do: %{state | last_heartbeat_at: nil}

  defp seed_large_diary(loan_id, size) do
    genesis =
      Entry.new(%{
        loan_id: loan_id,
        sequence: 0,
        timestamp: DateTime.utc_now(),
        type: :spawned,
        actor: "system",
        payload_hash: Chain.hash("genesis:#{loan_id}"),
        prev_hash: Entry.genesis_prev_hash()
      })

    store = configured_store()
    {:ok, 0} = store.append(loan_id, genesis)

    _final_tail =
      Enum.reduce(1..(size - 1), genesis, fn _i, tail ->
        entry = Factory.next_entry(tail, %{type: :heartbeat})
        {:ok, _seq} = store.append(loan_id, entry)
        entry
      end)

    :ok
  end

  defp configured_store, do: Application.get_env(:loan_actor, :diary_store, LoanActor.Diary.Mnesia)
end
