# Contract — LLM escalation port (`LoanActor.LLM.Adapter` behaviour + `assess_via_llm` tool)

*(Added by intent 0003.)* **This is the first and only non-deterministic capability in this
project's history.** Reachable from exactly one call site — `evaluate_gate`'s own
`:indeterminate` outcome, routed to the `assess_via_llm` tool (FR-004/FR-007/FR-012). No other
module may call this adapter; `LoanActor.Credo.NoLLM`'s allow-list names `assess_via_llm.ex` as
the one sanctioned exception, per `research.md` R-1.

## The port

```elixir
defmodule LoanActor.LLM.Adapter do
  @moduledoc "Single generic escalation callback — FR-012's resolved shape (not task-typed)."

  @callback assess(situation :: map(), opts :: keyword()) ::
              {:ok, output :: term()}
              | {:error, :timeout}
              | {:error, {:malformed_output, reason :: term()}}
              | {:error, :refusal}
              | {:error, {:low_confidence, score :: float()}}
end
```

`situation` carries whatever the escalating gate's `cause` + the relevant `%Assessment{}` fields
expose — never raw PII (PIIGuard runs on this input before it ever reaches the adapter, same
order-of-operations rule as every other tool's args, per `tool-behaviour.md` invariant 3).

## `assess_via_llm` tool

```elixir
defmodule LoanActor.Tools.AssessViaLlm do
  @behaviour LoanActor.Tool

  @impl LoanActor.Tool
  def execute(args, ctx) do
    case adapter() do
      nil -> {:error, :not_configured}
      module -> dispatch(module, args)
    end
  end

  defp dispatch(module, args) do
    case module.assess(args, []) do
      {:ok, output} -> {:ok, %{escalation_output: output}}
      {:error, mode} -> {:ok, %{escalation_fallback: mode}}   # see Failure modes below
    end
  end
end
```

Note the tool-behaviour contract's own shape: an adapter *failure* still returns `{:ok, effects}`
from the TOOL's own perspective (the tool succeeded at doing its job — determining that the LLM
failed and applying the defined fallback) — `{:error, _}` at the tool level is reserved for the
tool itself malfunctioning (e.g. args validation failure, or no adapter configured at all — see
below), not for the LLM's own failure modes, which are first-class, expected,
deterministically-handled outcomes, not tool errors.

**No adapter configured is a tool malfunction, not a fifth LLM failure mode** (resolved during
`/speckit-checklist`, finding CHK012) — `{:error, :not_configured}` at the tool level, diary
`:tool_failed` per the standard foundation path every tool already has (`tool-behaviour.md`
invariant 5's args-validation-failure path is the closest existing precedent: a config problem,
not a judgment call the LLM couldn't make). This is deliberately distinct from the four
FR-006 failure modes below, which are all about an LLM that DID respond in some fashion — an
unconfigured adapter never got the chance to respond at all. A deployment that registers
`assess_via_llm` in `config :loan_actor, :tools` without also configuring an adapter module is a
genuine operational error, not a scenario FR-006's fail-closed policy needs to cover.

## Failure modes (FR-006 — every one has ONE deterministic fallback, no exceptions)

| Failure mode | Trigger | Deterministic fallback |
|---|---|---|
| `:timeout` | Adapter does not respond within a configured deadline. | Escalation resolves as `{:fallback, :timeout}`; the gate's outcome is treated as `:fail` (fail-closed — an unanswered judgment call does not silently pass). |
| `:malformed_output` | Adapter responds, but the output cannot be parsed into the shape the escalating gate expects. | Same fail-closed fallback as `:timeout` — `{:fallback, :malformed_output}`, gate outcome `:fail`. |
| `:refusal` | Adapter explicitly declines to answer. | `{:fallback, :refusal}`, gate outcome `:fail`. Distinguished from `:malformed_output` in the diary (different `failure_mode` value) even though the practical outcome is the same — an auditor needs to tell "the model said no" from "the model's answer was garbage," even if both fail closed identically today. |
| `:low_confidence` | Adapter responds with a confidence signal below a threshold. | `{:fallback, :low_confidence}`, gate outcome `:fail`. Same fail-closed policy — a low-confidence "maybe pass" is not a pass. |

**The `:low_confidence` threshold itself is an adapter-configuration concern, not defined by
this port** (clarified during `/speckit-checklist`, finding CHK006) — consistent with
`research.md` R-1 scoping a real vendor adapter out of this feature's own delivery (port + test
double only), the specific numeric/qualitative threshold that decides "low" is whatever the
eventual concrete adapter implementation configures, since it is inherently model-specific (a
threshold meaningful for one model's confidence scale may not transfer to another's). This
port's own contract only requires that SOME threshold exists and that crossing it deterministically
produces `{:error, {:low_confidence, score}}` — the recorded-fixture test double picks an
arbitrary, documented threshold for its own contract-test fixtures, not a real one.

