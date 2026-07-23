# Research — Autonomous Decision Harness

Phase 0 output of `/speckit-plan`. Each item lists the question, the answer adopted, and the
source/justification. Items here are **closed**; reopening requires an amendment intent.

Intent 0003's own Q1 (gate rule DSL) and Q2 (where facts come from) already carried the
author's recommendation, treated as an informed default rather than reopened here — R-2 and R-3
below formalize those recommendations into a concrete, contract-pinned design rather than
re-litigating the choice itself. Q3/Q4 were resolved as FR-012/FR-011 during `/speckit-specify`
and are not research questions.

---

## R-1 — Is a real LLM vendor adapter in scope for this feature?

**Question.** Intent 0003's own Non-goals list "production LLM vendor selection/procurement" as
out of scope, but the Outcome section describes "an LLM-assessment tool (new, the first
non-deterministic tool)" as something this feature delivers. Does "delivers" mean a real,
callable adapter, or the port + a test double only?

**Adopted answer.** The port (a behaviour: one `assess/2`-style callback, per FR-012) plus a
recorded-fixture-backed test double ship with this feature. A real vendor adapter does not — it
is a thin, separately-scoped follow-up that plugs into the same behaviour once a vendor is
chosen. This reads the Non-goal literally ("vendor selection/procurement" is exactly what
choosing and wiring a real API key/client would require) without reading it as blocking the
*port* itself, which the Outcome section clearly does want. `contracts/llm-escalation-port.md`
documents the behaviour precisely enough that a real adapter is a mechanical, low-risk follow-up.

**Validation.** SC-003/SC-004 and the constitution's 3-test LLM requirement (deterministic path,
escalation trigger, each failure mode) are all satisfiable entirely against the test double — none
require a live model. `LoanActor.Credo.NoLLM`'s allow-list update (naming `assess_via_llm.ex` as
the one sanctioned exception) only needs the module to exist, not a real vendor call inside it.

**Source.** Intent 0003's own Non-goals + Outcome sections, read together; this project's
existing precedent of shipping a behaviour + test double before a real implementation (the
`DiaryStore` behaviour itself, `LoanActor.Diary.File` as the "alternative implementation" proving
the abstraction is real before Mnesia's own production hardening).

---

## R-2 — Gate rule predicate DSL grammar

**Question.** Intent 0003 Q1 recommends "a tiny declarative predicate DSL (field, op, value,
all/any)" over compiled Elixir modules. What is the exact, hard-capped grammar?

**Adopted answer.** A gate pack's rule expression is restricted to:

- **Field reference**: a dotted path into the assessment struct or loan state (e.g.,
  `assessment.document_completeness`, `state.goals`).
