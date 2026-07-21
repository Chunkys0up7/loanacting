# CLAUDE.md — Loan-as-Actor

This file is the standing contract for every Claude session in this repo. Read it first.
Follow it without exception unless the user explicitly overrides a rule for a specific turn.
It mirrors the constitution at [`.specify/memory/constitution.md`](.specify/memory/constitution.md)
(**v1.2.0**) — the constitution is normative; amend one only by amending the other in the
same change.

---

## 0. Prime directives

Three rules outrank everything else in this file. When in doubt, they decide.

### PD-1 — Specs only. No vibe coding.

**No code without a spec. No spec without an intent. Ever.** Every requirement — including
"small" ones — enters as `intents/NNNN-<slug>.md`, runs the full speckit pipeline
(specify → clarify → plan → analyze → tasks → checklist → implement), and only then becomes
code. If work is not traceable to a task in a committed `tasks.md`, stop and spec it. If an
implementation needs a data structure, API, or behavior `tasks.md`/`plan.md` didn't specify,
**stop and amend the spec** — do not invent mid-implementation.

### PD-2 — Test-driven. Tests are the deliverable.

Tests are written **first or in the same commit** as the code they prove — never after,
never "later". A change without tests is incomplete by definition. Coverage is **taxonomic,
not numeric**: happy / boundary / error / race / replay / regulatory / security / contract /
performance — every applicable category, every task, mapped in the commit/PR description.
Test data comes from **factories** ([`factory.ex`](apps/loan_actor/test/support/factory.ex),
test-data-forge discipline), never hand-rolled fixtures. No mocks at architectural
boundaries — real BEAM, real diary store, real streams.

### PD-3 — Tools + skills execution.

Every **self-initiated** agent function is a **tool** (typed, JSON-schema'd, registered,
diary-logged, streamed to the UI as AG-UI ToolCall events). All when-to-use knowledge is a
**skill pack** (versioned markdown content, trigger in front-matter). Which tools exist =
code; when to use them = content. Nothing the actor does on its own initiative may bypass
the tool registry; no routing/trigger logic may live in code. Full rules in §5.

---

## 1. What this project is

**Loan-as-Actor** inverts mortgage tech: instead of a passive loan record moved between
stations by orchestrator-agents, the **loan itself is the live actor** — a long-running
supervised process with its own diary, goals, tools, skills, and 30-year lifespan. Runtime:
**BEAM (Elixir/OTP)**. UI: **CopilotKit** over **AG-UI** (SSE). Full rationale:
[`loan-as-actor.html`](loan-as-actor.html) — read it before architecture-level work.

Architecture invariants (load-bearing — do not weaken without an amendment intent):

- **The loan is the actor.** Capabilities are summoned *by* the loan, never orchestrated
  *over* it. No top-level orchestrator, no workflow engine holding loan state.
- **Three-loop harness**: reactive (mailbox events) · periodic (heartbeat reflection) ·
  planning (state-driven goals). Every handler is tagged with its loop.
- **Deterministic-first, LLM-escalated.** Rules and calculations run as code. LLM calls are
  escalations, never the default; every escalation is diary-logged with cause. Foundation
  contains **zero** LLM calls (grep-tested, SC-009).
- **Immutable diary.** Every event, decision, tool invocation, and state transition is an
  append-only, BLAKE2b-256 chain-linked diary entry. State is reproducible by replay;
  tampering is detectable (`verify_chain`).
- **Agent functions are tools and skills** (constitution Principle VIII, intent 0004). See
  PD-3 and §5.
- **Operating procedures are content** (Principle VI). Skill packs are the mechanism.
- **PII never enters the diary or the UI stream.** Hashes and vault pointers only; tool args
  pass PIIGuard *before* hashing and *before* emission.
- **Portable identity.** Stable `loan_id` (UUIDv7; MISMO overlay is a later intent).

---

## 2. Project state (snapshot 2026-07-21, updated later same day — update this section when it drifts)

**Where truth lives** (check these at session start, in order):
1. Status ledger in [`specs/001-loan-actor-foundation/tasks.md`](specs/001-loan-actor-foundation/tasks.md) — which FT tasks are DONE.
2. [`work-log/sessions.md`](work-log/sessions.md) — gitignored session narrative, newest first. Append an entry every session; never edit prior entries.
3. `git log` / open PRs on `Chunkys0up7/loanacting`.

**Intents:**

