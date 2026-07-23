# Contract — Gate pack format (extends `skill-format.md`)

*(Added by intent 0003.)* A gate pack is a skill pack (per
`001-loan-actor-foundation/contracts/skill-format.md`) with additive front-matter fields carrying
the rule this feature's `evaluate_gate` tool evaluates. **Same loader, same layout, same
restricted front-matter grammar** — this is not a parallel format or a fork of `Skill.Loader`.

## Layout (unchanged from skill-format.md)

```
priv/skills/<id>/                  # e.g. 0002-demo-gate-pack
├── SKILL.md                       # manifest — REQUIRED, additive fields below
└── references/                    # optional supporting files
```

## `SKILL.md` front-matter — additive fields

```markdown
---
name: document-completeness-gate
version: 1.0.0
description: When assessing document completeness for an income goal, check the required documents are present and current.
tools_required: [evaluate_gate]
gate_id: document-completeness
rule:
  combinator: all
  predicates:
    - field: assessment.document_completeness
      op: eq
      value: complete
---

# Body: human-readable explanation of what this gate checks and why (regulator-readable,
# per Principle VI) — same convention as every other skill pack's body.
```

- **All of `skill-format.md`'s existing required keys still apply** (`name`, `version`,
  `description`, `tools_required`) — `tools_required` for a gate pack names `evaluate_gate`
  (not the gate's own eventual pass/fail action tools like `transition_state`/`satisfy_goal`,
  which the Server invokes separately once a `:decision` results, per `data-model.md`'s
  relationships diagram).
- **`gate_id`** (new, required for gate packs) — the stable identity carried into every
  `:gate_evaluated`/`:decision`/`:escalated` diary entry (`data-model.md`). Distinct from the
  pack's own `id` (the directory name) — `gate_id` is the semantic identity that survives a pack
  being renamed/relocated; the directory `id` is a loader/versioning concern only.
- **`rule`** (new, required for gate packs) — the front-matter grammar's ONE exception to
  "`key: value` lines and `[a, b, c]` lists only" (skill-format.md's own restricted grammar):
  `rule` is a nested map, specifically because `contracts/gate-behaviour.md`'s predicate DSL
  needs structure a flat key-value line cannot express. This is the single, deliberate,
  named exception — not a general relaxation of the front-matter grammar. Its own internal
  structure is separately hard-capped by `gate-behaviour.md`, so the overall "restricted, not
  general YAML" discipline still holds one level down.

## Trigger matching (extends, does not replace, `Skill.Loader.match/2`)

Per `research.md` R-5: a gate pack's `description` is still its trigger, matched via the SAME
`Skill.Loader.match/2` naive keyword-overlap mechanism every skill pack uses — no new selection
algorithm. What changes is the `loan_context` input `match/2` is called with during the loop
passes this feature adds assessment to: it gains an `assessment:` key
(`%{status:, event_type:, goal_descriptions:, assessment: %Assessment{}}`), so a gate pack's
trigger text can meaningfully reference assessment-derived concepts (e.g. "document
completeness") and actually overlap against real signal, not just whatever a goal's free-text
description happens to say. A loan whose current assessment/context doesn't overlap any gate
pack's trigger activates zero gates that pass — same invariant as SC-014's "non-matching state
activates zero skills," extended to gates.

## Loader invariants (all of `skill-format.md`'s 5 invariants apply unchanged, plus)

6. **`gate_id` uniqueness is NOT enforced by the loader** — two packs may legitimately share a
   `gate_id` across versions (an updated gate pack, same `gate_id`, higher `version`); FR-011's
   per-loan version pinning is what disambiguates which version a given loan's decision used, not
   a loader-level uniqueness constraint.
7. **A gate pack missing `gate_id` or `rule`, or whose `rule` violates `gate-behaviour.md`'s
   hard-capped grammar, is rejected at load time** — same "skipped with a logged reason, never
   silently evaluated as if valid" discipline as every other rejection path in `skill-format.md`
   invariant 1, extended to these two new required fields.

## Demonstration gate pack

`priv/skills/0002-demo-gate-pack/` — at least 3 rules (SC-002), mirroring
`0001-demo-document-request/`'s role as a real, exercised example rather than a synthetic
test-only fixture. Illustrative only (spec.md's own Assumptions section) — not a real compliance
rule set.

## Test pins

- `test/skill/gate_pack_loader_test.exs` (or an extension of the existing
  `skill/loader_test.exs` — implementation's call, not this contract's) — load/reject cases
  for `gate_id`/`rule` specifically, against new fixture packs under
  `test/fixtures/skills/` mirroring the existing valid/bad-front-matter/unresolvable-tools/
  multi-file catalog.
- Factory: extends `LoanActor.Factory.write_skill_pack!/2` to accept `gate_id`/`rule` overrides
  (test-data-forge) — not a new, parallel factory function.
