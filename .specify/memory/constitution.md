<!--
Sync Impact Report
==================
Version change: (none) → 1.0.0
Bump rationale: Initial ratification of the Loan-as-Actor constitution.
Modified principles: N/A (initial draft)
Added sections:
  - Core Principles (I–VII)
  - Architectural Invariants
  - Development Workflow (Spec-Driven)
  - Governance
Removed sections: N/A
Templates requiring updates:
  - .specify/templates/plan-template.md          ⚠ pending (Constitution Check section may need additions; review in /speckit-plan)
  - .specify/templates/spec-template.md          ⚠ pending (review scope & requirements alignment)
  - .specify/templates/tasks-template.md         ⚠ pending (task taxonomy must reflect testing/diary/HITL gates)
  - .specify/templates/checklist-template.md     ⚠ pending (taxonomic coverage categories must appear)
Follow-up TODOs:
  - TODO(RATIFICATION_DATE): confirm 2026-05-26 as official adoption date with project owner.
-->

# Loan-as-Actor Constitution

This constitution establishes the non-negotiable principles for the Loan-as-Actor project. It is the supreme operating contract for the codebase: every spec, plan, task, and PR must comply. Amendments follow the procedure in **Governance**.

The companion file [`CLAUDE.md`](../../CLAUDE.md) contains the same load-bearing rules in a form addressed to AI coding agents working in this repo. Both files MUST remain consistent; amend one only by also amending the other in the same change.

---

## Core Principles

### I. Loan-Is-The-Actor (NON-NEGOTIABLE)

A mortgage loan is modeled as a long-running, supervised process — not a database row, not a state object passed between services. Capabilities (compliance, valuation, document extraction, escalation) are summoned **by** the loan; they are never orchestrated **over** it.

**Rules:**
- MUST: Every loan exists as an addressable, supervised actor on the BEAM runtime from the moment it is originated until it is paid off, sold, or written down.
- MUST NOT: Introduce a top-level orchestrator or workflow engine that holds loan state outside the loan actor itself.
- Rationale: Stage transitions (origination → underwriting → closing → servicing) are seams where context drops in conventional architectures. Eliminating the orchestrator eliminates the seam.

### II. Three-Loop Harness (NON-NEGOTIABLE)

Every loan actor runs three explicit loops. Code that mixes them or adds a fourth requires constitutional amendment.

- **Reactive loop** — handles incoming events (mailbox). Latency-sensitive. Deterministic.
- **Periodic loop** — heartbeat reflection. Inspects state, may set goals. Runs on a wall-clock interval.
- **Planning loop** — state-driven. When goals are set, emits outbound events/requests.

**Rules:**
- MUST: Every actor-side handler is classified into one of the three loops in code and in the relevant spec.
- MUST NOT: Add ad-hoc background tasks or timers outside the periodic loop.

### III. Deterministic-First, LLM-Escalated (NON-NEGOTIABLE)

Rules, calculations, and routing run as code. LLM calls are escalations — invoked only when deterministic logic cannot resolve a case, and always logged with cause.

**Rules:**
- MUST: Every LLM call site has a documented deterministic predecessor and a documented escalation trigger.
- MUST: Every LLM call appends a diary entry containing: trigger, prompt id, model, version, full input hash, full output, decision delta.
- MUST NOT: Use an LLM as the first or default reasoning path for a capability that can be specified deterministically.
- Rationale: Regulatory traceability, replay-ability, and cost discipline.

### IV. Immutable Diary (NON-NEGOTIABLE)

Every event the loan accepts, every state transition it makes, every output it emits is appended to its diary. The diary is append-only. State is reproducible by diary replay.

**Rules:**
- MUST: Every state-mutating handler appends a diary entry within the same logical transaction.
- MUST: Diary entries are chain-linked (`prev_hash`) so tampering is detectable.
- MUST NOT: Mutate or delete diary entries. GDPR-style erasure of PII operates on a separate vault, not the diary; the diary holds hashes/pointers, not the PII itself.
- MUST: Every state-mutating handler has a test that proves its state is reproducible from diary replay.

### V. Test-First, Taxonomic Coverage (NON-NEGOTIABLE)

Tests are part of the deliverable. Coverage is measured by **what category of behavior is exercised**, not by line percentage.

**Rules:**
- MUST: Tests are written before or in the same commit as implementation. A PR with implementation but no tests is rejected.
- MUST: Each non-trivial change exercises every applicable category from the taxonomy — `happy`, `boundary`, `error`, `race`, `replay`, `regulatory`, `security`. PR descriptions map each applicable category to test files.
- MUST: Integration tests run against a real BEAM node and a real diary store. Mocks at architectural boundaries are forbidden; unit-level mocking inside a module is permitted.
- MUST: Test data comes from factories documented under the `test-data-forge` discipline. Hand-rolled fixtures of opaque provenance are forbidden.
- MUST: Every LLM escalation path has three tests: deterministic-only path, escalation trigger, and each documented LLM failure mode.
- MUST: State-machine code uses property-based testing (PropEr / StreamData).
- MUST: Performance budgets (p95 latency, memory ceiling, mailbox depth) are encoded as test assertions, not aspirations.

### VI. Operating Procedures Are Content (NON-NEGOTIABLE)

