defmodule LoanActor.HITLTest do
  @moduledoc """
  FT-028 — `LoanActor.HITLRequest`/`LoanActor.HITLResponse` +
  `LoanActor.Server`'s `respond_hitl/3`. Taxonomy: happy / error / race.

  A pending HITL request is discovered the same way a real operator
  client would: subscribing to the AG-UI stream and reading the
  `request_id` out of the `CustomEvent name="hitl_request"` frame — diary
  entries only ever carry a HASH of tool args/results (constitution
  Principle VIII), so the request_id cannot be recovered from the diary
  alone. The `request_operator_approval` tool only ever fires from the
  planning loop (no public invoke API, Principle I), so a temporary skill
  pack (test-data-forge, mirrors `test/skill/loader_test.exs`'s inline
  fixture-writing pattern) is what actually summons it here.
  """

  use ExUnit.Case, async: false

  alias LoanActor.Diary.File, as: FileStore
  alias LoanActor.Diary.Mnesia, as: MnesiaStore
  alias LoanActor.Factory
  alias LoanActor.FileTestSupport
  alias LoanActor.HITLRequest
  alias LoanActor.HITLResponse
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
    previous_skills_dir = Application.get_env(:loan_actor, :skills_dir)
    on_exit(fn -> restore(:skills_dir, previous_skills_dir) end)
    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:loan_actor, key)
  defp restore(key, value), do: Application.put_env(:loan_actor, key, value)

  defp hitl_skill_dir do
    dir = Factory.unique_tmp_dir("loan_actor_hitl_skill")
    pack_dir = Path.join(dir, "0001-demo-hitl")
    File.mkdir_p!(pack_dir)

    File.write!(Path.join(pack_dir, "SKILL.md"), """
    ---
    name: demo-hitl
    version: 1.0.0
    description: During plan review, ask the operator to approve or reject this loan.
    tools_required: [request_operator_approval]
    ---

    Body.
    """)

    dir
  end

  defp spawn_loan_with_hitl_skill do
    Application.put_env(:loan_actor, :skills_dir, hitl_skill_dir())
    loan_id = Factory.unique_loan_id()
    {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)
    {:ok, ref} = LoanActor.subscribe(loan_id)
    {:ok, 1} = LoanActor.send_event(loan_id, Factory.event(%{type: :goal_set}))
    {loan_id, ref}
  end

  defp fresh_response(request_id, overrides \\ %{}) do
    HITLResponse.new(
      Map.merge(
        %{
          request_id: request_id,
          decision: "approve",
          operator_id: "alice",
          responded_at: DateTime.utc_now()
        },
        overrides
      )
    )
  end

  describe "happy — deferred ToolCallResult observed" do
    test "request_operator_approval parks a HITLRequest; respond_hitl completes the deferred ToolCallResult" do
      {loan_id, ref} = spawn_loan_with_hitl_skill()

      # RunStarted-equivalent setup frames don't exist on subscribe/2 (that's
      # the HTTP route's job, FT-027) — the first frames here are whatever
      # the reactive+planning loops produce.
      assert_receive {:ag_ui_event, ^ref,
                      %{"type" => "CustomEvent", "name" => "hitl_request", "loan_id" => ^loan_id, "request" => request}},
                     2_000

      assert request["loan_id"] == loan_id
      assert is_binary(request["prompt"])
      assert request["options"] == ["approve", "reject"]
      request_id = request["request_id"]

      response = fresh_response(request_id)
      assert :ok = LoanActor.respond_hitl(loan_id, request_id, response)

      assert_receive {:ag_ui_event, ^ref, %{"type" => "ToolCallResult", "tool_call_id" => ^request_id} = result_event},
                     2_000

      content = Jason.decode!(result_event["content"])
      assert content["decision"] == "approve"
      assert content["operator_id"] == "alice"
    end
  end

  describe "race — double respond, first wins" do
    test "a second response for an already-answered request is a conflict, not a second ToolCallResult" do
      {loan_id, ref} = spawn_loan_with_hitl_skill()

      assert_receive {:ag_ui_event, ^ref, %{"type" => "CustomEvent", "name" => "hitl_request", "request" => request}},
                     2_000

      request_id = request["request_id"]
      first = fresh_response(request_id, %{operator_id: "alice", decision: "approve"})

      assert :ok = LoanActor.respond_hitl(loan_id, request_id, first)
      assert_receive {:ag_ui_event, ^ref, %{"type" => "ToolCallResult", "tool_call_id" => ^request_id}}, 2_000

      second = fresh_response(request_id, %{operator_id: "bob", decision: "reject"})
      assert {:conflict, ^first} = LoanActor.respond_hitl(loan_id, request_id, second)

      assert_receive {:ag_ui_event, ^ref,
                      %{"type" => "CustomEvent", "name" => "hitl_conflict", "loan_id" => ^loan_id, "request_id" => ^request_id}},
                     2_000

      # First response's ToolCallResult was already consumed above — the
      # conflicting second response must not produce a second one for the
      # same tool_call_id (AG-UI's contract: exactly one Result per invocation).
      refute_receive {:ag_ui_event, ^ref, %{"type" => "ToolCallResult", "tool_call_id" => ^request_id}}, 200
    end
  end

  describe "error — responding to a non-existent request" do
    test "an unknown request_id returns {:error, :not_found}" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      response = fresh_response("not-a-real-request")
      assert {:error, :not_found} = LoanActor.respond_hitl(loan_id, "not-a-real-request", response)
    end
  end

  describe "HITLRequest.new/1 — happy + error (construction invariants)" do
    test "a valid attribute map builds a %HITLRequest{}" do
      assert %HITLRequest{} = Factory.hitl_request()
    end

    for {label, attrs} <- Factory.invalid_hitl_request_variants() do
      test "rejects invalid variant #{label}" do
        attrs = unquote(Macro.escape(attrs))
        assert_raise ArgumentError, fn -> HITLRequest.new(attrs) end
      end
    end
  end

  describe "HITLResponse.new/1 — happy + error (construction invariants)" do
    test "a valid attribute map builds a %HITLResponse{}" do
      assert %HITLResponse{} = Factory.hitl_response()
    end

    test "comment defaults to nil" do
      assert Factory.hitl_response().comment == nil
    end

    for {label, attrs} <- Factory.invalid_hitl_response_variants() do
      test "rejects invalid variant #{label}" do
        attrs = unquote(Macro.escape(attrs))
        assert_raise ArgumentError, fn -> HITLResponse.new(attrs) end
      end
    end
  end
end
