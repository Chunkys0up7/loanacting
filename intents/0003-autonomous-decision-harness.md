---
id: "0003"
slug: autonomous-decision-harness
title: Autonomous decision harness — deterministic gates with data assessment and logged escalation
status: Ready
author: cameron
created: 2026-07-21
supersedes: []
depends_on: ["0001", "0004"]
execution_spec: null
---

# Intent 0003 — Autonomous decision harness

## Problem

Foundation (intent 0001) gives the loan a body: a supervised process, a diary, and a
three-loop harness that runs usefully with deterministic logic only. What it deliberately
does **not** give the loan is judgment. The foundation's planning loop can emit a request
when a goal is set, but it cannot *decide* anything: it has no gate evaluation, no notion
of assessing the data it holds against the rules it is subject to, and no escalation path
when deterministic rules are insufficient. Writing LLM-escalation policies was an explicit
foundation non-goal.

Without this layer the loan remains reactive scaffolding. An operator (or a future
orchestrator — exactly what this architecture forbids) would have to make every judgment
call from outside. The architectural promise — "the loan itself notices, assesses, decides,
and only escalates when it must" — is unfulfilled.

## Outcome

The loan actor becomes **autonomous and decision-based**. On every pass of every loop
(reactive, periodic, planning), the actor:

1. **Assesses its data.** A deterministic `assess_loan` **tool** derives a typed
   `%Assessment{}` from current state + diary-derived facts (document completeness,
   goal ages, SLA clocks, data-quality flags). Assessments are pure functions —
   same state in, same assessment out — and every invocation follows the 0004 tool
   discipline (diary `:tool_invoked`/`:tool_completed` + ToolCall AG-UI events).
2. **Evaluates deterministic gates.** An `evaluate_gate` **tool** executes gates whose
   rule *content* lives in **skill packs** (per 0004's skill format: a gate pack is a
   skill whose front-matter/reference files carry the rule expression) — never
   hardcoded branches. Each evaluation produces `:pass | :fail | :indeterminate`
   plus a machine-readable cause.
3. **Decides.** `:pass`/`:fail` outcomes drive state transitions and goal updates
   through the foundation tools (`transition_state`, `satisfy_goal`) — code, not LLM.
   Every decision is a diary entry carrying the gate id, gate pack version, inputs
   digest, and outcome.
4. **Escalates only on `:indeterminate`.** Escalation targets are pluggable **tools**:
   `request_operator_approval` (HITL — exists in foundation/0004) or an LLM-assessment
   tool (new, the first non-deterministic tool, reachable ONLY from this path).
   Every escalation is diary-logged with cause; every LLM failure mode
   (timeout, malformed output, refusal, low-confidence) has a defined deterministic
   fallback, and each is tested.

The result: an operator can watch a loan work through its goals unattended, see every
assessment and decision in the diary with its cause, and be pulled in only at genuine
judgment boundaries.

## Non-goals

- **Not** implementing any specific business rule set (compliance, valuation). Gates ship
  as content; this intent builds the gate *engine* plus a small demonstration rule pack.
- **Not** building a policy-authoring UI. Gate packs are markdown skills in `priv/skills/` (0004 format).
- **Not** multi-loan portfolio coordination. Single-loan autonomy only.
- **Not** production LLM vendor selection/procurement. The escalation port is a behaviour;
  foundation-grade adapter(s) + a recorded-fixture contract test are enough.

## Constraints

- **Deterministic-first is load-bearing.** The LLM path is reachable ONLY via a gate
  returning `:indeterminate`. A grep/Credo check must prove no other call site exists.
- **Determinism of the deterministic path.** Same diary replayed → same assessments,
  same gate outcomes, same decisions. Property-based tests enforce.
- **Every escalation logged with cause** (constitution Principle III). Diary entry types
  extend: `:assessment`, `:gate_evaluated`, `:decision`, `:escalated`, `:escalation_resolved`,
  `:escalation_failed`.
- **Gates are content.** Versioned markdown with front-matter (id, version, trigger,
  inputs, rule expression). The engine loads and evaluates; it never embeds rules.
- **No mocks at boundaries.** LLM adapter tested against recorded fixtures via a contract
  test (per anti-vibe rules), not ad-hoc mocks.
