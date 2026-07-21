# CLAUDE.md — Loan-as-Actor

This file is the standing contract for every Claude session in this repo. Read it first. Follow it without exception unless the user explicitly overrides a rule for a specific turn.

---

## 1. What this project is

**Loan-as-Actor** inverts mortgage tech: instead of a passive loan record moved between stations by orchestrator-agents, the **loan itself is the live actor** — a long-running process with its own diary, goals, supervisors, and 30-year lifespan. Runtime target: **BEAM (Erlang/Elixir)** with OTP supervision trees. UI layer: **CopilotKit** over **AG-UI**.

The full architectural rationale lives in [`loan-as-actor.html`](loan-as-actor.html). Read it before touching architecture-level work.

Key invariants of the architecture (treat as load-bearing — do not weaken without an intent spec):

- **The loan is the actor.** Capabilities (compliance, valuation, doc-extract, etc.) are summoned *by* the loan, not orchestrated *over* it.
- **Three-loop harness per actor**: reactive (events) · periodic (heartbeat reflection) · planning (state-driven goals).
- **Deterministic-first, LLM-escalated.** Rules and calculations run as code. LLM calls are escalations, never the default. Every escalation is logged with cause.
- **Immutable diary.** Every decision, input, escalation, and state transition is appended to the loan's diary. Diary is the audit trail and the basis for time-travel debugging.
- **Operating procedures are content.** Compliance rules, escalation playbooks, and triggers live as versioned markdown the agent reads — not as hardcoded branches.
- **Agent functions are tools and skills** *(constitution v1.2.0, intent 0004)*. Every self-initiated actor function is a typed, registered **tool** (JSON-schema'd args, diary-logged, streamed as AG-UI ToolCall events); when-to-use knowledge lives in **skill packs** (`priv/skills/<id>/SKILL.md` + references, trigger in front-matter). Which tools exist = code; when to use them = content. See §4a.
- **Portable identity.** The loan carries its own MISMO + chain-anchor identity across origination → servicing → secondary market.

---

## 2. Spec-driven development — non-negotiable

Every new requirement follows this pipeline. **No code without specs. No specs without intent.**

```
  user request
       │
       ▼
  intents/NNNN-<slug>.md          ← INTENT SPEC (the WHY + WHAT, human-authored)
       │
       │  /speckit-specify  (consumes the intent)
       ▼
  specs/<feature>/spec.md         ← EXECUTION SPEC (formal, machine-readable)
       │
       │  /speckit-clarify → /speckit-plan → /speckit-analyze → /speckit-tasks
       ▼
  specs/<feature>/{plan,tasks,data-model,api-spec,quickstart,research}.md
       │
       │  /speckit-checklist  (testing + quality gates BEFORE code)
       ▼
  specs/<feature>/checklists/*.md
       │
       │  /speckit-implement
       ▼
  code + tests (tests written FIRST or alongside, never after)
```

### Rules

- **Every new requirement → new intent spec.** Numbered sequentially (`intents/0001-foundation.md`, `0002-...`). Use the template at [`intents/TEMPLATE.md`](intents/TEMPLATE.md).
- **No skipping `/speckit-tasks`.** Even for small changes — the dependency order is what keeps `/speckit-implement` safe.
- **No skipping `/speckit-checklist`.** Quality gates are written **before** implementation, not after.
- **All four artifact layers are committed** (intent, execution spec, plan, tasks). Intent specs are the source of truth for the WHY; spec-kit artifacts are the source of truth for the HOW.
- **Constitution lives at `.specify/memory/constitution.md`** once `specify init` has run. The constitution mirrors the rules in this CLAUDE.md but in spec-kit's own format.

The `speckit` skill (installed at `.claude/skills/speckit/`) is the playbook for running this pipeline. Invoke it whenever you touch any `/speckit-*` step.

---

## 3. Testing discipline — non-negotiable

This project does not ship vibe-coded results. Tests are part of the deliverable, not an afterthought.

### Hard rules

- **Tests written first or in the same commit.** Never "I'll add tests later". A PR with implementation but no tests is incomplete.
- **No mocks at architectural boundaries.** Integration tests hit a real BEAM node, a real database, a real diary store. Unit-level mocking is fine inside a module; never mock the seams where bugs actually live.
- **Real test data, generated through factories.** Use the patterns in the `test-data-forge` skill. No hand-rolled fixtures of dubious provenance. Every factory has a discovery checklist note explaining what scenarios it covers.
- **Every escalation path is tested.** If the loan can call an LLM, there is a test that asserts what the deterministic path produces, a test that asserts what triggers the escalation, and a test that asserts what happens when the LLM returns each documented failure mode.
- **Coverage is taxonomic, not numeric.** Use the `test-guardian` coverage taxonomy — happy path, boundary, error, race, replay, regulatory, security. A 95%-line-coverage PR that skips the race or replay categories is a fail.
- **Property-based tests for state machines.** The loan actor is a state machine. Use property-based testing (PropEr / StreamData) to fuzz transitions.
- **Time-travel tests.** Because the diary is immutable, every state must be reproducible by replaying the diary. There is a test that proves this for every state-mutating handler.
- **Performance budgets are tests.** P95 latency, memory ceiling, mailbox depth — encode them as assertions, not aspirations.

### Triggered skills

When testing-related work happens, the harness will auto-invoke:
- **`test-guardian`** — for test strategy, taxonomy, antipatterns, Python/Erlang/Elixir test patterns
- **`test-data-forge`** — for factories, isolation, coverage gaps, enhancing existing suites

Do not write tests without consulting both.

---

## 4. UI layer

CopilotKit + AG-UI is the only sanctioned UI path. **Do not introduce a second chat/agent UI framework.**

- The agent-side talks **AG-UI** (17 canonical events — see the `copilotkit` skill).
- The frontend uses CopilotKit's React components (`CopilotChat`, `CopilotSidebar`, etc.) and hooks (`useCopilotAction`, `useCoAgent`, `useLangGraphInterrupt`).
- **Loan diary surfacing**: the user-facing view of a loan's diary is a CopilotKit generative-UI surface — the loan actor emits AG-UI events (text + state + custom), and the React app renders them via `useCoAgentStateRender`.
- **Operator HITL**: every operator-approval gate uses `useHumanInTheLoop` or `useLangGraphInterrupt`. Approvals are diary events.

The `copilotkit` skill (installed at `.claude/skills/copilotkit/`) is the canonical reference. Invoke it for any UI work.

---

## 4a. Agent functions: tools + skills (constitution Principle VIII)

Added by intent 0004. Binding rules when touching anything the loan actor *does on its own initiative* (periodic/planning loops, HITL emission):

- **Every self-initiated function is a tool** — a module implementing `LoanActor.Tool` (`spec/0` + `execute/2`), listed in the config-driven registry. No bypassing the registry. Inbound event ingestion (reactive pipeline) is NOT a tool call.
- **Tools return effects; the Server applies them** through `State.transition/2`. A tool that mutates state directly is a constitution violation (`NoDirectStateMutation`).
- **Every invocation is glass-box**: diary pair (`:tool_invoked` → `:tool_completed`/`:tool_failed`) + AG-UI `ToolCallStart/Args/End/Result` (HITL's Result is deferred until the operator responds).
- **PII order of operations**: tool args pass `PIIGuard` BEFORE diary hashing and BEFORE any UI emission. Cleartext PII never reaches the stream.
- **Skills are content packs**: `priv/skills/<NNNN-slug>/SKILL.md` (front-matter: `name`, `version`, `description` = trigger, `tools_required`) + optional `references/`. Loader validates `tools_required` against the registry at load time. Every pack links to a test proving it fires.
- **No routing logic in code**: the registry and tool modules contain zero trigger/selection logic — that's skill content (Principle VI).
- **Hard caps**: args schemas use only `type`/`properties`/`required`/`enum`; front-matter is `key: value` + `[a, b]` lists only. Extending either requires an amendment intent.
- Contracts: [`tool-behaviour.md`](specs/001-loan-actor-foundation/contracts/tool-behaviour.md) · [`skill-format.md`](specs/001-loan-actor-foundation/contracts/skill-format.md) · [`ag-ui-events.md`](specs/001-loan-actor-foundation/contracts/ag-ui-events.md) (tool-call semantics).

---

## 5. Anti-vibe rules

Things that look productive but degrade the codebase. **Refuse them.**

- ❌ "Let's just stub this out and come back to it." → No. Either spec it as an intent, or don't write it.
- ❌ "I'll add a quick mock for the LLM call." → No. Determine the deterministic path or write a contract test against a recorded fixture.
- ❌ "We can skip the intent spec for this small change." → No. Small changes still have a WHY. Write a one-paragraph intent. The discipline is the point.
- ❌ Inventing data structures mid-implementation. → If `tasks.md` didn't specify it, stop and revise the spec.
- ❌ Generating "example" code in CLAUDE.md or docs that doesn't compile against the current codebase. → If you write an example, it lives in a test file and runs in CI.
- ❌ Adding dependencies without an entry in the relevant intent spec's "dependencies" section. → No silent dep additions.
- ❌ "I think this is roughly right." → No. State precisely what's verified and what isn't. Uncertainty is fine; vagueness is not.

---

## 6. Repeatable processes (skills)

Four skills are installed at `.claude/skills/`. Each is auto-triggered by the descriptions in its frontmatter. **Use them — don't reinvent.**

| Skill | When it fires |
|---|---|
| **`speckit`** | Any `/speckit-*` command, spec/plan/task work, constitution edits |
| **`copilotkit`** | CopilotKit, AG-UI, React UI for the loan/agent, HITL, generative UI |
| **`test-guardian`** | Testing strategy, coverage planning, Python/Erlang/Elixir test patterns, antipatterns |
| **`test-data-forge`** | Factories, fixtures, isolation, test-data coverage taxonomy |

If you find yourself doing work that *would* match a skill but the skill isn't firing, **invoke it explicitly** rather than rolling your own.

---

## 6b. Post-implementation audit cycle — every spec gets a closeout

After every `FT-*` task PR for a spec has merged, the spec runs through a **closeout phase** before its intent can move to `Closed`. Three artifacts, one commit. (Full normative wording: constitution v1.1.0 "Post-Implementation Audit Cycle".)

```
spec(NNNN) commit                          ← spec authored (§6a)
   │
   ▼
FT-001 PR, FT-002 PR, … (many)             ← implementation (each tests + code)
   │
   ▼
audit(NNNN) commit                         ← closeout (§6b — THIS section)
  ├── specs/NNN-slug/audit.md              independent verification of spec ↔ code
  ├── specs/NNN-slug/report.md             operator-facing implementation report
  └── specs/NNN-slug/test-evidence.md      taxonomy + factory + load-test record
```

### What goes in each artifact

- **`audit.md`** — SHOULD have a different author than the implementer (solo work permitted, self-attest). MUST map every FR/NFR/SC to the test or code that proves it. MUST list deviations (empty list OK; missing section NOT OK). MUST list new/changed procedure documents.
- **`report.md`** — Plain business-language summary; PR/SHA links by track; follow-up list (becomes future intents); UI screenshots where relevant.
- **`test-evidence.md`** — Coverage taxonomy table (happy / boundary / error / race / replay / regulatory / security / contract / performance) mapped to SCs; factory inventory per entity (`test-data-forge` discipline); load-test actuals vs. NFR budgets; green CI run cited.

### Commit format

```
audit(NNNN): <slug> — implementation closeout (v<spec-version>)
```

One commit, three artifacts plus the intent status change `Implemented` → `Closed`. **No code in this commit.** Follow-up intents go in their own files in `intents/`.

### Discipline triggers

- The `test-guardian` skill MUST be invoked when authoring `test-evidence.md`.
- The `test-data-forge` skill MUST be invoked for the factory inventory.
- "All criteria met, no deviations" is acceptable ONLY when verified and explicitly stated — boilerplate is a fail.
- Audit findings outrank PR review. If `audit.md` finds a gap, intent moves back to `Implemented`, gap is closed, closeout is re-attempted.

### Lifecycle (extended)

`Draft` → `Ready` → `Specified` → `Implemented` → **`Closed`** (terminal).

---

## 6a. Commit cadence — one spec, one check-in

**Rule.** Every completed spec is one git commit. Not less (no committing mid-spec), not more (no splitting an intent's specs across commits).

- A "completed spec" means: the intent moved from `Draft` → `Specified`, AND all the spec-kit artifacts for that intent are in place — `spec.md`, `clarifications.md` (if `/speckit-clarify` ran), `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `contracts/`, `analysis.md`, `tasks.md`, `checklists/`.
- Implementation tasks (`FT-001` … the per-task PRs that `/speckit-implement` produces) have **their own** cadence — one task per PR, tests in the same commit. That cadence is independent of the per-spec cadence.
- The commit message MUST reference the intent id and the spec slug:
  - `spec(0001): loan-actor-foundation — initial constitution + spec + plan + tasks + checklists`
- The spec commit MUST NOT include implementation code. Specs and code never share a commit; that's how we keep the artifact trail clean.
- An amendment to an already-Specified intent produces an amendment intent (`intents/NNNN-amend-…`) which goes through its own spec → commit cycle.

**Work log.** A running narrative log of session work, decisions made, and artifacts produced lives under [`work-log/`](work-log/). It is **gitignored** — it's a private notebook for the operator and for future Claude sessions, not part of the public artifact trail. Treat it as a journal: append new entries at the top with a date stamp; never edit prior entries.

---

## 7. Artifact discipline

Every change leaves a paper trail:

```
intents/NNNN-<slug>.md              ← the WHY (you write this)
specs/<feature>/spec.md             ← the WHAT (speckit writes this)
specs/<feature>/plan.md             ← the HOW (speckit writes this)
specs/<feature>/tasks.md            ← the STEPS (speckit writes this)
specs/<feature>/checklists/*.md     ← the QUALITY GATES (speckit writes this)
src/...                             ← the CODE (only after the above)
test/...                            ← the TESTS (alongside code, never after)
```

All of these are **committed**. Diary entries from the runtime are also artifacts but live in their own immutable store, not in git.

---

## 8. First-session bootstrap

If this is the first Claude session in this repo, do this in order:

1. Read [`SETUP.md`](SETUP.md) — installs `uv`, `specify-cli`, runs `specify init . --here --integration claude`.
2. Read [`intents/0001-foundation-loan-as-actor.md`](intents/0001-foundation-loan-as-actor.md) — the foundational intent.
3. Run `/speckit-constitution` and use this CLAUDE.md as input — produces `.specify/memory/constitution.md`.
4. Run `/speckit-specify` against the 0001 intent — produces the first execution spec.
5. Continue the pipeline from there.

Do not write any code until steps 1-4 are done.

---

## 9. URLs

- Project rationale: [`loan-as-actor.html`](loan-as-actor.html)
- Spec-kit: <https://github.com/github/spec-kit>
- CopilotKit: <https://docs.copilotkit.ai/>
- AG-UI: <https://docs.ag-ui.com/>
- Erlang/OTP: <https://www.erlang.org/docs>
- Elixir: <https://elixir-lang.org/docs.html>

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->
