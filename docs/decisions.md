# Architecture Decision FAQ

Answers to "why is it designed this way?" questions about the codebase.

---

## Authentication & Security

**Why does each service validate the JWT independently instead of the Gateway doing it once?**

Defence in depth. If the Gateway is misconfigured or bypassed (e.g., via a direct internal call),
downstream services still reject unauthenticated requests. Each service is a full OAuth2 Resource
Server and does not trust that the caller has already authenticated. Services can also be tested
independently without a gateway in front.

**Why `jwk-set-uri` instead of `issuer-uri` for JWT validation?**

Keycloak issues tokens with `iss: http://localhost:8080/auth/realms/crm` (the external URL).
Inside Docker, services resolve Keycloak as `http://keycloak:8080` — a different hostname.
`issuer-uri` fetches the OIDC discovery document and validates that the token's `iss` claim
matches the document's issuer. Since the hostnames differ, this always fails. `jwk-set-uri`
bypasses issuer verification and only validates the cryptographic signature — correct for an
internal service that trusts the network boundary.

**Why is `ownerId` set server-side from `jwt.getSubject()` and not accepted from the request body?**

Clients cannot be trusted to report their own identity. If `ownerId` were accepted from the body,
any authenticated user could create resources claiming to belong to another user. Setting it from
the validated JWT `sub` claim server-side eliminates this class of vulnerability entirely.

**Why does `PermissionService.canAccess()` return `false` (→ HTTP 403) for non-existent resources?**

Returning 404 for "not found OR not yours" leaks information — an attacker can distinguish
"this resource doesn't exist" from "this resource exists but belongs to someone else." Returning
403 in both cases keeps resource existence opaque to unauthorised callers.

**Why `preferred_username` (not `sub`) in audit activity text?**

`sub` is a UUID. `preferred_username` is the human-readable login name. Audit logs are read by
humans — the username is useful without requiring a Keycloak lookup.

---

## Configuration Management

**Why a Spring Cloud Config Server instead of per-service `application.properties`?**

Seven services previously duplicated the same properties: JPA dialect, JWK URI, actuator
settings, datasource driver. Any change required updating seven files and rebuilding seven images.
Config Server centralises shared config in one file (`application.properties`) and per-service
overrides in `<name>.properties`. A config change only requires restarting the Config Server.

**Why classpath/native backend instead of a Git-backed Config Server?**

Git backend is right when config changes need to happen in production without rebuilding images.
For this project (config committed alongside code), the classpath native backend is simpler: no
Git server, no access tokens, no network dependency. Switch to Git backend by changing one
property if independent config-without-redeploy is needed later.

**Why must `spring.application.name` be lowercase?**

The Config Server's native backend resolves config files by the client's
`spring.application.name`. The filename `accounts.properties` must exactly match the name
`accounts`. An uppercase `Accounts` causes the server to look for `Accounts.properties` — not
found, service starts with empty config.

**Why set `max-interval` explicitly when `initial-interval` is raised?**

`RetryTemplateBuilder.exponentialBackoff` requires `maxInterval > initialInterval` strictly (not
`≥`). The default `max-interval` is 2000ms. Setting `initial-interval=2000` without also raising
`max-interval` throws `IllegalArgumentException` at startup before the application context is
created — the service appears to fail with no useful error unless you read the full stack trace.

---

## Database Design

**Why three separate PostgreSQL instances instead of one?**

Separate instances give each concern an independent lifecycle:
- **Main postgres** — shared by CRM services. Wiped together with `compose-down -Volumes`.
- **Keycloak postgres** — Keycloak owns its schema. Upgrading Keycloak without touching CRM data.
- **Logs postgres** — different retention policy (log data grows unboundedly), can be archived
  or truncated independently.

**Why Flyway for schema management?**

Flyway runs at service startup and applies pending `V{n}__description.sql` migrations. A fresh
deployment on an empty database is fully self-provisioning — no manual `psql` commands needed.
`ddl-auto=validate` ensures Hibernate validates the schema without modifying it.

**Why `restart: on-failure` on Spring Boot services?**

`pg_isready` reports healthy as soon as PostgreSQL accepts TCP connections, but the init SQL runs
after that. A service starting immediately may encounter "database does not exist." `restart:
on-failure` handles this race condition: the service restarts, init has finished, second start
succeeds.

---

## API Design

**Why are Contacts and Activities nested under their parent resources?**

`/api/accounts/{id}/contacts` and `/api/opportunities/{id}/activities` reflect the domain model:
a contact only exists in the context of an account, an activity only in the context of an
opportunity. Nested URLs make ownership implicit in the path, simplify access control (parent ID
is a required parameter), and produce cleaner Swagger documentation.

**Why does `PATCH /opportunities/{id}/stage` require `amount` and `closeDate` before `WON`?**

`WON` is a financial milestone. A won opportunity without an amount makes pipeline reporting
meaningless. Requiring both fields at the moment of winning enforces data completeness at the only
point where it matters, rather than relying on downstream consumers to handle nulls.

**Why can any stage transition directly to `LOST` but only forward otherwise?**

