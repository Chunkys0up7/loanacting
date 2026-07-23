defmodule LoanActor.Skill do
  @moduledoc """
  A versioned markdown skill pack (FT-044; supersedes the single-file
  `%Procedure{}` stub). Fields per `data-model.md` `%LoanActor.Skill{}` and
  `contracts/skill-format.md`.

  Built exclusively by `LoanActor.Skill.Loader` after successful load-time
  validation — there is no raising `new/1` here, because an invalid pack
  is never constructed as a `%Skill{}` at all; it is skipped (with a
  logged reason) by the loader before this struct comes into existence.

  `:gate` (intent 0003, ADH-005) is `nil` for every ordinary skill pack;
  a gate pack (one declaring `gate_id`/`rule` per
  `contracts/gate-pack-format.md`) carries its parsed, validated
  `%LoanActor.Gate{}` here so `Skill.Loader.resolve_gate/2` can find it
  without re-parsing front-matter.
  """

  @enforce_keys [:id, :name, :version, :description, :tools_required, :body, :files, :path]
  defstruct [:id, :name, :version, :description, :tools_required, :body, :files, :path, gate: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          version: String.t(),
          description: String.t(),
          tools_required: [String.t()],
          body: String.t(),
          files: [Path.t()],
          path: Path.t(),
          gate: LoanActor.Gate.t() | nil
        }
end
