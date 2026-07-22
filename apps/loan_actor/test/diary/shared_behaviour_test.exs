defmodule LoanActor.Diary.SharedBehaviourTest do
  @moduledoc """
  FT-006 contract tests for the `DiaryStore` behaviour itself.

  The parameterized per-implementation suite lives in
  `test/support/diary_store_shared.ex` (`LoanActor.Diary.StoreSharedTests`)
  and is instantiated by each implementation's test module:

  - `LoanActor.Diary.File`   → `test/diary/file_test.exs`   (FT-007)
  - `LoanActor.Diary.Mnesia` → `test/diary/mnesia_test.exs` (FT-008)

  This file pins the behaviour's callback surface against
  `contracts/diary-store-behaviour.md` so contract-doc drift fails CI.
  """

  use ExUnit.Case, async: true

  alias LoanActor.Diary.Store

  describe "DiaryStore behaviour — contract" do
    test "declares exactly the callbacks documented in diary-store-behaviour.md" do
      expected =
        MapSet.new(
          init: 1,
          append: 2,
          tail: 1,
          read_range: 3,
          stream: 2,
          verify_chain: 1,
          wipe: 1
        )

      actual = MapSet.new(Store.behaviour_info(:callbacks))

      assert actual == expected,
             "DiaryStore callbacks drifted from the contract doc: " <>
               inspect(MapSet.symmetric_difference(actual, expected))
    end
  end
end
