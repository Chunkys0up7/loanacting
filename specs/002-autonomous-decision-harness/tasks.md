# Tasks — Autonomous Decision Harness

Derived from [`spec.md`](spec.md), [`plan.md`](plan.md), [`data-model.md`](data-model.md),
[`research.md`](research.md), and [`contracts/`](contracts/).

Conventions:
- `ADH-NNN` = Autonomous Decision Harness Task NNN (this feature's own prefix — `FT-NNN` from
  spec 001 specifically means "Foundation Task"; reusing it here would misname a different
  feature's tasks).
- `[P]` = parallelizable with same-numbered other `[P]` tasks (no ordering dep).
- Every task lists: deliverable artifacts, applicable test-taxonomy categories, dependency tasks.
- Tests are committed in the **same** PR as code (constitution Principle V, NON-NEGOTIABLE —
  this project does not treat tests as optional the way the generic tasks template does).
- Organized by user story per spec.md's priorities (P1/P1/P2), but — like spec 001's own task
  graph — Setup/Foundational carries the shared Assessment/Gate/Decision plumbing every story
  needs; user stories are independently *testable* once Foundational lands, not independently
  *buildable* from zero (the three stories share too much machinery for artificial separation to
  be honest about the real dependency shape).

## Status ledger

Updated by `/speckit-implement` as each task lands. Absent = not started.

| Task | Status | Commit |
|---|---|---|
| ADH-001 | Done (folded into ADH-002/ADH-004 — `config :loan_actor, :tools` gained `AssessLoan`/`EvaluateGate` directly as each module was built, not as a separate placeholder-first step) | `9c8d4a8`, `88ecbf7` |
| ADH-002 | Done | `9c8d4a8` |
| ADH-003 | Done | `f172e2a` |
| ADH-004 | Done | `88ecbf7` |
| ADH-005 | Done | `5611eab` |
| ADH-006 | Done | (pending commit) |

---

## Phase 1 — Setup

### ADH-001 — Register the tool-layer extension points
- Deliverable: `config :loan_actor, :tools` gains placeholder entries for `assess_loan`,
  `evaluate_gate`, `assess_via_llm` (modules created by later tasks; config wiring is separable
  from module implementation, matching foundation's own FT-042 registry pattern).
- Taxonomy: n/a (config only, no logic).
- Depends on: none (spec 001 Closed; `LoanActor.Tool.Registry` already exists).

---

## Phase 2 — Foundational (blocks all three user stories)

### ADH-002 — `%LoanActor.Assessment{}` struct + `assess_loan` tool
- Deliverable: `lib/loan_actor/assessment.ex` (struct per `data-model.md`), `lib/loan_actor/tools/assess_loan.ex`
  (deterministic derivation from `ctx.state` only — `research.md` R-6: no diary I/O).
- Tests: `test/assessment_test.exs` (struct validation, boundary field values),
  `test/tools/assess_loan_test.exs` (shared tool suite instantiation + determinism property:
  same state in → same assessment out, StreamData-generated states).
- Taxonomy: happy / boundary / replay (determinism IS a replay-adjacent property here).
- Depends on: ADH-001.

### ADH-003 — Gate rule-predicate DSL parser (hard-capped grammar)
- Deliverable: `lib/loan_actor/gate.ex` (`%LoanActor.Gate{}` + parse/validate per
  `contracts/gate-behaviour.md`'s exact grammar — field/op/value/combinator only, one level of
  nesting).
- Tests: `test/gate_test.exs` — one test per operator (`eq`/`neq`/`gt`/`gte`/`lt`/`lte`/
  `present`/`absent`/`contains`), per combinator (`all`/`any`), boundary (empty predicate list,
  single predicate, max one nesting level), error (each malformed-grammar variant rejected with
  a specific reason, per `LoanActor.Factory`-style invalid-variant catalog — test-data-forge).
- Taxonomy: happy / boundary / error / contract (pins `gate-behaviour.md`'s hard cap).
- Depends on: ADH-001.

### ADH-004 — `evaluate_gate` tool
- Deliverable: `lib/loan_actor/tools/evaluate_gate.ex` — loads a `%Gate{}` (via ADH-003's
  parser) for the given `gate_id` from whichever gate pack the Server resolved (FR-011 version
  pinning is a Server-level concern per `gate-behaviour.md` invariant 8, not this tool's own
  logic), evaluates it against `ctx`'s current assessment/state, returns `:pass`/`:fail`/
  `:indeterminate` + cause as an effect.
- Tests: `test/tools/evaluate_gate_test.exs` (shared tool suite instantiation; determinism
  property: same gate version + same assessment → same outcome + cause).
- Taxonomy: happy / boundary / error / replay.
- Depends on: ADH-002, ADH-003.

### ADH-005 — Gate pack format: extend `Skill.Loader` for `gate_id`/`rule` fields
- Deliverable: `Skill.Loader` gains recognition of the two additive front-matter fields
  (`gate_id`, `rule`) per `contracts/gate-pack-format.md`; load-time validation rejects a pack
  missing either field (for packs whose `tools_required` includes `evaluate_gate`) or whose
  `rule` violates ADH-003's hard-capped grammar. `Skill.Loader.match/2`'s `loan_context` input
  extended with an `assessment:` key per `research.md` R-5 (algorithm unchanged, input enriched).
  Per `/speckit-checklist` findings CHK002/CHK008/CHK019: gate packs are additive-only on disk
  (a version, once loaded, is never deleted/overwritten); when multiple currently-loaded packs
  share a `gate_id`, the loader picks the highest `version` as current.
- Tests: `test/skill/gate_pack_loader_test.exs` against new fixture packs under
  `test/fixtures/skills/` (valid gate pack, missing `gate_id`, missing `rule`, malformed `rule`
  grammar) — mirrors the existing valid/bad-front-matter/unresolvable-tools/multi-file catalog
  exactly, extended rather than duplicated. `Factory.write_skill_pack!/2` extended to accept
  `gate_id`/`rule` overrides (test-data-forge — one factory, not a parallel one).
- Taxonomy: happy / boundary / error / contract.
- Depends on: ADH-003.

### ADH-006 — Per-loan gate-version pinning (FR-011)
- Deliverable: the Server resolves and records, per `(loan_id, gate_id)`, the gate-pack version
  active the FIRST time that gate is evaluated for that loan — subsequent evaluations of the
  same gate on the same loan use the pinned version even if the pack is later updated. Every
  `:decision`/`:escalated` diary entry carries the pinned version actually used.
- Tests: `test/server_gate_pinning_test.exs` — evaluate a gate, update the pack (new version,
  same `gate_id`), evaluate again on the SAME loan (still old version) and a NEW loan (gets new
  version); diary entries show the correct pinned version in each case.
- Taxonomy: happy / boundary / regulatory (this IS the regulatory-traceability requirement
  SC-006 names).
- Depends on: ADH-004, ADH-005.

### ADH-007 — `%LoanActor.Decision{}` diary entry + effect application
- Deliverable: `lib/loan_actor/decision.ex` (documents the `:decision` payload shape per
  `data-model.md` — not necessarily a persisted struct, per that doc's own note); Server wiring
  applying a `:pass`/`:fail` gate outcome through the EXISTING `transition_state`/`satisfy_goal`
  tools (no new mutation path — Principle IV/VIII compliance), appending `:decision` in the same
  step.
- Tests: `test/server_decision_test.exs` — pass outcome drives a real state/goal change via the
  existing tools; fail outcome does not; diary entry carries `gate_id`/`gate_version`/
  `input_digest`/`outcome` exactly per `data-model.md`.
- Taxonomy: happy / boundary / error / replay.
- Depends on: ADH-004, ADH-006.

### ADH-008 — Incremental diary-derived facts in `state.context` (research R-3)
- Deliverable: the tool-effect mechanism that updates `state.goals` today gains a sibling for
  incrementally updating `state.context`'s fact keys (document-completeness signals, goal ages,
  SLA/timing clocks) as the relevant foundation events/tools fire — not a new mutation surface,
  an extension of `LoanActor.State`'s own existing pattern (`add_goal/2`-shaped).
- Tests: `test/state_context_facts_test.exs` — the replay invariant from `research.md` R-3:
  folding incremental updates over any diary prefix produces `state.context` identical to a
  full, from-scratch recomputation over that same prefix (StreamData property test).
- Taxonomy: happy / boundary / replay.
- Depends on: ADH-002.

**Checkpoint**: Foundational complete — Assessment, gate parsing/evaluation, gate-pack loading
+ version pinning, decision wiring, and incremental facts all exist and are independently
tested. User story work can begin.

---

## Phase 3 — User Story 1: A loan works through its goals unattended (Priority: P1) 🎯 MVP

**Goal**: A loan spawned with a goal, fed a scripted event stream, reaches `:completed` with
zero operator interaction when every applicable gate passes (SC-001).

**Independent Test**: Per spec.md's own Acceptance Scenario 1 — spawn, set goal, script events,
assert zero-operator-action completion + one assessment/gate-evaluation diary entry per pass.

### ADH-009 [P] [US1] — Demonstration gate pack (≥3 rules) + scale test (SC-002)
- Deliverable: `priv/skills/0002-demo-gate-pack/` — at least 3 distinct rules, together covering
  every predicate operator and combinator `contracts/gate-behaviour.md` defines, mirroring
  `0001-demo-document-request/`'s role as a real, exercised example (per `gate-pack-format.md`).
- Tests: `test/demo_gate_pack_test.exs` — a factory-generated set of ≥10 loan situations
  (test-data-forge: `Factory` gains a situation-generator covering all 3 outcomes at least once
  per SC-002's tightened wording), asserting each evaluation's outcome matches the expected
  result and is diary-logged with the rule's identity, version, and cause. Distinct from
  ADH-010's end-to-end test (which proves zero-operator-interaction completion, SC-001, not this
  scale/coverage claim).
- Taxonomy: happy / boundary (this task's own test IS SC-002's proof — previously miscategorized
  as "n/a, covered by ADH-010," corrected during `/speckit-analyze`: SC-001 and SC-002 are
  distinct claims needing distinct proof).
- Depends on: ADH-005.

### ADH-010 [US1] — End-to-end autonomous-progress test (SC-001)
- Deliverable: `test/autonomous_progress_test.exs` — spawn a real loan against a real BEAM
  node + real diary store, set a goal, feed the exact scripted event stream the demo gate pack's
  rules need, assert `:completed` with zero operator interaction, and assert the diary contains
  one `:assessment` + one `:gate_evaluated` entry (with gate id/version/outcome) per loop pass
  (spec.md Acceptance Scenario 1).
- Tests: itself (integration-level; no unit test needed beyond what Foundational already covers).
- Taxonomy: happy (this IS SC-001's own proof).
- Depends on: ADH-007, ADH-008, ADH-009.

### ADH-011 [US1] — Diary-reconstructable "why" test (Acceptance Scenario 2)
- Deliverable: extends ADH-010's scenario — after autonomous progress, assert an operator
  reading the diary alone (no other state access) can reconstruct every assessment and gate
  outcome with its cause, matching spec.md Acceptance Scenario 2's literal claim.
- Tests: itself.
- Taxonomy: happy / regulatory (audit-trail completeness — SC-006's regulatory category, US1's
  own slice of it).
- Depends on: ADH-010.

**Checkpoint**: User Story 1 fully functional and independently testable/demoable (MVP).

---

## Phase 4 — User Story 2: The loan asks for help only when a rule can't decide (Priority: P1)

**Goal**: An `:indeterminate` gate outcome — and only that — raises an escalation; every LLM
failure mode has a defined, tested, deterministic fallback (SC-003/SC-004).

**Independent Test**: Construct a genuinely indeterminate scenario; assert exactly one
escalation, not a silent guess either way (spec.md Acceptance Scenarios 1-3).

### ADH-012 [US2] — `%LoanActor.Escalation{}` + `:indeterminate` → escalation wiring
- Deliverable: `lib/loan_actor/escalation.ex` (struct per `data-model.md`); Server wiring routing
  an `:indeterminate` `evaluate_gate` outcome to an escalation (never a `:decision`), appending
  `:escalated` with `escalation_id`/`gate_id`/`gate_version`/`trigger`/`target`/`input_hash`.
  Server-side `gen_state.escalations` mirrors the existing `hitl_requests` map shape — multiple
  simultaneous pending escalations per loan are allowed (`/speckit-checklist` finding CHK016).
- Tests: `test/server_escalation_test.exs` — `:indeterminate` produces exactly one escalation,
  never a decision; `:pass`/`:fail` never produce an escalation (the boundary this whole feature
  exists to prove precisely).
- Taxonomy: happy / boundary / error / regulatory.
- Depends on: ADH-004, ADH-007.

### ADH-013 [US2] — Human escalation target (reuses `request_operator_approval`)
- Deliverable: an escalation with `target: :operator` invokes the EXISTING
  `request_operator_approval` tool unchanged (foundation's own deferred-`ToolCallResult`
  pattern); `respond_hitl/3`'s answer produces `:escalation_resolved` + a follow-on `:decision`.
- Tests: `test/server_escalation_test.exs` (extended) — operator answers, escalation resolves,
  decision follows, all diary-logged; crash-mid-escalation + restart reproduces the same pending
  state (spec.md Edge Case: "loan crashes before it's answered").
- Taxonomy: happy / error / replay / race (mirrors `hitl_test.exs`'s own first-response-wins
  pattern if two targets somehow both resolve — unlikely for `:indeterminate` specifically, but
  the existing conflict path is inherited, not reinvented).
- Depends on: ADH-012.

### ADH-014 [US2] — LLM escalation port + recorded-fixture test double
- Deliverable: `lib/loan_actor/llm/adapter.ex` (behaviour per `contracts/llm-escalation-port.md`)
  + a fixture-backed test double implementation (no live vendor call — `research.md` R-1).
- Tests: `test/llm/adapter_contract_test.exs` — the constitution's 3 mandated LLM tests
  (deterministic-only path never invokes it; escalation trigger invokes it exactly once with the
  expected shape; each of the 4 failure modes via its own recorded fixture).
- Taxonomy: happy / error / security (situation passed to the adapter has already passed
  PIIGuard — order-of-operations test, mirrors `tool/pii_integration_test.exs`).
- Depends on: ADH-012.

### ADH-015 [US2] — `assess_via_llm` tool + fail-closed fallback wiring
- Deliverable: `lib/loan_actor/tools/assess_via_llm.ex` — the ONE call site for ADH-014's
  adapter; `{:error, :not_configured}` (tool-level failure, `:tool_failed`) if no adapter module
  is configured (`/speckit-checklist` finding CHK012 — distinct from the 4 LLM-response failure
  modes below); on adapter success, `:escalation_resolved` with cleartext `output`
  (post-PIIGuard, per `research.md` R-4) plus `prompt_id`/`model`/`model_version`/
  `decision_delta_hash`; on any of the 4 failure modes, `:escalation_failed` + the gate outcome
  treated as `:fail` (uniform fail-closed policy, `llm-escalation-port.md`).
- Tests: `test/tools/assess_via_llm_test.exs` (shared tool suite) + one test per failure mode
  asserting the exact `:escalation_failed`/`fail` outcome; one test for the PIIGuard-rejects-
  output fail-closed path (R-4's own named edge).
- Taxonomy: happy / boundary / error / security / regulatory (this is where Principle III's
  itemized escalation fields get their concrete proof).
- Depends on: ADH-013, ADH-014.

### ADH-016 [US2] — `NoLLM` Credo check allow-list update
- Deliverable: `LoanActor.Credo.NoLLM` gains an explicit, named exception for
  `lib/loan_actor/tools/assess_via_llm.ex` (and, transitively, `lib/loan_actor/llm/adapter.ex`)
  — every other file in `lib/loan_actor/` stays fully covered, unchanged.
- Tests: `test/credo/no_llm_test.exs` extended — a fixture proving the allow-listed file is
  exempt AND a fixture proving a DIFFERENT file referencing an LLM term is still rejected (the
  check's scope narrowed correctly, not broadened).
- Taxonomy: happy / error / security / contract (SC-004's own static-check proof).
- Depends on: ADH-015.

**Checkpoint**: User Stories 1 AND 2 both independently functional; the deterministic/
LLM-escalation boundary is precisely proven.

---

## Phase 5 — User Story 3: Rules are content, not code (Priority: P2)

**Goal**: A new or malformed gate pack is a content change, never a code change; malformed
packs are rejected with a specific reason, never silently evaluated.

**Independent Test**: Author a new pack with zero code changes; confirm it loads/evaluates/logs
like the demo pack.

### ADH-017 [US3] — New-pack-without-code-change test
- Deliverable: `test/gate_pack_content_only_test.exs` — write a SECOND gate pack (distinct from
  ADH-009's demo pack) purely via `Factory.write_skill_pack!/2` at test time (no `lib/` file
  touched), reload, and confirm it evaluates on its own declared trigger (spec.md Acceptance
  Scenario 1).
- Tests: itself.
- Taxonomy: happy / contract.
- Depends on: ADH-005.

### ADH-018 [US3] — Malformed-pack rejection test
- Deliverable: extends ADH-017's test file — a gate pack with an unrecognized `rule` structure,
  or a `gate_id` referencing something the system doesn't recognize, is rejected at load with a
  specific logged reason, never silently evaluated (spec.md Acceptance Scenario 2).
- Tests: itself (uses ADH-005's own invalid-variant fixture catalog — no new fixtures beyond
  what ADH-005 already built for this exact purpose).
- Taxonomy: error / boundary.
- Depends on: ADH-017.

**Checkpoint**: All three user stories independently functional and demonstrable.

---

## Phase 6 — Polish & cross-cutting concerns

### ADH-019 — Full replay-reproducibility property test (SC-005)
- Deliverable: extends `server_property_test.exs`'s own pattern (not a parallel property suite)
  — for random legal walks now ALSO exercising this feature's tools (assess/evaluate/decide/
  escalate), a crash + rehydration reproduces the identical assessment/decision/escalation
  history, not just status/version/tool-invocation-sequence as before this feature.
- Tests: itself.
- Taxonomy: replay (this feature's own capstone proof — directly answers intent 0001's own
  closeout-audit-found gap that goal content doesn't survive replay, by proving THIS feature's
  new state does, from day one rather than discovering the gap later).
- Depends on: ADH-011, ADH-016, ADH-018.

### ADH-020 — Load-test extension (assessment/gate overhead vs. NFR-001)
- Deliverable: extends `nfr_load_test.exs`'s own SC-001 scenario — with the demo gate pack
  active (assessment + gate evaluation now firing every loop pass in addition to existing tool
  ceremony), re-measure p95 event-to-diary latency against the SAME 100ms budget.
- Tests: itself. Per `plan.md`'s own Performance Goals note, measure on a real Linux environment
  (mirrors intent 0001's own closeout finding that the local Windows dev machine is not
  representative) — not just a local run.
- Taxonomy: performance (treated as boundary, matching FT-035's own established precedent).
- Depends on: ADH-019.

### ADH-021 — Taxonomy coverage confirmation (SC-006)
- Deliverable: no new code — a review pass confirming every applicable taxonomy category
  (happy/boundary/error/race/replay/regulatory/security) has ≥1 test among ADH-001..020,
  mapped in this feature's own closeout-equivalent note (mirrors spec 001's own tasks.md
  "Taxonomy coverage summary" table below).
- Tests: n/a (this task IS the confirmation).
- Taxonomy: n/a.
- Depends on: ADH-020.

---

## Dependencies & execution order

```
ADH-001 ─► ADH-002 ─► ADH-008
ADH-001 ─► ADH-003 ─► ADH-004
ADH-003 ─► ADH-005 (gate-pack loader extension needs the grammar to validate against)
ADH-004 + ADH-005 ─► ADH-006 ─► ADH-007
ADH-007 + ADH-008 ─► ADH-009 [P] ─► ADH-010 ─► ADH-011                    (US1)
ADH-004 + ADH-007 ─► ADH-012 ─► ADH-013 ─► ADH-015                        (US2)
ADH-012 ─► ADH-014 ─► ADH-015 ─► ADH-016                                  (US2)
ADH-005 ─► ADH-017 ─► ADH-018                                             (US3)
ADH-011 + ADH-016 + ADH-018 ─► ADH-019 ─► ADH-020 ─► ADH-021              (Polish)
```

## Parallel batches

- Batch A (after ADH-001): ADH-002 `[P]` ADH-003.
- Batch B (after ADH-002+ADH-003): ADH-004, ADH-005, ADH-008 — largely parallel (different
  files), though ADH-005 needs ADH-003's grammar to validate against and ADH-004 needs ADH-002's
  assessment shape to evaluate against; genuinely independent of each other.
- Batch C (after Foundational/ADH-006/007/008 complete): US1 (ADH-009→011), US2
  (ADH-012→013→014→015→016), and US3 (ADH-017→018) can all proceed in parallel — this is where
  the "share Foundational, independent thereafter" structure pays off.

`/speckit-implement` selects batches respecting the graph above.

## Taxonomy coverage summary

| Category | Tasks covering it |
|---|---|
| Happy | All production tasks. |
| Boundary | ADH-002, ADH-003, ADH-006, ADH-007, ADH-009, ADH-012, ADH-015, ADH-018. |
| Error | ADH-003, ADH-004, ADH-005, ADH-013, ADH-014, ADH-015, ADH-016, ADH-018. |
| Race | ADH-013. |
| Replay | ADH-002, ADH-004, ADH-007, ADH-008, ADH-013, ADH-019. |
| Regulatory | ADH-006, ADH-011, ADH-012, ADH-015 (rule-version traceability + escalation
  audit-trail completeness — SC-006's own named regulatory angle; foundation had zero regulatory
  coverage, this is entirely new). |
| Security | ADH-014, ADH-015, ADH-016. |
| Contract | ADH-003, ADH-005, ADH-016, ADH-017. |
| Performance | ADH-020. |

Every applicable category has at least one task → SC-006 satisfied.

## Definition of done (this feature)

- All ADH-001..021 merged.
- `mix test` green twice consecutively, `mix credo --strict` (incl. the narrowed `NoLLM`
  allow-list) clean, `mix dialyzer` zero errors (both `MIX_ENV=dev` and `MIX_ENV=test`, per the
  environment-parity lesson from intent 0001's own closeout audit).
- CI green, including this feature's load-test extension (ADH-020) measured on a real Linux
  environment, not assumed from local dev hardware (same lesson).
- `quickstart.md`'s smoke checklist passes.
- Constitution v1.2.0's Constitution Check (plan.md) still holds after implementation — no new
  violations beyond what's already justified there.
- Intent 0003 status updated to `Implemented`, pending its own post-implementation audit cycle
  before `Closed` (constitution §"Post-Implementation Audit Cycle", same discipline spec 001
  just went through).