| Intent | Status | What |
|---|---|---|
| 0001 foundation-loan-as-actor | Specified → implementing | The runtime foundation (spec 001, FT-001..FT-045) |
| 0002 amend: post-impl audit cycle | Specified | Constitution v1.1.0 — closeout artifacts (§7b) |
| 0003 autonomous-decision-harness | Draft, **uncommitted** | Gates-as-tools decision layer; enters `/speckit-specify` only after 0001 is Implemented |
| 0004 amend: tools + skills | Specified | Constitution v1.2.0 Principle VIII; spec 001 amended in place |

**Implementation state (spec 001):** DONE — FT-001..FT-017, FT-041..FT-044 (everything
through Track 5's reactive loop plus the full tool+skill layer): umbrella/deps/credo/CI,
diary Entry/Chain/Store/File/Mnesia + shared suite, State+Goal+transition/2+Model,
NoDirectStateMutation Credo check (real AST walk), Event+validate/1, PIIGuard (hard gate)
+ pii_patterns.yml, Idempotency (carries diary sequence — clarifications Q13),
Supervisor+Registry+Application, **Server reactive loop is alive**: `LoanActor.spawn/1` →
`send_event/2` runs validate → PIIGuard → idempotency → transition → diary append
atomically, crash-recovery rehydration replays the diary, all proven by an end-to-end
integration test. Tool layer: `Tool`/`Tool.Spec`/`Tool.Context`, config-driven `Registry`,
the 7 foundation tools (`set_goal`, `satisfy_goal`, `request_document`, `transition_state`,
`append_note`, `request_operator_approval`, `verify_diary_chain`), `Skill`/`Skill.Loader` +
the demo pack. FT-018b superseded by FT-044.

**Next in dependency order:** FT-018 (periodic/heartbeat loop) ∥ FT-019 (planning loop) —
both now unblocked (needed FT-017+FT-043+FT-044, all done) — then FT-020/021 (remaining
Credo check AST walks), FT-022 (LLM-absence grep test), FT-023 (AG-UI encoder, 15 event
types), FT-025..028 (HTTP + HITL), FT-029+ (frontend, currently just a scaffold stub),
FT-034+ (property/load tests) per the amended graph in tasks.md.

**Genuine spec ambiguities resolved this session (see clarifications.md Q12/Q13 for full
reasoning — read before touching PIIGuard or Idempotency):** PIIGuard is a hard gate, not
redact-and-continue; Idempotency's `loan_idem` record carries the diary sequence via a
reserve-then-fill two-phase design. Also fixed: the FT-042 registry's `tool_pii_guard` slot
now matches `PIIGuard.apply/1`'s real 3-shape return exactly.

**Repo map:** `apps/loan_actor` (Elixir OTP app — lib, test, priv/skills) ·
`apps/web` (Vite/React/TS + CopilotKit — scaffold incomplete, FT-029) ·
`intents/` · `specs/001-loan-actor-foundation/` (spec, plan, data-model, contracts×6,
checklists×5, tasks + ledger) · `.specify/memory/constitution.md` · `work-log/` (gitignored).

---

## 3. Spec-driven development — the pipeline (PD-1 in practice)

```
  user request
       │
       ▼
  intents/NNNN-<slug>.md          ← INTENT (the WHY; template: intents/TEMPLATE.md)
       │  /speckit-specify
       ▼
  specs/<feature>/spec.md         ← EXECUTION SPEC (FRs/NFRs/SCs)
       │  /speckit-clarify → /speckit-plan → /speckit-analyze → /speckit-tasks
       ▼
  specs/<feature>/{plan,tasks,data-model,research,quickstart,contracts/}.md
       │  /speckit-checklist  (quality gates BEFORE code)
       ▼
  specs/<feature>/checklists/*.md
       │  /speckit-implement
       ▼
  code + tests (tests FIRST or same commit — PD-2)
```

- **All seven steps run for every feature. No skipping** `/speckit-tasks` or
  `/speckit-checklist`, even for "small" changes. The discipline is the point.
- **Amendments are intents too.** Changing an already-Specified spec, a contract doc, the
  constitution, or an AG-UI event set requires an amendment intent
  (`intents/NNNN-amend-…`) through the same pipeline. Precedents: 0002, 0004.
- **Contracts are source of truth.** `specs/*/contracts/*.md` are test-pinned; the contract
  doc changes FIRST, code follows, drift fails CI.
- **All artifact layers are committed** (intent, spec, plan, tasks, checklists). Intent =
  WHY; spec-kit artifacts = HOW.
- The `speckit` skill is the playbook for every `/speckit-*` step — invoke it, don't wing it.
- **Lifecycle**: `Draft → Ready → Specified → Implemented → Closed` (terminal; requires the
  §7b closeout). Also `Abandoned` / `Superseded`.

---

## 4. Test-driven development — hard rules (PD-2 in practice)

- **Tests first or same commit. Never after.** A PR with implementation but no tests is
  incomplete and gets rejected.
- **Per-commit gates — all of them, every commit:**
  1. `mix test` green **twice consecutively** (catches cross-run state leaks — this rule
     found a real bug in FT-008);
  2. `mix credo --strict` clean (custom checks included);
  3. `mix dialyzer` zero errors;
  4. commit message maps taxonomy categories → test files.
- **Taxonomy, not percentage**: happy / boundary / error / race / replay / regulatory /
  security / contract / performance. Every applicable category per task (see the taxonomy
  table in tasks.md); N/A requires a one-sentence justification.
- **No mocks at architectural boundaries.** Integration tests hit a real BEAM node, real
  diary store (File AND Mnesia via the shared suite), real SSE streams. Unit-level mocking
  inside a module is fine; never at the seams.
- **Factories only** (test-data-forge): all non-trivial test data flows through
  [`factory.ex`](apps/loan_actor/test/support/factory.ex) — deterministic defaults (pure
  functions of inputs; fixed timestamps), documented invalid-variant catalogs for negative
  tests, StreamData generators for property tests, per-run-token unique ids (stores persist
  across BEAM runs). Every factory carries a discovery-checklist moduledoc.
- **Shared behaviour suites** for every behaviour contract: `diary_store_shared.ex`,
  `tool_shared.ex` — a new implementation MUST pass the suite unchanged.
- **Property-based tests** (StreamData) for state machines and chain/replay invariants.
- **Time-travel tests**: every state-mutating handler proves replay reproduces its state.
- **Performance budgets are assertions** (`mix test.load`, tag `:load`, excluded by default);
  NFR budgets re-proven whenever ceremony is added to a hot path.
- **Every escalation path** (future 0003): deterministic-path test + trigger test + one test
  per documented LLM failure mode.
- **Triggered skills**: `test-guardian` (strategy/taxonomy) and `test-data-forge`
  (factories/fixtures) MUST be consulted for any test work. Don't reinvent.
- Windows note: working tree is CRLF-majority — new `.ex/.exs` files must be CRLF or credo's
  consistency check fails.

---

## 5. Tools + skills execution (PD-3 in practice — constitution Principle VIII)

Binding for anything the loan actor does **on its own initiative** (periodic/planning loops,
HITL emission). Contracts: [`tool-behaviour.md`](specs/001-loan-actor-foundation/contracts/tool-behaviour.md) ·
[`skill-format.md`](specs/001-loan-actor-foundation/contracts/skill-format.md) ·
[`ag-ui-events.md`](specs/001-loan-actor-foundation/contracts/ag-ui-events.md).

- **Every self-initiated function is a tool**: a module implementing `LoanActor.Tool`
  (`spec/0` + `execute/2`), listed in the config-driven `Tool.Registry`
  (`config :loan_actor, :tools`). No bypassing the registry. Inbound event ingestion
  (reactive pipeline) is NOT a tool call (clarify Q11).
- **Tools return effects; the Server applies them** through `State.transition/2`. A tool
  mutating state directly is a constitution violation (`NoDirectStateMutation`).
- **Glass-box**: every invocation appends the diary pair (`:tool_invoked` →
  `:tool_completed`/`:tool_failed`) and streams `ToolCallStart/Args/End/Result` over AG-UI.
  HITL (`request_operator_approval`) defers its Result until `respond_hitl/3`. Tool failures
  complete the sequence with an error-shaped Result — never a `RunError`.
- **PII order of operations**: args pass `PIIGuard` BEFORE diary hashing and BEFORE any UI
  emission. The registry's `redacted_args/2` is the exact form hashed and streamed.
- **Skills are content packs**: `priv/skills/<NNNN-slug>/SKILL.md` (front-matter `name`,
  `version`, `description` = trigger, `tools_required`) + optional `references/`. The loader
  validates `tools_required` against the registry at load time, supports reload, and
  trigger-matches against `{status, event type, open goal descriptions}`. Every pack links
  to a test proving it fires.
- **No routing logic in code** — registry and tool modules contain zero trigger/selection
  logic; that's skill content.
- **Hard caps** (extending either requires an amendment intent): args schemas use only
  `type`/`properties`/`required`/`enum`; skill front-matter is `key: value` + `[a, b]`
  lists only.
- **No public invoke API** — tools are summoned by the loan's own loops (Principle I;
  clarify Q8). External influence = `send_event/2` and `respond_hitl/3`.