A deal can be lost at any point — after the first call or after months of negotiation. Forcing
`PROSPECT → QUALIFY → ... → LOST` would require dummy intermediate transitions with no business
meaning. Backward transitions (e.g., `PROPOSE → QUALIFY`) are not allowed because they represent
data corruption rather than a real sales event; close as LOST and open a new opportunity instead.

---

## PMBOK Project Management

**Why are PMBOK roles in a `project_role_assignment` table instead of Keycloak roles?**

Keycloak realm roles are global — they apply across the entire system. PMBOK roles are
*per-project*: the same person is PM on project A and STAKEHOLDER on project B simultaneously.
Keycloak has no built-in concept of resource-scoped roles without custom extensions. The
`project_role_assignment(project_id, user_id, role)` table is the simplest solution that can be
queried efficiently and doesn't require Keycloak customisation.

**Why does approving a SCOPE/SCHEDULE/COST change request auto-create a new baseline draft?**

PMBOK requires that approved changes to scope, schedule, or cost result in a revised performance
measurement baseline — you cannot have an approved scope change without a revised plan. Auto-
creating the baseline draft on CR approval enforces this mechanically: the PM cannot reach
`IMPLEMENTED` without going through the baseline approval gate. The link
(`baseline_set.change_request_id`) provides an audit trail — every approved baseline traces back
to either the original planning phase or a specific approved CR.

**Why does `baseline_set` store snapshots as JSON blobs instead of versioned FK references?**

Versioned rows would copy every `wbs_item`, `schedule_task`, and `cost_item` row with a version
tag on approval, multiplying table size and complicating all planning queries with a version
filter. JSON snapshots are written once (at baseline creation), never updated (baselines are
immutable after `APPROVED`), and can be compared or exported without joining across a version
dimension. Active planning tables remain unversioned and fast to query.

**Why is the Projects service a separate microservice?**

Project management is a distinct bounded context from CRM. Accounts/Contacts/Opportunities model
the sales pipeline; Projects models delivery. They share identity (Keycloak sub) but have no
domain-level relationships requiring cross-service joins. Separate service = independent
deployability, independent DB migrations, no risk of a PMBOK schema change breaking the CRM.

**Why is the `approval` table polymorphic (one table, `resource_type` column)?**

Charter, baseline, change request, deliverable, and closure all need the same approval record:
who submitted, who approved/rejected, when, and a comment. Five tables with identical columns
would be pure duplication. `resource_type` enum + `resource_id` UUID covers all cases. The
trade-off (no DB-level FK from `resource_id`) is acceptable because approvals are always created
inside a service transaction that already holds the resource entity.

**Why does `work_log` not have a `project_id` column?**

A work log is always linked to a `schedule_task`, and every task already carries `project_id`.
Adding `project_id` to `work_log` would be denormalised redundancy — two sources of truth that
could drift. Querying work logs by project uses a JPQL subquery through the task relationship.

**Why can any project member submit a change request, but only PM or SPONSOR can approve it?**

A team member discovering a scope gap or schedule risk should be able to raise a formal CR
without waiting for the PM — bottlenecking CR creation on the PM defeats the purpose of a
controlled change process. The multi-step workflow (DRAFT → SUBMITTED → IN_REVIEW by PM →
APPROVED/REJECTED by SPONSOR or PM) ensures every CR is reviewed before approval.

---

## Infrastructure & Docker

**Why Docker Compose overlay files instead of a single file with profiles?**

Compose profiles can show/hide services but cannot cleanly add `depends_on` entries or
`deploy.resources` limits per-environment. Overlay files are the standard mechanism:
- `docker-compose.yml` — common services (app + Keycloak + RabbitMQ)
- `docker-compose.dev.yml` — adds DB containers + DB `depends_on`
- `docker-compose.prod.yml` — adds external DB env vars + `restart: always` + memory limits

**Why do Spring Boot services use Config Server rather than env vars for all config?**

Config Server carries 90% of the config (JPA, JWK URI, service URIs, RabbitMQ). Only the DB
connection string changes between environments. Spring Boot's property precedence means Docker
Compose `environment:` entries override Config Server without requiring separate config files
for dev and prod.

**Why `wget` instead of `curl` in the Config Server healthcheck?**

`eclipse-temurin:17-jre` (the base image for all services) includes `wget` but not `curl`.

**Why single-stage Dockerfiles (`COPY build/libs/*.jar app.jar`) instead of multi-stage?**

Multi-stage Dockerfiles run Gradle inside the container, downloading the full Gradle cache on
every build. On this dev machine, Gradle runs on the host where the cache is warm, making builds
significantly faster. `compose-up.ps1` explicitly runs `gradlew clean build` before
`docker compose up --build`. The trade-off: `docker compose up --build` alone does not rebuild
the JAR — always use the script.

**Why `--progress plain` in the `docker compose up` call?**

Docker Desktop's interactive TUI exits with code 1 in non-interactive terminals (VS Code
PowerShell). `--progress plain` switches to line-buffered text output that works in all terminal
types. The flag must appear after `compose` but before the subcommand — it is a global
`docker compose` flag, not an `up` flag.
