---
id: "0005"
slug: amend-reactive-pipeline-throughput
title: Reactive event pipeline misses its latency budget at production scale — collapse per-event Mnesia transaction overhead
status: Specified
author: cameron
created: 2026-07-22
specified: 2026-07-22
supersedes: []
depends_on: ["0001", "0004"]
amends: "specs/001-loan-actor-foundation/* (data-model.md Idempotency section; FT-015/FT-017-pinned behavior in LoanActor.Idempotency)"
execution_spec: "specs/001-loan-actor-foundation/ (amended in place)"
---

# Intent 0005 — Reactive pipeline throughput

## Problem

A loan actor cannot currently sustain the operator-facing latency budget the foundation
already committed to. `FT-035`'s load test (`apps/loan_actor/test/load/nfr_load_test.exs`,
commit `1a3998d`) measured the reactive event-to-diary path at full production scale — 100
concurrent loans, 10 events/sec/loan, 60 seconds — and found p95 event-to-diary latency of
496.64 ms (max 1444.25 ms) against `NFR-001`'s 100 ms budget, after two real, unrelated fixes
were already applied (an Mnesia log-dump threshold tuning, and a broken load-test mix alias).
Every other budget in the same run holds comfortably: `NFR-002` (memory, 235 MB / 256 MB),
`NFR-003`/`SC-002` (crash-recovery at scale), `NFR-004` (AG-UI delivery latency).

The load test's own investigation traced this to how many storage round-trips a single
inbound event costs today. Handling one event currently performs three separate,
sequentially-serialized Mnesia transactions: `LoanActor.Idempotency.check_and_record/3`
(reserve the dedup key), `LoanActor.Diary.Mnesia.append/2` (write the diary entry), and
`LoanActor.Idempotency.record_sequence/4` (fill in the reserved key with the entry's real
sequence). At 100 loans × 10 events/sec, that is roughly 3,000 Mnesia transactions/sec
against a single-node instance — more than this reference machine sustains inside the 100 ms
budget.

