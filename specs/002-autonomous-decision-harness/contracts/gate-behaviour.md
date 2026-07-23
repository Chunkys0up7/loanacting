# Contract — Gate evaluation (`evaluate_gate` tool + rule-predicate DSL)

*(Added by intent 0003.)* `evaluate_gate` is a `LoanActor.Tool` (per
`001-loan-actor-foundation/contracts/tool-behaviour.md` — this feature adds no new tool
behaviour, it adds new *tool modules* through the existing one) whose rule *content* comes from
a gate pack's front-matter, per `contracts/gate-pack-format.md`.

```elixir
defmodule LoanActor.Tools.EvaluateGate do
  @behaviour LoanActor.Tool

  @impl LoanActor.Tool
  def spec do
    Spec.new(%{
      name: "evaluate_gate",
      description: "Evaluate a named gate's rule against the current assessment.",
      parameters: %{
        "type" => "object",
        "properties" => %{"gate_id" => %{"type" => "string"}},
        "required" => ["gate_id"]
      }
    })
  end

  @impl LoanActor.Tool
  def execute(%{"gate_id" => gate_id}, ctx) do
    # returns effects, per tool-behaviour.md invariant 1 — never mutates state directly
  end
end
```

Effect shape returned: `%{gate_outcome: %{gate_id:, gate_version:, outcome: :pass | :fail |
:indeterminate, cause: String.t()}}`. The Server applies `:pass`/`:fail` through the existing
`transition_state`/`satisfy_goal` tools' own effect-application path (this tool does not itself
call `State.transition/2` — it reports an outcome; `:decision` diary logging and state
application are a Server-level concern, mirroring how `set_goal`'s effect is applied by
`apply_add_goal/2` today).

## Rule-predicate DSL (HARD CAP)

A gate pack's rule expression, declared in front-matter, is restricted to exactly this grammar —
same discipline as `tool-behaviour.md`'s JSON-schema subset and `skill-format.md`'s front-matter
grammar. **Extending this grammar requires an amendment intent.**

```yaml
rule:
  combinator: all   # or: any
  predicates:
    - field: assessment.document_completeness
      op: eq
      value: complete
    - field: assessment.sla_state
      op: neq
      value: breached
```

- **`field`**: a dotted path into `assessment.*` or `state.*` only. No arbitrary expressions, no
  function calls.
- **`op`**: one of `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `present`, `absent`, `contains`.
  `present`/`absent` take no `value`; every other op requires one.
- **`value`**: always a scalar literal — string, number, or boolean. For `contains`
  specifically, `field` is expected to resolve to a LIST (e.g.
  `assessment.data_quality_flags`) and `value` is the single scalar checked for
  membership in it — corrected during `/speckit-implement` (ADH-003): an earlier draft of
  this line said `contains`'s own `value` could itself be a list, which didn't match the
  actual, more useful semantics ("does this list field contain this one thing") the
  implementation and its tests settled on.
- **`combinator`**: `all` (every predicate must pass) or `any` (at least one must pass). Nests
  exactly one level: a predicate list may itself contain a nested `{combinator, predicates}`
  map instead of a leaf predicate, but that nested map's own `predicates` MUST be leaf
  predicates only — no further nesting. This bounds evaluation cost and keeps gates readable by
  a non-programmer, per intent 0003's own User Story 3.

**A field the grammar cannot express, or a comparison the operator set cannot represent, is NOT
a workaround target.** Author a gate pack version once the cap itself is amended, or escalate
via `:indeterminate` if the ambiguity is genuinely data-dependent rather than a DSL gap.

## Outcome semantics

- **`:pass`** — every predicate (per the combinator) evaluated true against present, unambiguous
  data.
- **`:fail`** — every predicate (per the combinator) evaluated false against present,
  unambiguous data. `:fail` is a confident negative, not "couldn't tell."
- **`:indeterminate`** — exactly two distinct sources, both surfaced identically to the caller
  via the `cause` field, but worth naming separately for a reader classifying a test scenario
  (clarified during `/speckit-checklist`, finding CHK005): (a) **engine-level** — a predicate
  references a field that is structurally absent from the assessment/state (an actual missing
  capability, e.g. a field the assessment doesn't yet compute — the DSL genuinely cannot
  evaluate this predicate, full stop), or (b) **rule-design-level** — the gate pack's own
  front-matter explicitly declares a fact as "escalate if absent" even though the DSL COULD
  evaluate it as `false`/absent (the rule author chose ambiguity-as-a-feature over a confident
  fail). Both produce `:indeterminate`; the `cause` field's own text (not a separate outcome
  value) is what tells the two apart for anyone reading the diary. `:indeterminate` is never an
  engine-level GUESS — the engine's job is to report exactly which of (a)/(b) produced it, not
  to have its own ambiguity about whether to escalate.

## Invariants (extends `tool-behaviour.md`'s invariants 1-6 — does not replace them)

7. **Determinism of parsing + evaluation** — the same gate pack version + the same assessment
   input always produces the same outcome + cause. Property-tested (`research.md` R-3's
   sibling property, scoped to gate evaluation specifically).
8. **Version pinning is a Server-level concern, not this tool's** — `evaluate_gate` always
   evaluates whatever gate-pack version the Server hands it via `ctx`; FR-011's per-loan pinning
   is enforced by which version the Server resolves and passes in, not by logic inside this tool.
9. **Engine-level failure is a tool failure, not a gate outcome** (resolved during
   `/speckit-checklist`, finding CHK001) — if `evaluate_gate` itself raises or would otherwise
   return a shape outside `:pass`/`:fail`/`:indeterminate` (a bug in the engine, not a gate
   pack's content), this is NOT a fourth outcome value: it is an ordinary tool malfunction,
   already handled generically by the foundation registry's existing rescue path
   (`tool-behaviour.md`'s own invariant 4 — `:tool_failed`, full ToolCall sequence still
   emitted). No new mechanism needed; this invariant exists only to say so explicitly rather
   than leave a reader to infer it.
10. **Evaluation order across multiple matched gates in the same pass is deterministic but
    input-independent** (resolved during `/speckit-checklist`, finding CHK015) — every gate
    matched in a given loop pass evaluates against the SAME single `%Assessment{}` snapshot
    (spec.md Edge Cases: "a rule never evaluates against a mix of before/after data from the
    same pass"), so no gate's INPUT depends on another gate's outcome within that pass, and
    evaluation order among them is irrelevant to correctness. The Server still applies the
    resulting effects (decisions/escalations) in a fixed, deterministic order (sorted by
    `gate_id`) purely for diary-ordering determinism/replay-reproducibility — not because
    ordering affects any gate's own result.
11. **Predicate-list size is bounded by the DSL's own hard cap** (R-2's one-level-of-nesting,
    fixed operator set) — no separate performance requirement is needed for `evaluate_gate`
    itself beyond what that cap already guarantees (resolved during `/speckit-checklist`,
    finding CHK014); `plan.md`'s Performance Goals note is about the LOOP PASS's aggregate cost
    (assessment + all matched gates), not this tool's own per-call cost in isolation.

## Test pins

- `test/tool/evaluate_gate_test.exs` — one test per operator, per combinator, boundary (empty
  predicate list, single-predicate list), error (malformed rule expression rejected at gate-pack
  load time per `gate-pack-format.md`, not at evaluation time), determinism property test.
- Shared tool suite (`tool_shared.ex`) instantiated for `evaluate_gate` like every other tool.