- **Operator**: one of `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `present`, `absent`, `contains`.
- **Value**: a literal (string, number, boolean, or a list for `contains`).
- **Combinator**: `all` (every sub-rule must pass) or `any` (at least one must pass), nestable
  one level (a list of predicates or a list of combinators, not arbitrary recursion depth) —
  mirrors `tool-behaviour.md`'s own "hard cap... extending it requires an amendment" pattern for
  the JSON-schema args subset, applied here to rule expressions instead.
- A rule pack's front-matter carries the top-level combinator + predicate list; anything the
  grammar can't express is NOT a workaround target (author a new gate pack version once the
  cap itself is amended) — this is the explicit anti-vibe boundary against the DSL growing into
  an accidental programming language (intent 0003's own named Risk).

**Validation.** `evaluate_gate`'s parser is a small, exhaustively-tested pure function (parse →
validate → evaluate); every operator and combinator gets a happy + boundary + error test.
`contracts/gate-behaviour.md` pins this exact grammar as the hard cap.

**Source.** Intent 0003 Q1's own recommendation; `contracts/tool-behaviour.md`'s existing
JSON-schema-subset precedent (`type`/`properties`/`required`/`enum` only) as the template for how
this project caps and documents restricted grammars.

---

## R-3 — Incremental vs. recomputed-every-pass diary-derived facts

**Question.** Intent 0003 Q2 recommends incrementally maintaining facts in `State.context`
(with a replay invariant proving equivalence to full recomputation) over recomputing from the
full diary on every pass. Confirm this is still the right call and define the replay invariant
concretely.

**Adopted answer.** Confirmed: facts (document-completeness signals, goal ages, SLA/timing
clocks) are maintained incrementally in `state.context`, updated by the same tool-effect
mechanism that already updates `state.goals` (Principle IV: every state-mutating handler appends
its diary entry in the same logical step). The replay invariant: for any diary prefix, folding
the incremental update handlers over it MUST produce a `state.context` identical to computing
the same facts by a full, from-scratch derivation over that same prefix. This invariant is a
property test (StreamData), run alongside — not instead of — the existing
`server_property_test.exs`-style crash-recovery replay property, extending rather than forking it.

**Validation.** R-6 below narrows exactly which facts this covers. The property test is
Phase 2's own deliverable (track 7, "Property-based replay").

**Source.** Intent 0003 Q2's own recommendation; this project's existing replay-invariant
testing pattern (`replay_test.exs`, `server_property_test.exs`) as the template rather than
inventing a new verification style for this feature specifically.

---

## R-4 — Escalation diary entry shape vs. Principle III/VIII tension

**Question.** Constitution Principle III requires every LLM call's diary entry to carry
"trigger, prompt id, model, version, full input hash, full output, decision delta." Principle
VIII requires tool diary entries to carry only a hash of args/results, never raw values. Does
"full output" in Principle III mean the actual output value in cleartext (a new exception to
Principle VIII), or a hash of it (consistent with VIII, but then Principle III's own wording
"full output" — not "full output hash" — would be imprecise)?

**Adopted answer.** Raised directly rather than guessed, per this project's own established
discipline (Q12/Q14/Q15 precedent: raise ambiguities between two normative documents explicitly).
**Resolution: "full output" in Principle III means the actual LLM output value, in cleartext, in
the diary entry — a deliberate, narrow, named exception to Principle VIII's hash-only rule,
justified because LLM escalation outputs are the one category of tool result this project
expects a human auditor to need to read verbatim (a compliance/regulatory judgment call, not a
raw financial identifier) — but ONLY after the same PIIGuard hard gate every other diary-bound
value already passes through (Principle VIII's PII-before-hashing-and-emission order of
operations is unchanged; this exception is about hashing, not about the PII gate). If PIIGuard
would reject the LLM's raw output, the escalation fails closed into the `escalation_failed`
diary type with a `pii_violation` cause — it never silently substitutes a hash to route around
the gate.

**Validation.** `data-model.md`'s escalation entry shape encodes this explicitly, distinguishing
it from every other tool's hash-only entries with a named, documented reason — not a silent
inconsistency an auditor discovers later (the exact failure mode intent 0001's own closeout
audit found and flagged for goal content, which this research question exists to avoid repeating
here).

**Source.** Constitution v1.2.0 Principles III and VIII, read literally against each other;
`specs/001-loan-actor-foundation/audit.md` §4 item 3 (the goal-content-replay gap) as the
cautionary precedent this resolution is explicitly trying not to repeat.

---

## R-5 — Reconciling `skill-format.md`'s "intent 0003 owns real assessment-driven selection"

**Question.** `001-loan-actor-foundation/contracts/skill-format.md` explicitly forward-references
this intent: foundation's trigger matching is "intentionally naive... intent 0003 owns real
assessment-driven selection." Intent 0003's own draft never mentions this — it's silent on
whether gate-pack *triggering* (deciding a gate applies to this loan right now, as opposed to
gate *evaluation* once triggered) changes at all. Left unresolved, `contracts/gate-pack-format.md`
can't say how a gate pack declares when it's even considered.

**Adopted answer.** Reuse `Skill.Loader.match/2` unchanged — no new selection algorithm — but
enrich its `loan_context` input with assessment-derived facts (`%{status, event_type,
goal_descriptions, assessment: %Assessment{}}`, extending the existing map rather than replacing
it) so a gate pack's trigger keywords can reference assessment fields the way `contracts/
gate-behaviour.md`'s rule DSL does (e.g. a gate pack whose description mentions "document
completeness" now genuinely keyword-overlaps against a real completeness signal, not just
whatever the loan's raw goal descriptions happen to say). This is the minimal reading of
"assessment-driven": the SELECTION mechanism is still naive keyword overlap (unchanged, not
re-litigated — that would be a much larger, unscoped rework of `Skill.Loader` itself), but what
it's matching AGAINST is now assessment-informed rather than purely goal-text-informed. A gate
pack is loaded and matched exactly like a skill pack (same `SKILL.md`-shaped manifest, same
loader) — `contracts/gate-pack-format.md` is additive front-matter fields on the existing format,
not a parallel loader.

**Validation.** `evaluate_gate` is only ever invoked for gates that already matched via this
enriched `match/2` call — a non-matching loan never even attempts evaluation, keeping the
"activates zero skills on a non-matching loan" invariant (SC-014, foundation) true for gates too.

**Source.** `001-loan-actor-foundation/contracts/skill-format.md`'s own forward-reference,
resolved conservatively (extend the input, not the algorithm) to avoid an unscoped rework of
`Skill.Loader` that neither this intent nor 0001 ever asked for.

---

## R-6 — Scope of `assess_loan`'s diary-derived facts

**Question.** Does `assess_loan` need any information beyond what `state.context`/`state.goals`
and existing diary entry types already expose, or does it need a new read path over the diary
itself?

**Adopted answer.** No new read path. `assess_loan` derives its `%Assessment{}` purely from the
live `state` struct (goals, context, status, `last_heartbeat_at`) — the same inputs every other
foundation tool already receives via `Tool.Context`. "Diary-derived" in intent 0003's own Problem
statement refers to facts that were ORIGINALLY populated by folding diary replay into
`state.context` (R-3's incremental-facts mechanism) — not to `assess_loan` itself re-reading the
diary at assessment time. This keeps `assess_loan` as simple and fast as every other deterministic
foundation tool, and keeps the performance-goals note in `plan.md` (assessment on every loop pass
must not blow the reactive-loop budget) achievable without a new I/O path.

**Validation.** `assess_loan`'s own determinism property test (same state in, same assessment
out) is trivially satisfiable if it never touches the diary store directly — confirms this
adopted answer rather than assuming it.

**Source.** Intent 0003's own Outcome section ("derives a typed `%Assessment{}` from current
state + diary-derived facts") read together with R-3's incremental-facts design — the two
together resolve where "diary-derived" facts actually live by the time `assess_loan` runs.
