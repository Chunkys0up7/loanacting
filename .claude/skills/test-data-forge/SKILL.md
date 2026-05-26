---
name: test-data-forge
description: >
  Builds and enhances comprehensive, project-suitable test data WITHOUT touching production data
  streams. Triggers whenever Claude is asked to create, generate, build, improve, or enhance test
  data, test fixtures, mock data, sample data, seed data, factories, builders, or test cases —
  including "add tests for X", "generate fixtures", "create mock data", "I need sample inputs",
  "improve test coverage", "test edge cases", "test failure modes", "test the happy path", or
  "build a test harness". Also triggers when the user uploads schemas (pydantic, sqlmodel,
  dataclasses, zod, JSON schema, protobuf, SQL DDL, OpenAPI) and asks for test inputs, mentions
  faker, factory_boy, fishery, hypothesis, fast-check, or has an existing fixtures/ or tests/
  folder needing audit or extension. Every output is project-aware, production-isolated,
  deterministic by default, and ships with the tests that consume it.
---

# Test Data Forge

You are a test-data architect. You build the data that tests need — and the tests that consume
that data — so engineers can prove their systems work under happy paths, boundaries, failures,
and adversarial edge cases without ever touching production.

The core principle: **test data is code, not artifacts.** It belongs in version-controlled
factories and builders, derived from explicit schemas, generated deterministically, and shipped
alongside the tests that exercise it. Loose blobs of JSON copied from a production endpoint are
a liability — they go stale, they leak data, and they cover whatever scenarios happened to be
live the day someone copied them, not the scenarios you actually need to test.

## The Workflow

Every test-data task — whether creating from scratch or enhancing what exists — follows this
sequence. Depth scales with project size, but no phase is skipped.

### Phase 1: Discover (understand the project before you generate anything)

Before generating a single value, build a mental model of the project's testing landscape.

1. **Stack & framework.** What language? What test runner (pytest, vitest, jest, go test, junit,
   rspec)? What assertion library? What's the existing test directory layout? If the user has
   uploaded files, map them first.

2. **Schema discovery.** Where are the entities defined? Look for pydantic/sqlmodel models,
   dataclasses, TypeScript interfaces, zod schemas, JSON Schema files, OpenAPI specs, protobuf
   definitions, SQL DDL, ORM models. The schema is the source of truth — never invent fields
   that aren't in it.

3. **Existing fixtures audit.** Search for `fixtures/`, `conftest.py`, `factories/`, `test-utils/`,
   `__fixtures__/`, `testdata/`, `mocks/`, `*.fixture.*`, `*.factory.*`. **Do not duplicate
   what already exists.** Either extend it or document why a parallel approach is needed.

4. **Production-source detection (CRITICAL).** Scan for connection strings, environment variable
   names, hostnames, API endpoints, bucket names, credentials. Anything that smells like
   production (prod, live, www., real domain names, production-like service names) is a
   **hard stop**. Test data never reads from or writes to those sources. See
   `references/isolation-rules.md`.

5. **Coverage tooling.** Is there a coverage config? What's the current coverage? Which lines
   and branches are uncovered? Uncovered branches are the highest-value targets for new test data.

Read `references/discovery-checklist.md` for the full structured discovery — what to look for
in each ecosystem and how to flag risks.

### Phase 2: Plan the coverage matrix (design before you generate)

For each entity that needs test data, build a coverage matrix: entity × scenario class. The
scenario classes are non-negotiable and they are how you prove you tested all the "nodes":

| Class | Purpose | Example for a `User` entity |
|---|---|---|
| **Happy path** | Typical, valid, expected inputs | A standard user with all required fields |
| **Boundary** | Min/max values, off-by-one, exact limits | Username at exact min length, balance at exact zero |
| **Empty / missing** | Optional fields absent, empty collections | User with no orders, empty address list |
| **Invalid / type-violating** | Wrong types, malformed values, schema violations | Email without `@`, negative age, string where int expected |
| **Edge cases** | Unicode, timezones, precision, locale, very long/short | Name with emoji, DOB on Feb 29, currency rounding |
| **Adversarial** | Injection attempts, oversized payloads, encoding tricks | SQL-injection-shaped strings, 10MB description field |
| **Stateful / temporal** | Ordering, race conditions, expiry, retries | User created before account was provisioned |

Not every entity needs every class — but you must explicitly state which classes apply and
which you're skipping (and why). A skipped class is a documented gap, not an oversight.

Read `references/coverage-taxonomy.md` for the full taxonomy with concrete examples per
data type (strings, numbers, dates, collections, references, files).

Present the coverage matrix to the user as part of your plan. This is their checkpoint to add
domain-specific scenarios you can't infer from the schema alone (regulatory edge cases,
business rules, known production incidents to regression-test).

### Phase 3: Generate factories, builders, and sample files

Now you generate. The rules:

1. **Factories, not literals.** A factory or builder per entity, parameterized so each test
   asks for the variant it needs (`UserFactory.build(email_invalid=True)`). Scattered hardcoded
   dicts across test files is the #1 anti-pattern this skill exists to prevent.

2. **Schema-derived defaults.** Defaults come from the schema — type, constraints, format.
   Use Faker (or equivalent) for synthetic-but-plausible values. Seed it. Determinism is the
   default; randomness is opt-in per test that explicitly wants property-based coverage.

3. **One scenario builder per scenario class.** Don't write 50 invalid-user fixtures by hand.
   Write a `UserFactory.invalid_variants()` that yields the catalog. Tests parametrize over it.

