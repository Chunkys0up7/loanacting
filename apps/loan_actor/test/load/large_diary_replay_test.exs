defmodule LoanActor.Load.LargeDiaryReplayTest do
  @moduledoc """
  FT-036 — diary scale test: folding `LoanActor.State.transition/2` over a
  1,000,000-entry diary reproduces the correct final state in under 30
  seconds. `replay_test.exs` (FT-009) already proves replay is CORRECT
  (byte-identical to direct application) at small scale and across both
  store backends; this proves it stays FAST at the literal spec'd scale —
  a distinct, performance claim.

  Genuine 1,000,000-step replay needs a genuinely unbounded legal walk.
  `State.Model`'s other five edges are strictly one-way (`spawned` ->
  `completed`, five hops total) and would exhaust immediately; its one
  cycle — `awaiting_documents` -[document_uploaded]->
  `documents_under_review` -[operator_approval_required]->
  `awaiting_operator_approval` -[operator_approval_denied]->
  `awaiting_documents` — repeats indefinitely (an operator bouncing a loan
  back for more documents, over and over), so the walk here is `goal_set`
  once, then that 3-cycle repeated to fill the remaining size.

  Uses `LoanActor.Diary.Mnesia`, not File — found empirically, not assumed:
  a first draft of this test against File (matching `diary/file_test.exs`'s
  100k-entry precedent) measured ~0.085ms/entry replay (JSONL line read +
  Jason.decode + three Base64 decodes per entry), which extrapolates to
  ~85s at 1,000,000 entries — already over budget on the replay side alone,
  before counting File's three-file-opens-plus-fsync-per-append seeding
  cost (hours at this scale). Mirrors `nfr_load_test.exs`'s own reasoning
  for NFR-001 (a PRODUCTION budget should be measured against production's
  actual default backend, not `config/test.exs`'s deliberately-simple File
  store) — Mnesia's `stream/2` is dirty ETS reads + `:erlang.binary_to_term`
  (no JSON, no repeated file opens), and its own moduledoc notes replay
  "does not pay transaction costs".

  Tagged `:slow` (excluded from the default `mix test` run by
  `test_helper.exs`, same shape as the existing `:load` tag) and run via
  the new `mix test.slow` alias — nightly in CI
  (`.github/workflows/ci-nightly.yml`), not on every push/PR: seeding a
  million entries, even at Mnesia's speed, is still too slow for the
  per-PR gate.

  `LOAN_DIARY_SCALE_SIZE` overrides the size for a quick local sanity run,
  mirroring `diary/file_test.exs`'s existing `LOAN_DIARY_LOAD_SIZE`
  precedent.
  """

  use ExUnit.Case, async: false

  alias LoanActor.Diary.Mnesia, as: MnesiaStore
  alias LoanActor.Factory
  alias LoanActor.MnesiaTestSupport
  alias LoanActor.State

  setup_all do
    :ok = MnesiaStore.init(dir: MnesiaTestSupport.dir())
    :ok
  end

  # Index 1 is the entry right after genesis (`:goal_set`); every index
  # after that cycles the model's one repeatable loop.
  defp event_type_at(1), do: :goal_set

  defp event_type_at(i) do
    case rem(i - 2, 3) do
      0 -> :document_uploaded
      1 -> :operator_approval_required
      2 -> :operator_approval_denied
    end
  end

  defp seed(loan_id, size) do
    genesis = Factory.entry(%{loan_id: loan_id})
    {:ok, 0} = MnesiaStore.append(loan_id, genesis)

    Enum.reduce(1..(size - 1), genesis, fn i, tail ->
      entry = Factory.next_entry(tail, %{type: event_type_at(i)})
      {:ok, _seq} = MnesiaStore.append(loan_id, entry)
      entry
    end)
  end

  @tag :slow
  @tag timeout: :infinity
  test "replaying a 1,000,000-entry diary reproduces state in under 30 seconds" do
    size = String.to_integer(System.get_env("LOAN_DIARY_SCALE_SIZE", "1000000"))
    loan_id = Factory.unique_loan_id()

    seed(loan_id, size)
    assert Enum.count(MnesiaStore.stream(loan_id, [])) == size

    t0 = System.monotonic_time(:millisecond)

    replayed =
      loan_id
      |> MnesiaStore.stream([])
      |> Enum.reduce(Factory.state(%{loan_id: loan_id}), fn entry, state ->
        if entry.type == :spawned, do: state, else: State.transition(state, entry.type)
      end)

    elapsed_ms = System.monotonic_time(:millisecond) - t0

    IO.puts("[FT-036] entries=#{size} replay_elapsed_ms=#{elapsed_ms}")

    assert replayed.version == size - 1
    assert replayed.status in [:awaiting_documents, :documents_under_review, :awaiting_operator_approval]

    assert elapsed_ms < 30_000,
           "replaying #{size} entries took #{elapsed_ms}ms, exceeds FT-036's 30s budget"

    :ok = MnesiaStore.wipe(loan_id)
  end
end
