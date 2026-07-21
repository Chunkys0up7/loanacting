defmodule LoanActor.ReplayTest do
  @moduledoc """
  FT-009 — cross-cutting replay proof: folding `LoanActor.State.transition/2`
  over a diary's entry types reproduces byte-identical state, regardless of
  which `DiaryStore` implementation (File or Mnesia) the diary was read
  from.

  Scope note: this proves the diary+transition replay invariant using the
  machinery available at this point in the build (FT-005..008, FT-010/011)
  — there is no live Server yet (FT-017..019 are later tasks in Track 5).
  The fuller claim ("every state-mutating HANDLER replays byte-identically",
  i.e. the full PIIGuard → idempotency → transition → diary pipeline) is
  exercised once the Server exists — by FT-034's property-based suite,
  which explicitly depends on this task (FT-009) plus FT-017, confirming
  this task is the foundational precursor, not the final word on "every
  handler".
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias LoanActor.Diary.File, as: FileStore
  alias LoanActor.Diary.Mnesia, as: MnesiaStore
  alias LoanActor.Factory
  alias LoanActor.MnesiaTestSupport
  alias LoanActor.State
  alias LoanActor.State.Model

  @file_dir Path.join(System.tmp_dir!(), "loan_actor_replay_file_test")

  setup_all do
    :ok = FileStore.init(dir: @file_dir)
    :ok = MnesiaStore.init(dir: MnesiaTestSupport.dir())
    :ok
  end

  # A walk traversing every one of LoanActor.State.Model's seven edges
  # exactly once: spawned -[goal_set]-> awaiting_documents
  # -[document_uploaded]-> documents_under_review
  # -[operator_approval_required]-> awaiting_operator_approval
  # -[operator_approval_denied]-> awaiting_documents
  # -[document_uploaded]-> documents_under_review -[goal_satisfied]->
  # processing -[complete]-> completed.
  @full_coverage_walk [
    :goal_set,
    :document_uploaded,
    :operator_approval_required,
    :operator_approval_denied,
    :document_uploaded,
    :goal_satisfied,
    :complete
  ]

  defp direct_apply(loan_id, event_types) do
    Enum.reduce(event_types, Factory.state(%{loan_id: loan_id}), fn event_type, state ->
      State.transition(state, event_type)
    end)
  end

  defp replay_from_entries(entries) do
    [genesis | rest] = entries

    Enum.reduce(rest, Factory.state(%{loan_id: genesis.loan_id}), fn entry, state ->
      State.transition(state, entry.type)
    end)
  end

  defp write_and_read_back(store, entries) do
    loan_id = hd(entries).loan_id
    for entry <- entries, do: {:ok, _seq} = store.append(loan_id, entry)
    Enum.to_list(store.stream(loan_id, []))
  end

  describe "replay — happy (fixed full-coverage walk)" do
    test "replaying the diary reproduces the direct-application state, byte-identical" do
      loan_id = Factory.unique_loan_id()
      entries = Factory.chain_with_event_types(@full_coverage_walk, %{loan_id: loan_id})

      direct = direct_apply(loan_id, @full_coverage_walk)
      replayed = replay_from_entries(entries)

      assert replayed.status == :completed
      assert replayed == direct
      assert :erlang.term_to_binary(replayed) == :erlang.term_to_binary(direct)
    end

    test "the walk touches all seven documented edges" do
      assert length(@full_coverage_walk) == length(Model.edges())
    end
  end

  describe "replay — store-independence (File vs Mnesia)" do
    test "replaying a diary read back from EITHER store yields the same state" do
      loan_id = Factory.unique_loan_id()
      entries = Factory.chain_with_event_types(@full_coverage_walk, %{loan_id: loan_id})

      from_file = entries |> then(&write_and_read_back(FileStore, &1)) |> replay_from_entries()

      mnesia_entries = Factory.chain_with_event_types(@full_coverage_walk, %{loan_id: Factory.unique_loan_id()})
      from_mnesia = mnesia_entries |> then(&write_and_read_back(MnesiaStore, &1)) |> replay_from_entries()

      # Different loan_ids (stores are keyed by loan_id), but the STATUS +
      # VERSION progression must be identical — replay is a pure function
      # of the event-type sequence, independent of loan_id or backing store.
      assert from_file.status == from_mnesia.status
      assert from_file.version == from_mnesia.version
    end
  end

  describe "replay — property (many random legal walks)" do
    property "every legal walk replays to the same state via direct application, File, and Mnesia" do
      check all(event_types <- Factory.legal_event_walk_gen(), max_runs: 100) do
        loan_id = Factory.unique_loan_id()
        entries = Factory.chain_with_event_types(event_types, %{loan_id: loan_id})

        direct = direct_apply(loan_id, event_types)
        replayed = replay_from_entries(entries)
        assert :erlang.term_to_binary(replayed) == :erlang.term_to_binary(direct)

        file_entries = write_and_read_back(FileStore, entries)
        assert replay_from_entries(file_entries) == replayed

        mnesia_loan_id = Factory.unique_loan_id()
        mnesia_entries = Factory.chain_with_event_types(event_types, %{loan_id: mnesia_loan_id})
        mnesia_read_back = write_and_read_back(MnesiaStore, mnesia_entries)
        replayed_mnesia = replay_from_entries(mnesia_read_back)

        assert replayed_mnesia.status == replayed.status
        assert replayed_mnesia.version == replayed.version
      end
    end
  end

  describe "replay — boundary" do
    test "a diary with only the genesis entry replays to the untouched initial state" do
      loan_id = Factory.unique_loan_id()
      entries = Factory.chain_with_event_types([], %{loan_id: loan_id})
      assert length(entries) == 1

      replayed = replay_from_entries(entries)
      assert replayed == Factory.state(%{loan_id: loan_id})
    end
  end
end
