defmodule LoanActor.Tool.Spec do
  @moduledoc """
  Typed description of a tool + the args validator (FT-041).

  `parameters` is a JSON-Schema map restricted to the foundation subset —
  **HARD CAP** per `contracts/tool-behaviour.md`:

  - `"type"` — `"object" | "string" | "integer" | "boolean" | "array"`
  - `"properties"` — map of key → sub-schema (objects only)
  - `"required"` — list of property names (objects only)
  - `"enum"` — list of allowed values

  Any other keyword is rejected at spec construction time (`new/1`), so a
  drifting schema fails fast in the tool's own tests, not at invocation.
  Extending the subset requires an amendment intent.

  Validation follows JSON-Schema defaults: properties not listed in
  `"required"` are optional, and keys not covered by `"properties"` are
  permitted (no `additionalProperties` semantics in the subset).

  Schemas and args use **string keys** — args cross the JSON boundary
  (AG-UI `ToolCallArgs`, diary payload hashing) and must round-trip.
  """

  @allowed_keywords ~w(type properties required enum)
  @allowed_types ~w(object string integer boolean array)

  @enforce_keys [:name, :description, :parameters]
  defstruct [:name, :description, :parameters]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          parameters: map()
        }

  @doc """
  Build a validated spec. Raises `ArgumentError` if `name`/`description` are
  empty or `parameters` uses anything outside the schema subset.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)

    fields = %{
      name: attrs |> Map.fetch!(:name) |> validate_binary(:name),
      description: attrs |> Map.fetch!(:description) |> validate_binary(:description),
      parameters: attrs |> Map.fetch!(:parameters) |> validate_schema!([])
    }

    struct!(__MODULE__, fields)
  end

  @doc """
  Validate `args` against `spec.parameters`.

  Returns `:ok` or `{:error, {:invalid_args, [{path, reason}, ...]}}` where
  `path` is the list of keys from the root to the offending value.
  """
  @spec validate_args(t(), map()) :: :ok | {:error, {:invalid_args, [{[String.t()], atom()}]}}
  def validate_args(%__MODULE__{parameters: schema}, args) do
    case errors(schema, args, []) do
      [] -> :ok
      errs -> {:error, {:invalid_args, Enum.reverse(errs)}}
    end
  end

  defp validate_binary(v, _field) when is_binary(v) and byte_size(v) > 0, do: v

  defp validate_binary(v, field),
    do: raise(ArgumentError, "#{field} must be a non-empty binary, got: #{inspect(v)}")

  # ---- schema-shape validation (construction time) ----

  defp validate_schema!(schema, path) when is_map(schema) do
    check_keywords!(schema, path)
    check_type!(schema, path)
    check_properties!(schema, path)
    check_required!(schema, path)
    check_enum!(schema, path)
    schema
  end

  defp validate_schema!(other, path),
    do: raise_cap_violation(path, "schema must be a map, got: #{inspect(other)}")

  defp check_keywords!(schema, path) do
    case Enum.find(Map.keys(schema), &(&1 not in @allowed_keywords)) do
      nil -> :ok
      key -> raise_cap_violation(path, "keyword #{inspect(key)} is outside the subset")
    end
  end

  defp check_type!(schema, path) do
    case Map.get(schema, "type") do
      nil -> :ok
      type when type in @allowed_types -> :ok
      type -> raise_cap_violation(path, "type #{inspect(type)} is outside the subset")
    end
  end

  defp check_properties!(schema, path) do
    case Map.get(schema, "properties", %{}) do
      props when is_map(props) ->
        Enum.each(props, fn {key, sub} -> validate_schema!(sub, path ++ [key]) end)

      _other ->
        raise_cap_violation(path, "properties must be a map")
    end
  end

  defp check_required!(schema, path) do
    required = Map.get(schema, "required", [])

    if is_list(required) and Enum.all?(required, &is_binary/1) do
      :ok
    else
      raise_cap_violation(path, "required must be a list of strings")
    end
  end

  defp check_enum!(schema, path) do
    case Map.get(schema, "enum") do
      nil -> :ok
      enum when is_list(enum) and enum != [] -> :ok
      _other -> raise_cap_violation(path, "enum must be a non-empty list")
    end
  end

  @spec raise_cap_violation([String.t()], String.t()) :: no_return()
  defp raise_cap_violation(path, message) do
    raise ArgumentError,
          "tool parameters schema violates the foundation subset at #{inspect(path)}: " <>
            message <> " (see contracts/tool-behaviour.md)"
  end

  # ---- args validation (invocation time) ----

  defp errors(schema, value, path) do
    []
    |> type_errors(schema, value, path)
    |> enum_errors(schema, value, path)
    |> object_errors(schema, value, path)
  end

  defp type_errors(acc, %{"type" => type}, value, path) do
    if type_ok?(type, value), do: acc, else: [{path, :wrong_type} | acc]
  end

  defp type_errors(acc, _schema, _value, _path), do: acc

  defp type_ok?("object", v), do: is_map(v)
  defp type_ok?("string", v), do: is_binary(v)
  defp type_ok?("integer", v), do: is_integer(v)
  defp type_ok?("boolean", v), do: is_boolean(v)
  defp type_ok?("array", v), do: is_list(v)

  defp enum_errors(acc, %{"enum" => enum}, value, path) do
    if value in enum, do: acc, else: [{path, :not_in_enum} | acc]
  end

  defp enum_errors(acc, _schema, _value, _path), do: acc

  defp object_errors(acc, schema, value, path) when is_map(value) do
    required = Map.get(schema, "required", [])
    properties = Map.get(schema, "properties", %{})

    acc =
      Enum.reduce(required, acc, fn key, acc ->
        if Map.has_key?(value, key), do: acc, else: [{path ++ [key], :missing_required} | acc]
      end)

    Enum.reduce(properties, acc, fn {key, sub}, acc ->
      case Map.fetch(value, key) do
        {:ok, sub_value} -> errors(sub, sub_value, path ++ [key]) ++ acc
        :error -> acc
      end
    end)
  end

  defp object_errors(acc, _schema, _value, _path), do: acc
end
