defmodule LoanActor.PIIGuardTest do
  @moduledoc """
  FT-014 — `LoanActor.PIIGuard`. Taxonomy: happy / error / security.

  Design: foundation is a HARD GATE (confirmed 2026-07-21, resolving an
  ambiguity between data-model.md's narrative and tasks.md FT-014's literal
  `apply/1` return-shape contract) — any PII-pattern match anywhere rejects
  the whole payload; no partial redact-and-continue.

  The "200-case synthetic corpus" requirement (tasks.md FT-014) is met by a
  200-run StreamData property (test-data-forge: a generative corpus is
  stronger than 200 hand-rolled fixtures), complemented by named
  example-based tests per category for readability.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias LoanActor.Factory
  alias LoanActor.PIIGuard

  describe "apply/1 — happy" do
    test "a payload with no PII-shaped values passes through unchanged" do
      payload = %{"note" => "document uploaded successfully", "status" => "pending"}
      assert {:ok, ^payload, []} = PIIGuard.apply(payload)
    end

    test "an empty payload passes through unchanged" do
      assert {:ok, %{}, []} = PIIGuard.apply(%{})
    end

    test "clean values inside nested maps and lists pass" do
      payload = %{
        "borrower" => %{"name" => "pat", "notes" => ["hello", "world"]},
        "tags" => ["alpha", "beta"]
      }

      assert {:ok, ^payload, []} = PIIGuard.apply(payload)
    end

    test "non-string leaf values (integers, booleans, nil) never trigger a match" do
      payload = %{"count" => 42, "active" => true, "note" => nil}
      assert {:ok, ^payload, []} = PIIGuard.apply(payload)
    end
  end

  describe "apply/1 — error (named category examples)" do
    test "an SSN-shaped value is rejected" do
      assert {:error, :pii_violation, [["ssn"]]} =
               PIIGuard.apply(%{"ssn" => "123-45-6789"})
    end

    test "an account-number-shaped value is rejected" do
      assert {:error, :pii_violation, [["account"]]} =
               PIIGuard.apply(%{"account" => "123456789012"})
    end

    test "a routing-number-shaped value is rejected" do
      assert {:error, :pii_violation, [["routing"]]} =
               PIIGuard.apply(%{"routing" => "021000021"})
    end

    test "a date-of-birth-shaped value (ISO) is rejected" do
      assert {:error, :pii_violation, [["dob"]]} = PIIGuard.apply(%{"dob" => "1985-03-14"})
    end

    test "a date-of-birth-shaped value (US format) is rejected" do
      assert {:error, :pii_violation, [["dob"]]} = PIIGuard.apply(%{"dob" => "3/14/1985"})
    end
  end

  describe "apply/1 — error (boundary / structural location)" do
    test "a match nested inside a map is reported with the full path" do
      payload = %{"borrower" => %{"ssn" => "123-45-6789"}}
      assert {:error, :pii_violation, [["borrower", "ssn"]]} = PIIGuard.apply(payload)
    end

    test "a match inside a list is reported with its index in the path" do
      payload = %{"notes" => ["hello", "123-45-6789"]}
      assert {:error, :pii_violation, [["notes", 1]]} = PIIGuard.apply(payload)
    end

    test "a today-shaped date (2026) does not false-positive as a date of birth" do
      assert {:ok, _, []} = PIIGuard.apply(%{"created" => "2026-07-21"})
    end

    test "multiple violations are all reported (order-independent)" do
      payload = %{"ssn" => "123-45-6789", "dob" => "1985-03-14"}
      assert {:error, :pii_violation, paths} = PIIGuard.apply(payload)
      assert MapSet.new(paths) == MapSet.new([["ssn"], ["dob"]])
    end
  end

  describe "patterns/0 — contract" do
    test "loads all four documented categories from priv/pii_patterns.yml" do
      names = PIIGuard.patterns() |> Enum.map(&elem(&1, 0))
      assert "ssn" in names
      assert "account_number" in names
      assert "routing_number" in names
      assert Enum.any?(names, &String.starts_with?(&1, "date_of_birth"))
    end
  end

  describe "synthetic PII corpus — security (200-run generative corpus)" do
    property "any payload built entirely from clean values passes; any containing one dirty value is rejected" do
      check all(
              clean_fields <-
                StreamData.list_of(Factory.pii_clean_value_gen(), min_length: 1, max_length: 4),
              target <-
                StreamData.one_of([
                  StreamData.tuple({StreamData.constant(:clean), Factory.pii_clean_value_gen()}),
                  StreamData.tuple({StreamData.constant(:dirty), Factory.pii_dirty_value_gen()})
                ]),
              max_runs: 200
            ) do
        {kind, target_value} = target

        payload =
          clean_fields
          |> Enum.with_index()
          |> Map.new(fn {v, i} -> {"field_#{i}", v} end)
          |> Map.put("target", target_value)

        case kind do
          :clean ->
            assert {:ok, ^payload, []} = PIIGuard.apply(payload)

          :dirty ->
            assert {:error, :pii_violation, paths} = PIIGuard.apply(payload)
            assert ["target"] in paths
        end
      end
    end
  end
end