- **Zero LLM tools in foundation.** The first non-deterministic tool arrives with intent
  0003, reachable ONLY through a gate returning `:indeterminate`.

---

## 6. UI layer

CopilotKit + AG-UI is the only sanctioned UI path. **No second chat/agent UI framework.**

- Backend emits the 15-event foundation subset (incl. the four ToolCall events per 0004)
  over SSE from Bandit/Plug — see `contracts/ag-ui-events.md`. Frontend consumes via
  CopilotKit components/hooks (`useCoAgent`, `useCoAgentStateRender`, `useCopilotAction`).
- Diary feed + tool activity are generative-UI surfaces (`ToolCallCard` correlates frames
  by `tool_call_id`). Operator HITL uses `useHumanInTheLoop`/`useLangGraphInterrupt`;
  approvals are diary events.
- The `copilotkit` skill is the canonical reference for any UI work.

---

## 7. Commit cadence + closeout

### 7a. Cadence

- **One spec = one commit** (`spec(NNNN): <slug> — …`). All spec-kit artifacts for the
  intent, intent status → Specified, **no code**. Amendments follow the same format.
- **One implementation task = one PR/commit** (`FT-NNN: …`), tests in the same commit,
  gates green (§4). Update the status ledger in tasks.md in the same commit.
- Specs and code never share a commit. Follow-up intents get their own files.
- Work happens on feature branches (e.g. `001-loan-actor-foundation`); PRs to `main`.

