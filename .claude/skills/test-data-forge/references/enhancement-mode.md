# Enhancement Mode

The playbook for working with existing test data. When the user asks to "improve test data,"
"audit our fixtures," "add edge cases to the existing tests," or "extend coverage" — this is
the mode.

The discipline: **audit before you generate, extend before you replace, replace only with
explicit user approval.** A pile of existing fixtures, however ugly, encodes domain knowledge
the user paid for. Don't burn it down.

## The Audit (run before any new generation)

### Step 1: Inventory

For each entity that has test data, fill in this row:

| Entity | Factory exists? | Style | Scenarios covered | Used by N tests |
|---|---|---|---|---|
| User | Yes — `tests/factories/user.py` | factory_boy | happy only | 14 |
| Order | No — hardcoded dicts in 7 test files | literals | happy only | 23 |
| Invoice | Partial — `tests/fixtures/invoices.json` | static JSON | unclear | 6 |
| Payment | No fixtures | — | — | 0 (untested) |

This inventory drives the priorities. "No fixtures, 0 tests" is the urgent gap; "factory exists,
happy only" is a coverage gap; "literals in 7 files" is a refactor gap.

### Step 2: Quality audit per existing factory or fixture

For each existing factory, score it against these dimensions:

| Dimension | Question | Common failure |
|---|---|---|
| **Schema-derived** | Do defaults match the current schema, or have they drifted? | Factory has fields that no longer exist on the model; or model fields the factory doesn't set |
| **Deterministic** | Same input → same output every run? | Uses unseeded `random` or unseeded Faker |
| **Composable** | Can a test ask for the variant it needs without copy-pasting the factory? | One factory function per variant; or factory is a frozen dict |
| **Fresh** | Each call returns a new object? | Module-level constant being mutated by tests |
| **Used** | Is the factory referenced by tests, or orphaned? | Factory exists, no test imports it |

The audit produces a per-entity report:

```
UserFactory (tests/factories/user.py):
  ✅ Schema-derived (matches User v2.3.0)
  ❌ Deterministic — Faker is not seeded; runs vary
  ⚠️ Composable — has admin/staff/customer variants but no way to compose them with order count
  ✅ Fresh per call
  ✅ Used by 14 tests

OrderFactory: none. Hardcoded dicts in 7 test files. Refactor candidate.

invoices.json (tests/fixtures/invoices.json):
  ❌ Schema-derived — has 'invoiceID' field; current schema uses 'invoice_id'
  ✅ Deterministic (static file)
  ❌ Composable — single canned blob
  ✅ Fresh (read-only file)
  ✅ Used by 6 tests
  ⚠️ Suspicious: contains plausible-but-specific addresses (see production-leak audit)
```

### Step 3: Production-leak audit

Apply the customer-data signatures from `isolation-rules.md` to every existing fixture file
and factory default. Flag anything suspicious. Examples of red flags:

- Real consumer-domain emails: `*@gmail.com`, `*@yahoo.com`
- Phone numbers outside reserved ranges (e.g., not in the `555-01xx` block for North America)
- Sequential or otherwise-coherent narratives across many fields
- Filenames like `users_export.csv`, `prod_dump.json`

If you find these, do not silently replace them — surface them to the user with a quote and
file location. The user may know they're already synthetic (e.g., from a deliberate Faker run)
or may need to investigate.

### Step 4: Coverage gap analysis

Cross-reference the existing tests against the coverage taxonomy (`coverage-taxonomy.md`). For
each entity, fill in the matrix and identify gaps.

```
User entity coverage:
  Happy path:    ✅ covered (test_create_user)
  Boundary:      ❌ gap — no tests for age=0, age=max
  Empty:         ⚠️ partial — covers optional address but not optional phone
  Invalid:       ⚠️ partial — covers email format only, missing all other field validations
  Edge cases:    ❌ gap — no unicode names, no timezone handling
  Adversarial:   N/A — User is internal; no untrusted ingress
  Stateful:      ❌ gap — no soft-delete + reactivation tests
```

## The Enhancement (after audit, with user approval on the plan)

Once the audit is in front of the user, present a priority-ordered enhancement plan:

```
Proposed enhancements (ordered by ROI):

1. Add Invalid scenario catalog for User (8 new tests, ~30 min)
   — Highest value. Currently a single regression in validation would go unnoticed.

2. Refactor Order hardcoded dicts → OrderFactory (touches 7 test files, ~1 hr)
   — Touches many files but unlocks all subsequent Order enhancements.

3. Replace invoices.json with InvoiceFactory + JSON snapshot (~45 min)
   — Removes drift risk and suspected production-leak data.

4. Seed Faker in conftest.py (5 min)
   — Cheap fix; prevents future "Tuesday in May" flakes.

5. Add Boundary + Edge tests for User and Order (~1 hr)
   — Closes the largest remaining coverage gaps.

6. Cover Payment entity from scratch (~2 hr)
   — New surface; full coverage matrix from scratch.

Total: ~5.5 hours. I recommend starting at item 1 — happy to ship that as a standalone change
and revisit the next steps after review.
```

Wait for the user to confirm before executing. They may reorder, defer, or drop items.

## The Refactor (literals → factories)

When existing tests use hardcoded dicts, refactor cautiously.

### Step 1: Build the factory first, in parallel

Create the new factory without touching existing tests. Verify it produces objects that pass
the schema validation.

### Step 2: Migrate one test file at a time

For each test file using literals:
1. Identify the canonical literal — the one that represents the happy path
2. Replace it with a factory call: `user = UserFactory.build()` (or `.create()` if persisted)
3. For each variant in the file, parameterize via `UserFactory.build(role="admin", ...)`
4. Run the tests; they should still pass

### Step 3: Don't migrate brittle tests blindly

A test that depends on `user.email == "specific.value@example.com"` is brittle and refactoring
it to use a factory will break the assertion. Two choices:
1. Keep the literal, but route it through `UserFactory.build(email="specific.value@example.com")` —
   the factory still wins because all other fields are now schema-derived
2. Rewrite the assertion to not depend on the specific value (assert email contains `@`, etc.)

Make the call per test. The factory pattern is the goal, not the rule.

### Step 4: Add a regression test, then delete the literal

After migration, the original literal still works elsewhere. Search the repo for it and verify
no stale references. Once clean, remove dead constants.

## The Replacement (only with explicit user approval)

Sometimes existing fixtures are beyond enhancement — they're production data, they're for a
schema that no longer exists, they're entangled with abandoned code. Only then:

1. **Get explicit user approval to delete.** Quote the files, show the audit findings, propose
   the new structure.
2. **Build the replacement before deleting the old.** Both live side by side briefly.
3. **Migrate the tests.** Switch them to the new factories.
4. **Run the suite.** Same tests pass against the new factories.
5. **Delete the old fixtures in a separate commit** so it's reversible.

## Anti-Patterns Specific to Enhancement Mode

- **"Rewrite the whole fixture layer."** Almost never the right move. Audit, extend, refactor
  incrementally. Big-bang rewrites lose embedded domain knowledge.
- **Silent deletion of fixtures.** Even if a fixture looks dead, it might be used by a CI-only
  test, an external integration, or another developer's branch. Surface before deleting.
- **Refactoring tests "while you're in there."** Each enhancement is a discrete change. If you
  see a test you'd rewrite, note it and do it in a separate task. Don't expand scope mid-flight.
- **Skipping the production-leak audit because "they wouldn't have committed real data."**
  They might have. Audit anyway. Three minutes of grep prevents potentially-disclosable leaks.
- **Treating enhancement as a one-shot.** The end state of enhancement isn't "all gaps closed";
  it's "the next gap is documented." Some scenarios genuinely require domain input you don't
  have. Surface them, don't fake them.

## The Enhancement Report

When you finish, produce a closing report:

```
Enhancement summary for [project]:

Closed gaps:
  ✅ User entity: added Invalid catalog (12 scenarios, 12 new parametrized tests)
  ✅ User entity: added Edge catalog (5 unicode names, 4 timezone variants)
  ✅ Order entity: refactored 7 test files to use OrderFactory; deleted 23 literal dicts
  ✅ Faker seeded in conftest.py — suite now deterministic

Remaining gaps (documented, not closed):
  ❌ User entity: Stateful — needs domain input on what "reactivation" should test
  ❌ Payment entity: untouched; recommend separate task to cover from scratch
  ❌ invoices.json: 4 entries flagged as possible production leak; awaiting user review

Coverage delta: 47% → 68% line coverage; 31% → 59% branch coverage.

Isolation audit: clean. No production hostnames, real secrets, or PII signatures introduced.

Determinism audit: passed. Suite ran identically across 5 consecutive invocations.
```

This is the closing handoff. The user knows what landed, what's left, and that the work didn't
regress isolation or determinism.
