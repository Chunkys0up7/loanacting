# Checklist — Test Data Quality

Per `test-data-forge` skill discipline. Applies to any PR adding or modifying test data.

## Factory discipline

- [ ] All non-trivial test inputs come from `apps/loan_actor/test/support/factory.ex` (or the equivalent frontend factory).
- [ ] No JSON-blob fixtures pasted from production data into the repo.
- [ ] Each factory function has a docstring describing what scenarios it covers (the "discovery checklist note" from the skill).
- [ ] Factories use deterministic generators where possible (`StreamData.binary(length: 16)` not `:rand.bytes(16)`) so tests are reproducible.

## Coverage of test-data scenarios

For every entity type touched, at least one factory variant exists for:

- [ ] Minimal valid (only required fields populated).
- [ ] Fully populated (all optional fields).
- [ ] Boundary values (min/max of each numeric/string field).
- [ ] Documented invalid (used by negative tests; each factory has a `:invalid_X` variant where X is the violation).

## PII safety in tests

- [ ] No real PII in test fixtures. Synthetic only.
- [ ] PII test corpus (`test/fixtures/pii_corpus.json`) covers the patterns in `priv/pii_patterns.yml` and is itself synthetic.
- [ ] Any new pattern added to `pii_patterns.yml` has a corresponding corpus entry in the same PR.

## Isolation

- [ ] Tests that touch Mnesia run with a unique table prefix per test (no shared global state across tests).
- [ ] Tests that touch the file diary use a per-test temp dir, cleaned up in `on_exit/1`.
- [ ] No test depends on the lexical or temporal order of other tests.

## Test data evolution

- [ ] When the data model changes (`data-model.md`), every factory affected is updated in the same PR.
- [ ] Old factory functions that are no longer used are deleted, not commented out.
