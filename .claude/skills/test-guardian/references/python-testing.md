# Python Testing Stack

Python-specific patterns. Read this whenever the project is Python (which is most of the
time). pytest is assumed as the default — `unittest` is acceptable but pytest's fixtures,
parametrization, and plugin ecosystem make it the right default.

---

## Recommended Stack (2025/2026)

| Concern | Tool |
|---|---|
| Test runner | pytest |
| Coverage | pytest-cov (wraps coverage.py) |
| Fixtures / factories | factory_boy or model_bakery |
| HTTP mocking | respx (httpx), requests-mock, or vcrpy for cassettes |
| Database integration | testcontainers-python or pytest-postgresql |
| Async tests | pytest-asyncio |
| Time control | freezegun or time-machine |
| Snapshot tests | syrupy |
| Property tests | hypothesis |
| Mutation tests | mutmut or cosmic-ray |
| Benchmarks | pytest-benchmark |
| Load tests | locust (Python-native) or k6 (better DSL) |
| Test parallelization | pytest-xdist |
| Random test order | pytest-randomly |
| Security: SAST | bandit |
| Security: deps | pip-audit |
| Fuzzing | atheris or hypothesis |

If a project is using `unittest`, `requests-mock` with manual mocks, no factories, no
parametrization, and no coverage tooling — that's a legacy testing setup. Modernizing it
is a worthwhile task.

---

## pytest Project Layout

A clean test layout:
```
repo/
├── src/
│   └── myapp/
│       ├── __init__.py
│       └── ...
├── tests/
│   ├── conftest.py           # shared fixtures
│   ├── unit/
│   │   ├── conftest.py       # unit-only fixtures
│   │   └── test_*.py
│   ├── integration/
│   │   ├── conftest.py       # DB/HTTP fixtures
│   │   └── test_*.py
│   ├── e2e/
│   │   └── test_*.py
│   └── load/
│       └── locustfile.py
├── pyproject.toml
└── pytest.ini  (or in pyproject)
```

**Flag during audit:** `tests/` directory with no subfolders. If unit, integration, and e2e
are interleaved, you can't run a fast feedback loop and can't gate on the slow ones
separately.

---

## pyproject.toml Configuration

```toml
[tool.pytest.ini_options]
minversion = "8.0"
addopts = [
    "-ra",                          # short summary of all non-passes
    "--strict-markers",             # fail on undeclared markers
    "--strict-config",
    "-q",
    "--cov=src/myapp",
    "--cov-branch",
    "--cov-report=term-missing",
    "--cov-fail-under=80",
]
testpaths = ["tests"]
markers = [
    "slow: tests that take >1s",
    "integration: requires external services",
    "e2e: full-system tests",
    "load: load/perf tests; not run on every commit",
]

[tool.coverage.run]
branch = true
source = ["src/myapp"]
omit = ["tests/*", "*/__main__.py"]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
    "if TYPE_CHECKING:",
]
```

**Flag during audit:** no `--cov-fail-under` means coverage can silently fall. No
`--strict-markers` means typos in `@pytest.mark.xxx` are silently ignored.

---

## conftest.py Patterns

```python
# tests/conftest.py — shared across all tests
import pytest

@pytest.fixture
def freezer(freezer):
    """Convenience wrapper around freezegun."""
    return freezer

# tests/integration/conftest.py — integration only
import pytest
from testcontainers.postgres import PostgresContainer

@pytest.fixture(scope="session")
def postgres():
    with PostgresContainer("postgres:16-alpine") as pg:
        yield pg

@pytest.fixture
def db(postgres):
    """Fresh DB per test, fast via transactions."""
    engine = create_engine(postgres.get_connection_url())
    conn = engine.connect()
    trans = conn.begin()
    yield conn
    trans.rollback()
    conn.close()
```

**Anti-pattern:** putting database fixtures in the top-level `conftest.py`. Then "unit" tests
spin up a DB they don't need. Scope conftest by directory.

---

## Parametrization (pytest)

Single dimension:
```python
@pytest.mark.parametrize("input,expected", [
    ("",      0),
    ("a",     1),
    ("hello", 5),
    pytest.param("🐍", 1, id="emoji_single_codepoint"),
])
def test_length(input, expected):
    assert custom_len(input) == expected
```

Multiple dimensions (combinatorial — use sparingly):
```python
@pytest.mark.parametrize("tier", ["free", "paid", "premium"])
@pytest.mark.parametrize("quantity", [1, 10, 100])
def test_pricing(tier, quantity): ...
```

`pytest.param(..., id="...")` gives readable failure IDs.

---

## hypothesis Patterns

Property test:
```python
from hypothesis import given, strategies as st, assume, settings

@given(xs=st.lists(st.integers()))
def test_sort_idempotent(xs):
    assert sorted(sorted(xs)) == sorted(xs)

@given(s=st.text())
@settings(max_examples=500)
def test_parse_roundtrip(s):
    assume(is_valid(s))
    assert unparse(parse(s)) == s
```

Stateful test for stateful systems:
```python
from hypothesis.stateful import RuleBasedStateMachine, rule

class CartStateMachine(RuleBasedStateMachine):
    def __init__(self):
        super().__init__()
        self.cart = Cart()
        self.expected_total = 0

    @rule(price=st.integers(min_value=0, max_value=1000))
    def add(self, price):
        self.cart.add(Item(price))
        self.expected_total += price

    @rule()
    def check(self):
        assert self.cart.total == self.expected_total

TestCart = CartStateMachine.TestCase
```