Compliance rules, escalation playbooks, and routing decisions live as versioned markdown the actor reads at runtime — not as hardcoded conditional branches.

**Rules:**
- MUST: Every procedure declares its own trigger condition in front-matter.
- MUST: Procedure documents are versioned in git, linked to test cases that prove they fire correctly.
- MUST NOT: Hardcode a compliance threshold or routing rule when it could be authored as a procedure.
- Rationale: Regulator-readable; hot-swappable; preserves vendor portability.

### VII. Portable Identity & Artifacts (NON-NEGOTIABLE)

A loan's identity, diary, and contract surface must remain valid across origination, servicing, secondary-market sale, and platform changes. Every change must leave a paper trail of artifacts:

```
intents/NNNN-<slug>.md              ← the WHY (human-authored)
specs/<feature>/spec.md             ← the WHAT (via /speckit-specify)
specs/<feature>/plan.md             ← the HOW (via /speckit-plan)
specs/<feature>/tasks.md            ← the STEPS (via /speckit-tasks)
specs/<feature>/checklists/*.md     ← the QUALITY GATES (via /speckit-checklist)
src/...                             ← the CODE (only after the above)
test/...                            ← the TESTS (alongside code, never after)
```

**Rules:**
- MUST: Every new requirement begins as an intent file under `intents/`. No code without a spec; no spec without an intent.
- MUST: Loan identity is a stable `loan_id` independent of platform-internal database IDs; foundation uses UUIDv7, with MISMO overlay added in a later intent.
- MUST: All artifact layers (intent, spec, plan, tasks, checklists) are committed.
- MUST NOT: Skip `/speckit-tasks` or `/speckit-checklist`, even for "small" changes.

---

## Architectural Invariants

These are the load-bearing technical commitments. Changing any of them requires a MAJOR version bump.

- **Runtime**: BEAM (Erlang/OTP and/or Elixir). Supervision trees model the loan lifecycle.
- **Diary store**: append-only, chain-linked, with a clear interface so the backing technology (Mnesia / file / object store) is swappable.
- **UI layer**: CopilotKit (React) over the AG-UI protocol (17 canonical events, SSE transport). No second chat/agent UI framework may be introduced.
- **HITL**: Operator and borrower interventions surface through `useHumanInTheLoop` / `useLangGraphInterrupt` (or AG-UI equivalents). Every approval is a diary event.
- **PII handling**: PII is stored in a separate vault, never in the diary. The diary holds hashes and vault pointers. GDPR erasure is a vault-side operation.
- **Performance baseline (foundation)**: 100 concurrent loan actors at 10 events/sec/actor with p95 event-to-diary latency < 100ms and resident memory < 256MB.

---

## Development Workflow (Spec-Driven)

```
intent (human)
  → /speckit-specify   → spec.md
  → /speckit-clarify   → (resolves open questions)
  → /speckit-plan      → plan.md, data-model.md, research.md, quickstart.md
  → /speckit-analyze   → consistency check
  → /speckit-tasks     → tasks.md
  → /speckit-checklist → checklists/*.md  (quality gates BEFORE code)
  → /speckit-implement → code + tests
```

**Rules:**
- MUST: All seven steps run for every feature. No skipping.
- MUST: `/speckit-checklist` produces gates before `/speckit-implement` is invoked.
- MUST: Tests are authored alongside (or before) implementation in `/speckit-implement`.
- MUST: When the runtime emits a diary entry for an HITL approval, the corresponding intent must reference the gate in its `Success criteria` section.
- MUST: The `speckit`, `copilotkit`, `test-guardian`, and `test-data-forge` skills installed under `.claude/skills/` are the canonical playbooks. Agents working in this repo MUST consult them rather than reinventing the workflows.

### Anti-vibe Clauses

The following behaviors are constitutionally forbidden:

- Stubbing implementation "to come back to". Spec it or omit it.
- Mocking LLM calls in lieu of a deterministic path or a recorded-fixture contract test.
- Adding dependencies (npm, hex, mix, pip) without an entry in the relevant intent's `Dependencies` section.
- Inventing data structures during `/speckit-implement` not specified in `tasks.md` or `plan.md`.
- Writing "example" code in docs that does not compile against the current codebase. Examples MUST live in test files that CI executes.
- Submitting any artifact that uses the phrase "I think this is roughly right" or equivalent. State precisely what is verified and what is not.

---

## Governance

- **Authority**: This constitution supersedes any guidance not derived from it. Conflicts resolve in favor of the constitution.
- **Amendment procedure**: Open an intent (`intents/NNNN-amend-constitution-<topic>.md`) with the proposed change, rationale, and impact analysis on dependent templates. The amendment runs through the full spec-driven pipeline like any other change.
- **Versioning** (semver applied to governance):
  - MAJOR — removing or redefining a principle, or changing an architectural invariant.
  - MINOR — adding a principle, adding a section, materially expanding guidance.
  - PATCH — wording, typos, clarifications without semantic change.
- **Compliance review**: every PR description MUST state how the change complies with this constitution. PRs that do not are rejected by the reviewer (human or agent).
- **Source of truth for principles**: this file. `CLAUDE.md` mirrors these principles for agent context but does not override them.

**Version**: 1.0.0 | **Ratified**: 2026-05-26 | **Last Amended**: 2026-05-26
