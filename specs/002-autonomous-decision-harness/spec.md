# Feature Specification: Autonomous Decision Harness

**Feature Branch**: `002-autonomous-decision-harness`

**Created**: 2026-07-23

**Status**: Draft

**Input**: Intent [`intents/0003-autonomous-decision-harness.md`](../../intents/0003-autonomous-decision-harness.md)

**Constitution**: [`v1.2.0`](../../.specify/memory/constitution.md)

**Depends on**: spec 001 (`001-loan-actor-foundation`, Closed) — this feature builds directly on
the loan actor's three-loop harness, diary, `State.transition/2`, tool registry, and skill
loader. No foundation behavior is renegotiated here.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — A loan works through its goals unattended (Priority: P1)

An operator sets a goal on a loan (e.g., "obtain income documentation") and then does nothing
else. Instead of waiting for the operator to manually push it through each step, the loan itself
repeatedly checks whether it has what it needs, applies the applicable rules, and advances its
own status when the rules are satisfied — with no human touching it again until either it
completes or it hits a question only a human can answer.

**Why this priority**: This is the entire point of the feature. Without unattended progress
through deterministic rules, the loan is still just reactive scaffolding waiting on an external
operator for every step — exactly what intent 0001 built the actor model to avoid becoming.

**Independent Test**: Spawn a loan, set a goal, and feed it a scripted sequence of the documents/
events its own rules require. Verify it reaches `:completed` with zero operator interaction when
every rule is satisfiable from what it was given, and that its diary shows the full trail of
assessments, rule evaluations, and decisions that got it there.

**Acceptance Scenarios**:

1. **Given** a freshly-spawned loan with a goal set, **When** the loan's periodic/planning loops
   run and every applicable rule is currently satisfiable from the loan's own state, **Then** the
   loan advances its status without any operator action, and the diary contains one assessment
   entry and one rule-evaluation entry (with the rule's identity, version, and outcome) for each
   pass.
2. **Given** a loan that has advanced through several rule evaluations, **When** an operator
   inspects its diary, **Then** every assessment and rule outcome is visible with the cause that
   produced it — the operator can reconstruct exactly why the loan is where it is, without
   guessing.

---

### User Story 2 — The loan asks for help only when a rule can't decide (Priority: P1)

A loan's rules sometimes can't produce a clean pass/fail answer from the data on hand — the
information is ambiguous, missing in a way the rule didn't anticipate, or otherwise outside what
a deterministic check can resolve. In that specific situation, and only that situation, the loan
raises the question to a human (or, for a defined class of ambiguity, to an automated assessment
step) instead of silently guessing or getting stuck.

**Why this priority**: This is the other half of "autonomous" — a loan that escalates
everything isn't autonomous, and a loan that never escalates anything is unsafe. The boundary
between the two is the entire value of this feature; it has to be precise and provable, not
approximate.

**Independent Test**: Construct a scenario where a rule's evaluation is genuinely indeterminate
(not merely failing). Verify the loan escalates exactly then — not on a pass, not on a clean
fail — and that the escalation is fully diary-logged with the condition that triggered it.

**Acceptance Scenarios**:

1. **Given** a loan whose current data makes a rule's outcome indeterminate, **When** the rule
   is evaluated, **Then** the loan raises exactly one escalation (not a silent failure, not a
   guessed pass/fail), and the diary records the indeterminate condition, the rule identity, and
   the escalation target.
2. **Given** an escalation has been raised and the escalation target (human or automated) returns
   an answer, **When** the loan receives that answer, **Then** the loan resumes and its next
   decision reflects the answer received, all diary-logged.
3. **Given** an automated escalation step fails in a defined way (times out, returns something
   unusable, explicitly declines, or returns a low-confidence result), **When** that failure
   occurs, **Then** the loan falls back to a defined, deterministic outcome for that failure mode
   — it never hangs and never silently invents an answer.

---

### User Story 3 — Rules are content an operator can read, not code a developer must ship (Priority: P2)

The specific rules a loan applies (what counts as complete documentation, when an SLA clock has
expired, what data quality issues block progress) are authored as readable rule packs, the same
way the foundation's operating knowledge is authored as skill packs — not hardcoded into the
loan's own program logic. An operator (or a rules author who isn't a programmer) can read a rule
pack and understand exactly what it checks and why.