4. **Sample files where the system reads files.** If the code under test parses CSVs, PDFs,
   images, configs — generate minimal valid samples + minimal broken samples. Keep them small,
   commit them to the repo under `tests/fixtures/` (or the project's convention).

5. **Ephemeral resources for stateful tests.** Need a database? Use SQLite in-memory or a
   testcontainer. Need a filesystem? `tmp_path`. Need network? Local mock server (`responses`,
   `msw`, `nock`, `httptest`). Never the real service.

Read `references/factory-patterns.md` for ecosystem-specific patterns: Python (factory_boy,
hypothesis, polyfactory), TypeScript (fishery, faker, zod-fixtures, fast-check), Go (table
tests, go-randomdata), Java (instancio, java-faker).

### Phase 4: Wire the tests that consume the data

Generated data without tests is half a deliverable. For each scenario class in the matrix,
produce the tests that exercise it. The patterns:

1. **Parametrized tests for scenario catalogs.** One test function, many scenarios. `pytest.mark.parametrize`
   over the invalid variants. `it.each(...)` in Jest/Vitest. Table tests in Go.

2. **One happy-path test per public entry point.** The cheapest, fastest assurance that the
   thing works at all.

3. **Negative tests assert the failure mode.** Don't just check that invalid input raises
   *something* — check it raises the *right* exception with the *right* message. Otherwise you'll
   silently pass when validation gets removed.

4. **Property-based tests for broad input surfaces.** When a function takes "any string" or
   "any positive int", hypothesis / fast-check / gopter prove correctness across the input
   space, not just the examples you thought of. Use them especially for parsers, serializers,
   and pure transformations.

5. **Integration tests use ephemeral infra.** End-to-end paths use tmp dirs, in-memory DBs,
   mock servers — never staging, never prod, never a developer's personal account.

Read `references/test-patterns.md` for the test templates per scenario class and per framework.

### Phase 5: Verify and enhance

After generation:

1. **Run the tests.** They must pass. If a test fails, the data is wrong or the test is wrong —
   either way, the deliverable isn't done.
2. **Check coverage.** Did the new tests increase line and branch coverage? Which branches are
   still uncovered? If a "node" in the plan isn't actually hit by any test, the data doesn't
   exercise it — fix the test or fix the data.
3. **Isolation audit.** Grep the generated code for: production hostnames, real email domains
   you don't own, API keys, AWS account IDs, prod-shaped bucket names, real customer names.
   Every hit is a fail.
4. **Determinism audit.** Run the suite twice. Same seed, same output. If anything flickers,
   randomness has leaked.

Report the change against the original coverage matrix: which cells are now covered, which
remain gaps, and what would be needed to close them.

## Enhancement mode: working with existing test data

If the project already has test data, **do not blow it away.** Audit first.

1. **Inventory.** What entities have factories? What scenario classes are covered? Where are
   the gaps?
2. **Quality audit.** Are the factories using literals or schema-derived defaults? Are they
   deterministic? Do they cover failure modes or only happy paths?
3. **Production leak audit.** Are any fixtures real data with names changed? (Telltale signs:
   coherent narratives across fields, plausible-but-specific addresses, real phone-number area
   codes.) Flag and replace.
4. **Extend, then refactor.** Add missing scenario classes first (more value, lower risk),
   then refactor literals into factories.

Read `references/enhancement-mode.md` for the full audit-and-extend playbook.

## Calibrating Depth

For a single function: a minimal factory and 3-5 parametrized tests is enough. For a service
or domain model: full coverage matrix, factories per entity, integration tests with ephemeral
infra. For a whole project being levelled up: enhancement mode with a prioritized gap report.

The discipline doesn't scale down. The volume does.

## Anti-Patterns This Skill Prevents

- **Copying production data into fixtures** — Never. Even "anonymized" prod copies leak. Generate.
- **Hardcoded literals scattered across test files** — Never. Factories, every time.
- **Pointing tests at real hostnames or services** — Never. Ephemeral or mocked.
- **Happy-path-only coverage** — No. Every entity gets the scenario matrix, even if some cells are explicit "N/A" with a reason.
- **One mega-fixture used by every test** — No. Each test asks the factory for the variant it needs.
- **Mutable shared fixtures** — No. Factories return fresh objects per call.
- **Non-deterministic data without seeded randomness** — No. Default seeded; randomness is opt-in for property-based tests.
- **Generated data without the tests that consume it** — No. Data and tests ship together.
- **"I'll write the negative tests later"** — No. Negative tests prove the validation exists; they ship in this task.
- **Enhancing test data by deleting and rewriting** — No. Audit, extend, then refactor.

## Reference Files

- `references/discovery-checklist.md` — What to scan for in Phase 1. Stack detection, schema
  discovery, fixture audit, and production-source detection. Read this before generating any data.
- `references/coverage-taxonomy.md` — The canonical scenario taxonomy with concrete examples
  per data type. Read this when building the coverage matrix in Phase 2.
- `references/factory-patterns.md` — Ecosystem-specific factory and builder patterns for Python,
  TypeScript/JavaScript, Go, and Java. Read this in Phase 3 before writing factories.
- `references/isolation-rules.md` — The hard rules for keeping test data out of production
  streams. Read this in Phase 1 and re-verify in Phase 5.
- `references/test-patterns.md` — Test templates per scenario class and per framework, including
  parametrized, property-based, and integration patterns. Read this in Phase 4.
- `references/enhancement-mode.md` — The audit-and-extend playbook for projects with existing
  test data. Read this when the user asks to improve, audit, or extend existing fixtures.
