# Implementation Plan: Autonomous Decision Harness

**Branch**: `002-autonomous-decision-harness`
**Date**: 2026-07-23
**Spec**: [`spec.md`](spec.md)
**Constitution**: [`v1.2.0`](../../.specify/memory/constitution.md)
**Depends on**: spec 001 (`001-loan-actor-foundation`, Closed)

## Summary

Gives the loan actor judgment. Every loop pass, the actor derives a deterministic `%Assessment{}`
from its own state and diary-derived facts, evaluates one or more **gates** (rule content
authored as versioned skill-format packs, never hardcoded), and drives its own state/goal changes
from a `pass`/`fail` outcome through the foundation's existing tools. An `indeterminate` outcome
— and only that — raises an escalation through a pluggable target: `request_operator_approval`
(already exists) or a new `assess_via_llm` tool, the first and only non-deterministic tool this
project has ever had, reachable from exactly one call site. Every assessment, gate evaluation,
decision, and escalation is diary-logged and replay-reproducible, extending the foundation's
existing tool/skill/diary discipline rather than introducing a parallel mechanism.

## Technical Context

**Language/Version**: Elixir 1.17.3 on Erlang/OTP 27.3.4.7 (unchanged from foundation — no new
runtime).

**Primary Dependencies**: No new backend dependencies expected. Gate packs reuse
`LoanActor.Skill.Loader`'s existing restricted front-matter grammar (no new parser). The LLM
escalation adapter is a behaviour with a recorded-fixture contract test; the concrete vendor
adapter (if any lands with this feature at all — see Phase 0 R-1) is a thin, swappable module
behind that behaviour, not a hard dependency of the gate-evaluation path itself.

**Storage**: Same two `DiaryStore` implementations (Mnesia primary, File for tests) — no new
storage. New diary entry types only (`:assessment`, `:gate_evaluated`, `:decision`, `:escalated`,
`:escalation_resolved`, `:escalation_failed`), which `Entry.validate_type/1`'s open-atom design
(confirmed by intent 0004's own retrospective: adding tool/skill diary types touched zero merged
code) admits without any schema migration.

**Testing**: ExUnit + StreamData (property-based determinism of `assess_loan`), the existing
shared tool contract suite (`test/support/tool_shared.ex`) extended to cover the new tools, a
recorded-fixture contract test for the LLM adapter (no live model calls in CI, per constitution
Principle V's "no mocks at boundaries" read together with Principle III's LLM-escalation rules —
a *recorded fixture* is not a mock of this system's own boundary, it's a substitute for an
external, non-deterministic third party).

**Target Platform**: Same as foundation — single-node BEAM, dev on Linux/macOS/Windows.

**Project Type**: Extends the existing Mix umbrella (`apps/loan_actor/`); no new app.

**Performance Goals**: Assessment + gate evaluation runs on every loop pass (reactive, periodic,
planning) — must not blow the foundation's existing p95 event-to-diary budget. Given intent
0001's closeout audit found that budget's prior failures were local-Windows-machine artifacts,
not architectural (see `001-loan-actor-foundation/audit.md` §4), this feature's own load-test
re-run should be measured on the same footing (a real Linux environment, not assumed from a
laptop) before drawing conclusions.

**Constraints**: Deterministic path has zero LLM call sites outside the one escalation adapter
(Principle III, statically checkable — mirrors the existing `LoanActor.Credo.NoLLM` check's
"production paths" scope, extended to allow exactly one new, explicitly-named exception).
Replay must reproduce assessments/decisions/escalations exactly (Principle IV), independent of
wall-clock timestamps (same caveat as `last_heartbeat_at` elsewhere in this codebase).

