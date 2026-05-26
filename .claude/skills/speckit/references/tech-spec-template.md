# Technical Specification: [FEATURE_NAME]

> **Phase**: Plan (Phase 2 of 4)
> **Purpose**: Define HOW we build what the product spec describes. This document adds technology choices, architecture decisions, data models, API contracts, and integration details. It is the input to `/speckit.plan`.
>
> **Prerequisite**: Product spec (02-product-spec) must pass the spec-to-plan gate (04-spec-to-plan-gate.md) before this document is authored.
>
> **Audience**: AI coding agents and senior engineers
> **Spec Kit command**: `/speckit.plan`
>
> **Constitution reference**: All decisions here must comply with the project constitution (01-constitution). If a decision conflicts with the constitution, the constitution wins — or the constitution must be amended first.

---

## 1. Architecture Overview

### 1.1 System Context

> Where does this feature sit in the broader system? What external systems does it interact with?

```
[Draw the system context — external actors, this system, and adjacent systems]

┌──────────┐     ┌──────────────────┐     ┌──────────────┐
│  [Actor] │────▶│  THIS SYSTEM     │────▶│ [External    │
│          │◀────│                  │◀────│  System]     │
└──────────┘     └──────────────────┘     └──────────────┘
                         │
                         ▼
                 ┌──────────────┐
                 │ [External    │
                 │  System 2]   │
                 └──────────────┘
```

### 1.2 Architecture Pattern

- **Pattern**: [e.g., "Layered monolith", "Microservices", "Event-driven", "CQRS"]
- **Rationale**: [Why this pattern fits the requirements]
- **Key constraint**: [The architecture constraint from the constitution that shaped this decision]

### 1.3 Component Diagram

> Break the system into its major internal components.

```
┌─────────────────────────────────────────────────┐
│                   [SYSTEM NAME]                  │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ [Layer 1]│  │ [Layer 2]│  │ [Layer 3]    │  │
│  │ e.g., API│─▶│ e.g.,    │─▶│ e.g.,        │  │
│  │ Routes   │  │ Services │  │ Data Access  │  │
│  └──────────┘  └──────────┘  └──────────────┘  │
│                                      │           │
│                              ┌───────▼────────┐ │
│                              │ [Data Store]   │ │
│                              └────────────────┘ │
└─────────────────────────────────────────────────┘
```

---

## 2. Technology Decisions

> Every technology choice must reference the constitution's approved stack. If something is not on the approved list, flag it with `[NEEDS APPROVAL]`.

### 2.1 Stack Summary

| Layer | Technology | Version | Constitution §Ref |
|-------|-----------|---------|------------------|
| Language | [e.g., TypeScript] | [e.g., 5.4+] | §3.1 |
| Framework | [e.g., FastAPI] | [e.g., 0.111+] | §3.2 |
| Database | [e.g., PostgreSQL] | [e.g., 15] | §3.3 |
| LLM | [e.g., Claude via Bedrock] | [e.g., claude-sonnet-4-20250514] | §3.3 |
| UI | [e.g., React + Salt DS] | [e.g., 18.3 + Salt 1.x] | §3.2 |
| Testing | [e.g., pytest + Playwright] | [e.g., 7.x + 1.x] | §3.2 |

### 2.2 Architecture Decision Records (ADRs)

> For significant technology choices, document the decision, alternatives considered, and rationale.

#### ADR-001: [DECISION_TITLE]

- **Status**: Accepted
- **Context**: [What situation or constraint drove this decision]
- **Decision**: [What we chose]
- **Alternatives considered**:
  - [Alternative 1] — rejected because [reason]
  - [Alternative 2] — rejected because [reason]
- **Consequences**: [What changes as a result of this decision — both positive and negative]

#### ADR-002: [DECISION_TITLE]

- **Status**: Accepted
- **Context**: [Context]
- **Decision**: [Decision]
- **Alternatives considered**: [Alternatives]
- **Consequences**: [Consequences]

---

## 3. Data Model

> Translate the domain model from the product spec into concrete schemas. Reference entity IDs from the product spec.

### 3.1 Database Schema

```sql
-- Maps to product spec Entity 1
CREATE TABLE [table_name] (
    id          [TYPE] PRIMARY KEY,
    [column]    [TYPE] NOT NULL,
    [column]    [TYPE],
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT [constraint_name] [constraint_definition]
);

-- Maps to product spec Entity 2
CREATE TABLE [table_name] (
    id          [TYPE] PRIMARY KEY,
    [fk_column] [TYPE] NOT NULL REFERENCES [parent_table](id),
    [column]    [TYPE] NOT NULL,
    [column]    [TYPE],
    
    CONSTRAINT [constraint_name] [constraint_definition]
);

-- Indexes
CREATE INDEX idx_[name] ON [table]([column]);
```

