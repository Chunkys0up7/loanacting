# Factory Patterns

Concrete patterns for building factories and builders, per ecosystem. The principles are the
same everywhere; the syntax differs.

## Universal Principles (apply in every language)

1. **One factory per entity.** Don't bundle multiple entities into one helper.
2. **Schema-derived defaults.** Defaults match the schema's constraints. If the schema says
   `email: EmailStr`, the default is a valid synthetic email — not `"test"`.
3. **Parametrized variants.** The factory exposes the levers a test needs:
   `UserFactory.build(email="...", role="admin")`. Tests pass the dimensions that matter for
   the scenario; everything else falls back to a sensible default.
4. **Scenario builders.** For each non-happy scenario class, expose a named builder:
   `UserFactory.invalid_email_variants()`, `UserFactory.boundary_balances()`. Tests parametrize
   over the catalog.
5. **Seeded randomness.** All synthetic generation runs through a seeded Faker / random. The
   seed lives in `conftest.py` (Python), `setup.ts` (JS), or the test-init function (Go).
6. **Build vs. create.** `build()` returns an in-memory object. `create()` persists it. Keep
   these distinct — many tests need only `build()`.
7. **Fresh per call.** Every call returns a new instance. No shared mutable state.

## Python

### Recommended stack
- **factory_boy** for entity factories
- **Faker** (re-exported via factory_boy as `factory.Faker`) for synthetic values
- **polyfactory** if you're on pydantic v2 and want schema-driven generation for free
- **hypothesis** for property-based tests (Phase 4)

### factory_boy template

```python
# tests/factories/user.py
import factory
from factory import Faker
from myapp.models import User, Role

class UserFactory(factory.Factory):
    class Meta:
        model = User

    id = factory.Sequence(lambda n: n + 1)
    email = Faker("email")
    full_name = Faker("name")
    age = Faker("pyint", min_value=18, max_value=99)
    role = Role.USER
    created_at = Faker("date_time_this_year", tzinfo=None)

    class Params:
        admin = factory.Trait(role=Role.ADMIN)
        minor = factory.Trait(age=factory.Faker("pyint", min_value=0, max_value=17))


# Scenario catalog for the invalid class
INVALID_USER_PAYLOADS = [
    # Each entry is (label, payload, expected_error_substring)
    ("missing_email",        {"full_name": "X", "age": 30},                       "email"),
    ("malformed_email",      {"email": "not-an-email", "full_name": "X", "age": 30}, "email"),
    ("negative_age",         {"email": "a@b.co", "full_name": "X", "age": -1},    "age"),
    ("age_overflow",         {"email": "a@b.co", "full_name": "X", "age": 10**9}, "age"),
    ("wrong_type_age",       {"email": "a@b.co", "full_name": "X", "age": "old"}, "age"),
    ("empty_full_name",      {"email": "a@b.co", "full_name": "",   "age": 30},   "full_name"),
]

BOUNDARY_AGES = [0, 17, 18, 99, 100, 1, -1]

UNICODE_NAMES = ["Zoë", "山田 太郎", "Müller", "🙂 the user", "I̥nve̥rted"]
```

### polyfactory (pydantic v2)

For pydantic models, polyfactory generates from the schema automatically:

```python
# tests/factories/order.py
from polyfactory.factories.pydantic_factory import ModelFactory
from myapp.models import Order

class OrderFactory(ModelFactory[Order]):
    __model__ = Order
    __set_as_default_factory_for_type__ = True
    # Override only the fields where you want non-default behavior
    status = "pending"
```

This gives you valid Orders with no effort. You then add scenario catalogs the same way as above.

### Seeding determinism

In `tests/conftest.py`:

```python
import pytest
from faker import Faker

@pytest.fixture(autouse=True)
def _seed_faker():
    Faker.seed(0)
```

For property-based tests with hypothesis, use the `@settings(derandomize=True)` decorator on
tests where reproducibility matters more than search.

## TypeScript / JavaScript

### Recommended stack
- **fishery** for entity factories (cleanest API)
- **@faker-js/faker** for synthetic values
- **fast-check** for property-based tests (Phase 4)
- **zod-fixture** if you have zod schemas — auto-derives factories from them

### fishery template

```typescript
// tests/factories/user.ts
import { Factory } from "fishery";
import { faker } from "@faker-js/faker";
import type { User } from "../../src/models/user";

export const userFactory = Factory.define<User>(({ sequence, params }) => ({
  id: sequence,
  email: faker.internet.email(),
  fullName: faker.person.fullName(),
  age: faker.number.int({ min: 18, max: 99 }),
  role: "user",
  createdAt: faker.date.recent(),
}));

// Variant factories via .params() or transient state
export const adminUserFactory = userFactory.params({ role: "admin" });

// Scenario catalogs
export const invalidUserPayloads: Array<{
  label: string;
  payload: unknown;
  expectedError: string;
}> = [
  { label: "missing_email", payload: { fullName: "X", age: 30 }, expectedError: "email" },
  { label: "malformed_email", payload: { email: "not-an-email", fullName: "X", age: 30 }, expectedError: "email" },
  { label: "negative_age", payload: { email: "a@b.co", fullName: "X", age: -1 }, expectedError: "age" },
  { label: "empty_full_name", payload: { email: "a@b.co", fullName: "", age: 30 }, expectedError: "fullName" },
];

export const boundaryAges = [0, 17, 18, 99, 100, 1, -1];
export const unicodeNames = ["Zoë", "山田 太郎", "Müller", "🙂 the user"];
```