**All four modes fail closed to `:fail`, never to `:pass`.** This is a deliberate, uniform
policy (not decided per-mode) — an escalation exists because the deterministic path couldn't
decide; a failed escalation must not silently become more permissive than "we couldn't
determine this," so it resolves as the conservative outcome. Revisiting this policy (e.g. some
gate wanting a different failure disposition) is a future amendment, not a per-gate configuration
this contract introduces speculatively.

## Diary discipline (extends `tool-behaviour.md` invariant 4, does not replace it)

- Every `assess_via_llm` invocation gets the standard `:tool_invoked`/`:tool_completed` pair
  (unchanged tool discipline) **plus** the feature-specific `:escalation_resolved` or
  `:escalation_failed` entry (`data-model.md`), which carries the constitution's own itemized
  fields (trigger, prompt id, model, version, full input hash, decision delta) — resolved
  per `research.md` R-4, with `output` in cleartext ONLY for a successful `:answered` resolution
  that has already passed `PIIGuard`.
- `prompt id`/`model`/`version` come from the adapter implementation's own identity (a
  `LoanActor.LLM.Adapter.info/0`-style capability, or equivalent — implementation detail beyond
  this contract's own scope; the diary entry shape requires these fields exist, not how the
  adapter reports them).

## Contract test (recorded fixtures, no live model calls — per `research.md` R-1)

`test/llm/adapter_contract_test.exs` instantiates the adapter behaviour against a fixture-backed
test double covering:

1. **Deterministic-only path** — a gate that never reaches `:indeterminate` never invokes this
   adapter at all (constitution's 3-test LLM requirement, test 1 of 3).
2. **Escalation trigger** — an `:indeterminate` outcome invokes the adapter exactly once, with
   the expected `situation` shape (test 2 of 3).
3. **Each of the 4 failure modes** — one recorded fixture per mode, asserting the exact
   deterministic fallback and diary entry (test 3 of 3, x4 sub-cases).

Fixtures are versioned alongside the adapter implementation (mirrors `research.md` R-1's own
"fixtures versioned with the adapter" risk mitigation) — a scheduled, non-CI-blocking live smoke
job (mirrors `ci-nightly.yml`'s existing precedent for genuinely-slow/external-dependent checks)
re-records and diffs against a real model periodically, without making CI depend on live model
availability or determinism.

## Static check (extends `LoanActor.Credo.NoLLM`)

`NoLLM`'s existing rule ("rejects imports/uses of OpenAI, Anthropic, Bumblebee.Text.completion,
fetch URLs matching LLM-provider regex, in production paths") gains an explicit allow-list of
exactly one file: `lib/loan_actor/tools/assess_via_llm.ex` (and, transitively, whatever concrete
adapter module it's configured to call — named explicitly in the check's own test fixture, not a
wildcard). Every other file in `lib/loan_actor/` remains fully covered by the existing check
unchanged — this is a named exception, not a broadened scope.