Hypothesis finds the empty list, the string with embedded `\x00`, and the integer that's one
past the boundary. Example tests will not.

---

## Async Tests (pytest-asyncio)

```python
import pytest

@pytest.mark.asyncio
async def test_fetch():
    result = await fetch_user(1)
    assert result.id == 1

@pytest.fixture
async def client():
    async with AsyncClient(base_url="http://test") as c:
        yield c
```

Config:
```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"  # or "strict"
```

**Flag during audit:** mixing sync and async tests with `asyncio.run()` calls inside sync
tests. Use pytest-asyncio properly.

---

## Time Control

```python
from freezegun import freeze_time

@freeze_time("2026-01-15 10:00:00")
def test_subscription_expiry():
    sub = Subscription(start=datetime.now(), days=30)
    assert sub.expires_at == datetime(2026, 2, 14, 10)
```

`time-machine` is a faster modern alternative.

**Anti-pattern flagged in audit:** tests that compare against `datetime.now()` without
freezing time. They'll fail at midnight, on Feb 29, or when run slow on CI.

---

## HTTP Mocking

For `httpx`:
```python
def test_fetch(httpx_mock):  # respx fixture
    httpx_mock.add_response(
        url="https://api.example.com/users/1",
        json={"id": 1, "name": "Cam"},
    )
    user = fetch_user(1)
    assert user.name == "Cam"
```

For `requests`:
```python
def test_fetch(requests_mock):
    requests_mock.get("https://api.example.com/users/1", json={"id": 1, "name": "Cam"})
    user = fetch_user(1)
    assert user.name == "Cam"
```

For complex flows, **VCR cassettes** — record a real interaction once, replay it:
```python
@pytest.mark.vcr()
def test_signup_flow():
    # First run: records to tests/cassettes/test_signup_flow.yaml
    # Subsequent runs: replays
    ...
```

VCR is great for testing against complex third-party APIs without maintaining hand-written
mocks. Re-record when the upstream changes.

---

## Factories

```python
# tests/factories.py
import factory
from myapp.models import User, Order

class UserFactory(factory.Factory):
    class Meta:
        model = User
    id = factory.Sequence(lambda n: n)
    name = factory.Faker("name")
    email = factory.LazyAttribute(lambda u: f"{u.name.lower().replace(' ', '.')}@x.com")
    tier = "free"

class PremiumUserFactory(UserFactory):
    tier = "premium"

class OrderFactory(factory.Factory):
    class Meta:
        model = Order
    user = factory.SubFactory(UserFactory)
    total = factory.Faker("pydecimal", left_digits=3, right_digits=2, positive=True)
```

Usage:
```python
def test_order():
    order = OrderFactory(user__tier="premium")
    assert order.discount > 0
```

---

## Coverage Configuration That Actually Helps

```toml
[tool.coverage.run]
branch = true                    # not just line coverage
source = ["src/myapp"]
parallel = true                  # for pytest-xdist runs

[tool.coverage.report]
fail_under = 80
show_missing = true              # show line numbers of uncovered code
skip_covered = true              # focus on what's missing
exclude_lines = [
    "pragma: no cover",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
    "if TYPE_CHECKING:",
    "@(abc\\.)?abstractmethod",
]
```

Run:
```bash
pytest --cov --cov-branch --cov-report=html
open htmlcov/index.html
```

The HTML report is where you find the *uncovered branches* — usually error paths.

---

## Running Tests in Random Order

Add `pytest-randomly`. It will:
- Run tests in a random order
- Catch order-dependent tests
- Seed random.random() / numpy with a fixed value per test

```bash
pytest -p randomly
```

If tests fail under random ordering, you have hidden dependencies. Always flag this.

---

## Mutation Testing

```bash
mutmut run --paths-to-mutate src/myapp
mutmut results
```

Look at the surviving mutants. Each one is a code change your tests didn't catch.

Run weekly in CI, not per commit (slow). The signal is "is our test suite catching real
changes?" — answered by mutation score, not coverage percent.

---

## CI Integration

A baseline pipeline:
```yaml
- pytest --cov-fail-under=80 -m "not slow and not integration"
- pytest -m integration
- pytest -m e2e
- bandit -r src/
- pip-audit
- pytest-benchmark compare --fail=mean:10%  # only on hot-path benchmarks
```

Each step is a gate. If any are missing, that's a finding.

---

## Common Python Test Audit Findings

1. **No `conftest.py`** → fixtures get re-defined per file, drift across the suite.
2. **No `pytest.ini` / `pyproject` test config** → no markers, no coverage gate, no strict
   mode.
3. **`unittest.TestCase` with pytest** — works but you lose fixtures, parametrize, plugins.
4. **Mocks for the database in "integration" tests** — that's a unit test in disguise.
5. **`time.sleep` in tests** — flaky.
6. **`datetime.now()` in assertions without freezegun** — flaky.
7. **No `--cov-fail-under`** → coverage can collapse silently.
8. **No `pytest-randomly`** → hidden order dependencies invisible.
9. **No hypothesis** → wide-input functions are tested with 3 examples.
10. **No `pytest-benchmark`** → no protection against performance regression.
11. **No `pip-audit` / `bandit` in CI** → vulnerable deps and obvious security smells go in
    unobserved.

Almost every Python project audit will turn up 4-6 of these. They are standard findings.
