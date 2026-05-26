# Isolation Rules

The hard rules for keeping test data — and the tests that use it — out of production data
streams. These are non-negotiable. Every rule here exists because someone, somewhere, has
already paid the cost of violating it.

## The Top-Level Rule

**Test code never reads from, writes to, or sends requests to a system that humans use for
real work.** Not "should rarely." Not "with care." Never.

If you find yourself thinking "but it would be easier to just point this test at the real
service," stop. The shortcut is the trap.

## Approved Sources for Test Data

Test data may come from exactly these places:

1. **Schema-derived synthesis.** Generated from the schema by a factory, using seeded Faker
   or equivalent. This is the default.
2. **Committed sample files.** Small, hand-crafted or synthetic files in `tests/fixtures/`
   that exercise specific parsing scenarios. Each file should have a comment explaining what
   scenario it represents.
3. **Recordings from a sandbox/dev environment**, **only** if:
   - The environment is explicitly designated as non-production
   - The recording contains no real user data (verify before saving)
   - The recording is checked in with a note describing its provenance
   - The recording will be regenerated periodically (it can go stale)
4. **The user's explicit, documented dev/test instance** that the user has confirmed is safe
   to use. The user must say so — not the codebase, not a config file.

## Forbidden Sources

Test data must **never** come from:

- Production databases (even for "read-only" queries — schema drift, cardinality leaks, and
  one careless `UPDATE` in test code can corrupt prod)
- Production APIs (even GETs — they cost money, hit rate limits, and leak the test runner's
  identity into prod logs)
- Customer support exports
- "Anonymized" production dumps (anonymization fails more often than it works — see the
  re-identification literature)
- Screenshots, transcripts, or logs containing real user content
- Personal accounts of developers or testers (their data is real too)

## Hostname & URL Patterns

### Safe to use in fixtures and test config

| Pattern | Use for |
|---|---|
| `localhost`, `127.0.0.1`, `::1` | Local services |
| `*.localhost`, `*.local`, `*.test`, `*.example`, `*.invalid` | Reserved by RFC 6761 / RFC 2606 |
| `example.com`, `example.org`, `example.net` | Reserved by IANA for documentation |
| `example.email`, `*@example.com` | Email addresses in fixtures |
| `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24` | RFC 5737 documentation IPs |
| `2001:db8::/32` | RFC 3849 documentation IPv6 |
| `00000000-0000-0000-0000-000000000000` and seeded UUIDs | UUIDs in fixtures |

### Treat as suspicious — verify before using

| Pattern | Why suspicious |
|---|---|
| Any domain you don't own | Might hit real systems; might leak via DNS |
| `*.dev`, `*.app` | These are real TLDs; the subdomain may resolve |
| Real-looking company names (`acme.com`, `widgets.io`) | If these resolve, your test may hit them |
| `staging.*`, `dev.*`, `test.*` of a real production domain | Still hits infrastructure you don't own |

### Hard stops

Any of these in a test file or fixture is a defect:

- Your company's production domain
- Customer domains
- Real third-party API hostnames (`api.stripe.com`, `api.openai.com`, etc.) without a
  documented mock or recording layer in front

## Credentials & Secrets

### Safe

- Obviously-fake placeholders: `sk_test_FAKE_DO_NOT_USE`, `dummy-api-key`, `test-secret-42`
- Test-mode keys from providers that document a test-mode endpoint (Stripe `sk_test_*`, etc.) —
  but only when the test code is also pointing at the test-mode endpoint
- Empty strings or `None` where the test specifically exercises the absent-credential path

### Hard stops

- Any string matching real-secret patterns: `sk_live_*`, `AKIA[0-9A-Z]{16}`, GitHub PAT formats,
  Slack tokens, Stripe live keys, JWTs with real-looking claims
- Connection strings with non-placeholder credentials
- Environment variable names that production also uses (use `TEST_*` prefixes)

If you find a real-looking secret committed to the repo, **stop immediately** and report it to
the user — it may already be exposed and need rotation.

## Customer Data Signatures

Synthetic data, when generated properly, has detectable structure: Faker's outputs have known
distributions and recognizable patterns. Real customer data does not. If you see any of these
patterns in existing fixtures, treat them as production-leak candidates:

- **Internally-consistent narratives across fields.** Real Jane Smith really does live at a
  real address with a phone number whose area code really matches. Faker rarely produces this
  coincidence by accident.
- **Plausible-but-specific addresses.** "742 Evergreen Terrace" is fine; "8347 NE Birchwood Ln,
  Apt 4B, Portland OR 97232" is suspicious.