**Scale/Scope**: One new tool module family (`assess_loan`, `evaluate_gate`, `assess_via_llm`),
one new entry point into the existing skill-pack mechanism (gate packs are skills whose
`tools_required` names `evaluate_gate`), ~4 new diary entry types plus the itemized escalation
fields Principle III's own rules already specify. One demonstration gate pack (≥3 rules).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence in this plan |
|---|---|---|
| I. Loan-is-the-actor | ✅ | Assessment/gate-evaluation/decision/escalation all run inside the existing per-loan `Server` process, driven by its own loop passes — no external orchestrator decides for it. |
| II. Three-loop harness | ✅ | Assessment + gate evaluation run on every loop pass (reactive/periodic/planning), per spec User Story 1 — no new loop type introduced. |
| III. Deterministic-first, LLM-escalated | ⚠→✅ (the gate this whole feature exists to satisfy) | `assess_loan`/`evaluate_gate` are pure, deterministic tools. The LLM path (`assess_via_llm`) is reachable ONLY from an `:indeterminate` gate outcome (FR-004/FR-007/FR-012) — this is the FIRST non-deterministic tool in the project's history, so this gate gets the most scrutiny in Phase 0/1: a static check (mirroring `LoanActor.Credo.NoLLM`) must prove no other call site exists, and every escalation diary entry must carry the constitution's own itemized fields (trigger, prompt id, model, version, full input hash, full output, decision delta) — Phase 1's `data-model.md` must define this shape explicitly, not just "diary-logged" in the abstract the spec currently says. |
| IV. Immutable diary | ✅ | New entry types append within the same transaction as the decision/escalation they record, chain-linked like every existing entry. FR-008/SC-005 require full replay-reproducibility. |
| V. Test-first, taxonomic coverage | ✅ | SC-006 requires every taxonomy category incl. regulatory (gate-version traceability, escalation audit-trail completeness — this feature's own regulatory angle, foundation had none). LLM escalation gets its constitution-mandated 3 tests (deterministic-only path, escalation trigger, each failure mode) per FR-006/SC-003. |
| VI. Operating procedures are content | ✅ | Gates are versioned markdown packs (skill format), never hardcoded branches (FR-002/FR-009/FR-010) — this is the principle's own worked example, arguably more central to it than the foundation's one demo pack was. |
| VII. Portable identity & artifacts | ✅ | No change to `loan_id`. All spec-kit artifact layers committed per this pipeline. |
| VIII. Agent functions are tools and skills | ✅ | `assess_loan`, `evaluate_gate`, `assess_via_llm` are all registered `LoanActor.Tool` modules through the existing config-driven registry — no new mechanism, no routing logic in code (gate *content* lives in packs, matching 0004's own "which tools exist = code, when to use them = content" split). |
| Anti-vibe clauses | ✅ | No hardcoded rule thresholds (would violate Principle VI directly) — the DSL cap for gate rule expressions must be pinned in a new contract doc (mirrors `tool-behaviour.md`/`skill-format.md`'s existing hard-cap pattern), not left implicit. |

**Re-check at end of Phase 1**: deferred until `data-model.md` (especially the escalation entry
shape) + the new gate-behaviour/gate-format contract docs exist.

## Project Structure

### Documentation (this feature)

```text
specs/002-autonomous-decision-harness/
├── spec.md
├── plan.md              ← this file
├── research.md          ← Phase 0 output
├── data-model.md        ← Phase 1 output
├── quickstart.md         ← Phase 1 output
├── contracts/
│   ├── gate-behaviour.md         # the gate-evaluation tool's contract + rule-DSL cap
│   ├── gate-pack-format.md       # gate packs as skill-format packs — front-matter fields
│   └── llm-escalation-port.md    # the escalation adapter behaviour + failure-mode contract
├── tasks.md             ← Phase 2 output (/speckit-tasks)
└── checklists/
    └── requirements.md  ← already produced by /speckit-specify
```

### Source Code (repository root, additions only — foundation structure unchanged)

```text
apps/loan_actor/lib/loan_actor/
├── tools/
│   ├── assess_loan.ex                 # new — deterministic %Assessment{} derivation
│   ├── evaluate_gate.ex                # new — loads + evaluates a gate pack's rule
│   └── assess_via_llm.ex               # new — the ONE non-deterministic tool; escalation-only
├── assessment.ex                       # new — %LoanActor.Assessment{} struct
├── gate.ex                             # new — %LoanActor.Gate{} struct (parsed rule + metadata)
├── decision.ex                         # new — %LoanActor.Decision{} struct (if not folded into diary payload alone)
├── escalation.ex                       # new — %LoanActor.Escalation{} struct
└── llm/
    └── adapter.ex                      # new — behaviour + recorded-fixture-backed test double

apps/loan_actor/priv/skills/
└── 0002-demo-gate-pack/                # new — ≥3 rules, mirrors 0001-demo-document-request's shape

apps/loan_actor/test/
├── tools/
│   ├── assess_loan_test.exs
│   ├── evaluate_gate_test.exs
│   └── assess_via_llm_test.exs         # 3 constitution-mandated tests + all 4 failure modes
├── assessment_property_test.exs        # replay-reproducibility (StreamData)
└── llm/
    └── adapter_contract_test.exs       # recorded fixtures, no live model calls
```

**Structure Decision**: Extends `apps/loan_actor/` in place — no new app, no new umbrella member.
Every new module is additive; nothing in the foundation's existing tree is modified except
`config :loan_actor, :tools` (registering the three new tools) and the Credo `NoLLM` check's own
allow-list (naming `assess_via_llm.ex` as the one sanctioned exception, not disabling the check).

### Skill bindings

- **`speckit` skill** drives the workflow this plan was produced by.
- **`test-guardian` skill** drives the test taxonomy, especially the LLM-failure-mode and
  regulatory categories this feature adds that foundation never needed.
- **`test-data-forge` skill** drives factories for the four new entities (Assessment, Gate,
  Decision, Escalation) plus recorded-fixture design for the LLM adapter contract test.

## Phase 0 — Research (output: `research.md`)

Intent 0003's own Q1/Q2 already carry the author's recommendation (informed defaults, not
re-opened here); Q3/Q4 were resolved during `/speckit-specify` (FR-011/FR-012). Remaining
research questions:

- R-1: Concrete LLM escalation adapter — is a real vendor call included in this feature's own
  scope, or does this feature ship only the port + a recorded-fixture-backed test double, with a
  real adapter as separate follow-up work? (Intent 0003's own Non-goals say "production LLM
  vendor selection/procurement" is out of scope — leans toward: port + fixtures only.)
- R-2: Exact gate rule predicate DSL grammar (intent 0003 Q1's recommendation: field/op/value/
  all-any) — needs the same "restricted grammar, hard-capped, contract-pinned" treatment
  `tool-behaviour.md`'s JSON-schema subset and `skill-format.md`'s front-matter grammar already
  received, not a new ad hoc parser.
- R-3: Incremental vs. recomputed-every-pass facts (intent 0003 Q2's recommendation: incremental
  with a replay-invariant test proving equivalence to full recomputation) — needs a concrete
  `State.context` shape decision.
- R-4: Exact diary entry payload shape for each of the 4 new event types, cross-checked against
  Principle III's itemized escalation fields (trigger, prompt id, model, version, full input
  hash, full output, decision delta) and Principle VIII's hash-only-for-tool-args rule — these
  two constitution rules could be in tension for the escalation entry specifically (does "full
  input hash" mean a hash of the input, consistent with Principle VIII, or does "full output"
  mean the actual output value in cleartext, which would be new — needs explicit resolution, not
  assumption, mirroring how Q12/Q14/Q15 were each raised directly in the foundation build rather
  than guessed).
- R-5: `001-loan-actor-foundation/contracts/skill-format.md` forward-references this intent
  ("intent 0003 owns real assessment-driven selection") — intent 0003's own draft never
  mentions this; needs reconciling before `gate-pack-format.md` can say how a gate pack declares
  when it's even considered (as distinct from how it evaluates once triggered).
- R-6: Whether `assess_loan`'s "diary-derived facts" needs anything beyond what `state.context`
  and existing diary entry types already expose, or whether new derived-fact computation needs
  its own read path over the diary (performance-relevant given R-3).

## Phase 1 — Design (output: `data-model.md`, `quickstart.md`, `contracts/`)

- **`data-model.md`** — `%Assessment{}`, `%Gate{}`, `%Decision{}`, `%Escalation{}` struct
  definitions; the 4 new diary entry types' exact payload shapes (resolving R-4); gate-pack
  front-matter fields extending the existing skill-format grammar.
- **`contracts/gate-behaviour.md`** — the `evaluate_gate` tool's contract + the rule-predicate
  DSL's hard-capped grammar (resolving R-2), mirroring `tool-behaviour.md`'s existing pattern.
- **`contracts/gate-pack-format.md`** — gate packs as an extension of `skill-format.md`, not a
  parallel format.
- **`contracts/llm-escalation-port.md`** — the adapter behaviour, the 4 failure modes and their
  deterministic fallbacks, the recorded-fixture contract-test shape.
- **`quickstart.md`** — extends foundation's own: how to author a new gate pack, spawn a loan,
  and watch it progress autonomously through the demo gate pack; how to force an
  `:indeterminate` and watch the escalation flow.

## Phase 2 — Tasks (output: `tasks.md`, NOT produced by `/speckit-plan`)

Expected tracks (final sequencing + dependency graph is `/speckit-tasks`'s job, not this plan's):

1. **Assessment** — `%Assessment{}` struct, `assess_loan` tool, determinism property test.
2. **Gate engine** — `%Gate{}`, rule-predicate DSL parser (hard-capped), `evaluate_gate` tool,
   gate-pack loading (extends `Skill.Loader`, does not fork it).
3. **Decisions** — wiring `pass`/`fail` outcomes through existing `transition_state`/
   `satisfy_goal` tools; the `:decision` diary entry.
4. **Escalation core** — `%Escalation{}`, the `:indeterminate` → escalation wiring, diary entries
   for raised/resolved, reusing `request_operator_approval`'s existing deferred-Result pattern
   for the human-target case.
5. **LLM adapter** — the escalation-port behaviour, the 4 failure-mode fallbacks, recorded-fixture
   contract test, the `assess_via_llm` tool, the `NoLLM` Credo check's allow-list update.
6. **Demonstration gate pack + end-to-end autonomy test** — ≥3 rules, the zero-operator-
   interaction scripted-event-stream test (SC-001).
7. **Property-based replay** — full assessment/decision/escalation replay-reproducibility
   (SC-005), extending `server_property_test.exs`'s pattern rather than a parallel property suite.
8. **Load-test extension** — assessment-and-gate-evaluation-on-every-pass overhead measured
   against the existing NFR-001 budget, on a real Linux environment per this plan's own
   Performance Goals note.

## Risks & mitigations (delta from foundation)

| Risk | Mitigation |
|---|---|
| The predicate DSL grows into an accidental programming language | Hard cap pinned in `contracts/gate-behaviour.md`; extension requires its own amendment (mirrors the `tool-behaviour.md`/`skill-format.md` precedent). |
| LLM fixture-based contract tests drift from live model behavior | Fixtures versioned with the adapter; a scheduled (non-CI-blocking) live smoke job re-records and diffs — mirrors this project's own `ci-nightly.yml` precedent for genuinely-slow/external-dependent checks. |
| Assessment-on-every-loop-pass blows the reactive-loop latency budget | Load-test extension (Phase 2 track 8) is the early-warning gate, exactly as `FT-035` was for the tool-call ceremony in intent 0004. Incremental facts (R-3) is the designed fallback if recompute-every-pass is too expensive. |
| Principle III's itemized escalation fields (full output in cleartext) initially looked like it might conflict with a "tool diary entries are hash-only" rule | Raised directly as R-4, not assumed. On careful re-reading (confirmed twice — `/speckit-analyze` finding C1 and `/speckit-checklist` finding CHK022), the constitution's own literal text does not actually state a blanket hash-only rule; that convention is `tool-behaviour.md`'s (a contract, not the constitution), and is left fully intact — only a new, separate diary type carries cleartext, never the standard tool-invocation pair. No constitution amendment needed. |
| A second non-deterministic-adjacent gap like intent 0001's goal-content-replay finding | This feature's own replay property (SC-005) explicitly targets assessments/decisions/escalations from day one, rather than discovering the gap post-hoc during a later audit. |

## Re-check after Phase 1

All Phase 1 artifacts now exist (`data-model.md`, `contracts/gate-behaviour.md`,
`contracts/gate-pack-format.md`, `contracts/llm-escalation-port.md`, `quickstart.md`). Re-checking
each gate that was ⚠ or open at Phase 0:

- **Principle III (deterministic-first, LLM-escalated)** → ✅. `contracts/llm-escalation-port.md`
  names the exact one call site, the exact 4 failure modes with a uniform fail-closed policy, and
  the constitution's own itemized escalation-diary fields are resolved explicitly in
  `data-model.md`'s `:escalation_resolved`/`:escalation_failed`/`:escalated` entries (not left as
  "diary-logged" in the abstract) — all seven itemized fields (trigger, prompt id, model,
  version, full input hash, full output, decision delta) now have a named home. R-4's apparent
  tension with Principle VIII was investigated more carefully during `/speckit-analyze` (finding
  C1) and again during `/speckit-checklist`: the constitution's own literal text scopes its
  hash-only language to PII specifically (Principle IV) and states no blanket hash-only rule at
  all (Principle VIII) — the actual hash-only convention lives in `tool-behaviour.md`, a
  spec-001 CONTRACT, not the constitution. This is a documentation-clarity matter, resolved by
  being explicit (`data-model.md`'s own scoping sentence), not a constitution conflict requiring
  an amendment.
- **Anti-vibe / gate-DSL-cap concern** → ✅. `contracts/gate-behaviour.md` pins the exact grammar;
  `research.md` R-2 documents why (mirrors the existing JSON-schema-subset and front-matter-grammar
  caps this project already has precedent for).
- **New gap found during Phase 1, now closed**: `skill-format.md`'s forward-reference to this
  intent ("assessment-driven selection") was NOT in intent 0003's own draft and would have left
  `gate-pack-format.md` unable to say how gates get triggered at all — resolved as `research.md`
  R-5 (extend `match/2`'s input, not its algorithm) before writing that contract, not discovered
  after implementation started.

No new violations introduced, so no Complexity Tracking section is included (nothing here
requires justifying against a simpler alternative — same "when a section doesn't apply, remove
it entirely" convention this pipeline follows elsewhere).

Ready for `/speckit-tasks`.
