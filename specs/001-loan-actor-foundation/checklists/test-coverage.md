# Checklist — Test Coverage (Taxonomic)

Per Constitution Principle V. Coverage is by **category**, not by percentage. A PR description maps each applicable category to test files; missing categories are blockers unless explicitly N/A with justification.

## Categories

### Happy path
- [ ] At least one test exercises the documented success path.
- [ ] The test uses a factory from `apps/loan_actor/test/support/factory.ex` for any non-trivial input.

### Boundary
- [ ] Inputs at the minimum, maximum, and zero values are tested.
- [ ] Empty collections, nil values, and the largest sane size are covered.
- [ ] Time-based logic is tested at the configured-interval edge.

### Error
- [ ] Every documented error return is exercised.
- [ ] Malformed inputs (bad enum values, missing required fields) produce the documented error, not a crash.
- [ ] No `rescue` that swallows an unexpected exception silently.

### Race
- [ ] If two callers can interact with the same resource, a test exercises that overlap.
- [ ] Tests use `Task.async_stream`, `:erlang.send_after`, or controlled scheduling to force interleavings.
- [ ] For diary writes: parallel append to the same loan is tested (must serialize correctly).
- [ ] *(0005)* `DiaryStore.append_with_dedup/4`'s concurrent-duplicate-delivery race is tested for both implementations: exactly one caller sees `:fresh`, all others see the same `{:duplicate, sequence}`.

### Replay
- [ ] If the change adds or modifies a state-mutating handler, a test replays the diary and asserts byte-equal state.
- [ ] `verify_chain/1` is invoked in the test.

### Regulatory *(N/A for foundation)*
- [ ] When introduced by a future intent (e.g., RESPA/TRID/QM), this row is filled. Foundation marks N/A.

### Security
- [ ] PII patterns: any new event field is checked against `priv/pii_patterns.yml`.
- [ ] Diary tampering: if the change touches diary write paths, a tamper-then-verify test is added.
- [ ] Auth: if an endpoint is added, `OperatorPlug` test covers 401 absent and ID propagation present.
- [ ] No new dependency provides LLM client capability (covered by Credo + grep test).

### Contract
- [ ] If `contracts/*.md` changed: the corresponding backend snapshot test and frontend type definitions also changed in the same PR.
- [ ] Cross-stack contract test (`apps/web/test/e2e/contract.spec.ts`) green.
- [ ] *(0004)* New/changed tools pass the shared tool contract suite (`tool_shared.ex` ↔ `contracts/tool-behaviour.md`).
- [ ] *(0004)* New/changed skill packs pass the loader validation tests (`contracts/skill-format.md`).

### Tools & skills *(added by intent 0004)*
- [ ] Any new tool: happy + invalid-args (each schema keyword) + determinism + PII order-of-operations tests.
- [ ] Any new skill pack: trigger-match positive AND negative (non-matching state activates nothing) tests.
- [ ] Tool invocations appear in the replay property test's generated diaries.

### Performance
- [ ] If the change could affect NFR budgets, `mix test.load` was run locally and the report attached to the PR description.
- [ ] If the change is in a hot path (event ingestion, diary append, AG-UI emission), an explicit Benchee microbenchmark is added.
- [ ] *(0005)* `mix test.load` run at its **default** `LOAN_LOAD_*` scale (not a reduced override) shows `NFR-001` p95 < 100 ms — a reduced-scale pass does not satisfy this gate.

### Reactive pipeline throughput *(added by intent 0005)*
- [ ] Duplicate delivery via `append_with_dedup/4` performs **zero** diary writes (only the fresh delivery writes).
- [ ] A forced abort partway through the combined transaction (e.g. `entry_builder` or `Chain.verify_append/2` raising) leaves **zero** trace in *either* `loan_diary` or `loan_idem` — the whole point of collapsing to one transaction is that there is no partial/reservation state to leak; this test proves atomicity, it does not simulate the old two-phase design's failure mode (that design no longer exists).
- [ ] `entry_builder` is exercised with `tail == nil` (a brand-new loan's first event through this path) as well as a real tail — genesis is a distinct boundary case.
- [ ] Chain-link rejection still aborts correctly through the new path: a corrupted `prev_hash` fed to `append_with_dedup/4` aborts exactly like today's `append/2` does (regression check — same invariant, new code path).
- [ ] `FT-034`'s property-based replay suite passes unmodified against the new code path (no diary entry shape changed; replay never touches `loan_idem`, so this is a non-regression gate, not new-logic coverage).
- [ ] The old FT-015 race test in `test/idempotency_test.exs` is **replaced** by the new shared-behaviour-suite race test (FT-046, parameterized across both `DiaryStore` implementations), not kept alongside it — the transaction-scoped helpers that remain in `Idempotency` after FT-047 only ever run inside an already-open transaction, so they get narrow unit tests, not a duplicate race test.

## Process

- [ ] PR description includes a table:  `| category | file(s) | notes |`
- [ ] N/A rows include a one-sentence justification.
- [ ] CI shows green across `mix test`, `mix dialyzer`, `mix credo --strict`, `mix test.load` (or nightly job), `npm test`, Playwright e2e.

## Forbidden in tests

- Mocks at architectural boundaries (real BEAM, real Mnesia / file diary, real AG-UI stream).
- Hand-rolled fixtures of opaque provenance — use factories.
- "Sleep" as a synchronization primitive (use `assert_receive`, polling helpers, or `:sys.get_state` with explicit waits).
- Tests skipped with `@tag :skip` without an associated open intent or issue.
