# Writing High-Quality Tests

Patterns for writing tests that catch real bugs and don't rot over time. Read this when the
task is to *write* tests (vs. review them).

The job is not to add tests — it's to add tests that would catch the next bug. Writing tests
that just exercise the happy path is barely better than not writing them. Every new test
should cover something a *future* change could break.

---

## The Default Test Set for Any Public Function

When a user says "write tests for `do_thing`", produce at least:

1. **Happy path** — typical input → expected output.
2. **Each documented error** — invalid input, wrong type, missing field → expected exception
   or error return.
3. **Each boundary** — empty, None, min, max, ±1.
4. **Each external dependency failure** — if it calls a service/DB/queue, test what happens
   when that fails.
5. **Idempotency / concurrency** — only if applicable, but ask the question.

Stop here only if the function is genuinely simple. For anything with branching, also add
parametrized tests covering the combinations.

---

## Test Naming

A test name should answer "what does this guarantee?" without reading the body.

**Bad:** `test_user`, `test_create_1`, `test_edge_case`.

**Good:**
- `test_create_user_persists_to_database`
- `test_create_user_with_duplicate_email_raises_conflict`
- `test_create_user_with_empty_name_raises_validation_error`
- `test_create_user_emits_created_event`

Pattern: `test_<subject>_<condition>_<expected_outcome>`.

---

## AAA — Arrange / Act / Assert

Every test has three phases, in order, with a blank line between them.

```python
def test_apply_coupon_reduces_total():
    # Arrange
    cart = Cart(items=[Item(price=100)])
    coupon = Coupon(percent_off=10)

    # Act
    result = cart.apply_coupon(coupon)

    # Assert
    assert result.total == 90
```

If a test has two AAAs back-to-back, split it.

---

## Fixtures: Don't Repeat Setup

If two tests share setup, extract a fixture. If two fixtures share data, layer them.

```python
# conftest.py
@pytest.fixture
def user():
    return UserFactory(email="cam@example.com")

@pytest.fixture
def premium_user(user):
    user.tier = "premium"
    return user
```

**Fixture scope:**
- `function` (default) — fresh per test. Safest.
- `module` / `class` — shared. Use only for expensive setup (e.g., DB container).
- `session` — shared across the whole run. Use sparingly.

**Rule:** never use `session` scope for *mutable* data. Recipe for order-dependent tests.

---

## Factories Over Hardcoded Setup

Hardcoded test data leads to copy-paste:
```python
user1 = User(id=1, name="A", email="a@x.com", tier="free", created_at=...)
user2 = User(id=2, name="B", email="b@x.com", tier="free", created_at=...)
```

Factories (factory_boy, model_bakery, FactoryBoy):
```python
class UserFactory(factory.Factory):
    class Meta:
        model = User
    name = factory.Faker("name")
    email = factory.Faker("email")
    tier = "free"

user = UserFactory()  # gets sensible defaults
admin = UserFactory(tier="admin")  # override one field
```

You write the test for *the field that matters*, not for the boilerplate.

---

## Parametrization for Combinations

When the same test logic applies to many inputs, parametrize. Don't copy.

```python
@pytest.mark.parametrize("tier,expected_discount", [
    ("free",    0),
    ("paid",    10),
    ("premium", 20),
    ("vip",     30),
])
def test_discount_by_tier(tier, expected_discount):
    assert discount(tier) == expected_discount
```

For multi-dimensional cases:
```python
@pytest.mark.parametrize("quantity", [1, 10, 100])
@pytest.mark.parametrize("tier", ["free", "paid", "premium"])
def test_pricing(quantity, tier): ...
```

That's 3 × 3 = 9 tests with one function.

---

## Property-Based Testing (hypothesis)

For any function with a wide input space — use property tests instead of guessing examples.

```python
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_sort_is_idempotent(xs):
    assert sorted(sorted(xs)) == sorted(xs)

@given(st.text())
def test_parse_unparse_roundtrip(s):
    assert unparse(parse(s)) == s
```

Hypothesis will find the empty list, the string with embedded null bytes, the integer that
overflows. Example-based tests will not.

**When to demand it:** parsers, validators, serializers, math, anything where you can write a
property that should always hold.

---

## Mocking — When and How

Mock the *boundary*, not the *behavior*.