### 3.2 Data Validation Rules

| Entity | Field | Validation | Error Message |
|--------|-------|-----------|---------------|
| [Entity] | [field] | [rule, e.g., "required, max 255 chars"] | [user-facing error] |
| [Entity] | [field] | [rule, e.g., "valid email format"] | [user-facing error] |
| [Entity] | [field] | [rule, e.g., "enum: draft, active, archived"] | [user-facing error] |

### 3.3 Migration Strategy

- **Approach**: [e.g., "Incremental migrations via Alembic / Prisma Migrate"]
- **Rollback plan**: [How to reverse a migration]
- **Data seeding**: [What seed data is required for development/testing]

---

## 4. API Contracts

> Define every endpoint the system exposes or consumes. These become the contracts that `/speckit.tasks` breaks into implementation work.

### 4.1 Endpoints

#### `[METHOD] [PATH]` — [PURPOSE]

**Maps to**: FR-[ID] from product spec

| Parameter | Location | Type | Required | Description |
|-----------|----------|------|----------|-------------|
| [param] | [path/query/body/header] | [type] | [yes/no] | [description] |

**Request body** (if applicable):
```json
{
  "[field]": "[type] — [description]",
  "[field]": "[type] — [description]"
}
```

**Response** `[STATUS_CODE]`:
```json
{
  "[field]": "[type] — [description]",
  "[field]": "[type] — [description]"
}
```

**Error responses**:

| Status | Condition | Body |
|--------|----------|------|
| 400 | [When] | `{"error": "[message]"}` |
| 401 | [When] | `{"error": "[message]"}` |
| 404 | [When] | `{"error": "[message]"}` |

#### `[METHOD] [PATH]` — [PURPOSE]

[Repeat the pattern above for each endpoint]

### 4.2 External Service Integrations

> APIs this system consumes. Include authentication, rate limits, and failure modes.

| Service | Endpoint | Auth Method | Rate Limit | Failure Mode |
|---------|----------|-------------|-----------|-------------|
| [Service] | [URL/path] | [e.g., Bearer token] | [e.g., 100/min] | [e.g., "Circuit breaker, retry 3x with exponential backoff"] |

---

## 5. Security Design

> How the security requirements from the product spec (NFRs) are implemented.

### 5.1 Authentication

- **Method**: [e.g., JWT via Authorization header]
- **Token lifetime**: [e.g., 15 minutes access, 7 days refresh]
- **Token source**: [e.g., "Issued by [AUTH_PROVIDER] via OIDC flow"]

### 5.2 Authorization

- **Model**: [e.g., RBAC, ABAC, row-level security]
- **Roles**: [List roles and their permissions]

| Role | Can create | Can read | Can update | Can delete | Can admin |
|------|-----------|---------|-----------|-----------|----------|
| [Role 1] | ✅ | ✅ | ✅ | ❌ | ❌ |
| [Role 2] | ✅ | ✅ | ✅ | ✅ | ✅ |

### 5.3 Data Protection

- **Encryption at rest**: [e.g., AES-256 via RDS encryption]
- **Encryption in transit**: [e.g., TLS 1.3]
- **PII handling**: [e.g., "PII fields are marked with @sensitive decorator and excluded from logging"]

---

## 6. Error Handling & Observability

### 6.1 Error Handling Strategy

- **User-facing errors**: [e.g., "Structured JSON with error code, message, and correlation ID"]
- **Internal errors**: [e.g., "Logged with full stack trace, masked PII, correlation ID"]
- **Retry policy**: [e.g., "Exponential backoff, max 3 retries, circuit breaker at 50% failure rate"]

### 6.2 Logging

- **Format**: [e.g., Structured JSON]
- **Levels**: [e.g., "ERROR for failures, WARN for degradation, INFO for business events, DEBUG for development"]
- **Required fields**: [e.g., "timestamp, correlation_id, service, operation, duration_ms, status"]

### 6.3 Monitoring & Alerting

| Metric | Threshold | Alert Channel |
|--------|----------|--------------|
| [e.g., Error rate] | [e.g., "> 5% over 5 min"] | [e.g., PagerDuty] |
| [e.g., Latency P95] | [e.g., "> 2s over 5 min"] | [e.g., Slack] |
| [e.g., Queue depth] | [e.g., "> 1000 messages"] | [e.g., PagerDuty] |

