defmodule LoanActor.Tools.SetGoal do
  @moduledoc """
  Adds a new goal to the loan's goal list (FT-043; periodic loop per
  `contracts/tool-behaviour.md`'s foundation tool table). Returns the
  effect `%{add_goal: %LoanActor.Goal{}}`; the Server (FT-018) applies it
  by appending to `state.goals` and diary-logging `:goal_set`.

  Deterministic: the new goal's `goal_id` is `ctx.invocation_id` — already
  unique per invocation — so the same `(args, ctx)` always produces the
  same goal, never a fresh random id (which would break the "same args+ctx
  → same result" determinism the shared tool suite requires).
  """

  @behaviour LoanActor.Tool

  alias LoanActor.Goal
  alias LoanActor.Tool.Spec

  @impl LoanActor.Tool
  def spec do
    Spec.new(%{
      name: "set_goal",
      description: "Add a new goal for the loan to pursue.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "description" => %{"type" => "string"},
          "due_at" => %{"type" => "string"}
        },
        "required" => ["description"]
      }
    })
  end

  @impl LoanActor.Tool
  def execute(args, ctx) do
    with {:ok, due_at} <- parse_due_at(Map.get(args, "due_at")) do
      goal =
        Goal.new(%{
          goal_id: ctx.invocation_id,
          description: args["description"],
          status: :open,
          due_at: due_at
        })

      {:ok, %{add_goal: goal}}
    end
  end

  defp parse_due_at(nil), do: {:ok, nil}

  defp parse_due_at(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, {:invalid_due_at, reason}}
    end
  end
end
