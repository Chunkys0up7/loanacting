# Checklist — Constitution Compliance

Every PR closing a task in [`tasks.md`](../tasks.md) MUST pass this checklist. PR description copies this checklist and ticks each item.

## Per-PR gates

### Principle I — Loan-is-the-actor
- [ ] No new module dispatches to multiple loans from a central position (no orchestrator pattern).
- [ ] All state-mutating code paths go through `LoanActor.Server` of a specific loan.

### Principle II — Three-loop harness
- [ ] Every `handle_*` clause in `LoanActor.Server` carries a `# loop: reactive|periodic|planning` tag.
- [ ] No new long-running process/timer added outside the periodic loop.
- [ ] Credo `LoopTagging` check is green.

### Principle III — Deterministic-first
- [ ] No dependency on OpenAI / Anthropic / Bumblebee / equivalent LLM library introduced.
- [ ] `mix test test/llm_absence_test.exs` green.
- [ ] Credo `NoLLM` check green.

### Principle IV — Immutable diary
- [ ] Every state mutation writes a diary entry in the same transaction.
- [ ] No mutation or deletion of existing diary entries (verified by `verify_chain/1` running in CI).
- [ ] PII never enters the diary (`PIIGuard` invoked; tested).
- [ ] Replay test exists for any new state-mutating handler.

### Principle V — Test-first, taxonomic coverage
- [ ] PR description lists each applicable taxonomy category (happy/boundary/error/race/replay/regulatory/security) mapped to the test files added.
- [ ] No integration test added that mocks an architectural boundary (real BEAM node, real diary store).
- [ ] If a state machine was touched: property-based test updated.
- [ ] If an LLM escalation path is introduced (future intent): three-tests rule applied (deterministic-only, escalation trigger, each LLM failure mode).

### Principle VI — Operating procedures are content
- [ ] If hardcoded logic was added that *could* be a procedure, justify in PR description why it isn't.
- [ ] Procedure loader test still green.

### Principle VII — Portable identity & artifacts
- [ ] New behavior is traceable back to an intent file under `intents/`.
- [ ] If new behavior was not in `tasks.md`, the task is added with a comment explaining why; or the change is rejected.
- [ ] All artifact layers updated as needed (spec/clarifications/plan/data-model/contracts).

## Architectural invariants
- [ ] No second UI framework introduced; UI changes use CopilotKit/AG-UI.
- [ ] No PII written to the diary (regex test green).
- [ ] No code that breaks NFR budgets (load test green).
- [ ] No new dep added without an entry in the relevant intent's Dependencies section.

## Anti-vibe
- [ ] No `# TODO: come back to this` left in production code.
- [ ] No mock at an architectural boundary.
- [ ] No "example" code in docs that does not compile / run in CI.
- [ ] PR description uses precise language ("verified by test X") — no "I think this is roughly right".
