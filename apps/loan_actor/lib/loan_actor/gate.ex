defmodule LoanActor.Gate do
  @moduledoc """
  The parsed, in-memory form of one gate pack's rule (intent 0003, ADH-003;
  `contracts/gate-behaviour.md`'s hard-capped predicate DSL).

  Built by `LoanActor.Tools.EvaluateGate` from a gate pack's front-matter
  (parsed into nested maps/lists by `LoanActor.Skill.Loader`'s own
  extension, ADH-005) — this module owns validating that structure against
  the hard cap, and evaluating it against an assessment/state pair. It
  does NOT read `SKILL.md` files itself.
  """

  @enforce_keys [:gate_id, :version, :combinator, :predicates, :pack_id]
  defstruct [:gate_id, :version, :combinator, :predicates, :pack_id]

  @type combinator :: :all | :any
  @type predicate :: %{required(:field) => String.t(), required(:op) => atom(), optional(:value) => term()}
  @type predicate_or_group :: predicate() | %{combinator: combinator(), predicates: [predicate()]}

  @type t :: %__MODULE__{
          gate_id: String.t(),
          version: String.t(),
          combinator: combinator(),
          predicates: [predicate_or_group()],
          pack_id: String.t()
        }

  @combinators [:all, :any]
  @ops [:eq, :neq, :gt, :gte, :lt, :lte, :present, :absent, :contains]
  @no_value_ops [:present, :absent]

  # The two sentinel "we don't know yet" values LoanActor.Assessment ever
  # produces (:unknown for document_completeness, :n_a for sla_state) — a
  # predicate whose resolved field holds one of these, and whose own
  # comparison isn't itself checking for that sentinel, cannot produce a
  # confident pass/fail (gate-behaviour.md's rule-design-level
  # :indeterminate case): "we don't know" is not the same claim as "we
  # checked and the answer is no."
  @sentinel_values [:unknown, :n_a]

  @doc "The closed set of legal `combinator` values."
  @spec combinators() :: [combinator()]
  def combinators, do: @combinators

  @doc "The closed set of legal predicate `op` values."
  @spec ops() :: [atom()]
  def ops, do: @ops

  @doc """
  Parse + validate a rule map (from a gate pack's front-matter, already
  decoded into nested Elixir maps/lists by the loader) into a `%Gate{}`.
  Returns `{:error, reason}` rather than raising — mirrors
  `LoanActor.Skill.Loader`'s own error-tuple convention, since a malformed
  gate pack is REJECTED with a specific logged reason (`gate-pack-format.md`
  invariant 9), not an exception the loader would have to rescue generically.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) do
    with {:ok, gate_id} <- fetch_binary(attrs, :gate_id),
         {:ok, version} <- fetch_binary(attrs, :version),
         {:ok, pack_id} <- fetch_binary(attrs, :pack_id),
         {:ok, rule} <- fetch_map(attrs, :rule),
         {:ok, combinator} <- parse_combinator(Map.get(rule, "combinator")),
         {:ok, predicates} <- parse_predicates(Map.get(rule, "predicates")) do
      {:ok,
       %__MODULE__{
         gate_id: gate_id,
         version: version,
         combinator: combinator,
         predicates: predicates,
         pack_id: pack_id
       }}
    end
  end

  @doc """
  Evaluate a `%Gate{}` against an evaluation context
  `%{assessment: %LoanActor.Assessment{}, state: %LoanActor.State{}}`.
  Returns `{outcome, cause}` where `outcome` is `:pass | :fail | :indeterminate`
  and `cause` is a machine-readable string naming exactly which
  predicate/condition produced it (`gate-behaviour.md` Outcome semantics).
  """
  @spec evaluate(t(), map()) :: {:pass | :fail | :indeterminate, String.t()}
  def evaluate(%__MODULE__{} = gate, eval_ctx) do
    case combine(gate.combinator, gate.predicates, eval_ctx) do
      {true, _cause} -> {:pass, "gate_id:#{gate.gate_id}"}
      {false, cause} -> {:fail, cause}
      {:indeterminate, cause} -> {:indeterminate, cause}
    end
  end

  # ---- combination (three-valued: true | false | :indeterminate) ----

  defp combine(:all, items, eval_ctx) do
    results = Enum.map(items, &evaluate_item(&1, eval_ctx))

    cond do
      Enum.any?(results, &match?({false, _}, &1)) ->
        {_, cause} = Enum.find(results, &match?({false, _}, &1))
        {false, cause}

      Enum.any?(results, &match?({:indeterminate, _}, &1)) ->
        {_, cause} = Enum.find(results, &match?({:indeterminate, _}, &1))
        {:indeterminate, cause}

      true ->
        {true, nil}
    end
  end

  defp combine(:any, items, eval_ctx) do
    results = Enum.map(items, &evaluate_item(&1, eval_ctx))

    cond do
      Enum.any?(results, &match?({true, _}, &1)) ->
        {true, nil}

      Enum.any?(results, &match?({:indeterminate, _}, &1)) ->
        {_, cause} = Enum.find(results, &match?({:indeterminate, _}, &1))
        {:indeterminate, cause}

      true ->
        {_, cause} = List.first(results) || {false, "empty_predicate_list"}
        {false, cause}
    end
  end

  defp evaluate_item(%{combinator: nested_combinator, predicates: nested_predicates}, eval_ctx) do
    combine(nested_combinator, nested_predicates, eval_ctx)
  end

  defp evaluate_item(%{field: field, op: op} = predicate, eval_ctx) do
    case resolve_field(eval_ctx, field) do
      :unresolvable ->
        {:indeterminate, "unresolvable_field:#{field}"}

      {:ok, value} ->
        evaluate_predicate(field, op, value, Map.get(predicate, :value))
    end
  end

  defp evaluate_predicate(field, op, value, _cmp) when op in @no_value_ops do
    result =
      case op do
        :present -> value != nil
        :absent -> value == nil
      end

    {result, "field:#{field},op:#{op}"}
  end

  defp evaluate_predicate(field, op, value, cmp) do
    if value in @sentinel_values and not checking_for_sentinel?(op, cmp, value) do
      {:indeterminate, "unknown_value:#{field}"}
    else
      {compare(op, value, cmp), "field:#{field},op:#{op},value:#{inspect(cmp)}"}
    end
  end

  defp checking_for_sentinel?(:eq, cmp, sentinel), do: normalize(cmp) == sentinel
  defp checking_for_sentinel?(:neq, cmp, sentinel), do: normalize(cmp) == sentinel
  defp checking_for_sentinel?(_op, _cmp, _sentinel), do: false

  defp compare(:eq, value, cmp), do: value == normalize(cmp)
  defp compare(:neq, value, cmp), do: value != normalize(cmp)
  defp compare(:gt, value, cmp), do: comparable(value, cmp) and value > cmp
  defp compare(:gte, value, cmp), do: comparable(value, cmp) and value >= cmp
  defp compare(:lt, value, cmp), do: comparable(value, cmp) and value < cmp
  defp compare(:lte, value, cmp), do: comparable(value, cmp) and value <= cmp
  defp compare(:contains, value, cmp) when is_list(value), do: normalize(cmp) in Enum.map(value, &normalize/1)
  defp compare(:contains, _value, _cmp), do: false

  defp comparable(value, cmp), do: is_number(value) and is_number(cmp)

  # Front-matter values may arrive as strings (e.g. "complete"); assessment
  # struct fields hold atoms. Normalizing lets a rule pack author write
  # `value: complete` and have it match `:complete` without the DSL
  # exposing Elixir-atom syntax to a non-programmer rule author.
  defp normalize(v) when is_binary(v), do: String.to_existing_atom(v)
  defp normalize(v), do: v

  # ---- field-path resolution (assessment.* or state.* only) ----

  defp resolve_field(eval_ctx, "assessment." <> rest), do: resolve_path(Map.get(eval_ctx, :assessment), rest)
  defp resolve_field(eval_ctx, "state." <> rest), do: resolve_path(Map.get(eval_ctx, :state), rest)
  defp resolve_field(_eval_ctx, _field), do: :unresolvable

  defp resolve_path(nil, _rest), do: :unresolvable

  defp resolve_path(struct, field) do
    key = String.to_existing_atom(field)

    if is_struct(struct) and Map.has_key?(struct, key) do
      {:ok, Map.get(struct, key)}
    else
      :unresolvable
    end
  rescue
    ArgumentError -> :unresolvable
  end

  # ---- parsing (hard cap enforcement) ----

  defp fetch_binary(attrs, key) do
    case Map.get(attrs, key) do
      v when is_binary(v) and byte_size(v) > 0 -> {:ok, v}
      _ -> {:error, {:missing_or_invalid, key}}
    end
  end

  defp fetch_map(attrs, key) do
    case Map.get(attrs, key) do
      v when is_map(v) -> {:ok, v}
      _ -> {:error, {:missing_or_invalid, key}}
    end
  end

  defp parse_combinator(v) when is_binary(v) do
    case v do
      "all" -> {:ok, :all}
      "any" -> {:ok, :any}
      _ -> {:error, {:invalid_combinator, v}}
    end
  end

  defp parse_combinator(v) when v in @combinators, do: {:ok, v}
  defp parse_combinator(v), do: {:error, {:invalid_combinator, v}}

  defp parse_predicates(list) when is_list(list) and list != [] do
    list
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case parse_predicate_or_group(item) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp parse_predicates(other), do: {:error, {:invalid_predicates, other}}

  defp parse_predicate_or_group(%{"combinator" => _, "predicates" => nested} = group)
       when is_list(nested) do
    with {:ok, combinator} <- parse_combinator(Map.get(group, "combinator")),
         {:ok, predicates} <- parse_leaf_predicates(nested) do
      {:ok, %{combinator: combinator, predicates: predicates}}
    end
  end

  defp parse_predicate_or_group(%{"field" => _} = leaf), do: parse_leaf_predicate(leaf)
  defp parse_predicate_or_group(other), do: {:error, {:invalid_predicate, other}}

  defp parse_leaf_predicates(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case parse_leaf_predicate(item) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp parse_leaf_predicate(%{"field" => field, "op" => op_str} = raw) when is_binary(field) do
    with {:ok, op} <- parse_op(op_str),
         {:ok, value} <- parse_value(op, Map.get(raw, "value")) do
      predicate = %{field: field, op: op}
      predicate = if op in @no_value_ops, do: predicate, else: Map.put(predicate, :value, value)
      {:ok, predicate}
    end
  end

  defp parse_leaf_predicate(other), do: {:error, {:invalid_predicate, other}}

  defp parse_op(op_str) when is_binary(op_str) do
    case Enum.find(@ops, &(Atom.to_string(&1) == op_str)) do
      nil -> {:error, {:invalid_op, op_str}}
      op -> {:ok, op}
    end
  end

  defp parse_op(other), do: {:error, {:invalid_op, other}}

  defp parse_value(op, nil) when op in @no_value_ops, do: {:ok, nil}
  defp parse_value(op, _value) when op in @no_value_ops, do: {:error, {:unexpected_value, op}}
  defp parse_value(_op, nil), do: {:error, :missing_value}
  defp parse_value(_op, value) when is_binary(value) or is_number(value) or is_boolean(value), do: {:ok, value}
  defp parse_value(_op, value), do: {:error, {:invalid_value, value}}
end
