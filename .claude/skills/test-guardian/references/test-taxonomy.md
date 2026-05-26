# Test Taxonomy

Every category of testing, what it covers, and what it does NOT cover. Use this during Pass 1
(Inventory) to classify what exists, and during Pass 4 to spot categories that are missing.

A healthy project does not need *all* of these — but it needs more than one. A project with
only unit tests is undertested. A project with only integration tests is slow and undertested.
Match the categories to the risk profile of the system.

---

## Functional Tests (does the code do the right thing?)

### Unit Tests
- **Scope:** A single function, method, or class in isolation.
- **Dependencies:** Mocked or stubbed.
- **Speed:** <100ms each. The full suite should run in seconds.
- **What they catch:** Logic bugs, branch errors, off-by-one, type errors.
- **What they DON'T catch:** Integration issues, wiring bugs, config bugs, real I/O failures.
- **Tools:** pytest, unittest, jest, junit.
- **Smell:** If a "unit test" needs a database or network, it's not a unit test.

### Integration Tests
- **Scope:** Multiple components working together — often crossing process or library
  boundaries.
- **Dependencies:** Real where it matters (real DB, real queue, real HTTP), mocked at the
  edges (third-party APIs).
- **Speed:** Seconds each is acceptable.
- **What they catch:** ORM misconfig, schema mismatches, serialization bugs, wiring bugs,
  config bugs.
- **What they DON'T catch:** Whole-system behavior, user-facing flows, real-world latency.
- **Tools:** pytest with testcontainers, pytest-postgresql, embedded redis, localstack.
- **Critical missing case:** Integration tests that mock the integration. If you mock the DB
  in an "integration test", it's a unit test pretending to be more.

### Contract Tests
- **Scope:** The interface between two services — does what one produces match what the other
  consumes?
- **Speed:** Fast (no real services needed).
- **What they catch:** Breaking API changes, schema drift, missing required fields.
- **Tools:** Pact, schemathesis (for OpenAPI specs), Spring Cloud Contract.
- **When to demand them:** Any service that's called by or calls another service that's owned
  by a different team / deploys independently. Without contract tests, you discover breakage
  in production.

### End-to-End (E2E) Tests
- **Scope:** Full system, user-facing, top to bottom.
- **Dependencies:** Real everything (or as close as possible).
- **Speed:** Slow — seconds to minutes each.
- **What they catch:** Things that work in isolation but break together; user journey
  correctness.
- **What they DON'T catch:** Specific component bugs (you can't tell *where* it broke easily).
- **Tools:** Playwright, Cypress, Selenium for web; pytest with full Docker Compose stack for
  backend.
- **Rule:** Keep these few and meaningful. 1-2 dozen for a typical service. If you have 500
  E2E tests, your test pyramid is upside down.

### Smoke Tests
- **Scope:** A handful of critical paths that prove the system is alive.
- **Run:** After every deploy, before promotion to the next environment.
- **What they catch:** Catastrophic regressions, broken deploys.
- **Tools:** Same as E2E but a tiny subset.

### Regression Tests
- **Scope:** Specific past bugs.
- **Rule:** Every fixed bug must have a test that would have caught it. If a bug is fixed
  without a regression test, the same bug will return.
- **Where they live:** Same suite as unit/integration — but identifiable (e.g., `test_regression_*`
  or referenced to an issue number).

### Snapshot Tests
- **Scope:** Output matches a stored snapshot.
- **Useful for:** UI component output, generated documents, serialized payloads.
- **Risk:** Snapshots can be updated without thought — "rubber-stamp" updates hide real
  regressions. Require a human to review every snapshot diff.

### Property-Based Tests
- **Scope:** Properties that hold across a generated input space.
- **Example:** `reverse(reverse(xs)) == xs` for any list `xs`.
- **What they catch:** Whole classes of bugs that example-based tests miss — unicode edge
  cases, integer overflow, empty inputs, weird Nones, ordering issues.
- **Tools:** hypothesis (Python), fast-check (JS), QuickCheck (Haskell), jqwik (Java).
- **When to demand them:** Parsers, validators, serializers, math, anything with a wide input
  space. If a function takes an arbitrary string or arbitrary dict, you need property tests.

