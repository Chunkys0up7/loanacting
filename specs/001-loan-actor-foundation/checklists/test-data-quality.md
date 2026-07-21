# Checklist — Test Data Quality

Per `test-data-forge` skill discipline. Applies to any PR adding or modifying test data.

## Factory discipline

- [x] All non-trivial test inputs come from `apps/loan_actor/test/support/factory.ex` (or the equivalent frontend factory). *(FT-006: chain_test refactored onto Factory; store suites are factory-only.)*
- [x] No JSON-blob fixtures pasted from production data into the repo. *(Verified FT-006/007/008: all data generated.)*
- [x] Each factory function has a docstring describing what scenarios it covers (the "discovery checklist note" from the skill). *(Factory moduledoc carries the discovery checklist + per-function docs.)*
- [x] Factories use deterministic generators where possible (`StreamData.binary(length: 16)` not `:rand.bytes(16)`) so tests are reproducible. *(Defaults are pure functions of `(loan_id, sequence)`; randomness only in opt-in StreamData generators + the run token, which exists precisely to keep persisted-store reruns reproducible.)*

## Coverage of test-data scenarios

For every entity type touched, at least one factory variant exists for:

- [x] Minimal valid (only required fields populated). *(`Factory.entry/1` defaults — `payload_ref` nil.)*
- [x] Fully populated (all optional fields). *(Codec round-trip test builds `payload_ref` + microsecond timestamps via factory overrides.)*
- [ ] Boundary values (min/max of each numeric/string field). *(Zero/genesis + exact-32-byte hashes covered; max-side values not yet systematic — open for Diary.Entry, due with FT-037.)*
- [x] Documented invalid (used by negative tests; each factory has a `:invalid_X` variant where X is the violation). *(`Factory.invalid_entry_variants/0`, parametrized in factory_test + entry negatives.)*

## PII safety in tests

- [ ] No real PII in test fixtures. Synthetic only.
- [ ] PII test corpus (`test/fixtures/pii_corpus.json`) covers the patterns in `priv/pii_patterns.yml` and is itself synthetic.
- [ ] Any new pattern added to `pii_patterns.yml` has a corresponding corpus entry in the same PR.

## Isolation

> **Recorded deviation (FT-007/FT-008, to be ratified in the 0001 audit):** both
> store suites achieve isolation via loan-ids unique per test AND per BEAM run
> (`Factory.unique_loan_id/0` run token) on a shared tmp-dir/table, with
> `async: false`, instead of per-test table prefixes / per-test temp dirs.
> Equivalent guarantee (no cross-test or cross-run interference — proven by
> consecutive full-suite runs with different seeds); simpler than re-initializing
> Mnesia schemas per test. If the audit rejects the equivalence, retrofit here.

- [x] Tests that touch Mnesia run without shared global state across tests *(via run-token loan-id namespacing — see deviation note)*.
- [x] Tests that touch the file diary are isolated in the OS tmp dir, never `priv/` *(same mechanism)*.
- [x] No test depends on the lexical or temporal order of other tests. *(Randomized seeds; suite green across consecutive runs.)*

## Test data evolution

- [ ] When the data model changes (`data-model.md`), every factory affected is updated in the same PR.
- [ ] Old factory functions that are no longer used are deleted, not commented out.
