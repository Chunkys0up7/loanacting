defmodule LoanActor.TestTools do
  @moduledoc """
  Fixture tool modules for exercising the registry and the shared tool suite
  (FT-042). These are TEST DATA (test-data-forge): deterministic, minimal, and
  each one exists to exercise a specific registry path — happy, `{:error, _}`
  passthrough, raise-rescue, `{:pending, _}`, and behaviour-contract violation.
  Real foundation tools land in FT-043 under `lib/loan_actor/tools/`.
  """

  defmodule Echo do
    @moduledoc "Happy-path fixture: echoes its args deterministically."
    @behaviour LoanActor.Tool

    alias LoanActor.Tool.Spec

    @impl LoanActor.Tool
    def spec do
      Spec.new(%{
        name: "echo_note",
        description: "Echo a note back (fixture).",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "text" => %{"type" => "string"},
            "level" => %{"type" => "string", "enum" => ["info", "warn"]}
          },
          "required" => ["text"]
        }
      })
    end

    @impl LoanActor.Tool
    def execute(args, ctx) do
      {:ok,
       %{
         "echoed" => args["text"],
         "level" => Map.get(args, "level", "info"),
         "loop" => Atom.to_string(ctx.loop)
       }}
    end
  end

  defmodule Failing do
    @moduledoc "Fixture returning the behaviour's error shape."
    @behaviour LoanActor.Tool

    alias LoanActor.Tool.Spec

    @impl LoanActor.Tool
    def spec do
      Spec.new(%{
        name: "always_fails",
        description: "Always returns an error (fixture).",
        parameters: %{"type" => "object"}
      })
    end

    @impl LoanActor.Tool
    def execute(_args, _ctx), do: {:error, :always_fails}
  end

  defmodule Raising do
    @moduledoc "Fixture that crashes mid-execute; registry must rescue."
    @behaviour LoanActor.Tool

    alias LoanActor.Tool.Spec

    @impl LoanActor.Tool
    def spec do
      Spec.new(%{
        name: "raises",
        description: "Raises mid-execute (fixture).",
        parameters: %{"type" => "object"}
      })
    end

    @impl LoanActor.Tool
    def execute(_args, _ctx), do: raise("boom")
  end

  defmodule Pending do
    @moduledoc "Fixture for the deferred-result path (HITL-shaped)."
    @behaviour LoanActor.Tool

    alias LoanActor.Tool.Spec

    @impl LoanActor.Tool
    def spec do
      Spec.new(%{
        name: "pending_tool",
        description: "Returns a pending correlation id (fixture).",
        parameters: %{
          "type" => "object",
          "properties" => %{"id" => %{"type" => "string"}},
          "required" => ["id"]
        }
      })
    end

    @impl LoanActor.Tool
    def execute(args, _ctx), do: {:pending, args["id"]}
  end

  defmodule BadReturn do
    @moduledoc "Fixture violating the behaviour's return contract."
    @behaviour LoanActor.Tool

    alias LoanActor.Tool.Spec

    @impl LoanActor.Tool
    def spec do
      Spec.new(%{
        name: "bad_return",
        description: "Returns a shape outside the behaviour contract (fixture).",
        parameters: %{"type" => "object"}
      })
    end

    @impl LoanActor.Tool
    def execute(_args, _ctx), do: :oops
  end

  defmodule RedactingGuard do
    @moduledoc """
    Fixture PII guard matching `LoanActor.PIIGuard.apply/1`'s real shape
    exactly (`{:ok, guarded, paths} | {:error, :pii_violation, paths}`) —
    proves order-of-operations without exercising the real regex patterns.
    Replaces `"ssn"`, rewrites `"text"`, and hard-rejects any `"reject_me"`
    key (to exercise the registry's hard-gate branch).
    """

    def redact(args) when is_map(args) do
      if Map.has_key?(args, "reject_me") do
        {:error, :pii_violation, [["reject_me"]]}
      else
        guarded =
          Map.new(args, fn
            {"ssn", _v} -> {"ssn", "<redacted>"}
            {"text", v} when is_binary(v) -> {"text", "[guarded]" <> v}
            pair -> pair
          end)

        {:ok, guarded, []}
      end
    end
  end

  @doc "Every fixture tool module, in registry-config order."
  def all, do: [Echo, Failing, Raising, Pending, BadReturn]
end