---

## 7. Testing Strategy

> Maps directly to the success criteria and acceptance criteria in the product spec.

### 7.1 Test Pyramid

| Level | Scope | Framework | Target Coverage |
|-------|-------|-----------|----------------|
| Unit | Individual functions/methods | [e.g., pytest] | [e.g., 80%] |
| Integration | Service-to-service, DB interactions | [e.g., pytest + testcontainers] | [e.g., Key paths] |
| E2E | Full user scenarios | [e.g., Playwright] | [e.g., All P1 user stories] |
| Contract | API contract validation | [e.g., Pact / Schemathesis] | [e.g., All endpoints] |

### 7.2 Test Data

- **Fixtures**: [Where they live, how they're generated]
- **Factories**: [e.g., "Use factory_boy / faker for synthetic test data"]
- **Seed data**: [What's needed for local development]

### 7.3 Critical Test Scenarios

> These map 1:1 to the user scenarios in the product spec (§7).

| Product Spec Scenario | Test Type | What It Validates |
|----------------------|-----------|------------------|
| Scenario 1 (happy path) | E2E | [Full user journey works end to end] |
| Scenario 2 (edge case) | Integration | [System handles boundary condition correctly] |
| Scenario 3 (error path) | Unit + Integration | [Error handling and recovery work correctly] |

---

## 8. File & Module Layout

> Concrete file structure the agent will create. This directly feeds `/speckit.tasks` for file path specifications.

```
[PROJECT_ROOT]/
├── src/
│   ├── [module_1]/
│   │   ├── models.py          # Data models for [domain area]
│   │   ├── service.py         # Business logic for [domain area]
│   │   ├── router.py          # API routes for [domain area]
│   │   └── schemas.py         # Request/response schemas
│   ├── [module_2]/
│   │   ├── models.py
│   │   ├── service.py
│   │   ├── router.py
│   │   └── schemas.py
│   ├── core/
│   │   ├── config.py          # Configuration management
│   │   ├── auth.py            # Authentication middleware
│   │   ├── errors.py          # Error handling
│   │   └── logging.py         # Structured logging setup
│   └── main.py                # Application entry point
├── tests/
│   ├── unit/
│   │   ├── test_[module_1]_service.py
│   │   └── test_[module_2]_service.py
│   ├── integration/
│   │   ├── test_[module_1]_api.py
│   │   └── test_[module_2]_api.py
│   ├── e2e/
│   │   └── test_[scenario_1].py
│   ├── conftest.py
│   └── fixtures/
├── migrations/
│   └── versions/
├── docs/
│   └── specs/
└── [CONFIG_FILES]
```

---

## 9. Deployment & Infrastructure

- **Deployment target**: [e.g., ECS Fargate, Lambda, Kubernetes]
- **CI/CD**: [e.g., "GitHub Actions — build → test → deploy on merge to main"]
- **Environment promotion**: [e.g., "dev → staging → prod with manual approval gate"]
- **Feature flags**: [e.g., "LaunchDarkly for gradual rollout"]
- **Rollback**: [e.g., "Blue-green deployment with instant rollback"]

---

## 10. Implementation Phasing

> Suggested order for `/speckit.tasks` to decompose work. Dependencies flow top to bottom.

| Phase | What | Dependencies | Parallel? |
|-------|------|-------------|-----------|
| 0 | Project scaffolding, config, CI setup | None | No |
| 1 | Data models, migrations, seed data | Phase 0 | No |
| 2 | Core services (business logic) | Phase 1 | Yes — per module |
| 3 | API routes and middleware | Phase 2 | Yes — per module |
| 4 | Integration with external services | Phase 3 | Yes — per service |
| 5 | Frontend (if applicable) | Phase 3 (API contracts) | Yes |
| 6 | E2E tests and polish | Phase 3-5 | No |

---

## 11. Open Technical Decisions

> Technical questions that surfaced during planning. These should be resolved before `/speckit.tasks`.

| ID | Decision | Options | Recommendation | Status |
|----|---------|---------|---------------|--------|
| TD-001 | [Decision] | [Option A / Option B] | [Recommendation with rationale] | 🔴 Open |
| TD-002 | [Decision] | [Option A / Option B] | [Recommendation] | 🟢 Decided |

---

## Revision History

| Date | Author | Change |
|------|--------|--------|
| [DATE] | [AUTHOR] | Initial tech spec |
