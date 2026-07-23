# Quickstart — Autonomous Decision Harness

Extends `001-loan-actor-foundation/quickstart.md` — same setup, same run commands. This document
only covers what's NEW: authoring a gate pack, watching a loan progress autonomously, and forcing
an escalation.

## Prerequisites

Same as foundation's quickstart — no new runtime dependency (`research.md` R-1: the LLM adapter
ships as a port + recorded-fixture test double, no live vendor client to install for local dev).

## Author a new gate pack

```
priv/skills/0002-demo-gate-pack/SKILL.md
```

```markdown
---
name: document-completeness-gate
version: 1.0.0
description: When assessing document completeness for an income goal, check the required documents are present and current.
tools_required: [evaluate_gate]
gate_id: document-completeness
rule:
  combinator: all
  predicates:
    - field: assessment.document_completeness
      op: eq
      value: complete
---

# Document completeness gate

Checks that all required documents for an income-verification goal are present and current
before allowing the loan to advance. See `contracts/gate-behaviour.md` for the rule grammar.
```

No code change, no restart required — `Skill.Loader.reload/0` (or the next natural reload cycle)
picks it up, exactly like a skill pack (`gate-pack-format.md`).

## Watch a loan work through its goals unattended

```powershell
iex -S mix
```

```elixir
{:ok, _pid} = LoanActor.spawn("L-AUTONOMY-DEMO")
{:ok, _seq} = LoanActor.send_event("L-AUTONOMY-DEMO", %LoanActor.Event{
  event_id: Uniq.UUID.uuid7(),
  source: :operator,
  type: :goal_set,
  payload: %{},
  created_at: DateTime.utc_now()
})
```

Feed the scripted events the demo gate pack's rule needs (e.g. a `:document_uploaded` event
representing the required document arriving). Watch the diary (`LoanActor.state/1`, or the
frontend's `DiaryFeed`) show, per loop pass: an `:assessment` entry, a `:gate_evaluated` entry
naming `document-completeness` + its version + outcome, and — once the rule passes — a
`:decision` entry followed by the loan's own state/goal change, all with **zero further operator
action** (SC-001).

## Force an escalation

Send an event/state combination the demo gate pack's rule cannot resolve (e.g. a document
present but in a format `assessment.document_completeness` doesn't recognize, if the demo pack
is authored to treat that as `:indeterminate` rather than `:fail`). Watch the diary show
`:escalated` instead of `:decision`. Two ways to resolve it:

- **Human target**: same flow as foundation's own HITL quickstart step — an approval card
  appears in the UI; approve/reject resumes the loan (`:escalation_resolved`/`:decision`
  follows).
- **LLM target** (local dev, no live model): the recorded-fixture test double answers
  deterministically per whichever fixture matches the situation — useful for exercising the
  full escalation flow without a real vendor call. See `contracts/llm-escalation-port.md`'s
  contract test for the exact fixture set.

## Smoke checklist (what "works" looks like, extending foundation's own)

1. A loan with a goal set and every required document present reaches `:completed` with zero
   operator interaction (SC-001).
2. The diary shows one `:assessment` + one `:gate_evaluated` entry per loop pass, each carrying
   the gate's identity, version, and outcome (SC-002).
3. A rule pack change (edit + reload) is visible on the very next loop pass with no code change
   or redeploy.
4. Forcing each of the 4 LLM failure modes (timeout, malformed output, refusal, low-confidence)
   produces its own deterministic fallback and diary entry (SC-003).
5. `mix credo --strict` still reports zero `NoLLM` violations outside the one named exception
   (SC-004).
6. Replaying the diary after a crash reproduces the exact assessment/decision/escalation history
   (SC-005) — same crash-kill-restart smoke step as foundation's own, extended to check this
   feature's own diary types too.

If any step fails, the feature is incomplete — open an intent describing the gap before patching
(same discipline as foundation's own quickstart).
