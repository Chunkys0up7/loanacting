# Research — Loan-Actor Foundation

Phase 0 output of `/speckit-plan`. Each item lists the question, the answer we will adopt, and the source/justification. Items here are **closed**; reopening requires an amendment intent.

---

## R-1 — Mnesia transaction granularity vs. per-loan throughput

**Question.** Can Mnesia sustain 100 loans × 10 events/sec (1,000 transactions/sec aggregate, each containing a state update + diary append) at p95 < 100 ms with `disc_copies`?

**Adopted answer.** Yes, with these constraints:
- Two tables: `loan_state` (set, `disc_copies`) and `loan_diary` (ordered_set, `disc_copies`, sorted by `{loan_id, sequence}`).
- One `:mnesia.transaction/1` per event: read current state → compute next state → read prev diary tail (for `prev_hash`) → write state + diary entry.
- `:mnesia.dirty_*` is forbidden. The chain-link invariant requires read-modify-write under a transaction.
- Per-table dump intervals tuned conservatively (default is fine).
- Single-node only in foundation; multi-node Mnesia is a known-hard problem and explicitly deferred.

**Validation.** SC-001 load test asserts the budget. Fallback (if budget missed): switch to a file-backed implementation with `:fsync` after each append; the `DiaryStore` behaviour makes this swap mechanical.

**Source.** Erlang/OTP docs (Mnesia chapter, transaction sub-section); pragmatic experience reports from production Elixir systems running 10⁴-row-update/sec workloads on a single node.

**Addendum (2026-07-22, intent 0005).** The as-built system diverged from "one
`:mnesia.transaction/1` per event" in two ways this research didn't anticipate: (a) loan
state was never actually stored in a `loan_state` Mnesia table read-modify-write per event —
it lives in the GenServer's own memory and rehydrates via diary replay instead, so that part
of the adopted answer never applied; (b) `FT-015`/`FT-017` added idempotency
(`loan_idem`) as two *additional* Mnesia transactions per event on top of the diary append,
without revisiting this research's transaction-count budget. `FT-035`'s load test found the
resulting three-transactions-per-event shape misses `NFR-001` at full scale. Intent 0005
restores this research's original one-transaction-per-event intent (for the diary-append +
idempotency work that does hit Mnesia) via `DiaryStore.append_with_dedup/4` — see
`clarifications.md` Q17.

---

## R-2 — AG-UI SSE backpressure in Bandit

**Question.** How do we handle slow CopilotKit clients without blocking the loan actor?

**Adopted answer.** Per-subscriber buffered stream with bounded queue.
- Each `LoanActor.AGUI.Subscriber` is a separate process holding a small bounded mailbox (default 128 events).
- The loan actor `cast`s to the subscriber; if the subscriber's mailbox exceeds the bound, the subscriber drops to "resync mode" and the next event sent to the client is a fresh `StateSnapshot` + `MessagesSnapshot` rather than a `StateDelta`.
- The subscriber never back-pressures the loan actor. Loan actor → subscriber is fire-and-forget.
- Bandit chunked SSE writes use `8 KiB` chunks; one event per chunk is fine — events are small.
- Resync on slow-client recovery: send `StateSnapshot` only. Foundation does not implement chat-message history, so `MessagesSnapshot` is intentionally not emitted (see `contracts/ag-ui-events.md` "events not emitted").

**Validation.** A test in `apps/web/test/ag-ui-client.test.ts` simulates a slow consumer and asserts (a) the loan stays responsive, (b) the client receives a `StateSnapshot` on resume.

**Source.** Bandit issue tracker on SSE; AG-UI spec on `StateSnapshot` semantics (`.claude/skills/copilotkit/references/ag-ui-protocol.md`).

---

## R-3 — StreamData generators for the state machine

**Question.** How do we generate event sequences that exercise the full state machine without leaning on trivial uniform random sampling?

