defmodule LoanActor.SmokeTest do
  @moduledoc """
  FT-040 — backend-level proof of `quickstart.md`'s "Smoke checklist" (its
  six numbered items), run via `mix test.smoke` (`mix test --only smoke`)
  in CI. One fast, concrete walk through the real system — distinct from
  FT-034's exhaustive property-based replay proof (25-10,000 random
  walks) and FT-035's NFR load test (throughput/latency budgets under
  sustained load): this is "does the whole system still basically work
  end to end", the fast regression tripwire a CI smoke gate is for.

  Item 1 ("Loan view renders within 1 second") is pure UI rendering — no
  backend equivalent; covered instead by `apps/web/test/e2e/smoke.spec.ts`
  and `spawn-and-event.spec.ts` (this file's frontend-side counterpart).
  Items 2-6 below are each backend-observable and mapped 1:1 to the
  checklist's own numbering.
  """

  use ExUnit.Case, async: false

  alias LoanActor.Diary.File, as: FileStore
  alias LoanActor.Diary.Mnesia, as: MnesiaStore
  alias LoanActor.Factory
  alias LoanActor.FileTestSupport
  alias LoanActor.HITLResponse
  alias LoanActor.MnesiaTestSupport
  alias LoanActor.ServerTestSupport

  @dir FileTestSupport.dir()

  setup_all do
    :ok = FileStore.init(dir: @dir)
    # LoanActor.Idempotency's loan_idem table is always Mnesia, independent
    # of which DiaryStore backs the actual entries.
    :ok = MnesiaStore.init(dir: MnesiaTestSupport.dir())
    :ok
  end

  setup do
    # A temporary pack requiring request_operator_approval, triggered by
    # the planning loop unconditionally (its description contains "plan",
    # the planning loop's own event_type) — mirrors hitl_test.exs's own
    # established technique for reaching item 5's "Trigger HITL" flow.
    previous_skills_dir = Application.get_env(:loan_actor, :skills_dir)

    tmp_dir =
      Factory.write_skill_pack!(Factory.unique_tmp_dir("loan_actor_smoke_skill"), %{
        id: "0001-smoke-hitl",
        name: "smoke-hitl",
        description: "During plan review, ask the operator to approve or reject this loan.",
        tools_required: ["request_operator_approval"]
      })

    Application.put_env(:loan_actor, :skills_dir, tmp_dir)

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

  # Excludes ambient heartbeat/tool-verification entries the 100ms test
  # heartbeat cadence (config/test.exs) may add between the pre-crash
  # snapshot and the post-restart read — a real regression would still be
  # caught (the recorded entries wouldn't be a prefix any more), while an
  # innocent extra heartbeat tick isn't mistaken for one.
  defp same_prefix?(post_crash_entries, pre_crash_entries) do
    Enum.take(post_crash_entries, length(pre_crash_entries)) == pre_crash_entries
  end

  @tag :smoke
  test "spawn, event, HITL approve, and crash-recovery all work, quickly (quickstart.md items 2-6)" do
    loan_id = Factory.unique_loan_id()
    {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)
    {:ok, ref} = LoanActor.subscribe(loan_id)

    # Item 2 — the diary feed shows a :spawned entry.
    assert %{type: :spawned} = List.first(entries(loan_id))

    # Item 3 — sending an event updates the diary and the state card,
    # fast (this is a smoke-level sanity budget, not NFR-001's rigorous
    # p95 proof — FT-035 owns that).
    t0 = System.monotonic_time(:millisecond)
    {:ok, _seq1} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))
    {:ok, _seq2} = LoanActor.send_event(loan_id, Factory.event(%{type: :document_uploaded}))
    {:ok, state_after_upload} = LoanActor.state(loan_id)
    elapsed_ms = System.monotonic_time(:millisecond) - t0

    assert state_after_upload.status == :documents_under_review
    assert Enum.any?(entries(loan_id), &(&1.type == :document_uploaded))
    assert elapsed_ms < 1_000, "spawn -> document_uploaded took #{elapsed_ms}ms, smoke budget is 1s"

    # Item 5 — "Trigger HITL... Click Approve": the planning loop's
    # matched skill invoked request_operator_approval (queued by the
    # goal_set event above, guaranteed processed before document_uploaded
    # per the Server's own FIFO mailbox — same reasoning
    # server_heartbeat_test.exs's own "skill-triggered set_goal" test
    # documents). Approving advances the diary exactly like the UI's
    # "Approve" click.
    assert_receive {:ag_ui_event, ^ref,
                    %{"type" => "CustomEvent", "name" => "hitl_request", "request" => request}},
                   5_000

    request_id = request["request_id"]

    response =
      HITLResponse.new(%{
        request_id: request_id,
        decision: "approve",
        comment: nil,
        operator_id: "smoke-operator",
        responded_at: DateTime.utc_now()
      })

    assert :ok = LoanActor.respond_hitl(loan_id, request_id, response)
    assert Enum.any?(entries(loan_id), &(&1.type == :hitl_responded))

    pre_crash_entries = entries(loan_id)
    {:ok, pre_crash_state} = LoanActor.state(loan_id)

    # Items 4 + 6 — "Refresh the browser; all diary entries reappear in
    # order" / "Stop and restart the backend; UI reconnects and shows the
    # same diary": a real crash + supervisor restart reproduces the same
    # diary and state (last_heartbeat_at excluded — same caveat
    # server_property_test.exs/nfr_load_test.exs document: its live value
    # comes from a DateTime.utc_now() call the diary never stores
    # verbatim).
    pid = LoanActor.whereis(loan_id)
    crash_ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^crash_ref, :process, ^pid, _reason}, 2_000

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

    assert is_pid(new_pid), "actor never restarted after crash"
    assert same_prefix?(entries(loan_id), pre_crash_entries)

    {:ok, post_crash_state} = LoanActor.state(loan_id)
    assert %{post_crash_state | last_heartbeat_at: nil} == %{pre_crash_state | last_heartbeat_at: nil}
  end
end
