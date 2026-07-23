---
id: "0001"
slug: foundation-loan-as-actor
title: Establish the loan-as-actor runtime foundation — supervised loan processes with diaries, three-loop harness, and AG-UI surface
status: Closed
author: cameron
created: 2026-05-26
specified: 2026-05-26
implemented: 2026-07-23
closed: 2026-07-23
supersedes: []
depends_on: []
execution_spec: "specs/001-loan-actor-foundation/spec.md"
---

# Intent 0001 — Loan-as-actor runtime foundation

## Problem

Today, mortgage platforms — including the agentic ones — treat a loan as a row in a database that gets moved between workstations. Orchestrator agents sit above the row and dispatch work to specialist agents (doc extraction, compliance, underwriting). Every stage transition is a seam: context is lost, state is duplicated, exceptions queue up, and the audit trail is reconstructed retroactively from logs across systems.

The loan, which has a legal identity, a 30-year lifespan, and is bought and sold as an asset, is computationally inert. It cannot ask for things. It cannot notice missing context. It cannot replay its own history. Everything it "does" is something *done to it* by an external workflow.

This foundational intent establishes the inversion: the loan becomes a long-running supervised process with its own identity, diary, and goals. Without this, every downstream intent (compliance, valuation, servicing, secondary-market handoff) cannot escape the assembly-line model.

## Outcome

A single loan can be **spawned** as an OTP-supervised actor on the BEAM runtime. From the moment it is spawned until it is sold, paid off, or written down, it is alive: it accepts events, runs its own three-loop harness, appends to its own immutable diary, and exposes its state through AG-UI to a CopilotKit frontend.

A user — operator, borrower, or regulator (with appropriate auth) — can open the CopilotKit interface for any loan and see:
- The loan's current state and pending goals.
- A live diary feed of recent events and decisions.
- The capability to send the loan an event (e.g., "income document uploaded") and watch the actor respond.
- HITL gates surface as approval prompts in the UI when the loan escalates.

A loan that crashes is restarted by its supervisor and rehydrates its state from its diary. No state is lost. No event is processed twice (idempotency by diary key).

## Non-goals

- **Not** implementing compliance rules, valuation models, document extraction, or any business-domain capability. Those are subsequent intents.
- **Not** implementing the secondary-market sale flow. That's a later intent; foundation must make it *possible*, not done.
- **Not** building a UI for loan portfolios / fleets of loans. Single-loan UI is enough for the foundation.
- **Not** persisting to a production-grade database. A local diary store (file-backed or Mnesia) is sufficient for foundation; production storage is a separate intent.
- **Not** integrating with MISMO yet. The portable-identity story comes after foundation.
- **Not** writing the LLM-escalation policies. The harness must *support* escalation; the policies are content authored later.

## Constraints

- **Loan-is-the-actor**: every capability is summoned by the loan; no external orchestrator dispatches work to it.
- **Deterministic-first**: the foundation contains zero LLM calls. The three-loop harness must run usefully with deterministic logic only.
- **Immutable diary**: every event the loan accepts, every state transition it makes, every output it emits — appended, append-only, never mutated. Diary entry = (event_id, timestamp, actor_id, type, payload_hash, prev_hash).
- **Three-loop harness**:
  - **Reactive loop**: handles incoming events (mailbox).
  - **Periodic loop**: heartbeat reflection (default: every N minutes); inspects state, may set goals.
  - **Planning loop**: state-driven; when goals are set, may emit outbound events / requests.
- **OTP supervision**: loan processes are supervised. A crash → restart from diary, no data loss.
- **Portable identity**: each loan has a stable `loan_id` (UUIDv7 acceptable for foundation; MISMO ID overlay later).
- **AG-UI surface**: state and diary deltas reach the UI as AG-UI events (StateSnapshot, StateDelta, TextMessage, CustomEvent). No bespoke websocket protocol.

## Success criteria

