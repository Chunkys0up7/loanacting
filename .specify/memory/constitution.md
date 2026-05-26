<!--
Sync Impact Report
==================
Version change: 1.0.0 → 1.1.0
Bump rationale (MINOR): Added new section "Post-Implementation Audit Cycle"
  formalizing what happens after /speckit-implement completes for a spec.
  Driven by intent 0002.
Modified principles: none renamed/redefined.
Added sections:
  - Post-Implementation Audit Cycle (between Development Workflow and Governance)
Removed sections: N/A
Templates requiring updates:
  - intents/TEMPLATE.md                          ✅ updated (lifecycle adds Closed)
  - intents/README.md                            ✅ updated (lifecycle table)
  - CLAUDE.md                                    ✅ updated (new §6b)
  - specs/001-loan-actor-foundation/
      checklists/definition-of-done.md           ✅ updated (Closeout section)
  - .specify/templates/checklist-template.md     ⚠ pending (future intents should
                                                   reference closeout artifacts)

Prior history:
  v1.0.0 (2026-05-26) — Initial ratification.
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

## Post-Implementation Audit Cycle

Every spec runs through a closeout phase after `/speckit-implement` has merged all `FT-*` tasks for it. The phase produces exactly three artifacts and one commit; intent status moves from `Implemented` → `Closed`.

### Artifacts (all required)

Written into the spec's directory, alongside `spec.md` / `plan.md` / etc.

1. **`audit.md`** — Independent verification that the merged code fulfills the spec.
   - SHOULD be authored by an operator/agent different from the implementer. Solo work is permitted; in that case the auditor self-attests and the document records it.
   - MUST list every spec FR / NFR / SC and map to the test or code location proving fulfillment.
   - MUST list deviations from the spec (any FR / NFR / SC modified, deferred, or interpreted differently than the original spec stated). Empty deviation list is acceptable; missing deviation section is a fail.
   - MUST list any procedure documents (`priv/procedures/…`) added or modified during implementation, with their trigger conditions.

2. **`report.md`** — Operator-facing implementation report.
   - MUST summarize what shipped in business language (no Elixir module names in the summary; technical detail comes later in the doc).
   - MUST list follow-ups: known bugs, deferred work, performance observations, anything that should become a future intent.
   - MUST link the PRs (or commit SHAs) that implemented each track in `tasks.md`.
   - SHOULD include a screenshot or recording reference for any UI-touching feature.

3. **`test-evidence.md`** — Testing and test-data closure.
   - MUST contain a coverage taxonomy table: for each category (`happy`, `boundary`, `error`, `race`, `replay`, `regulatory`, `security`, `contract`, `performance`), list the test file(s) and which spec SCs they verify. N/A entries are permitted with a one-sentence justification.
   - MUST contain a factory inventory: for each entity in the spec's `data-model.md`, list the factory function(s) and the scenarios they cover, per the `test-data-forge` skill discipline.
   - MUST contain a load-test summary if NFR budgets exist for the spec: actual measured numbers (p50/p95/p99 latencies, peak memory, throughput) versus the spec's budgets.
   - MUST cite the green CI run that produced the evidence.

### Commit format

```
audit(NNNN): <slug> — implementation closeout (v<spec-version>)
```

- Exactly one commit per spec closeout.
- Contains the three artifacts above PLUS the intent status change (`Implemented` → `Closed`) PLUS any updated cross-references.
- MUST NOT contain implementation code, test code, or production config. Those landed in the FT-* PRs.
- If a follow-up intent is identified during closeout, it is created as a SEPARATE intent file in `intents/`, not in the closeout commit.

### Discipline rules

- **No spec is "Done" without `audit.md`.** A spec whose `FT-*` PRs are merged but whose `audit.md` is missing is in state `Implemented`, not `Closed`. CI MUST surface this state to operators.
- **An empty audit is a fail.** "All criteria met, no deviations" is acceptable language only if independently verified and explicitly stated; copy-pasted boilerplate is grounds for rejection.
- **Audit findings outrank PR review.** If the audit finds a spec criterion unmet by merged code, the spec moves back to `Implemented` and the gap is closed before re-closeout.
- **Test creation discipline (mirror of Principle V).** `test-evidence.md`'s taxonomy table is the formal record that Principle V was satisfied. A missing category without justification is a constitution violation.
- **Test data generation discipline.** `test-evidence.md`'s factory inventory is the formal record that the `test-data-forge` skill was followed. New entities without factories are a constitution violation.

### Lifecycle status (extended)

| Status | Meaning |
|---|---|
| `Draft` | Intent being written. |
| `Ready` | Intent author considers it complete; feed to `/speckit-specify`. |
| `Specified` | Execution spec exists. Intent is frozen. |
| `Implemented` | All `FT-*` tasks merged; closeout has not yet produced its artifacts. |
| **`Closed`** | Closeout artifacts committed via the `audit(NNNN)` commit. Intent file's status updated. **Terminal state.** |
| `Abandoned` | Decided not to do. Closeout cycle does not apply. |
| `Superseded` | Replaced by a later intent. Closeout cycle does not apply. |

## Governance

- **Authority**: This constitution supersedes any guidance not derived from it. Conflicts resolve in favor of the constitution.
- **Amendment procedure**: Open an intent (`intents/NNNN-amend-constitution-<topic>.md`) with the proposed change, rationale, and impact analysis on dependent templates. The amendment runs through the full spec-driven pipeline like any other change.
- **Versioning** (semver applied to governance):
  - MAJOR — removing or redefining a principle, or changing an architectural invariant.
  - MINOR — adding a principle, adding a section, materially expanding guidance.
  - PATCH — wording, typos, clarifications without semantic change.
- **Compliance review**: every PR description MUST state how the change complies with this constitution. PRs that do not are rejected by the reviewer (human or agent).
- **Source of truth for principles**: this file. `CLAUDE.md` mirrors these principles for agent context but does not override them.

**Version**: 1.1.0 | **Ratified**: 2026-05-26 | **Last Amended**: 2026-05-26
