# Discovery Checklist

Read this before generating any test data. Spend 2-5 minutes here — it prevents 30 minutes of
rework and prevents the worst outcome (a test that hits real production).

## 1. Stack & Framework Detection

Identify the language and test framework before anything else. The factory and test patterns
diverge significantly by ecosystem.

### Python
- **Test runner:** Look for `pytest.ini`, `pyproject.toml` `[tool.pytest.ini_options]`, `tox.ini`,
  `setup.cfg` `[tool:pytest]`, or a `conftest.py`. Default to pytest unless you see unittest-style
  `class TestX(unittest.TestCase)` files.
- **Assertion style:** pytest plain asserts? unittest `self.assertEqual`? `assertpy`?
- **Existing helpers:** `conftest.py` files (note their location — they set the scope for fixtures).

### TypeScript / JavaScript
- **Test runner:** `package.json` `scripts.test`, `vitest.config.*`, `jest.config.*`, `playwright.config.*`,
  `karma.conf.*`. Vitest and Jest have very similar APIs but different mocking semantics.
- **Module system:** ESM vs. CommonJS — affects how factories are imported.
- **Existing helpers:** `test/setup.*`, `tests/__helpers__/`, `__mocks__/`.

### Go
- **Test runner:** Always `go test`. Look for `_test.go` files alongside source files.
- **Table-test style:** Standard pattern — check the existing convention before introducing
  a fixture-generation library.

### Java / Kotlin
- **Test runner:** JUnit 4 vs JUnit 5 vs TestNG vs Spock. Check `pom.xml` or `build.gradle`.
- **Assertion library:** AssertJ, Hamcrest, Truth.

### Other signals
- CI config (`.github/workflows/`, `.gitlab-ci.yml`, etc.) often reveals which test commands are
  blessed and which directories CI expects to find tests in.

## 2. Schema Discovery — Find the Source of Truth

Test data MUST be derived from the schema, not invented. Locate the schema before generating.

### Python
- **Pydantic models:** `class X(BaseModel):` — fields, validators, constraints all readable.
- **SQLModel / SQLAlchemy:** `class X(SQLModel, table=True):` or `class X(Base):`.
- **dataclasses / attrs / msgspec:** `@dataclass`, `@attrs.define`.
- **TypedDict:** When dicts are the contract.
- **JSON Schema / OpenAPI:** Often in `schemas/`, `openapi.yaml`, `*.schema.json`.

### TypeScript
- **Interfaces / types:** Explicit `interface X` or `type X = { ... }`.
- **Zod / Yup / io-ts / Valibot:** Runtime schemas — best source because they include constraints.
- **GraphQL schemas:** `.graphql` files or generated `schema.ts`.
- **tRPC routers:** Input/output schemas are zod-typed.

### Go
- **Structs with tags:** `type User struct { Email string \`json:"email" validate:"email"\` }`.
- **protobuf:** `.proto` files; generated Go types follow.

### Universal
- **OpenAPI / Swagger:** `openapi.yaml`, `swagger.json` — full request/response shapes.
- **SQL DDL:** `migrations/`, `schema.sql` — column types, nullability, constraints.
- **protobuf:** `.proto` files — strict typing, optional/required, repeated.
- **JSON Schema:** Often co-located with config or API contracts.

If you cannot find a schema, ask the user to point you to one — or to confirm that the
schema-of-record is the code itself (in which case, read the validation logic carefully).

## 3. Existing Fixtures Audit — Don't Duplicate

Before generating anything new, find what's already there.

Search for these paths and patterns:
- `tests/fixtures/`, `tests/factories/`, `tests/__fixtures__/`, `tests/data/`, `testdata/`
- `conftest.py` files at every level — `pytest` fixtures cascade
- `**/factories/*.py`, `**/factories/*.ts`, `**/*.factory.ts`, `**/*.factory.py`
- `__mocks__/` folders (JS), `mocks/` folders (any)
- `**/*.fixture.*` files
- `fixtures.json`, `seed.json`, `test_data.json` at the repo root or in `tests/`
- Storybook stories (`*.stories.tsx`) — sometimes the most realistic UI fixtures live here