### Seeding determinism

In `tests/setup.ts` (or `vitest.setup.ts`):

```typescript
import { beforeEach } from "vitest";
import { faker } from "@faker-js/faker";

beforeEach(() => {
  faker.seed(0);
});
```

### zod-fixture (when zod is the schema)

```typescript
import { createFixture } from "zod-fixture";
import { UserSchema } from "../../src/schemas/user";

export const buildValidUser = () => createFixture(UserSchema);
```

This gives you valid Users with zero hand-mapping of the schema.

## Go

Go convention is table-driven tests rather than factory libraries. The "factory" is a builder
function; the catalog is a slice of test-case structs.

### Builder template

```go
// internal/users/testdata/builder.go
package testdata

import (
    "time"
    "myapp/internal/users"
)

// UserOpt is a functional option for tweaking a generated User.
type UserOpt func(*users.User)

func WithEmail(email string) UserOpt   { return func(u *users.User) { u.Email = email } }
func WithAge(age int) UserOpt          { return func(u *users.User) { u.Age = age } }
func WithRole(role users.Role) UserOpt { return func(u *users.User) { u.Role = role } }

func BuildUser(opts ...UserOpt) users.User {
    u := users.User{
        ID:        1,
        Email:     "valid@example.com",
        FullName:  "Synthetic User",
        Age:       30,
        Role:      users.RoleUser,
        CreatedAt: time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC),
    }
    for _, opt := range opts {
        opt(&u)
    }
    return u
}

// Scenario catalogs.
type InvalidUserCase struct {
    Label         string
    Payload       map[string]any
    ExpectedError string
}

func InvalidUserPayloads() []InvalidUserCase {
    return []InvalidUserCase{
        {"missing_email", map[string]any{"full_name": "X", "age": 30}, "email"},
        {"malformed_email", map[string]any{"email": "not-an-email", "full_name": "X", "age": 30}, "email"},
        {"negative_age", map[string]any{"email": "a@b.co", "full_name": "X", "age": -1}, "age"},
    }
}

func BoundaryAges() []int { return []int{0, 17, 18, 99, 100, 1, -1} }
```

## Java / Kotlin

### Recommended stack
- **Instancio** for schema-driven entity generation
- **java-faker** or **datafaker** for synthetic values
- **jqwik** for property-based tests (JUnit 5)

### Instancio template

```java
// src/test/java/com/myapp/testdata/UserFactory.java
import org.instancio.Instancio;
import com.myapp.User;

public class UserFactory {
    public static User happy() {
        return Instancio.of(User.class)
            .generate(field(User::getEmail), gen -> gen.net().email())
            .generate(field(User::getAge), gen -> gen.ints().range(18, 99))
            .create();
    }

    public static List<Map<String, Object>> invalidPayloads() { /* ... */ }
}
```

## Sample-File Generation

For tests that consume files (CSV parsers, PDF readers, image processors, config loaders), the
factory generates the file rather than an object.

```python
# tests/factories/csv_files.py
from pathlib import Path

def write_csv(tmp_path: Path, rows: list[dict[str, str]], *, header=True) -> Path:
    if not rows:
        target = tmp_path / "empty.csv"
        target.write_text("" if not header else "id,name,age\n")
        return target
    target = tmp_path / "users.csv"
    keys = list(rows[0].keys())
    lines = []
    if header:
        lines.append(",".join(keys))
    for row in rows:
        lines.append(",".join(row[k] for k in keys))
    target.write_text("\n".join(lines))
    return target

def malformed_csv_files(tmp_path: Path) -> dict[str, Path]:
    """Catalog of broken CSV scenarios. Each tests a specific parser failure mode."""
    files = {}
    files["empty"] = tmp_path / "empty.csv"; files["empty"].write_text("")
    files["header_only"] = tmp_path / "header_only.csv"; files["header_only"].write_text("id,name\n")
    files["unquoted_comma"] = tmp_path / "unquoted_comma.csv"
    files["unquoted_comma"].write_text("id,name\n1,Smith, Jr.\n")
    files["bom"] = tmp_path / "bom.csv"
    files["bom"].write_bytes("\ufeffid,name\n1,Alice\n".encode("utf-8"))
    files["mixed_line_endings"] = tmp_path / "mixed.csv"
    files["mixed_line_endings"].write_bytes(b"id,name\r\n1,Alice\n2,Bob\r3,Carol\n")
    files["unicode"] = tmp_path / "unicode.csv"
    files["unicode"].write_text("id,name\n1,Zoë\n2,山田\n")
    return files
```

## Anti-Patterns to Avoid

- **Building a factory and then duplicating its values in test files.** If the test does
  `user = {"email": "test@test.com", "age": 30}`, the factory isn't being used. Refactor.
- **`UserFactory.build_admin_with_two_orders_and_canceled_subscription()`** — methods that
  bake combinations are unmaintainable. Compose: `UserFactory.build(role=ADMIN)` +
  `OrderFactory.build_batch(2, user=u)` + `SubscriptionFactory.build(user=u, canceled=True)`.
- **Storing fixtures as static JSON files when the data can be generated.** JSON files drift,
  go stale, and lose their relationship to the schema. Use them only when the test specifically
  exercises file I/O.
- **Skipping seeding because "the tests pass anyway."** Until they don't, on the one Tuesday in
  May where Faker generates a string with a backslash that breaks the URL parser. Seed always.
- **One factory function with 15 boolean flags.** Split into traits or composition.