- **Email addresses on real consumer domains.** `someone@gmail.com`, `someone@yahoo.com`,
  `someone@protonmail.com` — these reach real mailboxes if the local part matches anyone.
  Always use `example.com` and friends instead.
- **Phone numbers in real area codes.** Use the 555-01xx range for North American phones in
  fixtures (reserved for fiction); equivalent reserved ranges exist for other countries.
- **Coherent timestamps clustered around a specific past date.** Real data clusters around
  real events; synthetic data is uniform unless you make it otherwise.
- **Field values that are unusual for synthesis but normal for real users.** Hyphenated names,
  unusual middle initials, apartment numbers in the address line, professional titles.

When in doubt, regenerate from the schema. The cost of regeneration is minutes; the cost of a
leaked PII fixture is hours-to-careers.

## Network Isolation in Tests

Tests that need to exercise networked code should never reach the actual network.

### Python
- `responses` or `respx` for mocking HTTP at the requests/httpx layer
- `pytest-httpx` for httpx
- `vcr.py` for record/replay (only with sandbox endpoints)
- `pytest-socket` to actively forbid network calls in tests — install it and add
  `--disable-socket` to `pytest.ini`; tests that need network are explicit

### TypeScript / JavaScript
- `msw` (Mock Service Worker) — best-in-class for HTTP mocking
- `nock` for older Node code
- `vi.mock()` / `jest.mock()` for module-level mocking

### Go
- `httptest.NewServer` for local test servers
- The `http.RoundTripper` interface for transport-level mocking

The principle: a test that accidentally hits the network during CI is a CI flake waiting to
happen. Treat network access from tests as a defect by default.

## Database Isolation

### Approved patterns
- **In-memory SQLite** for code that's database-agnostic
- **Testcontainers** for code that depends on Postgres/MySQL/Redis specifics — spins up a
  real container, throws it away after the test
- **Schema-per-test or transaction-per-test** in a dedicated test database
- **Embedded test runners** where the framework supports them (e.g., `pg-mem` for Postgres
  in Node tests, with documented limitations)

### Hard stops
- A shared "test" database used by all developers and CI simultaneously — order-dependent
  test failures, mysterious data appearing in test runs
- Pointing tests at a staging database that other systems also write to
- Any test that doesn't clean up after itself in a shared environment

## Filesystem Isolation

- Use the test framework's temp-directory primitive: `tmp_path` in pytest, `tmp.dir()` in Vitest,
  `t.TempDir()` in Go
- Never write to absolute paths in tests (`/tmp/foo.txt`, `~/.config/myapp/`)
- Never read from paths outside the test workspace
- Clean up explicitly even when the temp dir would clean itself — explicit is debuggable

## Time Isolation

Tests that depend on time must control time. The clock is a global production data stream —
treating it as such avoids "tests passed in October, fail in March" surprises.

- **Python:** `freezegun`, `time-machine`, or inject a clock dependency
- **JS/TS:** `vi.useFakeTimers()` / `jest.useFakeTimers()`
- **Go:** clock dependency injection (`benbjohnson/clock` or hand-rolled)

If a test calls `now()` directly without isolation, the data effectively varies with wall-clock
time — that's a leak from production-time into test-time, and it bites eventually.

## The Phase 5 Isolation Audit Checklist

Before declaring the deliverable complete, grep the changes for these red flags:

```
# Hostnames
grep -rEn '(prod|production|live)\.[a-z0-9-]+\.(com|net|org|io|app|dev)' tests/
grep -rEn 'https?://[a-z0-9-]+\.(com|net|org|io|app)/[^"]*' tests/ | grep -v example

# Secrets
grep -rEn '(sk_live_|AKIA[A-Z0-9]{16}|ghp_[A-Za-z0-9]{36}|xox[baprs]-)' tests/
grep -rEn '"[A-Za-z0-9+/]{40,}={0,2}"' tests/   # base64-shaped strings; review each hit

# Real-looking emails
grep -rEn '@(gmail|yahoo|hotmail|outlook|proton(mail)?|icloud)\.com' tests/

# Real-looking phones (NA, outside the 555-0100..0199 range)
grep -rEn '\b\([2-9][0-9]{2}\)\s?[2-9][0-9]{2}-[0-9]{4}\b' tests/

# Personal account giveaways
grep -rEn '(127\.0\.0\.1|localhost):(5432|6379|3306|9200)' tests/ | grep -v conftest
```

Every hit is reviewed. Most will be intentional (`example.com`, `localhost`, seeded UUIDs are
fine). A real production hostname or a real-looking secret is a stop-the-line event.
