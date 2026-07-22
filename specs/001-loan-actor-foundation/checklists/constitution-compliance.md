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
- [ ] *(0005)* Reactive-path storage changes (`append_with_dedup/4`) keep duplicate-detection and diary-append indivisible — no implementation may commit one without the other, even under a mid-write crash.

### Principle V — Test-first, taxonomic coverage
- [ ] PR description lists each applicable taxonomy category (happy/boundary/error/race/replay/regulatory/security) mapped to the test files added.
- [ ] No integration test added that mocks an architectural boundary (real BEAM node, real diary store).
- [ ] If a state machine was touched: property-based test updated.
- [ ] If an LLM escalation path is introduced (future intent): three-tests rule applied (deterministic-only, escalation trigger, each LLM failure mode).

### Principle VI — Operating procedures are content
- [ ] If hardcoded logic was added that *could* be skill content, justify in PR description why it isn't.
- [ ] Skill loader test still green.

### Principle VIII — Agent functions are tools and skills *(constitution v1.2.0, intent 0004)*
- [ ] Every new self-initiated actor function is a registered tool (behaviour + spec + schema'd args); none bypass the registry.
- [ ] Every tool invocation produces the diary pair (`:tool_invoked` → `:tool_completed`/`:tool_failed`) and the four ToolCall AG-UI events.
- [ ] Tool args pass PIIGuard BEFORE diary hashing and BEFORE AG-UI emission (synthetic-PII test green).
- [ ] Tools return effects; no tool mutates state directly (`NoDirectStateMutation` green; effects applied via `transition/2`).
- [ ] Zero routing/trigger/selection logic in the registry or tool modules — when-to-use lives in skill packs.
- [ ] New/changed skill packs are valid per `contracts/skill-format.md` and linked to a test proving they fire.

### Principle VII — Portable identity & artifacts
- [ ] New behavior is traceable back to an intent file under `intents/`.
- [ ] If new behavior was not in `tasks.md`, the task is added with a comment explaining why; or the change is rejected.
- [ ] All artifact layers updated as needed (spec/clarifications/plan/data-model/contracts).

## Architectural invariants
- [ ] No second UI framework introduced; UI changes use CopilotKit/AG-UI.
- [ ] No PII written to the diary (regex test green).
- [ ] No code that breaks NFR budgets (load test green).
- [ ] No new dep added without an entry in the relevant intent's Dependencies section.
- [ ] *(0005)* `NFR-001` is measured at the load test's **default** scale, not a reduced `LOAN_LOAD_*` override, before this gate is considered satisfied.

## Anti-vibe
- [ ] No `# TODO: come back to this` left in production code.
- [ ] No mock at an architectural boundary.
- [ ] No "example" code in docs that does not compile / run in CI.
- [ ] PR description uses precise language ("verified by test X") — no "I think this is roughly right".
