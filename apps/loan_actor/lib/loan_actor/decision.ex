defmodule LoanActor.Decision do
  @moduledoc """
  Documents the SHAPE of the `:decision` diary entry's payload (intent
  0003, ADH-007; `data-model.md`'s own `%LoanActor.Decision{}` row) — NOT
  a persisted struct; only the diary entry itself is durable, per that
  doc's own note. `payload/2` is the single, canonical builder so every
  call site produces byte-identical shape.
  """

  alias LoanActor.Assessment
  alias LoanActor.Diary.Chain

  @doc """
  Builds the `:decision` diary entry payload for a `:pass`/`:fail`
  `evaluate_gate` outcome. `gate_outcome` is exactly the map the
  `evaluate_gate` tool returns (`%{gate_id:, gate_version:, outcome:,
  cause:}`) — reused directly rather than re-deriving a `%Gate{}`, since
  only `gate_id`/`gate_version` are needed here. `input_digest` hashes
  exactly the `%Assessment{}` the gate was evaluated against — nothing
  else (checklist finding CHK007): per `gate-behaviour.md`, `evaluate_gate`
  reads only `assessment.*`/`state.*` fields, so the assessment alone
  fully captures what the gate saw.
  """
  @spec payload(map(), Assessment.t()) :: map()
  def payload(%{gate_id: gate_id, gate_version: gate_version, outcome: outcome}, %Assessment{} = assessment)
      when outcome in [:pass, :fail] do
    %{
      "gate_id" => gate_id,
      "gate_version" => gate_version,
      "input_digest" => input_digest(assessment),
      "outcome" => outcome
    }
  end

  defp input_digest(assessment) do
    assessment
    |> :erlang.term_to_binary()
    |> Chain.hash()
    |> Base.encode16()
  end
end