- [ ] **Spawn**: `LoanActor.spawn(loan_id)` returns a supervised pid; the loan's diary contains a `RunStarted`-equivalent first entry.
- [ ] **Event acceptance**: sending the loan a typed event (`%Event{type: :document_uploaded, payload: ...}`) results in a diary append within 100ms p95.
- [ ] **Reactive determinism**: a defined sequence of N events, replayed against a fresh loan, produces an identical final state and identical diary (modulo timestamps). Property-based test asserts this.
- [ ] **Heartbeat**: the periodic loop fires at the configured interval; each firing produces a diary entry of type `:heartbeat` with current state hash.
- [ ] **Planning**: when a goal is set (e.g., `:awaiting_document(:income)`), the planning loop emits a corresponding outbound event (e.g., a CopilotKit-surfaced request). Diary records the emission.
- [ ] **Crash recovery**: killing the loan process unexpectedly results in its supervisor restarting it within 1s; the rehydrated state matches pre-crash state exactly (diary replay test).
- [ ] **Idempotency**: re-delivering an event with the same `event_id` is a no-op; the diary does not double-append.
- [ ] **AG-UI events**: spawning the loan, sending an event, and observing state change produces `RunStarted` → `StateSnapshot` → `StateDelta` events at the AG-UI endpoint. A TypeScript consumer test verifies the sequence.
- [ ] **CopilotKit UI**: the React app at `/loans/:id` renders the loan's state and diary live, updated via `useCoAgent` + `useCoAgentStateRender`. Manual + Playwright test.
- [ ] **HITL stub**: a synthetic "approval required" event surfaces in the UI via `useLangGraphInterrupt`-equivalent (or `useHumanInTheLoop`). `respond({approved: true})` resumes the loan and is logged.
- [ ] **Test coverage taxonomy** (per `test-guardian`): happy / boundary / error / race / replay / regulatory(N-A here) / security categories each have at least one test. PR description maps each category to the test files.
- [ ] **No mocks at boundaries**: integration tests run against a real BEAM node and a real diary store (file or Mnesia). Mock-free at the seams.
- [ ] **Performance budget**: 100 concurrent loan actors, 10 events/sec each, p95 event-to-diary latency < 100ms, RAM < 256MB, asserted in a load test.

## Open questions

- **Q1**: BEAM language choice — Elixir or pure Erlang? *Recommendation: Elixir for ergonomics and Phoenix/LiveView interop with the JS UI, but worth confirming.*
- **Q2**: Diary backing store for foundation — flat append-only files, Mnesia, or DETS? *Recommendation: Mnesia, with a clear interface so we can swap later.*
- **Q3**: AG-UI endpoint host — does the BEAM node serve AG-UI SSE directly (via Plug/Phoenix), or do we put a thin Node CopilotRuntime in front? *Recommendation: serve directly from BEAM to avoid an extra hop; CopilotRuntime is optional.*
- **Q4**: How is the loan's state shape defined? Plain map, or a typed struct + behavior contract? *Recommendation: typed Elixir struct with a `Loan.State` module enforcing transitions.*
- **Q5**: Are reactive/periodic/planning loops three separate GenServer processes under one supervisor, or three responsibilities of a single GenServer? *Recommendation: single GenServer with three explicit `handle_*` clauses + a periodic message — simpler, fewer boundaries; revisit if it grows.*
- **Q6**: Idempotency key — `event_id` only, or `(event_id, source)`? *Open.*
- **Q7**: How do operators authenticate to a loan's UI? Is auth part of foundation or a later intent? *Recommendation: stub auth in foundation (env-injected operator ID); real auth is a separate intent.*

## Dependencies

### Intent dependencies
- None (this is the root intent).

### External dependencies (new)
- **Elixir / Erlang/OTP** — runtime. Required for the actor model. No substitute.
- **Mnesia** (bundled with OTP) — diary store. No new package; ships with Erlang.
- **Plug / Bandit** (or Phoenix) — HTTP layer for the AG-UI endpoint. Bandit alone if we avoid Phoenix.
- **PropEr** or **StreamData** — property-based testing for the state machine.
- **`@copilotkit/react-core`** + **`@copilotkit/react-ui`** — frontend. Already mandated by CLAUDE.md.
- **Vite + React + TypeScript** (or Next.js) — frontend bundler/framework. Decide in `/speckit.plan`.