**Why this priority**: This is what makes the rule *engine* reusable across every future business
rule set (compliance, valuation, underwriting) without rebuilding the harness each time. It's
lower priority than Stories 1-2 because a working, if temporarily hardcoded, first rule pack still
proves the other two stories independently — but the engine isn't done until rules are genuinely
content.

**Independent Test**: Author a new rule pack without touching any harness code, and confirm it
loads, evaluates, and its outcome shows up in the diary exactly like the demonstration rule pack
does — proving rules are additive content, not code changes.

**Acceptance Scenarios**:

1. **Given** a new rule pack added to the rules directory with no code changes, **When** the
   loan's next loop pass runs, **Then** the new rule is evaluated according to its own declared
   trigger, with no harness code modified or redeployed.
2. **Given** a rule pack that is malformed or references something the system doesn't recognize,
   **When** it is loaded, **Then** it is rejected with a specific, logged reason and never
   silently evaluated as if it were valid.

---

### Edge Cases

- **A rule's inputs change between two evaluations of the same loop pass.** The assessment and
  the rule evaluation it feeds must be computed from a single consistent snapshot of the loan's
  state — a rule never evaluates against a mix of before/after data from the same pass.
- **Two different rule packs both trigger on the same loop pass.** Each evaluates and is
  diary-logged independently; one rule's outcome never suppresses or overwrites another's entry.
- **An escalation is raised, but the loan crashes before it's answered.** On restart, the loan's
  diary replay reproduces the same pending escalation state — the question is not lost, and it is
  not silently re-asked as a duplicate.
- **The automated (LLM) escalation path is unreachable or misconfigured.** Every one of its
  defined failure modes (timeout, malformed output, refusal, low-confidence) has a deterministic
  fallback; there is no "escalation raised and then nothing happens" state.
- **A rule pack is updated (new version) while loans are already mid-flight under the old
  version.** Per FR-011, a loan keeps evaluating a gate it has already started under the version
  active at that time — it does not silently pick up a newer version mid-flight. The audit trail
  must still be able to say, for any past decision, exactly which rule version produced it.
- **A rule references a fact the loan's current data genuinely cannot supply** (not missing by
  oversight, but structurally absent). This is exactly the `:indeterminate` case Story 2 covers,
  not a special additional case — named here to make sure it's covered by that story's tests,
  not treated as a rule-authoring bug.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a deterministic assessment step that derives a structured,
  typed summary of a loan's current situation (document completeness, goal ages, SLA/timing
  state, data-quality flags) from the loan's own state and diary-derived facts — nothing else.
  The same state MUST always produce the same assessment.