### Mutation Tests
- **Scope:** Modify the production code and check if any test fails.
- **What they catch:** Tests that look like they cover code but don't actually assert
  meaningful behavior.
- **Score to watch:** Mutation score. >80% is excellent, <50% means the suite is mostly
  decorative.
- **Tools:** mutmut, cosmic-ray (Python), Stryker (JS/.NET/Scala), PIT (Java).
- **Cost:** Slow. Run weekly in CI, not on every PR.

---

## Non-Functional Tests (does the code do it well enough?)

### Performance / Benchmark Tests
- **Scope:** How fast is this specific function or path?
- **Goal:** Track over time. Fail the build on regression beyond a threshold.
- **Tools:** pytest-benchmark, Google benchmark, hyperfine, ASV (Airspeed Velocity).
- **Anti-pattern:** "It's faster on my laptop" — benchmarks need a stable environment.

### Load Tests
- **Scope:** What happens at expected production load?
- **Question answered:** Can the system handle the traffic it's designed for?
- **Tools:** locust, k6, Gatling, JMeter, Vegeta, wrk.
- **Mandatory metrics:** Throughput (req/s), latency (p50, p95, p99), error rate.

### Stress Tests
- **Scope:** What happens past the expected load? 2x, 5x, 10x?
- **Question answered:** Where does it break and how badly?
- **Goal:** Graceful degradation, not catastrophic failure. If load testing shows 500s at 2x
  capacity but no cascade failure, that's a pass.

### Spike Tests
- **Scope:** Sudden burst from low to very high load.
- **Question answered:** Does autoscaling kick in fast enough? Does the system recover after
  the spike?

### Soak / Endurance Tests
- **Scope:** Sustained moderate load for hours or days.
- **What they catch:** Memory leaks, connection leaks, file descriptor leaks, log/disk
  exhaustion, slow performance degradation.
- **When to demand them:** Long-running services.

### Scalability Tests
- **Scope:** Does adding resources actually increase throughput?
- **Question answered:** With N workers/replicas, do you get ~N× throughput, or do you hit a
  bottleneck (DB connection pool, locks, shared cache)?

### Chaos Tests
- **Scope:** Inject failures into a running system.
- **Examples:** Kill a service, partition the network, slow down DNS, fill the disk.
- **Tools:** Chaos Monkey, Litmus, Gremlin, Pumba, toxiproxy.
- **When to demand them:** Distributed systems claiming high availability. If you have not
  tested the failure modes, the claim is unverified.

### Security Tests
- **Static (SAST):** Code analysis. Tools: bandit, semgrep, CodeQL.
- **Dynamic (DAST):** Run-time analysis. Tools: OWASP ZAP, Burp.
- **Dependency scanning:** pip-audit, Snyk, Dependabot. Mandatory.
- **Fuzz testing:** atheris, hypothesis, AFL for binaries. Required for any parser or
  deserializer.
- **AuthN/AuthZ tests:** Every protected endpoint must have at least one negative test (no
  auth → 401, wrong role → 403).
- **Secret scanning:** gitleaks, trufflehog. Run in CI.

### Accessibility Tests
- **Scope:** UI compliance with WCAG.
- **Tools:** axe, pa11y, Lighthouse CI.
- **When to demand them:** Any user-facing UI. Not optional in 2026.

### Visual Regression Tests
- **Scope:** Pixel-level diff of UI snapshots.
- **Tools:** Percy, Chromatic, BackstopJS, Playwright with screenshot comparison.

---

## Categorization Quick Test

If you can't quickly answer these questions about a project, write the answer down as a
finding and remediate:

1. Does the project have unit tests? Integration tests? E2E tests?
2. What's the test pyramid look like — fat at the bottom, narrow at the top, or inverted?
3. Is there a single load test? A single benchmark?
4. When was the last time anyone ran a mutation test or property-based test?
5. If a third-party API the service depends on changes, would any test fail?
6. If a deploy ships, what runs after to verify it works?

Most projects can answer "yes" to 1, "I don't know" to 2-3, and "never / nothing" to 4-6. That
is the gap.
