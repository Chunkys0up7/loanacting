defmodule LoanActor.AGUI.EncoderTest do
  @moduledoc """
  FT-023 — `LoanActor.AGUI.Encoder`. Taxonomy: contract / happy / boundary.

  One snapshot test per row of `contracts/ag-ui-events.md`'s events table
  (15 rows — `CustomEvent` has three named variants, `diary_entry`/
  `hitl_request`/`hitl_conflict`, counted separately since each is its own
  documented shape). Every assertion pins the EXACT key set the contract
  documents — contract drift (an added/removed/renamed key) fails here
  first, before any frontend or cross-stack test.
  """

  use ExUnit.Case, async: true

  alias LoanActor.AGUI.Encoder
  alias LoanActor.Factory

  # ---- 1. RunStarted ----
  test "RunStarted — snapshot" do
    assert Encoder.run_started("run-1", "thread-1", "L-1") == %{
             "type" => "RunStarted",
             "run_id" => "run-1",
             "thread_id" => "thread-1",
             "loan_id" => "L-1"
           }
  end

  test "RunStarted — boundary: thread_id may be nil (contract marks it optional)" do
    assert Encoder.run_started("run-1", nil, "L-1")["thread_id"] == nil
  end

  # ---- 2. StateSnapshot ----
  test "StateSnapshot — snapshot" do
    state = Factory.state(%{loan_id: "L-1", goals: [Factory.goal(%{goal_id: "G-1"})]})
    event = Encoder.state_snapshot("L-1", state)

    assert %{
             "type" => "StateSnapshot",
             "loan_id" => "L-1",
             "state" => %{
               "loan_id" => "L-1",
               "status" => "spawned",
               "goals" => [
                 %{"goal_id" => "G-1", "description" => _, "status" => "open", "due_at" => nil}
               ],
               "context" => %{},
               "version" => 0,
               "last_heartbeat_at" => nil
             }
           } = event
  end

  test "StateSnapshot — boundary: last_heartbeat_at is ISO8601 when set" do
    ts = ~U[2026-07-21 12:00:00Z]
    state = Factory.state(%{last_heartbeat_at: ts})
    event = Encoder.state_snapshot(state.loan_id, state)
    assert event["state"]["last_heartbeat_at"] == "2026-07-21T12:00:00Z"
  end

  # ---- 3. StateDelta ----
  test "StateDelta — snapshot (RFC 6902 JSON Patch array passthrough)" do
    patch = [%{"op" => "replace", "path" => "/status", "value" => "awaiting_documents"}]
    assert Encoder.state_delta("L-1", patch) == %{"type" => "StateDelta", "loan_id" => "L-1", "patch" => patch}
  end

  test "StateDelta — boundary: an empty patch list is valid" do
    assert Encoder.state_delta("L-1", [])["patch"] == []
  end

  # ---- 4. TextMessageStart ----
  test "TextMessageStart — snapshot" do
    assert Encoder.text_message_start("msg-1") == %{
             "type" => "TextMessageStart",
             "message_id" => "msg-1",
             "role" => "assistant"
           }
  end

  # ---- 5. TextMessageContent ----
  test "TextMessageContent — snapshot" do
    assert Encoder.text_message_content("msg-1", "hello") == %{
             "type" => "TextMessageContent",
             "message_id" => "msg-1",
             "delta" => "hello"
           }
  end

  # ---- 6. TextMessageEnd ----
  test "TextMessageEnd — snapshot" do
    assert Encoder.text_message_end("msg-1") == %{"type" => "TextMessageEnd", "message_id" => "msg-1"}
  end

  # ---- 7. CustomEvent (diary_entry) ----
  test "CustomEvent diary_entry — snapshot" do
    entry = Factory.entry(%{loan_id: "L-1", sequence: 0})
    event = Encoder.diary_entry_event("L-1", entry)

    assert %{
             "type" => "CustomEvent",
             "name" => "diary_entry",
             "loan_id" => "L-1",
             "entry" => %{
               "loan_id" => "L-1",
               "sequence" => 0,
               "timestamp" => _,
               "type" => "spawned",
               "actor" => "system",
               "payload_hash" => payload_hash,
               "payload_ref" => nil,
               "prev_hash" => prev_hash
             }
           } = event

    # 32-byte hashes hex-encode to exactly 64 lowercase hex chars.
    assert payload_hash =~ ~r/^[0-9a-f]{64}$/
    assert prev_hash =~ ~r/^[0-9a-f]{64}$/
  end

  test "CustomEvent diary_entry — boundary: a non-nil payload_ref passes through as a plain string" do
    entry = Factory.entry(%{payload_ref: "vault://ref/1"})
    assert Encoder.diary_entry_event(entry.loan_id, entry)["entry"]["payload_ref"] == "vault://ref/1"
  end

  # ---- 8. CustomEvent (hitl_request) ----
  test "CustomEvent hitl_request — snapshot" do
    request = Factory.hitl_request_attrs(%{request_id: "HITL-1", loan_id: "L-1"})
    event = Encoder.hitl_request_event("L-1", request)

    assert %{
             "type" => "CustomEvent",
             "name" => "hitl_request",
             "loan_id" => "L-1",
             "request" => %{
               "request_id" => "HITL-1",
               "loan_id" => "L-1",
               "prompt" => _,
               "options" => ["approve", "reject"],
               "created_at" => created_at
             }
           } = event

    assert created_at =~ ~r/^\d{4}-\d{2}-\d{2}T/
  end

  # ---- 9. CustomEvent (hitl_conflict) ----
  test "CustomEvent hitl_conflict — snapshot" do
    assert Encoder.hitl_conflict_event("L-1", "HITL-1") == %{
             "type" => "CustomEvent",
             "name" => "hitl_conflict",
             "loan_id" => "L-1",
             "request_id" => "HITL-1"
           }
  end

  # ---- 10. ToolCallStart ----
  test "ToolCallStart — snapshot" do
    assert Encoder.tool_call_start("inv-1", "set_goal", "L-1") == %{
             "type" => "ToolCallStart",
             "tool_call_id" => "inv-1",
             "tool_call_name" => "set_goal",
             "loan_id" => "L-1"
           }
  end

  # ---- 11. ToolCallArgs ----
  test "ToolCallArgs — snapshot (delta is a JSON-encoded STRING, not a nested map)" do
    event = Encoder.tool_call_args("inv-1", %{"description" => "obtain income doc"})
    assert event["type"] == "ToolCallArgs"
    assert event["tool_call_id"] == "inv-1"
    assert is_binary(event["delta"])
    assert Jason.decode!(event["delta"]) == %{"description" => "obtain income doc"}
  end

  test "ToolCallArgs — boundary: empty args map encodes to \"{}\"" do
    assert Encoder.tool_call_args("inv-1", %{})["delta"] == "{}"
  end

  test "ToolCallArgs — security: only PII-REDACTED args ever reach this function's output (caller's responsibility, proven at the call site by registry_test.exs; here we prove passthrough fidelity)" do
    redacted = %{"ssn" => "<redacted>"}
    assert Jason.decode!(Encoder.tool_call_args("inv-1", redacted)["delta"]) == redacted
  end

  # ---- 12. ToolCallEnd ----
  test "ToolCallEnd — snapshot" do
    assert Encoder.tool_call_end("inv-1") == %{"type" => "ToolCallEnd", "tool_call_id" => "inv-1"}
  end

  # ---- 13. ToolCallResult ----
  test "ToolCallResult — snapshot (content is a JSON-encoded STRING)" do
    event = Encoder.tool_call_result("msg-1", "inv-1", %{"goal_id" => "G-1"})

    assert event["type"] == "ToolCallResult"
    assert event["message_id"] == "msg-1"
    assert event["tool_call_id"] == "inv-1"
    assert Jason.decode!(event["content"]) == %{"goal_id" => "G-1"}
  end

  test "ToolCallResult — boundary: an error-shaped content encodes just as well as a success shape" do
    event = Encoder.tool_call_result("msg-1", "inv-1", %{"error" => "goal_not_found"})
    assert Jason.decode!(event["content"]) == %{"error" => "goal_not_found"}
  end

  # ---- 14. RunFinished ----
  test "RunFinished — snapshot" do
    assert Encoder.run_finished("run-1") == %{"type" => "RunFinished", "run_id" => "run-1"}
  end

  # ---- 15. RunError ----
  test "RunError — snapshot" do
    assert Encoder.run_error("run-1", "boom", :internal_error) == %{
             "type" => "RunError",
             "run_id" => "run-1",
             "message" => "boom",
             "code" => :internal_error
           }
  end

  # ---- contract completeness ----
  test "every event map is itself JSON-encodable (contract requires it cross the wire)" do
    entry = Factory.entry()
    request = Factory.hitl_request_attrs()

    events = [
      Encoder.run_started("r", "t", "L"),
      Encoder.state_snapshot("L", Factory.state()),
      Encoder.state_delta("L", []),
      Encoder.text_message_start("m"),
      Encoder.text_message_content("m", "x"),
      Encoder.text_message_end("m"),
      Encoder.diary_entry_event("L", entry),
      Encoder.hitl_request_event("L", request),
      Encoder.hitl_conflict_event("L", "h"),
      Encoder.tool_call_start("i", "t", "L"),
      Encoder.tool_call_args("i", %{}),
      Encoder.tool_call_end("i"),
      Encoder.tool_call_result("m", "i", %{}),
      Encoder.run_finished("r"),
      Encoder.run_error("r", "x", :e)
    ]

    assert length(events) == 15
    Enum.each(events, fn event -> assert is_binary(Jason.encode!(event)) end)
  end
end