### 7b. Post-implementation audit cycle (constitution v1.1.0+)

After every FT task for a spec has merged, BEFORE its intent moves to `Closed`: one
`audit(NNNN): <slug> — implementation closeout (v<spec-version>)` commit containing exactly
three artifacts + the intent status flip — **no code**:

- `audit.md` — maps every FR/NFR/SC to proving test/code; deviations listed (empty list
  stated explicitly); new/changed skill packs listed. Different author than implementer
  where possible (solo: self-attest).
- `report.md` — business-language summary; PR/SHA links per track; follow-ups (→ future
  intents); UI screenshots where relevant.
- `test-evidence.md` — taxonomy table mapped to SCs; factory inventory per entity
  (test-data-forge MUST be invoked); load-test actuals vs NFR budgets; green CI run cited.
  `test-guardian` MUST be invoked.

Audit findings outrank PR review: a gap moves the intent back to `Implemented` until closed.
Boilerplate "all criteria met" without verification is a fail.

---

## 8. Repeatable processes (Claude skills)

| Skill | Fires for |
|---|---|
| `speckit` (+ `speckit-*` commands) | Any pipeline step, spec/plan/task work, constitution edits |
| `copilotkit` | CopilotKit, AG-UI, React UI, HITL, generative UI |
| `test-guardian` | Test strategy, taxonomy, coverage review, antipatterns |
| `test-data-forge` | Factories, fixtures, isolation, test-data coverage |

If work matches a skill and it isn't firing, **invoke it explicitly** rather than rolling
your own.

---

## 9. Anti-vibe rules — refuse these

- ❌ "Let's just stub this out and come back to it." → Spec it as an intent, or don't write it.
- ❌ "I'll add a quick mock for the LLM call." → Deterministic path or recorded-fixture
  contract test. Nothing else.
- ❌ "We can skip the intent/spec for this small change." → No. Small changes still have a
  WHY. The discipline is the point.
- ❌ "I'll write the tests after it works." → No. Tests first or same commit (PD-2).
- ❌ Inventing data structures/APIs mid-implementation. → If tasks.md didn't specify it,
  stop and amend the spec (PD-1).
- ❌ Hardcoding a rule/threshold/trigger that could be skill content. → Author it as a pack
  (PD-3, Principle VI).
- ❌ Adding an agent function that bypasses the tool registry. → Constitution violation
  (Principle VIII).
- ❌ Adding dependencies without an entry in the intent's Dependencies section.
- ❌ "Example" code in docs that doesn't compile — examples live in test files CI runs.
- ❌ "I think this is roughly right." → State precisely what's verified and what isn't.
  Uncertainty is fine; vagueness is not.

---

## 10. URLs

- Rationale: [`loan-as-actor.html`](loan-as-actor.html) · Spec-kit: <https://github.com/github/spec-kit>
- CopilotKit: <https://docs.copilotkit.ai/> · AG-UI: <https://docs.ag-ui.com/>
- Erlang/OTP: <https://www.erlang.org/docs> · Elixir: <https://elixir-lang.org/docs.html>
- Repo: <https://github.com/Chunkys0up7/loanacting>