- **Test data discipline.** Every new entity (Assessment, Gate, Decision, Escalation)
  gets a factory with the full scenario-class matrix (test-data-forge), and the coverage
  taxonomy (happy/boundary/error/race/replay/regulatory/security) applies — regulatory is
  IN scope here (gate versioning + audit-trail completeness are regulatory categories).

## Success criteria

- [ ] **Assessment purity**: property test — replaying any diary prefix reproduces the
      identical assessment sequence (modulo timestamps).
- [ ] **Gate evaluation**: a demonstration rule pack (≥3 gates) evaluates against factory
      loans; each outcome (`:pass`/`:fail`/`:indeterminate`) is produced and diary-logged
      with gate id + version + cause in the entry.
- [ ] **Autonomous progress**: a loan spawned with a goal and fed a scripted event stream
      reaches `:completed` with zero operator interaction when all gates pass — verified
      end-to-end against a real BEAM node + real diary store.
- [ ] **Escalation trigger**: exactly the documented `:indeterminate` conditions produce
      escalations; a test asserts the deterministic path result, the trigger condition,
      and the diary `:escalated` entry.
- [ ] **LLM failure modes**: timeout, malformed output, refusal, and low-confidence each
      have a test asserting the defined deterministic fallback and diary logging.
- [ ] **No stray LLM call sites**: static check proves the LLM port is referenced only by
      the escalation module.
- [ ] **Replay**: full time-travel test — decisions and escalations reproduce from diary
      replay for every state-mutating handler added by this intent.
- [ ] **Coverage taxonomy**: every category incl. regulatory has ≥1 test; factories for
      all new entities with documented scenario-class matrix.

## Open questions

- **Q1**: Gate rule expression language — front-matter-declared simple predicate DSL vs.
  compiled Elixir modules referenced by the markdown? *Recommendation: tiny declarative
  predicate DSL (field, op, value, all/any) — keeps gates as pure content; escape hatch
  can come later.*
- **Q2**: Where do diary-derived "facts" come from — computed on every loop pass, or
  incrementally maintained in `State.context`? *Recommendation: incremental with a replay
  invariant test proving equivalence to full recomputation.*
- **Q3**: LLM escalation port shape — one `assess/2` callback, or task-typed callbacks?
  *Open; resolve in /speckit-clarify.*
- **Q4**: Does gate versioning pin per-loan (loan keeps the gate version it started with)
  or always-latest with diary-logged version? *Regulatory implications; resolve in clarify.*

## Dependencies

### Intent dependencies
- **0001** (foundation, as amended by 0004) — must be Implemented (through Closed ideally)
  first: needs Server loops, DiaryStore, State.transition, the tool registry + foundation
  tools, and the skill loader.
- **0004** — supplies the tool/skill discipline this intent builds on (tool behaviour,
  skill pack format, ToolCall streaming, PII-before-emission rule).

### External dependencies (new)
- **Front-matter parsing** — reuse the 0004 skill-loader's restricted front-matter grammar;
  a YAML dep (e.g. `yaml_elixir`) only if /speckit-clarify finds the grammar insufficient.
- **LLM client** — deferred to /speckit-plan; must be wrapped behind the escalation port
  behaviour either way. No direct vendor SDK calls outside the adapter.

### External dependencies (existing)
- Everything foundation already pinned (Elixir/OTP, Mnesia, StreamData, Bandit/Plug).

## Risks

- **Risk**: The predicate DSL grows into an accidental programming language.
  *Mitigation*: hard cap the DSL surface in the spec; anything beyond it is an
  escalation, not a DSL extension. Amendment intent required to extend.
- **Risk**: LLM fixture-based contract tests drift from live model behavior.
  *Mitigation*: fixtures are versioned with the adapter; a scheduled (non-CI-blocking)
  live smoke job re-records and diffs.
- **Risk**: Assessment-on-every-loop-pass blows the p95 event-to-diary budget.
  *Mitigation*: performance budget test extends the foundation load test; incremental
  facts (Q2) is the fallback.

## Notes

Authored from the operator's 2026-07-21 directive: "The Agent must be autonomous and
decision based — using deterministic gates but thinking and assessing data throughout."
This intent is the WHY record for that requirement. It enters /speckit-specify only after
intent 0001 reaches `Implemented`.
