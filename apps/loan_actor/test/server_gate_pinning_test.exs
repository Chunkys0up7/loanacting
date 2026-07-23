defmodule LoanActor.ServerGatePinningTest do
  @moduledoc """
  ADH-006 — `LoanActor.Server.pin_gate/2` (FR-011 per-loan gate-version
  pinning). Taxonomy: happy / boundary / regulatory (this IS the
  regulatory-traceability requirement SC-006 names for this task).

  Tested directly against `gen_state`-shaped maps (mirrors
  `infer_doc_type/1`'s own precedent) rather than through a live
  `GenServer` round-trip: nothing yet triggers `evaluate_gate` from a real
  loop (that wiring is ADH-009's job), and no diary entry carries
  `gate_version` in the clear until ADH-007 — so the only currently
  observable proof of pinning is `pin_gate/2`'s own return value.
  """

  use ExUnit.Case, async: false

  alias LoanActor.Factory
  alias LoanActor.Gate
  alias LoanActor.Server

  setup do
    previous = Application.get_env(:loan_actor, :skills_dir)
    on_exit(fn -> restore(previous) end)
    :ok
  end

  defp restore(nil), do: Application.delete_env(:loan_actor, :skills_dir)
  defp restore(dir), do: Application.put_env(:loan_actor, :skills_dir, dir)

  defp gen_state(overrides \\ %{}) do
    Map.merge(%{gate_pins: %{}}, overrides)
  end

  defp write_gate_pack(dir, id, version) do
    Factory.write_skill_pack!(dir, %{
      id: id,
      name: "document-completeness-gate",
      description: "Checks document completeness.",
      tools_required: ["evaluate_gate"],
      gate_id: "document-completeness",
      version: version,
      rule: %{
        "combinator" => "all",
        "predicates" => [
          %{"field" => "assessment.document_completeness", "op" => "eq", "value" => "complete"}
        ]
      }
    })
  end

  describe "pin_gate/2 — happy" do
    test "the first evaluation resolves and pins the current on-disk version" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pin_first")
      File.mkdir_p!(dir)
      write_gate_pack(dir, "0002-demo-gate-pack", "1.0.0")
      Application.put_env(:loan_actor, :skills_dir, dir)

      {new_gen_state, gate} = Server.pin_gate(gen_state(), "document-completeness")

      assert %Gate{version: "1.0.0"} = gate
      assert new_gen_state.gate_pins["document-completeness"] == gate
    end
  end

  describe "pin_gate/2 — regulatory (FR-011: same loan keeps its pin across a pack update)" do
    test "a loan already pinned to v1 stays on v1 after the pack is updated to v2 on disk" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pin_same_loan")
      File.mkdir_p!(dir)
      write_gate_pack(dir, "0002-demo-gate-pack-v1", "1.0.0")
      Application.put_env(:loan_actor, :skills_dir, dir)

      {gen_state, first_gate} = Server.pin_gate(gen_state(), "document-completeness")
      assert first_gate.version == "1.0.0"

      # Additive-only update: a NEW pack directory, same gate_id, higher
      # version (contracts/gate-pack-format.md invariant 8) — the old
      # directory is never touched.
      write_gate_pack(dir, "0002-demo-gate-pack-v2", "2.0.0")

      {gen_state_after, second_gate} = Server.pin_gate(gen_state, "document-completeness")

      assert second_gate.version == "1.0.0"
      assert second_gate == first_gate
      assert gen_state_after == gen_state
    end

    test "a NEW loan's first evaluation resolves the current (updated) version" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pin_new_loan")
      File.mkdir_p!(dir)
      write_gate_pack(dir, "0002-demo-gate-pack-v1", "1.0.0")
      write_gate_pack(dir, "0002-demo-gate-pack-v2", "2.0.0")
      Application.put_env(:loan_actor, :skills_dir, dir)

      {_gen_state, gate} = Server.pin_gate(gen_state(), "document-completeness")
      assert gate.version == "2.0.0"
    end
  end

  describe "pin_gate/2 — boundary" do
    test "an unknown gate_id resolves to nil and leaves gate_pins unchanged" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pin_unknown")
      File.mkdir_p!(dir)
      Application.put_env(:loan_actor, :skills_dir, dir)

      original = gen_state()
      assert {^original, nil} = Server.pin_gate(original, "not-a-real-gate")
    end

    test "a second call for an already-pinned gate_id does not re-touch the loader" do
      dir = Factory.unique_tmp_dir("loan_actor_gate_pin_idempotent")
      File.mkdir_p!(dir)
      write_gate_pack(dir, "0002-demo-gate-pack", "1.0.0")
      Application.put_env(:loan_actor, :skills_dir, dir)

      {gen_state, gate} = Server.pin_gate(gen_state(), "document-completeness")

      # Removing the skills dir entirely proves the second call never
      # consults disk again — it only reads gen_state.gate_pins.
      File.rm_rf!(dir)
      assert {^gen_state, ^gate} = Server.pin_gate(gen_state, "document-completeness")
    end
  end
end
