# Coverage Taxonomy

The canonical scenario taxonomy. Every entity in the coverage matrix is graded against these
classes. A scenario class is either **covered** (you generate data for it) or **explicitly
skipped with a reason** — never silently omitted.

## The Seven Scenario Classes

### 1. Happy Path

The typical, valid, expected input. The shape of data the system was designed for.

- **Purpose:** Prove the system works at all under normal conditions.
- **Quantity:** Usually one well-formed example per entry point is enough — happy path doesn't
  need combinatorial coverage.
- **Anti-pattern:** Multiple slightly-different happy-path fixtures. Pick one canonical, name
  it clearly, reuse it.

### 2. Boundary

Values at the exact edge of what's valid. The off-by-one zone where most production bugs live.

- **For numbers:** min, max, min-1, max+1, exactly zero, exactly one.
- **For strings:** min length, max length, empty string (when allowed vs. when not).
- **For collections:** empty, one item, exactly-at-limit, one over limit.
- **For dates:** start-of-epoch, end-of-range, leap-year Feb 29, DST transitions, year boundaries.
- **For money:** zero, smallest unit (1 cent), max representable value, negative.
- **Anti-pattern:** Treating "small" and "boundary" as the same thing. `1` is small; the limit
  value `MAX_INT` is boundary. They catch different bugs.

### 3. Empty / Missing

Required fields present but empty; optional fields absent; null where allowed.

- **For each optional field:** at least one fixture with that field absent.
- **For each nullable field:** at least one fixture with that field explicitly null.
- **For collections:** empty list, empty dict, empty set — the system must handle these.
- **For relationships:** entity with no related entities (user with no orders).
- **Anti-pattern:** Conflating `None`, `""`, `[]`, `{}`, and "field absent." They are different
  states and good code distinguishes them. Generate fixtures that distinguish them too.

### 4. Invalid / Type-Violating

Inputs that violate the schema. Used to prove validation works.

- **Wrong types:** string where int expected, list where dict expected.
- **Format violations:** email without `@`, UUID that isn't a UUID, ISO date that isn't ISO.
- **Constraint violations:** age = -5, balance below allowed minimum, length over allowed max.
- **Required fields missing:** every required field, omitted in turn.
- **Extra fields:** when strict mode is enabled, an unexpected field should be rejected.
- **Anti-pattern:** One generic "invalid" fixture. You need one per validation rule, so that
  if validation regresses on a single rule, your tests pinpoint which one.

### 5. Edge Cases

Inputs that are technically valid but unusual. The "I didn't think of that" category.

- **Unicode:** emoji (`👋`), combining characters (`é` as `e + ́`), right-to-left text,
  zero-width characters, surrogate pairs.
- **Casing:** mixed case, all caps, all lowercase, Turkish dotted/dotless `i`.
- **Whitespace:** leading/trailing spaces, tabs, non-breaking spaces, line separators.
- **Numeric precision:** floats near precision limits, `Decimal("0.1") + Decimal("0.2")`,
  negative zero, scientific notation.
- **Timezones:** UTC, half-hour offsets (India, Newfoundland), DST jumps, dates straddling
  midnight in different zones, ambiguous local times during DST fall-back.
- **Locale:** comma vs period decimal separator, different date orderings, plural forms,
  collation differences.
- **Very long / very short:** name with 200 characters, address with one character, description
  with 65535 chars.
- **Special values:** `NaN`, `Infinity`, `-0`, `null` in JSON when the language doesn't distinguish.
- **File edges:** empty file, file with only a BOM, file with trailing newline, file without
  trailing newline, file with mixed line endings.

### 6. Adversarial

Inputs designed to break, exploit, or stress the system. Especially important for anything
that crosses a trust boundary.

- **Injection-shaped strings:** `'; DROP TABLE users; --`, `<script>alert(1)</script>`,
  `../../etc/passwd`, `${jndi:ldap://...}`. Don't try to actually exploit — just prove the
  input is rejected or escaped.
- **Oversized payloads:** 10MB description field, deeply nested JSON (100+ levels),
  arrays with millions of entries.
