# Coverage and Gap Analysis

The systematic methodology for finding what isn't tested. Use during Pass 2 of the audit.

Coverage is a multi-dimensional question. Line coverage is the weakest signal. The strongest
signals come from analyzing the *input space*, the *failure space*, and the *behavioral space*
of every public surface.

---

## Coverage Levels (Weakest → Strongest)

| Level | What it measures | Weakness |
|---|---|---|
| Line coverage | Was this line executed? | Says nothing about whether the line was *checked* |
| Branch coverage | Were both sides of each conditional taken? | Still doesn't check assertions |
| Path coverage | Were all paths through the function taken? | Combinatorial; impractical for big functions |
| Condition coverage | Was each boolean sub-expression evaluated both ways? | Useful for complex conditionals |
| MC/DC coverage | (Modified Condition/Decision) Aviation-grade | Overkill for most |
| Mutation score | Do tests catch deliberate code changes? | The real signal — but slow |

**Rule of thumb:** Demand at least branch coverage. Line coverage alone is theater.

**Coverage tools:** coverage.py (Python), Istanbul / nyc (JS), JaCoCo (Java), gcov (C/C++).

---

## The Five Gap-Finding Lenses

Apply all five to every function, endpoint, or component being audited.

### Lens 1: Equivalence Partitioning

Group inputs into classes where the system should behave the same. Test one from each class.

For a function `discount(price, customer_tier)`:
- Price classes: negative, zero, small (<$10), normal, very large (near max float)
- Tier classes: free, paid, premium, unknown, None

That's 5 × 5 = 25 cells. You don't need 25 tests — but you should have at least one for
each *partition*, and the partitions should be documented somewhere.

**Gap finding:** if the test file has 2 tests covering "normal price + paid customer", the
other partitions are gaps. Flag them.

### Lens 2: Boundary Value Analysis

Bugs cluster at boundaries. For every input with a range or limit, test:
- The minimum value
- One below the minimum (should fail)
- The maximum value
- One above the maximum (should fail)
- Zero (if not the minimum)
- The empty case (empty string, empty list, empty dict)
- Null / None

For `paginate(items, page_size)`:
- `page_size = 0` → error?
- `page_size = 1` → single item per page?
- `page_size = len(items)` → exactly one page?
- `page_size = len(items) + 1` → still one page with all items?
- `items = []` → no pages? Empty result?
- `page_size = -1` → error?

**Gap finding:** scan tests for boundary inputs. Count distinct boundary values tested vs. how
many should be. If only "normal" cases are tested, flag every boundary as a gap.

### Lens 3: Error Path Mapping

For every public function, list every `raise` and every error return. Each one needs a test.

Walk the function:
- Every explicit `raise X(...)` — is there a test that triggers it?
- Every `if not X: return None / return error` — is there a test for it?
- Every `try/except` — is there a test for what's caught?
- Every external call — is there a test for what happens when it fails (timeout, exception,
  unexpected response)?

**Gap finding:** if `coverage report` shows the lines inside `except` blocks are uncovered,
those are confirmed gaps. Worse, if the function has no explicit error handling at all but
calls external services, that's an *architectural* gap — what does it do on failure?

### Lens 4: Integration Point Inventory

List every external dependency:
- Database
- Cache
- Message queue
- Third-party API (per API)
- Internal service (per service)
- Filesystem
- Network (DNS, TCP)
- OS / shell calls
- Environment variables / config sources

For each: is there a test that exercises the real interaction OR a high-fidelity fake (e.g.,
testcontainers, localstack, wiremock, vcr cassette)?

**Gap finding:** any integration point with no test (real or fake) is a gap. Mock-only tests
do NOT count — they prove the code calls the mock, not that it works with the real thing.

### Lens 5: State Space and Concurrency

For stateful systems:
- Initial state → expected operation → expected next state. Tested?
- State machines: every transition tested? Every illegal transition rejected?
- Idempotency: calling twice = calling once?
- Concurrency: two parallel calls — race condition? Lost update? Deadlock?
- Retry safety: if the operation fails halfway, can it be retried safely?

**Gap finding:** if the project has a queue, a workflow engine, a database with transactions,
or a distributed lock anywhere, scan for tests that exercise *concurrent* access. Most
projects have none. Flag this.

---

## Functional Gap Worksheet (per function/endpoint)

Use this as a worksheet for any non-trivial public surface:

```
Function: ___________________________

[ ] Happy path tested
[ ] Each documented error path tested
[ ] Empty input (string / list / dict) tested
[ ] None / null input tested
[ ] Boundary values tested (min, max, ±1)
[ ] Invalid type tested
[ ] Each external dependency failure tested
[ ] Concurrency case tested (if applicable)
[ ] Idempotency tested (if applicable)
[ ] Permissions / auth tested (if applicable)
[ ] Logging / observability side-effects tested (if critical)
```

Anything unchecked is a gap. Don't be lenient.

---

## Integration Point Worksheet (per dependency)

```
Dependency: ___________________________ (e.g., PostgreSQL)

[ ] Real instance used in at least one test (testcontainers, etc.)
[ ] Connection failure tested
[ ] Timeout tested
[ ] Permission/auth failure tested
[ ] Schema migration tested (if applicable)
[ ] Transaction rollback tested (if applicable)
[ ] Reconnect / retry tested
```

---

## Regression Gap Analysis

Pull `git log --all --grep="fix\|bug"` (or your project's bug tracker). For each fixed bug:

- Is there a test in the codebase that explicitly references the issue or symptom?
- If not, the bug can return without anyone noticing.

**Output:** a list of "bug → no test" pairs. Each one is a gap with a clear fix.

---

## Coverage Threshold Calibration

Don't set "95% line coverage" as a global rule. Calibrate:

| Code type | Reasonable target |
|---|---|
| Pure business logic / domain core | 90%+ line, 80%+ mutation |
| API / endpoint layer | 85%+ line, integration tests required |
| Adapters / external integrations | 70%+ line, with real-integration tests |
| Glue / config | 50%+ — test the happy path |
| Dead-simple wrappers | Don't bother with line targets — test through them |

A blanket 95% rule causes people to write meaningless tests on glue code to chase the number
while skipping deep tests on critical logic.

---

## The "What Would Catch the Next Bug?" Drill

After running the formal gap analysis, do this exercise:

1. Open the last 5 bug fixes in `git log`.
2. For each, ask: what category of test (unit, integration, property, contract, load, chaos)
   would have caught it earliest?
3. Tally the answers. The most common answer points at the testing category the project is
   weakest in.

Example output:
- 3/5 last bugs: would have been caught by a contract test.
- 1/5: by a property test.
- 1/5: by a soak test.

The recommendation writes itself.