### External dependencies (existing)
- None — this is a greenfield repo.

## Risks

- **Risk**: BEAM is an unusual choice for the team / hiring market. *Mitigation*: foundation intent makes the language commitment irreversible only if we ship it; a working prototype validates the bet before scaling investment. Kill-criterion: if foundation cannot meet the performance budget (100 actors, 10 ev/s, <100ms p95) we revisit.
- **Risk**: AG-UI from Elixir has no first-party SDK as of 2026-05; we'd implement the SSE producer ourselves. *Mitigation*: the protocol is 17 events with a documented wire format; implementing the producer is a bounded task. The `copilotkit` skill has a Python reference implementation we can port.
- **Risk**: Diary append-only design conflicts with GDPR/right-to-erasure for borrower PII. *Mitigation*: diary stores hashes + pointers to mutable PII vault; erasure is a vault-side operation. Vault is a separate intent — foundation must keep PII out of the diary by design.
- **Risk**: Single GenServer for the three-loop harness becomes a bottleneck under load. *Mitigation*: success-criterion load test will catch this; falling back to multi-process is a refactor, not a rewrite.

## Notes

This is the root of the intent tree. Every subsequent intent assumes the foundation as given.

The `loan-as-actor.html` document at the repo root is the long-form rationale and should be the canvas for resolving Q1–Q7 — it already lays out BEAM, Mnesia, and the OTP supervision story in narrative form. `/speckit.clarify` should consume it.

## Retrospective

Closed 2026-07-23 per the post-implementation audit cycle (constitution §"Post-Implementation
Audit Cycle", added by intent 0002). Full detail in `specs/001-loan-actor-foundation/{audit,
report,test-evidence}.md`; summary here.

**What held up.** The core architectural bet — a loan as a single supervised GenServer with
three explicit, linter-enforced loops, diary-replay for crash recovery, and a hard `transition/2`
gate on state mutation — proved out completely. Every one of Q1–Q7's recommendations was adopted
as stated and none needed revisiting. The tool/skill layer added mid-build (intent 0004) slotted
in cleanly without touching any already-merged code, confirming the diary's `Entry.validate_type/1`
design (any atom, no fixed enum baked into merged modules) was the right call.

**What didn't hold up.** The reactive pipeline's throughput budget (NFR-001, this intent's own
success-criteria list) is not met at full production scale, and the one fix attempted for it
(intent 0005) was implemented, tested clean, and then proven by its own load test to be a
regression rather than an improvement — reverted. This is closed anyway, with the gap reported
honestly rather than papered over, per this project's own established norm (the same load test's
FT-035 commit set that precedent first). A second, deeper gap — a loan's open goals have no
recoverable trace in the diary at all, since tool diary entries are hash-only by design — was
found auditing this very closeout, not during original development; it does not block closing
(the crash-safety and status-recovery guarantees this intent's success criteria actually asked
for all hold), but it is a real, documented limit on how far "replay reproduces identical state"
can honestly be claimed today.

**What the audit itself found.** This repository's CI had never successfully scheduled a single
job, on any push, since the workflow file was first added — a configuration bug entirely
unrelated to the code it was supposed to be testing, caught only because this closeout insisted
on citing a real green run rather than assuming one existed. Fixing it immediately surfaced three
more real bugs (a test whose timeout only worked by chance at local scale, a test whose equality
check only passed by timing luck on a fast local machine, and three intentional test fixtures
dialyzer had never actually been run against locally) — a small, self-contained demonstration of
why "tests pass on my machine" and "CI is green" are different claims, and why this project's own
insistence on citing evidence rather than asserting completion is worth the friction it adds.

**For whoever picks up the follow-ups**: NFR-001 needs a genuinely different approach (batching
or Mnesia tuning, tried independently — not combined with more transaction-collapsing), the
goal-content-replay gap needs its own amendment deciding whether goal text is sensitive enough to
need hash-only treatment, and both are real engineering work, not loose ends left by neglect.