- **Encoding tricks:** double-encoded URLs, mixed encodings, byte-order marks in unexpected
  places, null bytes in strings.
- **Resource exhaustion:** regex catastrophic backtracking inputs, hash collisions, deeply
  recursive structures.
- **Authentication/authorization:** missing tokens, expired tokens, tokens for the wrong user,
  malformed tokens.

If the system doesn't cross a trust boundary, you can skip adversarial — but document why.

### 7. Stateful / Temporal

Scenarios where the data alone isn't enough — the system's state or the timing matters.

- **Ordering:** event B arrives before event A. Out-of-order delivery.
- **Race conditions:** two writes to the same resource at the same time.
- **Expiry:** token used after expiration, session that just expired mid-request.
- **Retries:** request that succeeded on the second attempt, idempotency key reuse.
- **Eventual consistency:** read after write, but before the write has propagated.
- **Stale references:** entity referenced after the referenced entity was deleted.
- **Time travel:** test running at midnight on Dec 31, scheduled job that fires during DST jump.

For these, the "test data" is partly fixtures and partly a controlled clock/scheduler (e.g.,
`freezegun`, `vi.useFakeTimers()`, `clockwork`).

## Building the Coverage Matrix

For each entity, fill a matrix like this:

| Scenario class | Status | Notes |
|---|---|---|
| Happy path | ✅ Covered | `UserFactory.build()` |
| Boundary | ✅ Covered | min/max length, exactly-zero balance |
| Empty / missing | ✅ Covered | optional fields absent variant |
| Invalid | ⚠️ Partial | covers email format only — missing required-field-omission cases |
| Edge cases | ❌ Gap | no unicode, no timezone variants |
| Adversarial | N/A | User entity is internal — no trust boundary |
| Stateful | ❌ Gap | no test for "user used after soft-delete" |

The matrix is presented to the user before generation. They can:
- Add domain-specific scenarios you can't infer from the schema (regulatory edges, business rules)
- Reclassify "N/A" cells you got wrong
- Prioritize which gaps to close first

## Per-Data-Type Cheat Sheet

When you need to quickly generate the right variants for a field, this is the lookup table:

### String fields
- Happy: a normal value
- Boundary: empty (if allowed), min-length, max-length, max-length + 1
- Edge: unicode, leading/trailing whitespace, mixed case
- Invalid: wrong type (int passed), null (if not nullable)
- Adversarial: injection patterns, oversized

### Integer / float fields
- Happy: a normal positive value
- Boundary: 0, 1, -1, min, max, min-1, max+1
- Edge: very large, very small, NaN/Infinity (float), precision limits
- Invalid: wrong type (string passed), null (if not nullable)
- Adversarial: `MAX_INT * 2` overflow attempts

### Date / datetime fields
- Happy: a recent valid date
- Boundary: epoch, far future, year boundary, month boundary
- Edge: Feb 29 in leap year, DST transitions, half-hour-offset timezones
- Invalid: wrong format, impossible date (Feb 30), wrong type
- Stateful: dates in the future when a past date is required, and vice versa

### Email / URL / UUID / phone (format-validated strings)
- Happy: a well-formed value
- Boundary: shortest possible valid form, longest possible valid form
- Edge: unicode local-part (email), international URL, phone with extension
- Invalid: missing required component (no `@`, no scheme, wrong length)

### Collection fields (list, dict, set)
- Happy: a few items
- Boundary: empty (if allowed), one item, max items, max items + 1
- Edge: duplicates (where uniqueness matters), nested collections
- Invalid: wrong element type, null

### Reference fields (foreign keys, IDs)
- Happy: a valid reference to an existing entity
- Boundary: reference to the first / last created entity
- Edge: reference to a soft-deleted entity, reference to entity created in same transaction
- Invalid: dangling reference (entity doesn't exist), wrong type

### File / blob fields
- Happy: a small valid file of the expected type
- Boundary: empty file, exactly-at-size-limit, exactly-over-size-limit
- Edge: file with BOM, file with unusual line endings, file in unexpected encoding
- Invalid: wrong MIME type, corrupted bytes
- Adversarial: zip bomb, malformed PDF/image headers
