defmodule LoanActor.DecisionTest do
  @moduledoc """
  ADH-007 — `LoanActor.Decision.payload/2`. Taxonomy: happy / boundary /
  contract (pins `data-model.md`'s `%LoanActor.Decision{}` payload shape).
  """

  use ExUnit.Case, async: true

  alias LoanActor.Decision
  alias LoanActor.Factory

  defp gate_outcome(overrides \\ %{}) do
    Map.merge(
      %{gate_id: "document-completeness", gate_version: "1.0.0", outcome: :pass, cause: "gate_id:document-completeness"},
      overrides
    )
  end

  describe "payload/2 — happy" do
    test "a :pass outcome builds the documented shape" do
      assessment = Factory.assessment(%{document_completeness: :complete})
      payload = Decision.payload(gate_outcome(), assessment)

      assert payload["gate_id"] == "document-completeness"
      assert payload["gate_version"] == "1.0.0"
      assert payload["outcome"] == :pass
      assert is_binary(payload["input_digest"])
      assert Map.keys(payload) |> Enum.sort() == ["gate_id", "gate_version", "input_digest", "outcome"]
    end

    test "a :fail outcome carries outcome: :fail" do
      assessment = Factory.assessment()
      payload = Decision.payload(gate_outcome(%{outcome: :fail}), assessment)
      assert payload["outcome"] == :fail
    end
  end

  describe "payload/2 — boundary (determinism + CHK007 scope)" do
    test "the same assessment always hashes to the same input_digest" do
      assessment = Factory.assessment(%{document_completeness: :complete})
      a = Decision.payload(gate_outcome(), assessment)
      b = Decision.payload(gate_outcome(), assessment)
      assert a["input_digest"] == b["input_digest"]
    end

    test "a different assessment produces a different input_digest" do
      complete = Factory.assessment(%{document_completeness: :complete})
      incomplete = Factory.assessment(%{document_completeness: :incomplete})

      refute Decision.payload(gate_outcome(), complete)["input_digest"] ==
               Decision.payload(gate_outcome(), incomplete)["input_digest"]
    end

    test "input_digest is a 64-char hex string (BLAKE2b-256, per LoanActor.Diary.Chain)" do
      payload = Decision.payload(gate_outcome(), Factory.assessment())
      assert String.match?(payload["input_digest"], ~r/^[0-9A-F]{64}$/)
    end
  end
end