For each existing fixture or factory, note:
- **What entity** it represents
- **What scenarios** it covers (only happy path? variants? failure cases?)
- **What style** it uses (literal dict, builder, factory_boy, faker, hand-rolled)
- **Whether it's used** — orphaned fixtures are a sign of churn; don't extend dead code

Then in Phase 3, the rule is: **extend if compatible, parallel if incompatible, replace only
if the user asks**. Never silently delete existing test data.

## 4. Production Source Detection — The Hard Stop

This is the most important step in this checklist. **Test data and tests must never touch
production data streams.** Scan for any of the following before writing a single line of test code:

### Connection strings & URLs
- Hostnames containing `prod`, `production`, `live`, `live-`, real customer-facing domains
- Database URLs pointing to anything other than `localhost`, `127.0.0.1`, `*.local`, or known
  test instances (`*-test`, `*-dev`, `*.testing.`, sandbox subdomains)
- API base URLs that are the actual production API (e.g., `api.acme.com`) rather than
  documented sandbox endpoints
- S3/GCS/Azure bucket names that look like production (`acme-customer-data`, `prod-uploads`)

### Credentials
- Real-looking API keys committed anywhere (not just `.env` — sometimes they leak into fixtures)
- AWS/GCP/Azure account IDs in fixtures or test config
- OAuth client IDs that match production apps
- Anything matching common secret patterns: `sk_live_*`, `AKIA*`, GitHub tokens, Stripe live keys

### Customer data signatures
- Files named like `users_export.csv`, `customers_backup.json`, `prod_dump.sql` — even if
  "anonymized," these are a red flag and should be replaced with synthesized data
- Fixtures with internally-consistent narratives across many fields (real Jane Smith at
  real address with real phone matching the real area code is almost certainly real Jane Smith)
- PII-shaped data in repository history (`git log -p` containing email addresses, SSNs, card
  numbers)

### What to do when you find these

1. **Stop generating.** Report the find to the user explicitly. Quote the line and file.
2. **Ask before continuing.** Confirm with the user whether the source is actually production
   or a test instance with a confusing name.
3. **If production:** propose a synthesized replacement. Generate equivalent shape, plausible
   values, but unmistakably synthetic (use clearly-fake domains like `example.com`, names from
   the public-domain "test names" list, etc.).
4. **Never auto-fix.** A connection string change is the user's call, not yours.

See `references/isolation-rules.md` for the canonical safe-domain and safe-data lists.

## 5. Coverage Tooling

If the project has coverage configured, the uncovered branches are your highest-priority targets.

- **Python:** `.coveragerc`, `pyproject.toml` `[tool.coverage.*]`. Run `pytest --cov` to see
  current state.
- **JS/TS:** `vitest --coverage`, `jest --coverage`. Config in `vitest.config.*` or `jest.config.*`.
- **Go:** `go test -cover ./...`.

If there's no coverage tooling, that's fine — but flag it as a gap. Coverage doesn't prove
correctness, but lack of coverage proves a lack of tests, which is what you're here to fix.

## 6. The Discovery Report

Before moving to Phase 2, produce a brief discovery report for the user:

```
Stack: Python / pytest 8.x / pydantic v2
Schemas found: User (pydantic), Order (SQLModel), Invoice (dataclass)
Existing fixtures: tests/factories/user.py (factory_boy, happy-path only)
                   conftest.py at repo root (db fixture, seeded SQLite)
Production sources detected: NONE  [or list them]
Coverage tooling: pytest-cov configured; current coverage 47%
Highest-value gaps: User validation branches (8 uncovered), Order.cancel() error paths (5 uncovered)
```

This report is the input to Phase 2's coverage matrix. The user sees what you found and can
correct misreads before you generate anything.