**Adopted answer.** Model-based generation.
- The state machine diagram from `data-model.md` is mirrored as a `LoanActor.State.Model` test helper containing `next_events_for(status)` returning legal events from each state.
- StreamData generator: start at `:spawned`, sample one of `next_events_for(state)`, apply, recurse. This produces only *reachable* event sequences — no wasted attempts on impossible transitions.
- A second generator deliberately injects *illegal* events (out-of-band types) to exercise the error category of the taxonomy.

**Validation.** Property: for every generated sequence, replaying the diary against a fresh actor produces the same final state. 10,000 sequences per CI run.

**Source.** ["Property-based testing with PropEr" by Hebert]; StreamData docs on `bind` + `tree`.

---

## R-4 — Chain-link hash function

**Question.** BLAKE2b vs SHA-256 for `prev_hash`?

**Adopted answer.** BLAKE2b-256 (`:crypto.hash(:blake2b, ...)` truncated to 32 bytes).
- Faster than SHA-256 on modern CPUs.
- 256-bit output is sufficient for tamper detection in this domain.
- Available in OTP without external dependency.

**Validation.** SC-006 tamper-detection test passes.

**Source.** BLAKE2 RFC 7693; OTP `:crypto` module docs.

---

## R-5 — Mnesia + property-based tests under `async: true`

**Question.** ExUnit's `async: true` parallelizes test cases; Mnesia has global table state. How do we isolate?

**Adopted answer.** Per-test schema reset is unworkable (too slow). Adopt:
- `:async, false` for any test module that touches Mnesia directly.
- Most unit tests run against `LoanActor.Diary.File` (in-process, per-test temp dir) and can be `async: true`.
- Integration and property-based tests use a dedicated Mnesia node started in the test setup, with a per-test prefix (`"test_#{:erlang.unique_integer()}"`) on table names — so the global state coexists.
- A shared `DataCase` test helper wraps both patterns.

**Validation.** `mix test --max-cases 8` completes the suite without flakes across 10 consecutive runs.

**Source.** ExUnit + Mnesia community guidance; ecto_sandbox-style patterns adapted (no Ecto here).

---

## R-6 — Why no Phoenix in foundation

**Question.** Phoenix gives us LiveView and channels. Why are we not using it?

**Adopted answer.** Three reasons:
1. Foundation's UI is a SPA driven by CopilotKit + AG-UI over SSE — Phoenix Channels would be a second, redundant transport.
2. Plug.Router on Bandit gives us the four HTTP endpoints we need in ~50 lines; Phoenix adds ~12 dependencies and a project layout we don't need yet.
3. Adopting Phoenix later (when, e.g., we want LiveView dashboards for portfolio views) is a clean addition — adopting it now would entangle foundation with framework choices that should be made by the relevant feature intent.

**Source.** Phoenix changelog notes on Bandit becoming the default adapter; CLAUDE.md UI section (CopilotKit is the only sanctioned chat/agent UI).

---

## R-7 — Frontend bundler / framework

**Question.** Vite + React + TS, or Next.js?

**Adopted answer.** Vite + React + TS.
- The frontend is a single SPA against a fixed backend; we do not need SSR, file-system routing, or API routes.
- Next.js would pull us toward putting a CopilotRuntime in front (we explicitly chose not to in clarification Q3).
- Faster cold start in dev; faster CI builds; fewer moving parts.

**Adoption later.** Phoenix LiveView OR Next.js becomes a candidate once we have a server-driven UI use case (e.g., dashboards, server-rendered portfolio screens). That is a separate intent.

**Source.** Vite docs; CopilotKit React quickstart works against any bundler.

---

## R-8 — UUIDv7 in Elixir

**Question.** Generation library?

**Adopted answer.** Pure-Elixir `Uniq.UUID` (`{:uniq, "~> 0.6"}`). Lightweight; supports UUIDv7. No NIF.

**Source.** Uniq library README (hex.pm).

---

## Closed; downstream tasks may rely on these answers.
