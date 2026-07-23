defmodule LoanActor.EventTest do
  @moduledoc """
  FT-013 — `LoanActor.Event` struct + `validate/1`.
  Taxonomy: happy / boundary / error. Data via `LoanActor.Factory` (test-data-forge).
  """

  use ExUnit.Case, async: true

  alias LoanActor.Event
  alias LoanActor.Factory

  describe "validate/1 — happy" do
    test "a fully populated, well-formed event validates" do
      assert :ok = Event.validate(Factory.event())
    end

    test "every documented source value validates" do
      for source <- Event.sources() do
        assert :ok = Event.validate(Factory.event(%{source: source}))
      end
    end

    test "every documented type value validates" do
      for type <- Event.event_types() do
        assert :ok = Event.validate(Factory.event(%{type: type}))
      end
    end
  end

  describe "validate/1 — boundary" do
    test "minimal (1-character) event_id is valid" do
      assert :ok = Event.validate(Factory.event(%{event_id: "e"}))
    end

    test "an empty payload map is valid" do
      assert :ok = Event.validate(Factory.event(%{payload: %{}}))
    end

    test "a fully populated payload map is valid" do
      payload = %{"doc_type" => "income", "size_bytes" => 1024, "tags" => ["a", "b"]}
      assert :ok = Event.validate(Factory.event(%{payload: payload}))
    end

    test "sources/0 is exactly the three documented values" do
      assert Event.sources() == [:operator, :system, :test]
    end

    test "event_types/0 is exactly the eleven documented values" do
      assert length(Event.event_types()) == 11
      assert :heartbeat in Event.event_types()
      assert :abort in Event.event_types()
    end
  end

  describe "validate/1 — error (parametrized invalid catalog)" do
    test "every invalid variant is rejected with the documented error shape" do
      for {label, attrs} <- Factory.invalid_event_variants() do
        event = struct!(Event, attrs)
        assert {:error, :invalid_event} = Event.validate(event), "expected #{label} to be invalid"
      end
    end

    test "a bare %Event{} (all fields nil) is invalid" do
      assert {:error, :invalid_event} = Event.validate(%Event{})
    end
  end
end
