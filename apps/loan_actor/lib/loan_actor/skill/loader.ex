defmodule LoanActor.Skill.Loader do
  @moduledoc """
  Loads skill packs from `priv/skills/` (FT-044; `contracts/skill-format.md`).
  Supersedes the single-file procedure loader (FT-018b, never built).

  **Restricted grammar** (NOT general YAML — same discipline as
  `LoanActor.PIIGuard`'s pattern file): `SKILL.md` front-matter is
  `key: value` lines and `[a, b, c]` lists only, between `---` fences.

  **Load-time validation**: a pack missing required keys, with unparsable
  front-matter, or whose `tools_required` names a tool absent from
  `LoanActor.Tool.Registry` is rejected — skipped with a logged reason
  (`load_all/1`) or returned as `{:error, reason}` (`load_pack/1`, for
  precise per-pack testability). Rejected packs never trigger.

  **Reload**: mirrors the `Diary.File`/`Diary.Mnesia` pattern — `:dir`
  passed to `load_all/1` is remembered in `Application` env; `reload/0`
  re-scans that same directory. There is no cache to invalidate (every
  call re-reads disk), so "reload" is inherent, not a separate mechanism.

  **Trigger matching**: foundation is intentionally naive — keyword
  overlap between the skill's `description` and the loan's normalized
  match-text (`{status, event_type, goal_descriptions}`), per
  `contracts/skill-format.md`. Real assessment-driven selection is
  intent 0003's job.
  """

  require Logger

  alias LoanActor.Assessment
  alias LoanActor.Gate
  alias LoanActor.Skill
  alias LoanActor.Tool.Registry

  @required_keys ~w(name version description tools_required)
  @stopwords ~w(the a an is has and or when for to of in on at from that this with will)

  @doc """
  Load every pack under `dir` (or the remembered/default directory).
  Invalid packs are skipped with a `Logger.warning/1`. Always succeeds.
  """
  @spec load_all(keyword()) :: {:ok, [Skill.t()]}
  def load_all(opts \\ []) do
    if dir = Keyword.get(opts, :dir) do
      Application.put_env(:loan_actor, :skills_dir, dir)
    end

    skills =
      dir()
      |> pack_dirs()
      |> Enum.flat_map(fn pack_dir ->
        case load_pack(pack_dir) do
          {:ok, skill} ->
            [skill]

          {:error, reason} ->
            Logger.warning("skill pack rejected: #{pack_dir} (#{inspect(reason)})")
            []
        end
      end)

    {:ok, skills}
  end

  @doc "Re-scan the remembered (or default) skills directory. See moduledoc."
  @spec reload() :: {:ok, [Skill.t()]}
  def reload, do: load_all([])

  @doc """
  Load a single pack directory. Returns `{:ok, %Skill{}}` or
  `{:error, reason}` — used by `load_all/1` and directly by tests wanting
  a precise reason for a specific fixture pack.
  """
  @spec load_pack(Path.t()) :: {:ok, Skill.t()} | {:error, term()}
  def load_pack(pack_dir) do
    skill_md = Path.join(pack_dir, "SKILL.md")

    with {:exists, true} <- {:exists, File.regular?(skill_md)},
         content <- File.read!(skill_md),
         {:ok, keys, body} <- parse(content),
         :ok <- validate_required(keys),
         :ok <- validate_tools_required(keys["tools_required"]),
         {:ok, gate} <- validate_gate(pack_dir, keys) do
      {:ok, build_skill(pack_dir, keys, body, gate)}
    else
      {:exists, false} -> {:error, :missing_skill_md}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Skills from `skills` whose trigger keyword-overlaps `loan_context`
  (`%{status: atom, event_type: atom | nil, goal_descriptions: [String.t],
  assessment: %LoanActor.Assessment{} | nil}`). The `assessment` key
  (intent 0003, `research.md` R-5) enriches the match haystack so a gate
  pack's `description` can meaningfully reference assessment-derived
  concepts — the overlap algorithm itself is unchanged.
  """
  @spec match(map(), [Skill.t()]) :: [Skill.t()]
  def match(loan_context, skills) do
    haystack = loan_context |> match_text() |> keywords()

    Enum.filter(skills, fn skill ->
      trigger = keywords(skill.description)
      not MapSet.disjoint?(haystack, trigger)
    end)
  end

  @doc """
  Among `skills` currently declaring `gate_id`, the one with the highest
  semver `version` — "current" per `contracts/gate-pack-format.md`
  invariant 6 (two on-disk packs may legitimately share a `gate_id` across
  versions; this is the deterministic tie-break, not an error). Returns
  `nil` if no loaded skill declares that `gate_id`.
  """
  @spec resolve_gate(String.t(), [Skill.t()]) :: Gate.t() | nil
  def resolve_gate(gate_id, skills) do
    skills
    |> Enum.filter(&(&1.gate != nil and &1.gate.gate_id == gate_id))
    |> Enum.reduce(nil, fn skill, best ->
      cond do
        best == nil -> skill
        Version.compare(skill.gate.version, best.gate.version) == :gt -> skill
        true -> best
      end
    end)
    |> case do
      nil -> nil
      skill -> skill.gate
    end
  end

  # ---- pack discovery + construction ----

  defp pack_dirs(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.sort()

      {:error, _reason} ->
        []
    end
  end

  defp build_skill(pack_dir, keys, body, gate) do
    %Skill{
      id: Path.basename(pack_dir),
      name: keys["name"],
      version: keys["version"],
      description: keys["description"],
      tools_required: keys["tools_required"],
      body: body,
      files: reference_files(pack_dir),
      path: pack_dir,
      gate: gate
    }
  end

  defp reference_files(pack_dir) do
    skill_md = Path.join(pack_dir, "SKILL.md")

    pack_dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: false)
    |> Enum.filter(&File.regular?/1)
    |> Enum.reject(&(&1 == skill_md))
    |> Enum.sort()
  end

  # ---- validation ----

  defp validate_required(keys) do
    missing = Enum.reject(@required_keys, &Map.has_key?(keys, &1))

    case missing do
      [] -> :ok
      _ -> {:error, {:missing_keys, missing}}
    end
  end

  defp validate_tools_required(tool_names) when is_list(tool_names) do
    unresolved = Enum.reject(tool_names, &match?({:ok, _}, Registry.fetch(&1)))

    case unresolved do
      [] -> :ok
      _ -> {:error, {:unresolvable_tools, unresolved}}
    end
  end

  defp validate_tools_required(other), do: {:error, {:invalid_tools_required, other}}

  # A gate pack (contracts/gate-pack-format.md) is any pack whose
  # tools_required names evaluate_gate — such a pack additionally requires
  # gate_id + rule, and rule must satisfy ADH-003's hard-capped grammar
  # (Gate.new/1 owns that validation entirely; not duplicated here).
  defp validate_gate(pack_dir, keys) do
    if is_list(keys["tools_required"]) and "evaluate_gate" in keys["tools_required"] do
      attrs = %{
        gate_id: Map.get(keys, "gate_id"),
        version: Map.get(keys, "version"),
        pack_id: Path.basename(pack_dir),
        rule: Map.get(keys, "rule")
      }

      case Gate.new(attrs) do
        {:ok, gate} -> {:ok, gate}
        {:error, reason} -> {:error, {:invalid_gate, reason}}
      end
    else
      {:ok, nil}
    end
  end

  # ---- restricted front-matter grammar (NOT general YAML) ----
  #
  # `rule:` (gate-pack-format.md's ONE exception to flat key-value lines)
  # is extracted and parsed separately, BEFORE the flat parser sees the
  # front-matter — its indented continuation lines would otherwise be
  # mis-parsed as bogus top-level keys.

  defp parse(content) do
    case String.split(content, ~r/^---[ \t]*\r?\n/m, parts: 3) do
      [leading, front_matter, body] -> parse_fenced(leading, front_matter, body)
      _ -> {:error, :missing_front_matter_fence}
    end
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  defp parse_fenced(leading, front_matter, body) do
    if String.trim(leading) == "" do
      {rest, rule_text} = extract_rule_block(front_matter)

      with {:ok, keys} <- merge_rule(parse_keys(rest), rule_text) do
        {:ok, keys, String.trim_leading(body)}
      end
    else
      {:error, :missing_front_matter_fence}
    end
  end

  defp extract_rule_block(front_matter) do
    lines = String.split(front_matter, ~r/\r?\n/)

    case Enum.split_while(lines, &(not rule_key_line?(&1))) do
      {_before, []} ->
        {front_matter, nil}

      {before, [_rule_line | after_lines]} ->
        {block_lines, remaining} = Enum.split_while(after_lines, &rule_block_line?/1)
        {Enum.join(before ++ remaining, "\n"), Enum.join(block_lines, "\n")}
    end
  end

  defp rule_key_line?(line), do: Regex.match?(~r/^rule:[ \t]*$/, line)
  defp rule_block_line?(line), do: String.trim(line) == "" or Regex.match?(~r/^[ \t]/, line)

  defp merge_rule(keys, nil), do: {:ok, keys}

  defp merge_rule(keys, rule_text) do
    case Gate.parse_rule_block_text(rule_text) do
      {:ok, rule_map} -> {:ok, Map.put(keys, "rule", rule_map)}
      {:error, reason} -> {:error, {:invalid_rule_block, reason}}
    end
  end

  defp parse_keys(front_matter) do
    front_matter
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Map.new(&parse_key_line!/1)
  end

  defp parse_key_line!(line) do
    case String.split(line, ":", parts: 2) do
      [key, value] -> {String.trim(key), parse_value(String.trim(value))}
      _ -> raise "malformed SKILL.md front-matter line: #{inspect(line)}"
    end
  end

  defp parse_value("[" <> rest) do
    rest
    |> String.trim_trailing("]")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_value(value), do: value

  # ---- trigger matching ----

  defp match_text(loan_context) do
    [
      Map.get(loan_context, :status),
      Map.get(loan_context, :event_type),
      Map.get(loan_context, :goal_descriptions, []) |> Enum.join(" "),
      assessment_text(Map.get(loan_context, :assessment))
    ]
    |> Enum.map(&to_string(&1 || ""))
    |> Enum.join(" ")
  end

  defp assessment_text(nil), do: ""

  defp assessment_text(%Assessment{} = assessment) do
    [assessment.document_completeness, assessment.sla_state]
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
  end

  defp keywords(text) do
    text
    |> String.downcase()
    |> String.replace("_", " ")
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&(&1 in @stopwords or String.length(&1) < 3))
    |> MapSet.new()
  end

  defp dir, do: Application.get_env(:loan_actor, :skills_dir, default_dir())

  defp default_dir do
    case :code.priv_dir(:loan_actor) do
      {:error, _} -> Path.join("priv", "skills")
      priv -> Path.join(List.to_string(priv), "skills")
    end
  end
end