| Mock these | Don't mock these |
|---|---|
| Third-party HTTP APIs | Your own pure functions |
| External services your team doesn't own | Your own data classes |
| Slow I/O when you have integration tests elsewhere | Database (use a real one in integration tests) |
| The clock (use freezegun) | Standard library |

**Patterns:**

```python
# Mocking a network call
@patch("myapp.api.requests.get")
def test_fetch_user(mock_get):
    mock_get.return_value = Mock(json=lambda: {"id": 1, "name": "Cam"})
    assert fetch_user(1).name == "Cam"
```

```python
# Mocking time
from freezegun import freeze_time
@freeze_time("2026-01-15")
def test_subscription_expiry():
    sub = Subscription(starts="2026-01-01", days=30)
    assert sub.is_active()
```

```python
# In-memory fake instead of mock — usually better
class FakeUserRepo:
    def __init__(self): self.store = {}
    def save(self, u): self.store[u.id] = u
    def get(self, id): return self.store.get(id)

def test_user_service():
    svc = UserService(repo=FakeUserRepo())
    svc.create({"name": "Cam"})
    assert svc.repo.store
```

---

## Testing Asynchronous Code

```python
import pytest

@pytest.mark.asyncio
async def test_fetch_async():
    result = await fetch_user_async(1)
    assert result.id == 1
```

For tests of code that schedules work or waits:
- Never `await asyncio.sleep(2)` — use deterministic event loop control or polling with
  timeout.
- Use `asyncio.wait_for` with strict timeouts so flake fails fast.

---

## Testing Error Paths

For every documented exception, write a test:

```python
def test_create_user_rejects_invalid_email():
    with pytest.raises(ValidationError, match="email"):
        create_user(email="not-an-email")
```

Always match on a property of the error (`match=` regex or `excinfo` attribute), never just
"some exception was raised" — that hides bugs.

---

## Testing Side Effects

Side effects (emits, log lines, metrics, external calls) are part of behavior. Test them.

```python
def test_signup_emits_event(event_bus):
    signup(user="cam")
    assert event_bus.events == [UserSignedUp(user="cam")]
```

For logs, prefer to test the structured event field, not the log string text.

---

## Testing What Was NOT Called

A common gap: code that incorrectly fires a side effect on the wrong branch.

```python
def test_failed_signup_does_not_emit_event(event_bus):
    with pytest.raises(ValidationError):
        signup(user="")
    assert event_bus.events == []
```

---

## Fixtures for External Systems

For databases, queues, etc., prefer **testcontainers** over mocks:

```python
@pytest.fixture(scope="session")
def db():
    with PostgresContainer("postgres:16") as pg:
        engine = create_engine(pg.get_connection_url())
        Base.metadata.create_all(engine)
        yield engine
```

For HTTP services, prefer **wiremock** / **VCR.py** / **respx**:

```python
@pytest.fixture
def mocked_api(httpx_mock):
    httpx_mock.add_response(
        url="https://api.example.com/users/1",
        json={"id": 1, "name": "Cam"},
    )
```

---

## Performance Tests as Regression Guards

Pin the speed of any hot path. pytest-benchmark:

```python
def test_parse_perf(benchmark):
    result = benchmark(parse, LARGE_INPUT)
    assert result is not None
```

Then store the baseline and fail the build on >X% regression.

---

## When You Finish Writing a Test File

Before declaring done, ask:

1. Does every test name describe behavior, not code?
2. Does each test follow AAA with one clear assertion focus?
3. Have I tested errors, boundaries, and edge cases — not just happy paths?
4. Have I run the suite in random order to catch hidden dependencies?
5. Have I run with no network to catch hidden network calls?
6. Have I checked that every test fails when the production code is broken (mutation
   intuition — break the code briefly, does the test catch it)?

If any "no", iterate.

---

## "Tests I Did Not Write" — The Honesty Section

When you write a test file in response to a user request, end the response with a short list
of tests you did *not* write but believe should exist. Examples:

> Tests I did not write but should exist:
> - Integration test against a real Postgres (testcontainers)
> - Load test for `/users` endpoint at expected production RPS
> - Contract test against the upstream `auth-service` API
> - Property test for the input validator (hypothesis)

This honesty is part of the skill. It surfaces gaps the user can choose to fill.
