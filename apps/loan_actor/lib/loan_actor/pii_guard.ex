defmodule LoanActor.PIIGuard do
  @moduledoc """
  The gate every event payload passes through before the diary write
  (FT-014; `data-model.md` "PII boundary"; constitution Principle IV).

  **Foundation implementation is a hard gate, not redact-and-continue** —
  resolved 2026-07-21 to close a genuine ambiguity between data-model.md's
  narrative description and `tasks.md` FT-014's literal `apply/1` return-shape
  contract (which documents two distinct outcomes, `{:ok, ...}` and
  `{:error, ...}`, without stating what distinguishes them). Confirmed
  design: any payload with a value anywhere matching a configured PII
  pattern is **rejected outright** — `redacted_paths` in the `:ok` branch is
  always `[]` in foundation, a forward-compatible field for the future
  PII-vault intent that data-model.md's closing note anticipates
  ("PIIGuard will then write to the vault and store the returned
  `payload_ref`") — that future version redacts-and-substitutes; foundation
  only gates.

  Patterns load from `priv/pii_patterns.yml`, parsed by a restricted
  hand-rolled reader (NOT a general YAML library — no such dependency is
  declared in intent 0001's or 0004's Dependencies sections; see the file's
  own header comment for the grammar and the rationale for avoiding a new
  dependency, mirroring the skill-format front-matter cap).
  """

  @type path :: [String.t() | non_neg_integer()]

  @doc """
  Load and compile the configured PII patterns. Raises on a malformed file
  or an invalid regex — a broken pattern file is a boot-time configuration
  error, not a runtime data condition.
  """
  @spec patterns() :: [{String.t(), Regex.t()}]
  def patterns do
    patterns_path()
    |> File.read!()
    |> parse!()
    |> Enum.map(fn {name, source} -> {name, Regex.compile!(source)} end)
  end

  @doc """
  Scan `payload` for any string value, at any nesting depth, matching a
  configured PII pattern.

  Returns `{:ok, payload, []}` if nothing matches (payload passed through
  unchanged) or `{:error, :pii_violation, paths}` — `paths` lists every
  offending key-path (root-relative, each a list of string map-keys and/or
  list indices) — if anything matches anywhere.
  """
  @spec apply(map()) :: {:ok, map(), []} | {:error, :pii_violation, [path()]}
  def apply(payload) when is_map(payload) do
    case scan(payload, [], patterns()) do
      [] -> {:ok, payload, []}
      paths -> {:error, :pii_violation, paths}
    end
  end

  # ---- scan ----

  defp scan(value, path, patterns) when is_map(value) do
    Enum.flat_map(value, fn {k, v} -> scan(v, [to_string(k) | path], patterns) end)
  end

  defp scan(value, path, patterns) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {v, i} -> scan(v, [i | path], patterns) end)
  end

  defp scan(value, path, patterns) when is_binary(value) do
    if Enum.any?(patterns, fn {_name, regex} -> Regex.match?(regex, value) end) do
      [Enum.reverse(path)]
    else
      []
    end
  end

  defp scan(_value, _path, _patterns), do: []

  # ---- restricted-grammar parser (see priv/pii_patterns.yml header) ----

  defp parse!(content) do
    content
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.chunk_every(2)
    |> Enum.map(&parse_pair!/1)
  end

  defp parse_pair!([name_line, regex_line]) do
    name = extract!(name_line, ~r/^-\s*name:\s*(\S+)$/)
    regex_source = extract!(regex_line, ~r/^regex:\s*"(.*)"$/)
    {name, regex_source}
  end

  defp parse_pair!(other), do: raise("malformed pii_patterns.yml entry: #{inspect(other)}")

  defp extract!(line, regex) do
    case Regex.run(regex, line) do
      [_, captured] -> captured
      _ -> raise("malformed pii_patterns.yml line: #{inspect(line)}")
    end
  end

  defp patterns_path do
    Path.join(priv_dir(), "pii_patterns.yml")
  end

  defp priv_dir do
    case :code.priv_dir(:loan_actor) do
      {:error, _} -> Path.join("priv", "")
      priv -> List.to_string(priv)
    end
  end
end
