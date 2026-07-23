defmodule LoanActor.AssessmentTest do
  @moduledoc """
  ADH-002 — `LoanActor.Assessment` struct + validated constructor.
  Taxonomy: happy / boundary / error. Data via `LoanActor.Factory` (test-data-forge).
  """

  use ExUnit.Case, async: true

  alias LoanActor.Assessment
  alias LoanActor.Factory

  describe "new/1 — happy" do
    test "builds an assessment with defaults (unknown completeness, n/a SLA, no flags)" do
      assessment = Factory.assessment()
      assert %Assessment{document_completeness: :unknown, sla_state: :n_a} = assessment
      assert assessment.goal_ages == %{}
      assert assessment.data_quality_flags == []
      assert assessment.computed_at_version == 0
    end

    test "accepts goal_ages and data_quality_flags" do
      assessment =
        Factory.assessment(%{
          goal_ages: %{"G-1" => 1_000},
          data_quality_flags: [:missing_source_field]
        })

      assert assessment.goal_ages == %{"G-1" => 1_000}
      assert assessment.data_quality_flags == [:missing_source_field]
    end
  end

  describe "document_completeness_values/0 and sla_states/0 — boundary" do
    test "every documented document_completeness value builds a valid assessment" do
      for value <- Assessment.document_completeness_values() do
        assert %Assessment{document_completeness: ^value} =
                 Factory.assessment(%{document_completeness: value})
      end
    end

    test "every documented sla_state value builds a valid assessment" do
      for value <- Assessment.sla_states() do
        assert %Assessment{sla_state: ^value} = Factory.assessment(%{sla_state: value})
      end
    end

    test "document_completeness_values/0 is exactly the three documented values" do
      assert Assessment.document_completeness_values() == [:complete, :incomplete, :unknown]
    end

    test "sla_states/0 is exactly the four documented values" do
      assert Assessment.sla_states() == [:on_track, :at_risk, :breached, :n_a]
    end

    test "goal_ages accepts a zero age (boundary)" do
      assert %Assessment{goal_ages: %{"G-1" => 0}} =
               Factory.assessment(%{goal_ages: %{"G-1" => 0}})
    end
  end

  describe "new/1 — error (parametrized invalid catalog)" do
    test "every invalid variant raises ArgumentError" do
      for {label, attrs} <- Factory.invalid_assessment_variants() do
        assert_raise ArgumentError, fn -> Assessment.new(attrs) end
        _ = label
      end
    end

    test "missing required keys raise KeyError" do
      assert_raise KeyError, fn -> Assessment.new(%{loan_id: "L-1"}) end
    end
  end
end
