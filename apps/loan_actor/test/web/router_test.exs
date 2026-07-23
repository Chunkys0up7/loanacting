defmodule LoanActor.Web.RouterTest do
  @moduledoc """
  FT-027 — `LoanActor.Web.Router`, per `contracts/http-endpoints.md`.
  Taxonomy: happy / boundary / error / contract. Real `Plug.Conn` structs
  via `Plug.Test.conn/3` dispatched through the actual router (no
  hand-rolled fixtures); real spawned actors via `ServerTestSupport`/the
  route itself, real diary/PII/idempotency pipeline underneath — no mocks
  at the boundary.
  """

  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias LoanActor.Diary.File, as: FileStore
  alias LoanActor.Diary.Mnesia, as: MnesiaStore
  alias LoanActor.Event
  alias LoanActor.Factory
  alias LoanActor.FileTestSupport
  alias LoanActor.MnesiaTestSupport
  alias LoanActor.ServerTestSupport
  alias LoanActor.Web.Router

  @opts Router.init([])

  setup_all do
    :ok = FileStore.init(dir: FileTestSupport.dir())
    # LoanActor.Idempotency's loan_idem table is always Mnesia (data-model.md),
    # independent of which DiaryStore backs the actual entries.
    :ok = MnesiaStore.init(dir: MnesiaTestSupport.dir())
    :ok
  end

  setup do
    on_exit(fn -> Application.delete_env(:loan_actor, :ag_ui_stream_max_events) end)
    :ok
  end

  defp call(conn), do: Router.call(conn, @opts)

  defp json_conn(method, path, body) do
    method
    |> conn(path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
  end

  defp track_for_cleanup(loan_id) do
    on_exit(fn ->
      case LoanActor.whereis(loan_id) do
        nil -> :ok
        pid -> DynamicSupervisor.terminate_child(LoanActor.Supervisor, pid)
      end
    end)
  end

  describe "POST /loans" do
    test "fresh loan_id spawns and returns 201" do
      loan_id = Factory.unique_loan_id()
      track_for_cleanup(loan_id)

      conn = json_conn(:post, "/loans", %{"loan_id" => loan_id}) |> call()

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["loan_id"] == loan_id
      assert body["status"] == "spawned"
      assert body["version"] == 0
    end

    test "an omitted loan_id is server-generated" do
      conn = json_conn(:post, "/loans", %{}) |> call()

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert is_binary(body["loan_id"])
      assert body["loan_id"] != ""
      track_for_cleanup(body["loan_id"])
    end

    test "re-POSTing an already-running loan_id is idempotent (200)" do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      conn = json_conn(:post, "/loans", %{"loan_id" => loan_id}) |> call()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["loan_id"] == loan_id
      assert body["status"] == "spawned"
    end
  end

  describe "POST /loans/:loan_id/events" do
    setup do
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)
      %{loan_id: loan_id}
    end

    defp event_body(overrides) do
      %{
        "event_id" => "EVT-#{System.unique_integer([:positive, :monotonic])}",
        "source" => "test",
        "type" => "goal_set",
        "payload" => %{},
        "created_at" => DateTime.to_iso8601(DateTime.utc_now())
      }
      |> Map.merge(overrides)
    end

    test "a legal event returns 202 ok with a sequence", %{loan_id: loan_id} do
      conn = json_conn(:post, "/loans/#{loan_id}/events", event_body(%{})) |> call()

      assert conn.status == 202
      body = Jason.decode!(conn.resp_body)
      assert body["result"] == "ok"
      assert is_integer(body["sequence"])
    end

    test "re-POSTing the same event_id returns 202 duplicate", %{loan_id: loan_id} do
      body = event_body(%{})

      first = json_conn(:post, "/loans/#{loan_id}/events", body) |> call()
      assert first.status == 202
      assert Jason.decode!(first.resp_body)["result"] == "ok"

      second = json_conn(:post, "/loans/#{loan_id}/events", body) |> call()
      assert second.status == 202
      assert Jason.decode!(second.resp_body)["result"] == "duplicate"
    end

    test "a structurally invalid event returns 400", %{loan_id: loan_id} do
      conn = json_conn(:post, "/loans/#{loan_id}/events", event_body(%{"event_id" => ""})) |> call()

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] == "invalid_event"
    end

    test "PII in the payload returns 422 with the offending paths", %{loan_id: loan_id} do
      body = event_body(%{"payload" => %{"note" => "SSN: 123-45-6789"}})

      conn = json_conn(:post, "/loans/#{loan_id}/events", body) |> call()

      assert conn.status == 422
      resp = Jason.decode!(conn.resp_body)
      assert resp["error"] == "pii_violation"
      assert resp["paths"] != []
    end

    test "an illegal transition returns 409", %{loan_id: loan_id} do
      body = event_body(%{"type" => "document_uploaded"})

      conn = json_conn(:post, "/loans/#{loan_id}/events", body) |> call()

      assert conn.status == 409
      resp = Jason.decode!(conn.resp_body)
      assert resp["error"] == "illegal_transition"
      assert resp["from"] == "spawned"
      assert resp["event_type"] == "document_uploaded"
    end

    test "an event to a loan that isn't running returns 404" do
      conn = json_conn(:post, "/loans/not-a-real-loan/events", event_body(%{})) |> call()

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "not_running"
    end
  end

  describe "POST /loans/:loan_id/hitl/:request_id" do
    defp hitl_skill_dir do
      Factory.write_skill_pack!(Factory.unique_tmp_dir("loan_actor_router_hitl_skill"), %{
        id: "0001-demo-hitl",
        name: "demo-hitl",
        description: "During plan review, ask the operator to approve or reject this loan.",
        tools_required: ["request_operator_approval"]
      })
    end

    setup do
      previous_skills_dir = Application.get_env(:loan_actor, :skills_dir)

      on_exit(fn ->
        case previous_skills_dir do
          nil -> Application.delete_env(:loan_actor, :skills_dir)
          value -> Application.put_env(:loan_actor, :skills_dir, value)
        end
      end)

      Application.put_env(:loan_actor, :skills_dir, hitl_skill_dir())

      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)
      # Discovering the request_id the way an operator client would (reading
      # the hitl_request CustomEvent) needs a live subscription; the route
      # under test here is respond_hitl's own HTTP surface, not the SSE
      # route (already covered above), so subscribing directly is the
      # narrowest way to learn the id without re-deriving it from a hash.
      {:ok, ref} = LoanActor.subscribe(loan_id)
      conn = json_conn(:post, "/loans/#{loan_id}/events", event_body(%{})) |> call()
      assert conn.status == 202

      assert_receive {:ag_ui_event, ^ref, %{"type" => "CustomEvent", "name" => "hitl_request", "request" => request}},
                     2_000

      %{loan_id: loan_id, request_id: request["request_id"]}
    end

    test "a valid decision returns 200 accepted", %{loan_id: loan_id, request_id: request_id} do
      conn =
        :post
        |> conn("/loans/#{loan_id}/hitl/#{request_id}", Jason.encode!(%{"decision" => "approve"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-operator-id", "alice")
        |> call()

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"result" => "accepted"}
    end

    test "a second response for the same request returns 409 conflict", %{loan_id: loan_id, request_id: request_id} do
      first =
        :post
        |> conn("/loans/#{loan_id}/hitl/#{request_id}", Jason.encode!(%{"decision" => "approve"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-operator-id", "alice")
        |> call()

      assert first.status == 200

      second =
        :post
        |> conn("/loans/#{loan_id}/hitl/#{request_id}", Jason.encode!(%{"decision" => "reject"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-operator-id", "bob")
        |> call()

      assert second.status == 409
      body = Jason.decode!(second.resp_body)
      assert body["result"] == "conflict"
      assert body["existing_response"]["operator_id"] == "alice"
      assert body["existing_response"]["decision"] == "approve"
    end

    test "an unknown request_id on a running loan returns 404 request_not_found", %{loan_id: loan_id} do
      conn =
        :post
        |> conn("/loans/#{loan_id}/hitl/not-a-real-request", Jason.encode!(%{"decision" => "approve"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-operator-id", "alice")
        |> call()

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "request_not_found"
    end

    test "responding on a loan that isn't running returns 404 not_running" do
      conn =
        :post
        |> conn("/loans/not-a-real-loan/hitl/not-a-real-request", Jason.encode!(%{"decision" => "approve"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-operator-id", "alice")
        |> call()

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "not_running"
    end
  end

  describe "GET|POST /loans/:loan_id/ag-ui" do
    test "streaming to a loan that isn't running returns 404 (GET)" do
      conn = :get |> conn("/loans/not-a-real-loan/ag-ui") |> call()

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "not_running"
    end

    test "streaming to a loan that isn't running returns 404 (POST)" do
      conn = json_conn(:post, "/loans/not-a-real-loan/ag-ui", %{}) |> call()

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "not_running"
    end

    test "a running loan streams RunStarted then StateSnapshot as SSE" do
      Application.put_env(:loan_actor, :ag_ui_stream_max_events, 0)
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      conn = :get |> conn("/loans/#{loan_id}/ag-ui") |> call()

      assert conn.status == 200
      assert conn |> get_resp_header("content-type") |> Enum.at(0) =~ "text/event-stream"
      assert conn.resp_body =~ ~s("type":"RunStarted")
      assert conn.resp_body =~ ~s("type":"StateSnapshot")
    end

    test "the stream also carries a subsequent broadcast diary event" do
      Application.put_env(:loan_actor, :ag_ui_stream_max_events, 1)
      loan_id = Factory.unique_loan_id()
      {:ok, _pid} = ServerTestSupport.spawn_and_track(loan_id)

      Task.start(fn ->
        Process.sleep(50)

        LoanActor.send_event(loan_id, %Event{
          event_id: "EVT-STREAM-#{System.unique_integer([:positive, :monotonic])}",
          source: :test,
          type: :goal_set,
          payload: %{},
          created_at: DateTime.utc_now(),
          received_at: DateTime.utc_now()
        })
      end)

      conn = :get |> conn("/loans/#{loan_id}/ag-ui") |> call()

      assert conn.status == 200
      assert conn.resp_body =~ "diary_entry"
    end
  end

  describe "unmatched routes" do
    test "an unknown path returns 404" do
      conn = :get |> conn("/nope") |> call()

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "not_found"
    end
  end
end