Notably, this three-transaction shape is itself a drift from what was originally decided.
`clarifications.md` Q6 (the idempotency-key decision) resolved that the dedup check would be
"a Mnesia `read` ... within the transaction that would append the diary entry" — one
transaction. `FT-017`'s Q13 clarification split it into the current reserve-then-fill
two-phase design because the diary sequence for a fresh event isn't known until after the
append succeeds, and added a same-key race guard for concurrent callers. But
`LoanActor.Idempotency`'s own moduledoc documents that callers are already a single
serialized process per loan (the `Server` GenServer's mailbox), so no concurrent caller can
ever observe the reserved-but-unfilled window the two-phase split defends against — the
guard may be paying for a race that structurally cannot happen, at the cost of throughput
that the architecture actually needs.

This is a real, already-spec-pinned piece of behavior (`FT-015`, `data-model.md`'s
Idempotency section) that a load test — not a hunch — has shown doesn't hold at the scale
the spec itself promises. Per this repo's spec-driven discipline, changing it needs its own
intent and pipeline pass, not an ad hoc patch.

## Outcome

A loan actor sustains `NFR-001` for real: p95 event-to-diary latency stays under 100 ms at
the full `SC-001` load profile (100 concurrent loans, 10 events/sec/loan, sustained 60
seconds), verified by re-running `FT-035`'s own load test (`mix test.load`) at its default
scale — not a reduced `LOAN_LOAD_*` override. Nothing else about the actor's externally
observable behavior changes: the same event still produces exactly one diary entry
(duplicates still short-circuit to `{:duplicate, sequence}`), the diary is still immutable,
chain-verifiable, and durable across a crash, and `contracts/loan-actor-api.md`'s public
return shapes are untouched.

## Non-goals

- **No change to idempotency semantics.** The composite key `(loan_id, event_id, source)`
  and the `{:duplicate, sequence}` return contract (`contracts/loan-actor-api.md`,
  `clarifications.md` Q6/Q13) are unchanged. This intent is about *how many storage
  round-trips* enforcing that semantics costs, not what the semantics are.
- **No change to diary immutability, chain-verification, or crash-recovery guarantees.**
  `NFR-003`/`SC-002` (rehydration correctness) and the chain-hash invariant are not
  renegotiated; any candidate fix must keep the existing property-based replay test
  (`FT-034`) and crash-recovery load test (`FT-035`'s own third scenario) green.
- **No multi-node Mnesia / clustering.** This is a single-node throughput problem; the fix
  stays single-node.
- **No revisiting `NFR-002`/`NFR-003`/`NFR-004`.** They already pass at full scale; nothing
  here should regress them, but this intent's success criteria are scoped to `NFR-001`.
- **No LLM involvement.** Deterministic-first stays intact — this is pure infrastructure.
- **No general-purpose write-batching framework.** If batching is the chosen direction, it
  is scoped to this one hot path, not a reusable abstraction speculatively built for future
  callers that don't exist yet.

## Constraints

- **Immutable diary** (constitution Principle IV): every decision/input/transition is still
  appended, in order, and never mutated after the fact. Any transaction-shape change must
  preserve gap-free sequences and the existing chain-hash linkage.
- **Deterministic-first**: no LLM anywhere in this path, before or after.
- **Three-loop harness**: this is entirely inside the reactive loop (`Server.handle_valid_event`
  → `handle_clean_event` → `apply_event`); the periodic and planning loops are untouched.
- **Portable identity / durability**: whatever replaces the current Mnesia-backed idempotency
  table must still survive a supervisor restart with correctness equivalent to today's
  Mnesia-backed table — a diary entry (`Diary.Entry`) does not currently carry `event_id` or
  `source`, so an in-memory-only dedup table cannot be reconstructed from diary replay alone
  without a data-model change; any direction relying on that must say so explicitly and
  justify the data-model amendment.
- **PD-1 (spec-driven development, CLAUDE.md §2)**: intent → `/speckit-specify` →
  `/speckit-clarify` → `/speckit-plan` → `/speckit-analyze` → `/speckit-tasks` →
  `/speckit-checklist` → `/speckit-implement`, all four artifact layers committed, no
  skipping `/speckit-tasks` or `/speckit-checklist`.
- **PD-2 (testing discipline, CLAUDE.md §3)**: tests first/alongside, taxonomic coverage
  (happy/boundary/error/race/replay/regulatory/security/performance), the existing race test
  proving exactly-one-`:fresh`-winner under concurrency must still pass (or be superseded by
  an equivalent test if the concurrency model itself changes), and `FT-035`'s load test is
  the literal acceptance proof.
- **One spec commit, no code** (CLAUDE.md §6a): the amendment's spec artifacts land in one
  commit; implementation is separate, one `FT-*` task per commit.

## Success criteria

- [ ] `mix test.load`'s NFR-001/SC-001 scenario passes at its **default** scale (100 loans,
      10 events/sec/loan, 60 s): p95 event-to-diary latency < 100 ms.
- [ ] The same run's `NFR-002` (memory < 256 MB) still passes — no regression traded for
      throughput.
- [ ] `FT-035`'s `NFR-003`/`SC-002` and `NFR-004` scenarios still pass unchanged.
- [ ] `FR-004` (exactly-one-diary-entry-per-event, including under concurrent duplicate
      delivery) is proven by a green test — either the existing race test or a replacement
      covering the same race if the concurrency shape changes.
- [ ] `FT-034`'s property-based crash-recovery replay test stays green: rehydrated state is
      identical to pre-crash state after the transaction-shape change.
- [ ] No weakening of durability is introduced silently — if any part of the dedup path
      moves off Mnesia disc_copies, the intent's own spec amendment says so explicitly and
      the checklist gates it.
- [ ] Every new/changed code path has taxonomy-mapped tests (test-guardian) with the
      duplicate-detection race test explicitly re-verified, and any new factories follow
      test-data-forge discipline.

## Open questions

- **Q1**: Collapse `check_and_record` + `record_sequence` + the diary `append` into a single
  Mnesia transaction (nested `:mnesia.transaction/1` spanning both `loan_idem` and
  `loan_diary`)? This directly removes the two extra round-trips and restores Q6's original
  single-transaction intent, and — as a side effect — makes the reservation and its fill
  atomic (today a crash between `check_and_record` and `record_sequence` leaves a
  permanently-orphaned `sequence: nil` reservation, a documented known limitation this would
  also close). *Needs `/speckit-clarify` to confirm no other caller path depends on the
  current two-phase visibility window.*
- **Q2**: Move the dedup table off Mnesia to a per-loan in-process ETS table (owned by the
  `Server` GenServer) with the diary itself remaining the durability boundary? Cheaper hot
  path, but `Diary.Entry` doesn't carry `event_id`/`source` today, so the dedup table cannot
  be rebuilt from diary replay on restart without a data-model addition — would need that
  addition specified explicitly, not assumed.
- **Q3**: Batch/pipeline Mnesia writes across events (e.g., a short debounce window
  coalescing multiple appends into one transaction)? Trades added latency for reduced
  transaction count — needs a concrete bound on how much latency this can spend before it
  eats the very budget it's trying to protect, and interacts with the "single serialized
  process per loan" model differently than Q1/Q2.
- **Q4**: Are there Mnesia-level tuning knobs beyond the already-raised
  `dump_log_write_threshold` (table fragmentation, `sync_transaction` vs. async, etc.) that
  close some of the gap without an application-level redesign at all — worth measuring
  before committing to a redesign?
- **Q5**: If the chosen direction changes the `loan_idem` Mnesia schema shape
  (`data-model.md`'s `{{loan_id, event_id, source}, {received_at, sequence}}`), does anything
  outside `LoanActor.Idempotency` read that table directly and need updating?

## Dependencies

### Intent dependencies
- **0001** — amends its execution spec in place (`data-model.md`'s Idempotency section,
  `FT-015`/`FT-017`-pinned behavior in `LoanActor.Idempotency`).
- **0004** — this is exactly the hot-path risk `0004`'s own text flagged FT-035 as the
  "early-warning gate" for; no functional dependency, but the context explains why the tool-
  call ceremony makes this budget tighter to hit than it would have been at 0001 alone.

### External dependencies (new)
- None expected. If Q2/Q3 end up requiring a new dependency (e.g. a batching library), that
  must be added here first, per CLAUDE.md's "no silent dep additions."

### External dependencies (existing)
- `:mnesia` (OTP, already the diary/idempotency backing store).

## Risks

- **Risk**: Collapsing transactions (Q1) still doesn't close the gap enough (496 ms → under
  100 ms is a >4.9x improvement needed; going 3 transactions → 1 is a 3x reduction in
  transaction *count*, not guaranteed to be a 3x latency reduction). *Mitigation*: the load
  test is the literal acceptance gate — if Q1 alone doesn't clear it, Q3/Q4 are evaluated
  next rather than declaring victory on transaction-count reduction alone.
- **Risk**: Any redesign accidentally reopens the concurrent-duplicate race the two-phase
  design was built to prevent. *Mitigation*: FT-015's existing race test (or a replacement
  covering the identical race) is a hard gate, not optional.
- **Risk**: Moving dedup off Mnesia (Q2) trades a durability guarantee for throughput without
  saying so plainly. *Mitigation*: constraints section above requires explicit justification
  and checklist gating if this path is chosen.
- **Risk**: This reference machine's throughput ceiling may not represent every deployment
  target, making "verified on this machine" a false sense of security. *Mitigation*: out of
  scope for this intent — `FT-035`'s load test already documents this is a reference-machine
  measurement; no claim beyond that is being made here either.

## Notes

Authored from the operator's load-test follow-up (2026-07-22), continuing directly from
`FT-035`'s own honestly-reported gap and root-cause diagnosis (commit `1a3998d`). Root cause
is already diagnosed by that commit; this intent exists to run the diagnosed problem through
the spec pipeline before any code changes, per PD-1 — not to re-diagnose it.