- **FR-002**: The system MUST provide a rule-evaluation step whose rule *content* is authored as
  versioned, readable rule packs (mirroring the foundation's skill-pack mechanism) — never as
  hardcoded branches in program logic. Each evaluation MUST produce exactly one of `pass`,
  `fail`, or `indeterminate`, plus a specific, machine-readable cause.
- **FR-003**: A `pass` or `fail` outcome MUST drive the loan's own state/goal changes through the
  foundation's existing mechanisms (never a new, parallel mutation path). Every decision MUST be
  diary-logged with the rule's identity, the rule pack's version, a digest of the inputs it used,
  and the outcome.
- **FR-004**: An `indeterminate` outcome, and only an `indeterminate` outcome, MUST raise an
  escalation. Escalation targets MUST be interchangeable (a human operator, or a defined
  automated assessment step) without changing the rule-evaluation step itself.
- **FR-005**: Every escalation MUST be diary-logged with the condition that triggered it, and its
  eventual resolution (answer received, or a defined failure-mode fallback applied) MUST also be
  diary-logged.
- **FR-006**: Every defined automated-escalation failure mode (timeout, malformed output,
  explicit refusal, low-confidence result) MUST have one specific, deterministic fallback
  outcome — never an unhandled/hanging state.
- **FR-007**: The automated escalation path MUST be reachable from exactly one place: the
  `indeterminate` outcome of rule evaluation. No other part of the system may invoke it.
- **FR-008**: Replaying a loan's diary MUST reproduce the identical sequence of assessments, rule
  outcomes, decisions, and escalations that originally occurred (independent of wall-clock
  timestamps) — this feature's additions are subject to the same replay guarantee as every
  foundation state-mutating handler.
- **FR-009**: A rule pack that is malformed, or that references something the system does not
  recognize, MUST be rejected at load time with a specific, logged reason — never silently
  evaluated as if valid, and never causing the loan to crash.
- **FR-010**: Adding a new rule pack, or changing an existing one, MUST NOT require changing any
  harness code — rules are content, loaded the same way the foundation's skill packs are.
- **FR-011**: A loan MUST pin the rule-pack version active when it first evaluates a given gate,
  for that gate's lifetime on that loan — later gate-pack updates MUST NOT change how an
  already-in-flight loan evaluates a gate it has already started evaluating under an earlier
  version. Every decision MUST record the exact gate-pack version it used, regardless. *(Resolved
  2026-07-23 — pin-per-loan: stable, auditable behavior for a given loan's lifetime; a loan's
  rules don't shift under it mid-flight, consistent with a 30-year loan's identity being stable.)*
- **FR-012**: The automated (LLM) escalation port MUST be a single generic capability — given an
  ambiguous situation, it returns either an answer or one of FR-006's defined failure modes. The
  system MUST NOT introduce multiple distinct escalation capability types for different question
  classes. *(Resolved 2026-07-23 — single generic callback: simplest port, one behaviour to
  implement and contract-test, and FR-006's four failure modes apply once rather than being
  multiplied per question type.)*

### Key Entities

- **Assessment** — A point-in-time, typed summary of a loan's situation, derived purely from its
  state and diary-derived facts. Not persisted beyond the diary entry that records it happened;
  reproducible by replay.
- **Rule** (a "gate") — A named, versioned check with a declared trigger and a pass/fail/
  indeterminate outcome. Content, not code — authored as a pack the same way foundation skill
  packs are, per intent 0003's own framing.
- **Decision** — The record of a rule's `pass`/`fail` outcome being applied to the loan's state or
  goals, carrying the rule's identity, version, an input digest, and the outcome.
- **Escalation** — The record of an `indeterminate` outcome being raised to a target (human or
  automated), together with however it was eventually resolved (an answer, or a defined
  fallback).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A loan spawned with a goal and fed a scripted event stream reaches `:completed`
  with zero operator interaction when every applicable rule passes, verified end-to-end against
  a real running actor and a real diary store.
- **SC-002**: A demonstration rule pack of at least three distinct rules, together covering every
  predicate operator and combinator `contracts/gate-behaviour.md` defines, evaluates against a
  factory-generated set of at least ten loan situations designed to produce all three outcomes
  (`pass`/`fail`/`indeterminate`) at least once — each evaluation's outcome must match the
  expected result for that situation, and every one is diary-logged carrying the rule's identity,
  version, and cause. *(Tightened 2026-07-23 per `/speckit-analyze` finding A1 — "correctly"/
  "representative" were unmeasurable as originally worded.)*
- **SC-003**: Every one of the defined automated-escalation failure modes (timeout, malformed
  output, refusal, low-confidence) is independently demonstrated to produce its specific,
  deterministic fallback and a diary entry — none left unhandled.
- **SC-004**: A single automated static check (one source-tree scan, independent of manual code
  review) confirms exactly one function in the entire codebase calls the automated-escalation
  capability. *(Tightened 2026-07-23 per `/speckit-checklist` finding CHK010 — "exactly one
  place" previously left "place" undefined; it means one call-site function, verified by one
  named check, mirroring the foundation's existing `LoanActor.Credo.NoLLM` mechanism.)*
- **SC-005**: For every scripted scenario this feature's own tests exercise, killing and
  restarting a loan produces an assessment/decision/escalation history that is field-for-field
  identical to the pre-crash history when compared via `:erlang.term_to_binary/1` equality —
  excluding only fields already excepted elsewhere in this codebase for the same documented
  reason (e.g. `last_heartbeat_at`'s live-clock value). This extends, not merely repeats, the
  foundation's own existing replay guarantee to this feature's new state. *(Tightened 2026-07-23
  per `/speckit-checklist` finding CHK011 — "exact"/"reproduces" previously had no stated
  comparison method; this now matches the exact mechanism `server_property_test.exs` already
  uses for the foundation's own replay claim.)*
- **SC-006**: Every applicable test-coverage category (happy, boundary, error, race, replay,
  regulatory, security) has at least one passing test, mapped in the delivering commit's own
  description — regulatory coverage specifically addresses rule-version traceability and
  escalation audit-trail completeness.

## Assumptions

- The demonstration rule pack built alongside the engine is illustrative only — it does not
  implement any real compliance, valuation, or underwriting rule set. Real business rules are
  future, separate work authored as their own rule packs against this engine.
- "Diary-derived facts" draws only from information already reachable from the loan's existing
  state and diary (document-completeness signals, goal ages, timing/SLA clocks already
  expressible in foundation terms) — this feature does not introduce new external data sources.
  Precisely: `assess_loan` itself reads ONLY the live `state` struct, never the diary directly;
  "diary-derived" describes how those facts originally got INTO `state.context` (via the
  incremental-update mechanism `research.md` R-3 adopts), not a second read path `assess_loan`
  also has. *(Reconciled 2026-07-23 per `/speckit-checklist` finding CHK020 — this Assumption
  and `research.md` R-6's adopted answer are now stated identically rather than merely
  compatible.)*
- The automated escalation path's underlying provider/vendor is not decided by this
  specification; only the port/contract it must satisfy (reachable only from `indeterminate`,
  every failure mode has a fallback, every call diary-logged) is in scope here.
- Single-loan autonomy only — no coordination or precedence rules across multiple loans' rule
  evaluations are introduced by this feature.
- Real-world rule authoring (a UI or authoring workflow for non-technical rule authors) is out of
  scope; rule packs are hand-authored markdown files, the same way foundation skill packs are.
- **Out of scope (added 2026-07-23 per `/speckit-checklist` findings CHK004/CHK018)**: an
  operator-initiated capability to cancel/revoke a pending escalation that is no longer
  relevant, and a cross-loan audit query capability (e.g. "every decision made under gate
  version X, across every loan"). Both are genuine, real capabilities a production system would
  likely eventually want — neither is introduced here. The first mirrors an already-accepted
  foundation limitation (pending HITL requests have no cancel mechanism either, per spec 001's
  own "operator never responds" edge case, deferred to a documented timeout in a later intent).
  The second would require a cross-loan index/reporting layer that doesn't exist anywhere in
  this codebase yet, consistent with this project's existing "no portfolio-level UI" exclusion
  (intent 0001) — a future intent's job, not a silent scope expansion of this one.
- **Escalation records (including the R-4 cleartext-output exception) have no separate retention
  policy** (added 2026-07-23 per `/speckit-checklist` finding CHK017) — they live exactly as
  long as the diary itself does. No diary retention/expiry mechanism exists anywhere in this
  codebase today (the diary is designed for a loan's full 30-year lifespan, per intent 0001's
  own framing); inventing a separate retention policy just for this one entry type would be new,
  unscoped work with nothing to attach to.
