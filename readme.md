# Project Y — CRM + PMBOK Project Management

## Architecture Diagram

The full architecture diagram is in [docs/architecture.puml](docs/architecture.puml).

| Tool | How |
|------|-----|
| Docker | `docker run --rm -v "$(pwd)/docs:/data" plantuml/plantuml /data/architecture.puml` (Bash) |
| Docker (PowerShell) | `docker run --rm -v "${PWD}/docs:/data" plantuml/plantuml /data/architecture.puml` |
| VS Code | Install [PlantUML extension](https://marketplace.visualstudio.com/items?itemName=jebbs.plantuml), open the file, press `Alt+D` |
| Online | Paste into [plantuml.com/plantuml](https://www.plantuml.com/plantuml/uml/) |

![Architecture](docs/architecture.png)

## Database Schema Diagram

The full entity-relationship diagram (all services, all tables, with design notes) is in [docs/database.puml](docs/database.puml).
Each table group includes inline annotations explaining **what** the table represents and **why** it is designed that way.

Render the same way as the architecture diagram:

```powershell
# PowerShell
docker run --rm -v "${PWD}/docs:/data" plantuml/plantuml /data/database.puml
# Bash
docker run --rm -v "$(pwd)/docs:/data" plantuml/plantuml /data/database.puml
```

![Database schema](docs/database.png)

---

## Services

| Service | Role |
|---------|------|
| **Gateway** | Single public entry point on `:8080`. Routes all traffic, enforces per-user rate limiting (5 req/sec via Bucket4j), publishes every `/api/*` request to RabbitMQ. |
| **Customer** | REST API for customer records. Requires a valid JWT. |
| **Accounts** | REST API for CRM accounts. |
| **Contacts** | REST API for contacts linked to accounts. |
| **Opportunities** | REST API for opportunities with stage-transition workflow. |
| **Activities** | REST API for activities linked to opportunities. |
| **Projects** | PMBOK-aligned project management service (`:8085`). Manages projects, charters, WBS, tasks, baselines, deliverables, change requests, and status reports. Uses per-project role assignments stored in `projectsdb`. |
| **Config Server** | Spring Cloud Config Server (`:8888`). Serves centralised `application.properties` to all services at startup; classpath/native backend. |
| **Keycloak** | Identity provider. Issues JWTs, manages the `crm` realm, roles (`crm_admin`, `crm_sales`). |
| **RabbitMQ** | Message broker. Decouples gateway from log writing via the `request-logs` queue. |
| **Log Consumer** | Listens to `request-logs` and writes each request (method, path, status, duration, username) to the logs DB. |
| **PostgreSQL (main)** | Shared DB for Customer, Accounts, Contacts, Opportunities, Activities (`maindb`, `accountsdb`, …). |
| **PostgreSQL (keycloak)** | Dedicated DB for Keycloak's internal state. |
| **PostgreSQL (logsdb)** | Dedicated DB for the request audit log. |

### Traffic flow

```
Browser / Postman / curl
        │
        ▼
  localhost:8080  (Gateway)
        │
        ├── /auth/**                       ──►  Keycloak :8080
        ├── /api/accounts/*/contacts/**    ──►  Contacts :8082
        ├── /api/accounts/**               ──►  Accounts :8081
        ├── /api/opportunities/*/activities/** ──► Activities :8084
        ├── /api/opportunities/**          ──►  Opportunities :8083
        ├── /api/projects/**               ──►  Projects :8085
        └── /api/customers/**             ──►  Customer :8080
                               │
                          GlobalFilter (all /api/* requests)
                          rate-limit 5 req/s · publish to RabbitMQ
                               │
                          Log Consumer ──► logsdb
```

### Test users (both environments)

| Username | Password | Role |
|----------|----------|------|
| `testuser` | `testpassword` | `crm_sales` |
| `testuser2` | `testpassword2` | `crm_sales` |

Get a JWT:
```
POST http://localhost:8080/auth/realms/crm/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=password&client_id=crm-api&username=testuser&password=testpassword
```

---

## Authentication

### How It Works

Every API endpoint (except `/actuator/health/**` and `/swagger-ui/**`) requires a Keycloak JWT in the `Authorization: Bearer <token>` header. The gateway does **not** validate tokens — each downstream service independently validates the JWT as an OAuth2 Resource Server, keeping auth logic self-contained per service.

### JWT Validation

Services use `jwk-set-uri` (not `issuer-uri`) to validate tokens:

```
spring.security.oauth2.resourceserver.jwt.jwk-set-uri=
  http://keycloak:8080/auth/realms/crm/protocol/openid-connect/certs
```

**Why `jwk-set-uri` not `issuer-uri`:** Keycloak issues tokens with `iss: http://localhost:8080/auth/realms/crm` (external URL) but services resolve Keycloak internally as `http://keycloak:8080`. `issuer-uri` would validate the issuer claim against the internal discovery endpoint and fail due to the hostname mismatch. `jwk-set-uri` skips issuer verification and validates only the signature.

### Role Extraction

Each service's `SecurityConfig` registers a `JwtAuthenticationConverter` that maps Keycloak's `realm_access.roles` claim to Spring Security `GrantedAuthority` objects:

```java
// JWT claim from Keycloak:
// { "realm_access": { "roles": ["crm_admin", "crm_sales", ...] } }

converter.setJwtGrantedAuthoritiesConverter(jwt -> {
    Map<String, Object> realmAccess = jwt.getClaim("realm_access");
    if (realmAccess != null && realmAccess.get("roles") instanceof List<?> roles) {
        for (Object r : roles) {
            authorities.add(new SimpleGrantedAuthority("ROLE_" + r));
        }
    }
    return authorities;
});
```

Keycloak role → Spring Security authority:
- `crm_admin` → `ROLE_crm_admin`
- `crm_sales` → `ROLE_crm_sales`

### Resource-Based Access Control

| Role        | Access                                                          |
|-------------|-----------------------------------------------------------------|
| `crm_admin` | Full access to all resources regardless of ownership           |
| `crm_sales` | Only resources where the record's `ownerId` equals `token.sub` |

`ownerId` is always set server-side from the JWT `sub` claim at creation time — clients cannot supply or override it.

Access is enforced via the `@perm` Spring bean (`PermissionService`) using `@PreAuthorize`:

```java
@GetMapping("/{id}")
@PreAuthorize("@perm.canAccess(#id, authentication)")
public ResponseEntity<Account> get(@PathVariable UUID id) { ... }
```

`PermissionService.canAccess()` logic:

```java
public boolean canAccess(UUID id, Authentication auth) {
    if (isAdmin(auth)) return true;                              // crm_admin bypasses ownership check
    String sub = ((Jwt) auth.getPrincipal()).getSubject();       // caller's Keycloak user UUID
    return repository.findById(id)
            .map(resource -> resource.getOwnerId().equals(sub))
            .orElse(false);
}

private boolean isAdmin(Authentication auth) {
    return auth.getAuthorities().stream()
            .anyMatch(a -> a.getAuthority().equals("ROLE_crm_admin"));
}
```

Non-owners receive `HTTP 403`. Non-existent resources return `false` from the check, which also yields `HTTP 403` (not 404 — avoids leaking existence of records to unauthorised callers).

---

## Business Rules

### Opportunity Stage Workflow

Opportunities move through a linear pipeline. Transitions are **forward-only**; skipping stages is not allowed. Any stage can transition directly to `LOST`.

```
PROSPECT → QUALIFY → PROPOSE → NEGOTIATE → WON
    ↓          ↓         ↓          ↓
   LOST      LOST      LOST       LOST
```

`WON` and `LOST` are terminal — no further transitions are permitted.

Enforced in `OpportunityStage.allowedTransitions()` and checked in `OpportunityController.updateStage()` before any save:

```java
if (!stageTransitionService.isAllowed(existing.getStage(), newStage)) {
    return ResponseEntity.badRequest()
            .body("Transition from " + existing.getStage() + " to " + newStage + " is not allowed");
}
```

Invalid transition → `HTTP 400`.

Endpoint: `PATCH /api/opportunities/{id}/stage` with body `{ "stage": "PROPOSE" }`.

### WON Gate Validation

Before moving to `WON`, both `amount` and `closeDate` must be set on the opportunity:

```java
if (newStage == OpportunityStage.WON
        && (existing.getAmount() == null || existing.getCloseDate() == null)) {
    return ResponseEntity.badRequest()
            .body("Transitioning to WON requires amount and closeDate to be set");
}
```

Returns `HTTP 400` if either field is missing. Set both fields first via `PUT /api/opportunities/{id}`, then issue the stage patch.

### Stage Change Audit Trail

Every successful stage transition automatically creates an Activity record of type `NOTE` on the opportunity. The audit entry is created by `StageAuditService` after the transition is persisted, with the caller's JWT forwarded so the Activities service can authenticate the internal request:

```
Stage changed QUALIFY -> PROPOSE by johndoe
```

Both the HTTP call to Activities and the RabbitMQ publish (see below) are **best-effort** — failures are logged as warnings and swallowed. A downstream failure never blocks a stage transition.

### Stage Changed Event (RabbitMQ)

In addition to the Activity record, `StageAuditService` publishes a `StageChangedEvent` to the `opportunity-events` queue on every successful stage transition:

```json
{
  "opportunityId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "fromStage": "QUALIFY",
  "toStage": "PROPOSE",
  "changedBy": "johndoe",
  "timestamp": "2025-06-01T10:30:00Z"
}
```

This allows any downstream consumer to react to stage changes without polling the Opportunities service. The queue is durable (`opportunity-events`). No consumer is implemented yet — the event is available for future integrations.

---

## PMBOK Project Management Module

The `Projects` service (port 8085) adds a PMBOK-aligned project management bounded context on top of the CRM. It has its own PostgreSQL database (`projectsdb`) and follows the same JWT/Spring Security pattern as the other services.

### Project-Level Roles

PMBOK roles are **per-project**, not global Keycloak roles. A user can be PM on one project and STAKEHOLDER on another.

| Role | Permissions |
|------|-------------|
| `PM` | Create/manage everything: charter, WBS, tasks, cost items, risks, baselines, deliverables, CRs, decision log, status reports |
| `SPONSOR` | Approve charter, approve baselines, accept/reject deliverables, approve/reject change requests |
| `TEAM_MEMBER` | Log work, create issues, submit deliverables, view project data |
| `QA` | Accept/reject deliverables (same as SPONSOR for deliverable approval) |
| `STAKEHOLDER`, `FINANCE`, `PROCUREMENT` | View project data |

`crm_admin` bypasses all project-role checks. Roles are stored in `project_role_assignment` and checked by `ProjectPermissionService` (`@Service("projectPerm")`).

When a project is created, the creator is automatically assigned `PM` and the supplied `sponsorId` user is assigned `SPONSOR`. Additional roles are added via `POST /api/projects/{id}/members`.

### PMBOK Lifecycle

```
POST /api/projects                              → Project DRAFT
POST /api/projects/{id}/charter                 → Charter DRAFT   (PM)
POST /api/projects/{id}/charter/submit          → Charter SUBMITTED (PM)
POST /api/projects/{id}/charter/approve         → Charter APPROVED → Project ACTIVE (SPONSOR)

POST /api/projects/{id}/wbs                     → WBS items       (PM)
POST /api/projects/{id}/tasks                   → Schedule tasks  (PM)
POST /api/projects/{id}/cost-items              → Cost plan       (PM)
POST /api/projects/{id}/baselines               → Baseline DRAFT  (PM, snapshots WBS+tasks+costs as JSON)
POST /api/projects/{id}/baselines/{v}/submit    → SUBMITTED       (PM)
POST /api/projects/{id}/baselines/{v}/approve   → APPROVED, immutable (SPONSOR)

PATCH /api/projects/{id}/tasks/{id}             → Update task status (any member)
POST  /api/projects/{id}/work-logs              → Log hours against a task (any member)
POST  /api/projects/{id}/deliverables           → Create deliverable PLANNED (PM)
POST  /api/projects/{id}/deliverables/{id}/submit → SUBMITTED (any member)
POST  /api/projects/{id}/deliverables/{id}/accept → ACCEPTED + approval record (SPONSOR or QA)
POST  /api/projects/{id}/deliverables/{id}/reject → REJECTED + approval record (SPONSOR or QA)

POST /api/projects/{id}/change-requests                     → CR DRAFT   (any member)
POST /api/projects/{id}/change-requests/{id}/submit         → SUBMITTED  (any member)
POST /api/projects/{id}/change-requests/{id}/review         → IN_REVIEW  (PM)
POST /api/projects/{id}/change-requests/{id}/approve        → APPROVED   (SPONSOR or PM)
  └─ if type is SCOPE|SCHEDULE|COST → new baseline DRAFT auto-created and linked to CR
POST /api/projects/{id}/change-requests/{id}/reject         → REJECTED   (SPONSOR or PM)
POST /api/projects/{id}/change-requests/{id}/implement      → IMPLEMENTED (PM)
  └─ requires linked baseline to be APPROVED first

POST /api/projects/{id}/decisions               → Decision log entry (PM)
POST /api/projects/{id}/status-reports          → RAG status report  (PM)
```

### Baseline Snapshots

When a baseline is created (`POST /api/projects/{id}/baselines`), the service serialises the current WBS items, schedule tasks, and cost items into three JSON TEXT columns (`scope_snapshot`, `schedule_snapshot`, `cost_snapshot`). Once a baseline reaches `APPROVED` status, the application never issues an UPDATE against that row — it is permanently immutable. This gives an auditable record of what the project scope/schedule/cost looked like at the moment of approval.

### Change Request → Baseline Link

When a change request of type `SCOPE`, `SCHEDULE`, or `COST` is approved, the service automatically creates a new `DRAFT` baseline and sets `baseline_set.change_request_id` to the CR's ID. The PM must then submit and get that baseline approved before the CR can be marked `IMPLEMENTED`. This enforces that every scope/schedule/cost change has a corresponding approved revised plan — traceability is enforced by the state machine, not by policy.

### Polymorphic Approval Record

All approval workflows (charter, baseline, change request, deliverable, closure) write into a single `approval` table with `resource_type` and `resource_id` columns. This avoids five separate approval tables with identical columns. The trade-off is the absence of a database-level FK from `resource_id` to the resource — the service layer enforces the link.

---

## Messaging (RabbitMQ)

Two queues are in use:

| Queue | Producer | Consumer | Purpose |
|-------|----------|----------|---------|
| `request-logs` | Gateway (all `/api/*` requests) | LogConsumer | Request audit log persisted to `logsdb` |
| `opportunity-events` | Opportunities (on stage transitions) | *(none yet)* | Stage change events for downstream consumers |

Both queues are durable. All publishes are best-effort — producer failures are logged and swallowed, never blocking the main operation.

---

## Architecture Decision FAQ

### Authentication & Security

**Why does each service validate the JWT independently instead of the Gateway doing it once?**

Defense in depth. If the Gateway is misconfigured or bypassed (e.g., via a direct internal call), downstream services still reject unauthenticated requests. Each service is a full OAuth2 Resource Server — it does not trust that the caller has already authenticated. This also means services can be tested independently without a gateway in front.

**Why `jwk-set-uri` instead of `issuer-uri` for JWT validation?**

Keycloak issues tokens with `iss: http://localhost:8080/auth/realms/crm` (the external URL that clients use). Inside Docker, services resolve Keycloak as `http://keycloak:8080` — a different hostname. `issuer-uri` fetches the OIDC discovery document and validates that the token's `iss` claim matches. Since the hostnames differ, this always fails. `jwk-set-uri` bypasses issuer verification and only validates the cryptographic signature — correct behaviour for an internal service.

**Why is `ownerId` set server-side from `jwt.getSubject()` and not accepted from the request body?**

Clients cannot be trusted to report their own identity. If `ownerId` were accepted from the request body, any authenticated user could create resources claiming to belong to another user, then read those resources if the other user is `crm_admin`. Setting it from the validated JWT's `sub` claim on the server side eliminates this class of vulnerability.

**Why does `PermissionService.canAccess()` return `false` (→ HTTP 403) for non-existent resources instead of triggering a 404?**

Returning 404 for "not found OR not yours" leaks information — an attacker can probe UUIDs and distinguish between "this resource doesn't exist" and "this resource exists but belongs to someone else." Returning 403 in both cases keeps resource existence opaque to unauthorised callers.

**Why `preferred_username` (not `sub`) in audit activity text?**

`sub` is a UUID like `3fa85f64-5717-4562-b3fc-2c963f66afa6`. `preferred_username` is the human-readable login name (`johndoe`). Audit logs are read by humans — the username makes them useful without requiring a Keycloak lookup.

---

### Configuration Management

**Why a Spring Cloud Config Server instead of per-service `application.properties`?**

Seven services previously duplicated the same properties: JPA dialect, JWK URI, actuator settings, datasource driver. Any change (e.g., Keycloak endpoint) had to be applied in seven places and required rebuilding seven images. Config Server centralises shared config in one file (`config/application.properties`) served to all clients. Per-service overrides live in `config/<name>.properties`. Rebuilding config changes only requires restarting the Config Server, not all services.

**Why classpath/native backend instead of a Git-backed Config Server?**

Git backend is the right choice when config changes need to happen in production without rebuilding images. For this project (staged Docker → Kubernetes deployment, config committed alongside code), the classpath native backend is simpler: no Git server to manage, no access tokens, no network dependency, config changes deploy with the image. If independent config-without-redeploy is needed later, the backend can be switched to Git with one property change.

**Why `spring.application.name` must be lowercase?**

The Config Server's native backend resolves config files by the client's `spring.application.name`. The filename `accounts.properties` must exactly match the name `accounts`. Docker Compose was previously passing `SPRING_APP_NAME=Accounts` (capital A), which would cause the server to look for `Accounts.properties` — not found. All `spring.application.name` values are now hardcoded lowercase in each service's bootstrap properties.

**Why `max-interval` must be set explicitly when `initial-interval` is raised?**

`RetryTemplateBuilder.exponentialBackoff` requires `maxInterval > initialInterval` strictly (not `≥`). The default `max-interval` is 2000ms. Setting `initial-interval=2000` without also raising `max-interval` causes an `IllegalArgumentException` at startup before the application context is created. The service appears to fail with no useful error unless you read the full stack trace.

---

### Database Design

**Why three separate PostgreSQL instances instead of one with multiple databases?**

Separate instances give each concern an independent lifecycle:
- **Main postgres** — shared by five CRM services. Wiped together with `compose-down -Volumes`. Its init script creates five databases on first start.
- **Keycloak postgres** — Keycloak owns its schema; upgrading Keycloak without touching CRM data is safer.
- **Logs postgres** — different retention policy (log data grows unboundedly), different user (`loguser`), can be archived or truncated independently without touching CRM data.

**Why Flyway for schema management?**

Flyway runs automatically at service startup, applying any pending `V{n}__description.sql` migrations. This means a fresh deployment on an empty database is fully self-provisioning — no manual `psql` commands needed. It also provides an auditable migration history and prevents accidental schema drift between environments. The `ddl-auto=validate` setting (not `create` or `update`) ensures Hibernate validates the schema matches the entities without modifying it.

**Why `restart: on-failure` (dev) / `restart: always` (prod) on Spring Boot services?**

`pg_isready` passes as soon as PostgreSQL accepts TCP connections, but the init SQL (`init-main-db.sql`) runs after that. A Spring Boot service that starts immediately after `pg_isready` reports healthy may encounter "database does not exist" if the init script hasn't finished creating databases yet. `restart: on-failure` handles this race condition gracefully: the service restarts, the init script has finished, and the second start succeeds. In production, `restart: always` additionally recovers from transient failures and host reboots.

---

### API Design

**Why are Contacts and Activities nested under their parent resources?**

`/api/accounts/{id}/contacts` and `/api/opportunities/{id}/activities` reflect the domain model: a contact only exists in the context of an account, and an activity only exists in the context of an opportunity. Nested URLs make the ownership implicit in the path, simplify access control (the parent ID is already a required parameter), and produce more intuitive Swagger documentation.

**Why does `PATCH /opportunities/{id}/stage` require `amount` and `closeDate` before allowing WON?**

`WON` is a financial milestone. Recording a won opportunity without an amount makes pipeline reporting meaningless. Requiring both fields before the transition enforces data completeness at the only point where it matters — the moment of winning — rather than relying on downstream consumers to handle null values.

**Why does the stage machine allow any stage → LOST but only sequential forward transitions otherwise?**

A deal can be lost at any point in the sales process — after the first call or after months of negotiation. Forcing `PROSPECT → QUALIFY → PROPOSE → ... → LOST` would require dummy intermediate transitions that carry no business meaning. Backward transitions (e.g., `PROPOSE → QUALIFY`) are not allowed because they represent data corruption rather than a real sales event; if an opportunity needs to go backward, it should be closed as LOST and a new one opened.

---

### PMBOK Project Management

**Why are PMBOK roles stored in a separate `project_role_assignment` table instead of Keycloak roles?**

Keycloak realm roles are global — they apply to the user across the entire system. PMBOK roles are *per-project*: the same person is PM on project A and STAKEHOLDER on project B simultaneously. Keycloak has no built-in concept of resource-scoped roles without custom extensions. The `project_role_assignment` table (`project_id`, `user_id`, `role`) is the simplest solution that can be queried efficiently and doesn't require Keycloak customisation. The user's Keycloak `sub` UUID is used as `user_id` to link the two systems without a cross-service FK.

**Why is a `SCOPE`, `SCHEDULE`, or `COST` change request automatically linked to a new baseline draft on approval?**

PMBOK requires that approved changes to scope, schedule, or cost result in a revised performance measurement baseline — you cannot have an approved scope change without also having a revised plan that reflects it. Auto-creating the baseline draft on CR approval enforces this rule mechanically: the PM cannot skip straight to `IMPLEMENTED` without going through the baseline approval gate. The link (`baseline_set.change_request_id`) also provides an audit trail — every APPROVED baseline can be traced back to either the original planning phase or a specific approved CR.

**Why does `baseline_set` store snapshots as JSON blobs instead of FK references to the live planning rows?**

A proper versioned schema would copy every `wbs_item`, `schedule_task`, and `cost_item` row with a version tag on approval — but that multiplies table size and complicates queries (every planning query must filter by version). JSON snapshots are written once (at baseline creation), never updated (baselines are immutable once APPROVED), and can be compared or exported without joining across a version dimension. The active planning tables (`wbs_item`, `schedule_task`, `cost_item`) remain unversioned and are fast to query.

**Why is the Projects service a separate microservice rather than adding PMBOK tables to an existing service?**

Project management is a distinct bounded context from CRM. Accounts/Contacts/Opportunities model the sales pipeline; Projects models delivery. They share identity (Keycloak sub) but have no domain-level relationships that would require cross-service joins. Keeping them separate means independent deployability, independent database migrations, and no risk of a PMBOK schema change breaking the CRM. The cost is one more service to operate — acceptable given that it follows the identical pattern (Spring Boot 3, Flyway, OAuth2 RS) as the other services.

**Why is the `approval` table polymorphic (one table for all resource types) rather than one approval table per resource?**

Charter, baseline, change request, deliverable, and closure all need the same approval record: who submitted it, who approved/rejected it, when, and a comment. Five separate tables with identical columns would be pure duplication. The `resource_type` enum (CHARTER / BASELINE / CHANGE_REQUEST / DELIVERABLE / CLOSURE) plus `resource_id` UUID covers all cases in a single table. The trade-off — no database FK from `resource_id` — is acceptable because approvals are always created inside a service transaction that already holds the resource entity, so the link is validated at write time.

**Why does `work_log` not have a `project_id` column?**

A work log is always linked to a `schedule_task`, and every task already carries `project_id`. Adding `project_id` to `work_log` would be a denormalised redundancy — two sources of truth that could drift if a task were ever moved. Instead, querying work logs by project uses a JPQL subquery: `WHERE w.taskId IN (SELECT t.id FROM ScheduleTask t WHERE t.projectId = :projectId)`. The extra join is negligible for the typical number of tasks and work logs per project.

**Why can any project member submit a change request, but only PM or SPONSOR can approve it?**

A team member discovering a scope gap or schedule risk should be able to raise a formal CR without waiting for the PM — bottlenecking CR creation on the PM defeats the purpose of a controlled change process. The multi-step workflow (DRAFT → SUBMITTED → IN_REVIEW by PM → APPROVED/REJECTED by SPONSOR or PM) ensures that every CR is reviewed before approval, even if anyone can initiate one.

---

### Infrastructure & Docker

**Why Docker Compose overlay files (`docker-compose.dev.yml`, `docker-compose.prod.yml`) instead of a single file with profiles?**

Docker Compose profiles can show/hide services but cannot cleanly add `depends_on` entries or `deploy.resources` limits per-environment. Overlay files are the standard Docker Compose mechanism for environment-specific overrides — they merge with the base file at the key level. The result is:
- `docker-compose.yml` — common services (no DB containers)
- `docker-compose.dev.yml` — adds DB containers + DB `depends_on` for app services
- `docker-compose.prod.yml` — adds external DB env vars + `restart: always` + memory limits

**Why do Spring Boot services point to Config Server rather than receiving DB credentials via Docker Compose env vars in production?**

Config Server handles the majority of configuration (JPA settings, JWK URI, service discovery URIs, RabbitMQ credentials). Only the DB connection string changes between environments. Spring Boot's property precedence means Docker Compose `environment:` entries (`SPRING_DATASOURCE_URL` etc.) override Config Server properties without requiring separate config files for dev and prod. The result: Config Server carries 90% of the config, Docker Compose only overrides what is environment-specific.

**Why `wget` instead of `curl` in the Config Server healthcheck?**

`eclipse-temurin:17-jre` (the base image for all services) includes `wget` but not `curl`. Using `curl` produces a `healthcheck failed: not found` error that looks like a service failure rather than a missing tool.

**Why single-stage Dockerfiles (`COPY build/libs/*.jar app.jar`) instead of multi-stage?**

Multi-stage Dockerfiles run Gradle inside the container, which downloads the entire Gradle cache on every build. On this dev machine, Gradle runs on the host where the cache is warm, making builds much faster. The script (`compose-up.ps1`) explicitly runs `gradlew clean build` before `docker compose up --build`, so the JAR is always current. The trade-off is that `docker compose up --build` alone does not rebuild the JAR — you must use the script.

**Why `--progress plain` in the `docker compose up` call?**

Docker Desktop's interactive progress renderer (the default TUI) exits with code 1 in non-interactive terminals such as VS Code's integrated PowerShell. `--progress plain` switches to line-buffered text output which works correctly in all terminal types. The flag must appear after `compose` but before the subcommand — it is a global `docker compose` flag, not an `up` flag.

---

## Environment Setup

<details>
<summary><strong>Docker Compose — Development (DBs in Docker)</strong></summary>

### How it works

All services including PostgreSQL run as Docker containers on a single bridge network. The Gateway listens on host port `8080`.

```
localhost:8080 (Gateway container, port published directly)
      │
      ├── /auth/**  ──►  keycloak:8080  (container-internal)
      └── /api/**   ──►  upstream service containers ──► postgres containers
```

Three PostgreSQL containers run alongside the app:

| Container | Databases | Used by |
|-----------|-----------|---------|
| `postgres` | maindb, accountsdb, contactsdb, opportunitiesdb, activitiesdb | customer, accounts, contacts, opportunities, activities |
| `postgres-keycloak` | keycloak | Keycloak |
| `postgres-logs` | logsdb | log-consumer |

RabbitMQ management UI: `http://localhost:15672` (guest / guest).

### Prerequisites

- Docker Desktop (running)
- Java 17 JDK on `PATH` (for Gradle builds)

### Scripts

| Script | Purpose |
|--------|---------|
| `.\scripts\docker\compose-up.ps1` | Build JARs + images, start all containers (dev) |
| `.\scripts\docker\compose-up.ps1 -SkipBuild` | Skip Gradle, rebuild images only |
| `.\scripts\docker\compose-up.ps1 -Foreground` | Stream logs (blocks terminal) |
| `.\scripts\docker\compose-up.ps1 -Services gateway,accounts` | Partial rebuild — listed services only |
| `.\scripts\docker\compose-down.ps1` | Stop and remove all containers |
| `.\scripts\docker\compose-down.ps1 -Volumes` | Also wipe all data volumes (full reset) |
| `.\scripts\docker\system-test.ps1` | End-to-end smoke tests (CRM + PMBOK) |
| `.\scripts\docker\system-test.ps1 -SkipPMBOK` | CRM tests only |
| `.\scripts\docker\system-test.ps1 -SkipCRM` | PMBOK tests only |

### Quick start

```powershell
# Build everything and start (takes ~3-5 min on first run)
.\scripts\docker\compose-up.ps1

# Watch logs
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f

# Run smoke tests (wait for all services to be healthy first)
.\scripts\docker\system-test.ps1
```

### Service health

```powershell
# Check all containers
docker compose -f docker-compose.yml -f docker-compose.dev.yml ps

# Follow logs for a specific service
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f gateway

# Inspect the request audit log
docker compose -f docker-compose.yml -f docker-compose.dev.yml exec postgres-logs psql -U loguser -d logsdb -c "SELECT * FROM request_log ORDER BY id DESC LIMIT 10;"
```

### Full reset

```powershell
# Stop everything and wipe all data volumes
.\scripts\docker\compose-down.ps1 -Volumes
```

### Keycloak admin

```
http://localhost:8080/auth/admin
Username: keycloak  |  Password: keycloak
Realm: crm
```

Users (`testuser`, `testuser2`) are created automatically by the `keycloak-init` container on first startup.

</details>

---

<details>
<summary><strong>Docker Compose — Production (external databases)</strong></summary>

### How it works

The production configuration runs all app services and Keycloak in Docker but connects to **externally managed databases** — no database containers are started. This keeps data management (backups, replication, upgrades) separate from application deployment.

```
localhost:8080 (Gateway)
      │
      └── /api/**  ──►  app service containers ──► external PostgreSQL
```

Compose files used: `docker-compose.yml` + `docker-compose.prod.yml`

`docker-compose.prod.yml` adds:
- `SPRING_DATASOURCE_*` env vars on each Spring Boot service → override Config Server's DB properties
- `restart: always` on all services
- Memory limits (`deploy.resources.limits`)

### Prerequisites

- Docker (Engine or Desktop) running
- Java 17 JDK on `PATH` (for Gradle builds)
- External PostgreSQL server(s) — see database setup below

### Database setup

Before first run, create the required databases on your external PostgreSQL server(s).

**App databases** (on `APP_DB_HOST`):
```sql
CREATE DATABASE maindb;
CREATE DATABASE accountsdb;
CREATE DATABASE contactsdb;
CREATE DATABASE opportunitiesdb;
CREATE DATABASE activitiesdb;
```

**Logs database** (on `LOGS_DB_HOST`):
```sql
CREATE DATABASE logsdb;
CREATE USER loguser WITH PASSWORD 'yourpassword';
GRANT ALL PRIVILEGES ON DATABASE logsdb TO loguser;
```

**Keycloak database** (on `KEYCLOAK_DB_HOST`):
```sql
CREATE DATABASE keycloak;
CREATE USER keycloak WITH PASSWORD 'yourpassword';
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;
```

Flyway manages schema creation for all Spring Boot services automatically on first startup. Keycloak manages its own schema.

### Configuration

1. Copy `.env.prod.example` to `.env.prod`:

```powershell
Copy-Item .env.prod.example .env.prod
```

2. Edit `.env.prod` and fill in all values:

```ini
APP_DB_HOST=your-postgres-host.example.com
APP_DB_PORT=5432
APP_DB_USER=postgres
APP_DB_PASSWORD=strongpassword

LOGS_DB_HOST=your-logs-postgres-host.example.com
LOGS_DB_PORT=5432
LOGS_DB_USER=loguser
LOGS_DB_PASSWORD=strongpassword

KEYCLOAK_DB_HOST=your-keycloak-postgres-host.example.com
KEYCLOAK_DB_NAME=keycloak
KEYCLOAK_DB_USER=keycloak
KEYCLOAK_DB_PASSWORD=strongpassword
```

> **Never commit `.env.prod` to version control.** It is listed in `.gitignore`.

### Start

```powershell
.\scripts\docker\compose-up.ps1 -Env prod
```

The script checks that `.env.prod` exists before proceeding and exits with an error if it is missing.

### Service health

```powershell
# Check container status
docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file .env.prod ps

# Follow gateway logs
docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file .env.prod logs -f gateway
```

### Production reliability notes

| Concern | How it is handled |
|---------|------------------|
| Service crashes | `restart: always` on all containers |
| DB connection at startup | Spring Boot retries on `DataSourceConnectionException`; Flyway retries on startup |
| Config server unavailability | `spring.cloud.config.fail-fast=true` + 10 retry attempts with exponential backoff |
| Partial RabbitMQ outage | Gateway and Opportunities use best-effort publish; failures logged but not fatal |
| RabbitMQ connection loss | `restart: always` reconnects; Spring AMQP has built-in reconnect logic |
| Memory pressure | Memory limits set per container in `docker-compose.prod.yml` |

### Keycloak in production

Keycloak runs in `start-dev` mode (no TLS, HTTP). For a real production deployment, switch to `start` mode with a valid TLS certificate and a proper hostname. The `keycloak-init` container creates `testuser`/`testuser2` on every startup — remove or restrict it before exposing to the internet.

</details>

---

<details>
<summary><strong>Kubernetes / Minikube (staging-like)</strong></summary>

### How it works

All services run as Kubernetes Deployments managed by a Helm chart. `ingress-nginx` routes traffic to the Gateway, which then routes internally. Port-forward is used to expose the ingress controller to the host because the Minikube Docker driver does not expose the node IP.

```
localhost:8080 (kubectl port-forward → ingress-nginx)
      │
      ▼
ingress-nginx
      │
      └── /*  ──►  Gateway :8080  ──►  upstream services
```

### Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/) with Docker driver
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm 3](https://helm.sh/)
- Docker Desktop
- Java 17 JDK on `PATH`

### Scripts

| Script | Purpose |
|--------|---------|
| `.\scripts\kubernetes\env-up.ps1` | Start Minikube, build all images, deploy Helm chart, start port-forward |
| `.\scripts\kubernetes\reinstall.ps1` | Rebuild all images + `helm upgrade` |
| `.\scripts\kubernetes\reinstall.ps1 -SkipBuild` | `helm upgrade` only (skip image rebuild) |
| `.\scripts\kubernetes\reinstall.ps1 -HardReset` | `helm uninstall` + `helm install` (clears PVCs) |
| `.\scripts\kubernetes\env-down.ps1` | Stop port-forward + `helm uninstall` |
| `.\scripts\kubernetes\env-down.ps1 -StopMinikube` | Also stop the Minikube VM |
| `.\scripts\kubernetes\port-forward.ps1 start/stop/status` | Manage background port-forward |
| `.\scripts\kubernetes\system-test.ps1` | End-to-end smoke tests |

### Quick start

```powershell
# First-time setup (takes ~10-15 min)
.\scripts\kubernetes\env-up.ps1

# After code changes: rebuild images + redeploy
.\scripts\kubernetes\reinstall.ps1

# After Helm/values changes only (no code change):
.\scripts\kubernetes\reinstall.ps1 -SkipBuild

# Run smoke tests
.\scripts\kubernetes\system-test.ps1
```

### Manual build (when needed)

```powershell
# Point Docker CLI at Minikube's daemon (required before every build session)
& minikube -p minikube docker-env --shell powershell | Where-Object { $_ -match '^\$Env:' } | Invoke-Expression

# Build a single service
Push-Location Gateway; .\gradlew.bat clean build -x test; docker build -t gateway:latest .; Pop-Location
```

### Watch pod status

```powershell
kubectl get pods -w
```

Expected steady state:

| Pod | Status |
|-----|--------|
| gateway | 1/1 Running |
| keycloak | 1/1 Running |
| customer | 1/1 Running |
| accounts, contacts, opportunities, activities | 1/1 Running |
| rabbitmq | 1/1 Running |
| log-consumer | 1/1 Running |
| postgres, postgres-keycloak, postgres-logs | 1/1 Running |
| postgres-init (Job) | Completed |
| keycloak-init (Job) | Completed |
| logsdb-init (Job) | Completed |

### Helm commands

```powershell
# List releases
helm list

# Show current effective values
helm get values project-y

# Render templates locally without applying
helm template project-y ./deployment -f ./deployment/values-dev.yaml --debug

# Rollback
helm rollback project-y
```

### Debug commands

```powershell
# Logs (follow)
kubectl logs -l app=gateway -f
kubectl logs -l app=log-consumer -f
kubectl logs -l app=keycloak -f

# Describe a failing pod
kubectl describe pod <pod-name>

# Check ingress routing
kubectl describe ingress api-ingress

# Inspect the request audit log
kubectl exec deployment/postgres-logs -- psql -U loguser -d logsdb -c "SELECT * FROM request_log ORDER BY id DESC LIMIT 10;"

# RabbitMQ management UI (temporary port-forward)
kubectl port-forward svc/rabbitmq 15672:15672
# then open http://localhost:15672  (guest / guest)
```

### Keycloak admin

```
http://localhost:8080/auth/admin
Username: admin  |  Password: admin
Realm: crm
```

</details>

---

## API Reference

All endpoints require `Authorization: Bearer <JWT>` (except `/auth/**`).

### Accounts
| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/accounts` | Create account (`ownerId` = caller's `sub`) |
| `GET` | `/api/accounts?search=&page=` | List accounts |
| `GET` | `/api/accounts/{id}` | Get account |

### Contacts
| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/accounts/{id}/contacts` | Create contact |
| `GET` | `/api/accounts/{id}/contacts` | List contacts |

### Opportunities
| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/accounts/{id}/opportunities` | Create opportunity |
| `GET` | `/api/opportunities?mine=true&stage=&closingBefore=` | List opportunities |
| `GET` | `/api/opportunities/{id}` | Get opportunity |
| `PATCH` | `/api/opportunities/{id}` | Update fields |
| `POST` | `/api/opportunities/{id}/stage` | Advance stage |

Stage transitions: `PROSPECT → QUALIFY → PROPOSE → NEGOTIATE → WON / LOST`
`WON` requires `amount` and `closeDate` to be set.

### Activities
| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/opportunities/{id}/activities` | Create activity |
| `GET` | `/api/opportunities/{id}/activities` | List activities |

### Projects (PMBOK module)

All project endpoints require the caller to be a **project member** (have a row in `project_role_assignment`) unless otherwise noted. `crm_admin` bypasses all project-role checks.

#### Project & Members
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/projects` | any JWT | Create project; caller → PM, `sponsorId` → SPONSOR |
| `GET` | `/api/projects/{id}` | member | Get project |
| `GET` | `/api/projects/{id}/members` | member | List role assignments |
| `POST` | `/api/projects/{id}/members` | PM | Add member with role |

#### Charter (Initiation)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/projects/{id}/charter` | PM | Create charter (DRAFT) |
| `POST` | `/api/projects/{id}/charter/submit` | PM | Submit for approval |
| `POST` | `/api/projects/{id}/charter/approve` | SPONSOR | Approve → project becomes ACTIVE |

#### Planning
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/projects/{id}/wbs` | PM | Add WBS item |
| `GET` | `/api/projects/{id}/wbs` | member | List WBS items |
| `POST` | `/api/projects/{id}/tasks` | PM | Create schedule task |
| `GET` | `/api/projects/{id}/tasks` | member | List tasks |
| `PATCH` | `/api/projects/{id}/tasks/{taskId}` | member | Update task status |
| `POST` | `/api/projects/{id}/cost-items` | PM | Add cost item |
| `GET` | `/api/projects/{id}/cost-items` | member | List cost items |
| `POST` | `/api/projects/{id}/baselines` | PM | Create baseline (snapshots current WBS/tasks/costs) |
| `GET` | `/api/projects/{id}/baselines` | member | List baselines |
| `POST` | `/api/projects/{id}/baselines/{version}/submit` | PM | Submit baseline |
| `POST` | `/api/projects/{id}/baselines/{version}/approve` | SPONSOR | Approve baseline (immutable after this) |

#### Execution
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/projects/{id}/deliverables` | PM | Create deliverable (PLANNED) |
| `GET` | `/api/projects/{id}/deliverables` | member | List deliverables |
| `POST` | `/api/projects/{id}/deliverables/{did}/submit` | member | Submit for acceptance |
| `POST` | `/api/projects/{id}/deliverables/{did}/accept` | SPONSOR or QA | Accept → ACCEPTED + approval record |
| `POST` | `/api/projects/{id}/deliverables/{did}/reject` | SPONSOR or QA | Reject → REJECTED + approval record |
| `POST` | `/api/projects/{id}/work-logs` | member | Log hours against a task |
| `GET` | `/api/projects/{id}/work-logs` | member | List work logs for project |
| `POST` | `/api/projects/{id}/issues` | member | Create issue |
| `GET` | `/api/projects/{id}/issues` | member | List issues |

#### Monitoring & Controlling
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/projects/{id}/change-requests` | member | Create CR (DRAFT) |
| `GET` | `/api/projects/{id}/change-requests` | member | List CRs |
| `GET` | `/api/projects/{id}/change-requests/{cid}` | member | Get CR |
| `POST` | `/api/projects/{id}/change-requests/{cid}/submit` | member | DRAFT → SUBMITTED |
| `POST` | `/api/projects/{id}/change-requests/{cid}/review` | PM | SUBMITTED → IN_REVIEW |
| `POST` | `/api/projects/{id}/change-requests/{cid}/approve` | SPONSOR or PM | IN_REVIEW → APPROVED (SCOPE/SCHEDULE/COST auto-creates baseline) |
| `POST` | `/api/projects/{id}/change-requests/{cid}/reject` | SPONSOR or PM | IN_REVIEW → REJECTED |
| `POST` | `/api/projects/{id}/change-requests/{cid}/implement` | PM | APPROVED → IMPLEMENTED (linked baseline must be APPROVED) |
| `POST` | `/api/projects/{id}/decisions` | PM | Add decision log entry |
| `GET` | `/api/projects/{id}/decisions` | member | List decision log |
| `POST` | `/api/projects/{id}/status-reports` | PM | Create RAG status report |
| `GET` | `/api/projects/{id}/status-reports` | member | List status reports (newest first) |

### Customers (legacy)
| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/customers/create` | Create customer record |
| `PUT` | `/api/customers/edit/{id}` | Update customer (owner or `boss-credential` only) |
