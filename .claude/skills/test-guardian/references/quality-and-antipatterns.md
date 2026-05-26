# Test Quality and Anti-Patterns

The catalog of weak tests. Use during Pass 3 of the audit. Every test in the suite should be
read through this lens; flag any that match, propose a rewrite.

A test that passes but gives no real signal is worse than no test — it provides false
confidence and inflates coverage numbers. Treat these as defects.

---

## Anti-Pattern Catalog

### 1. The Mock Mirror
The test sets up a mock, then asserts the mock was called the way the test set it up. The
production code is barely exercised.

**Smell:**
```python
def test_user_create():
    mock_db = Mock()
    mock_db.insert.return_value = {"id": 1}
    service = UserService(db=mock_db)
    service.create({"name": "Cam"})
    mock_db.insert.assert_called_once()  # ← tests the mock, not the code
```

**Rewrite:** assert on observable behavior — what was inserted, what was returned, what side
effects occurred. Better, use a real (or in-memory) DB:
```python
def test_user_create(db):  # real fixture
    service = UserService(db=db)
    result = service.create({"name": "Cam"})
    assert result.id is not None
    assert db.query(User).filter_by(name="Cam").one() is not None
```

### 2. The Tautology
The test re-implements the function inside the test, then asserts the function equals its own
re-implementation.

**Smell:**
```python
def test_total():
    items = [10, 20, 30]
    expected = sum(items)  # ← same function the code uses
    assert total(items) == expected
```

**Rewrite:** assert against a *constant* expected value:
```python
def test_total():
    assert total([10, 20, 30]) == 60
```

### 3. The Implementation Test
The test asserts internal details — private method calls, internal state — instead of
behavior. Refactor the implementation without changing behavior, and the test breaks.

**Smell:**
```python
def test_processor():
    p = Processor()
    p.run()
    assert p._step_1_called is True
    assert p._step_2_called is True
```

**Rewrite:** assert the public output / observable effect:
```python
def test_processor_produces_expected_output():
    assert Processor().run() == EXPECTED_RESULT
```

### 4. The Sleeping Test
Real-time delays in tests. Slow, flaky, environment-sensitive.

**Smell:**
```python
def test_eventual_consistency():
    submit_job()
    time.sleep(2)  # ← unreliable
    assert job_status() == "done"
```

**Rewrite:** poll with timeout, or use deterministic time control:
```python
def test_eventual_consistency():
    submit_job()
    assert eventually(lambda: job_status() == "done", timeout=10)
```

### 5. The Order-Dependent Test
Test B passes only if test A ran first (shared state, leftover DB rows, global config).

**Diagnostic:** run the suite with `pytest --random-order` (or jest with random sequencer). If
tests fail, you have hidden dependencies.

**Rewrite:** every test creates its own data and cleans up (use fixtures with proper scope).

### 6. The Brittle Assertion
Assertions on exact log strings, exact whitespace, exact error message text, timestamps, UUIDs.

**Smell:**
```python
assert response.body == '{"id":"abc-123","created_at":"2024-01-15T10:00:00Z"}'
```

**Rewrite:** assert on the meaningful parts:
```python
body = json.loads(response.body)
assert body["id"]
assert datetime.fromisoformat(body["created_at"])
```

### 7. The God Test
One test function, fifty assertions, three setup blocks, two phases. When it fails you have no
idea why.

**Rewrite:** split. One behavior per test. Use parametrization for variations.

### 8. The Asserts Nothing
A test that runs code and never asserts. Catches only "does this throw an exception?".

**Smell:**
```python
def test_render():
    render_template("homepage", {"user": "cam"})
    # no assertion
```

**Sometimes valid** (testing that something doesn't raise), but should be explicit:
```python
def test_render_does_not_raise():
    render_template("homepage", {"user": "cam"})  # implicit: no exception
```
Better — assert *what* it produced.

### 9. The Conditional Test
The test contains an `if` block that may or may not assert.

**Smell:**
```python
def test_user_list():
    users = get_users()
    if users:  # ← what if empty?
        assert users[0].name
```

**Rewrite:** set up the precondition you need, then assert without branching.

### 10. The Over-Mocked Test
80% of the test is mock setup. Reading the test tells you about the mocks, not the code.

**Diagnostic:** if removing the mocks would require you to mock 5+ collaborators, the code
under test has too many dependencies — refactor the production code, not the test.

### 11. The Hidden Network Call
A "unit" test makes a real HTTP call, real DNS lookup, real file read. Slow on bad days,
broken when offline.

**Diagnostic:** run tests with network disabled. If anything fails, find the leak.

### 12. The Flaky Test
Passes sometimes, fails sometimes. Almost always one of: time, network, ordering, shared
state, randomness without seed.

**Triage:** quarantine flaky tests immediately. Do not let "rerun on CI" become the workflow —
it normalizes flake.

### 13. The Coverage Filler
A test written purely to cover a line, with weak or no assertions.

**Smell:**
```python
def test_to_dict():
    obj = MyClass(1, 2)
    obj.to_dict()  # covers the line, asserts nothing
```

### 14. The Copy-Paste Family
Twenty tests, all identical except for one value. Should be one parametrized test.

**Rewrite (pytest):**
```python
@pytest.mark.parametrize("input,expected", [
    (1, 2), (2, 4), (3, 6), (4, 8),
])
def test_double(input, expected):
    assert double(input) == expected
```

### 15. The Snapshot Stamp
A snapshot test where snapshots are blindly regenerated whenever they fail. Effectively no
test at all.

**Rule:** require human review of every snapshot diff in PRs. Don't auto-update.

---

## Test Smells Quick Reference

When reviewing a test file, ask:

| Smell | Diagnostic |
|---|---|
| Hard to read | If a teammate can't tell what it tests in 10 seconds, fix the name and structure |
| Long setup | If setup > 10 lines, extract a fixture or factory |
| Many mocks | If > 3 mocks per test, the code is over-coupled |
| Assertion in setup | Means setup is doing work; split |
| Asserts on Mock objects | Almost always wrong; assert on real behavior |
| Multiple AAA cycles | Split into multiple tests |
| Random data without seed | Will eventually find a failing case once and you can't reproduce |

---

## What a Good Test Looks Like

```python
def test_premium_user_gets_20_percent_discount():
    # Arrange
    user = UserFactory(tier="premium")
    cart = CartFactory(subtotal=100)

    # Act
    total = checkout(user, cart)

    # Assert
    assert total == 80
```

Properties of this test:
- **Name describes behavior**, not implementation.
- **One clear AAA structure** (Arrange / Act / Assert).
- **Concrete expected value** (80), not derived.
- **Independent** — uses factories, no shared state.
- **Fast** — no I/O.
- **Robust** — won't break under refactor as long as the behavior holds.

When rewriting weak tests, this is the target.

---

## Reviewing a Test Suite — Sampling Strategy

Don't read 500 tests. Sample:

1. The newest 10 tests (recent quality signal).
2. The oldest 10 tests (legacy debt signal).
3. 10 tests from the most-failing files (where bugs land).
4. The 10 slowest tests (likely have I/O or sleeps).
5. Any test file with `skip` or `xfail` markers (find out why they're disabled — usually
   abandoned tests).

That's ~50 tests, enough to estimate the quality of the suite. Extrapolate, then audit
specific files of concern.
