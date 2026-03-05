# CRM MVP — Project Guide

## Goal

API-first CRM with Accounts, Contacts, Opportunities, stage workflow,
and resource-based access control via Keycloak JWT.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Language | Java 17 (dev machine has JDK 17; see debug log) |
| Framework | Spring Boot 3 |
| Database | PostgreSQL + Flyway |
| Auth | Spring Security OAuth2 Resource Server (Keycloak) |
| API docs | OpenAPI / Swagger UI |
| Infra | Docker Compose → k3s/kind → OpenShift (staged) |
| Async logging | RabbitMQ (optional, best-effort only) |

---

## Infrastructure Roadmap

Staged approach — each step is a working environment before moving to the next.

### Stage 1 — Docker Compose (current focus)
Local dev and integration testing with `docker-compose`.
- All services, Keycloak, PostgreSQL, RabbitMQ in one compose file
- No Kubernetes complexity; fast to start and tear down
- `system-test.ps1` runs against `http://localhost:8080`
- Goal: all system tests green before moving forward

### Stage 2 — Lightweight Kubernetes (k3s or kind)
Move to a real Kubernetes distribution without Minikube's overhead.
- **k3s**: single-binary K8s, works well on Windows via WSL2 or a Linux VM
- **kind** (Kubernetes in Docker): clusters as Docker containers, easy to reset
- Reuse existing Helm chart with minimal changes
- No port-forward hacks — use LoadBalancer or NodePort directly
- Goal: Helm chart deploys cleanly, all system tests pass

### Stage 3 — OpenShift (optional / future)
Production-grade platform if the project moves toward enterprise deployment.
- OpenShift uses Routes instead of Ingress
- Security context constraints (SCC) may require Dockerfile and pod spec changes
- Keycloak may be replaced by Red Hat SSO (same protocol)
- Evaluate when Stage 2 is stable

---

## Development Phases

### Phase 1 — Keycloak + Security ✅ DONE

- Realm: `crm`, client: `crm-api` ✅ (`deployment/files/realmconfig/keycloak-crm-realm-config.json`)
- Roles: `crm_admin`, `crm_sales` ✅ (realm JSON + assigned to testuser by `keycloak-init-job`)
- Spring Boot validates JWT via `jwk-set-uri`, maps `realm_access.roles` to authorities ✅ (all 4 services)
- Resource-based access control ✅:
  - `crm_admin`: full access to all resources
  - `crm_sales`: only resources where `ownerId == token.sub`
- Method-level security via `@perm` bean (`PermissionService`) ✅:

```java
@PreAuthorize("@perm.canAccess(#id, authentication)")
```

Implementation notes:
- `ownerId`/`createdBy` set from `jwt.getSubject()` (Keycloak user UUID = `token.sub`)
- `jwk-set-uri` avoids issuer mismatch between external (`localhost`) and internal (`keycloak:8080`) URLs
- `keycloak-init-job` auto-creates `testuser` with `crm_sales` role on every deploy

### Phase 2 — Domain + DB Schema ✅ DONE (indexes missing)

Entities implemented with UUID PKs and Flyway V1__init.sql in each service:

```sql
account(id, name, owner_id, created_at)
contact(id, account_id, name, email, phone)
opportunity(id, account_id, name, amount, stage, close_date, owner_id, updated_at)
activity(id, opportunity_id, type, text, due_at, created_by, created_at)
```

Enums:
- `OpportunityStage`: `PROSPECT → QUALIFY → PROPOSE → NEGOTIATE → WON | LOST` ✅
- `ActivityType`: `NOTE, CALL, MEETING, TASK` ✅

**Done:** `V2__indexes.sql` added to Accounts, Contacts, Opportunities, Activities — indexes on `owner_id`, `account_id`, `opportunity_id`, `stage`.

### Phase 3 — API Endpoints ✅ DONE

All endpoints require `Authorization: Bearer <JWT>`. Swagger UI at `/swagger-ui.html` ✅.

**Accounts** ✅
```
POST   /api/accounts                   (ownerId = caller's sub)
GET    /api/accounts?search=&page=
GET    /api/accounts/{id}
```

**Contacts** ✅ nested under accounts
```
POST   /api/accounts/{id}/contacts
GET    /api/accounts/{id}/contacts
GET    /api/accounts/{id}/contacts/{contactId}
PUT    /api/accounts/{id}/contacts/{contactId}
DELETE /api/accounts/{id}/contacts/{contactId}
```

**Opportunities** ✅
```
POST   /api/opportunities              (body includes accountId)
GET    /api/opportunities?accountId=&stage=&closingBefore=&mine=true&page=
GET    /api/opportunities/{id}
PUT    /api/opportunities/{id}         (name, amount, closeDate)
PATCH  /api/opportunities/{id}/stage  (body: { stage })
DELETE /api/opportunities/{id}
```

**Activities** ✅ nested under opportunities
```
POST   /api/opportunities/{id}/activities
GET    /api/opportunities/{id}/activities
GET    /api/opportunities/{id}/activities/{activityId}
DELETE /api/opportunities/{id}/activities/{activityId}
```

### Phase 4 — Business Rules ✅ DONE

**Stage transition validation** ✅
- `OpportunityStage.allowedTransitions()` enforced in controller — forward only, backward to `LOST` ✅
- Invalid transition returns HTTP 400 ✅

**WON gate validation** ✅
- `PATCH /api/opportunities/{id}/stage` checks `amount != null` AND `closeDate != null` before allowing WON ✅
- Returns HTTP 400 with message if either field is missing ✅

**Audit trail on stage change** ✅
- `StageAuditService` makes a best-effort POST to Activities after every successful stage transition ✅
- Creates `Activity(type=NOTE, text="Stage changed X -> Y by <username>")` ✅
- Forwards the caller's JWT so Activities can authenticate the internal request ✅
- Failures are logged and swallowed — stage transition is never blocked by audit failure ✅
- `ACTIVITIES_URI` env var wired in docker-compose.yml and opportunities-deployment.yaml ✅

### Phase 5 — RabbitMQ ✅ DONE

**Request logging via RabbitMQ** ✅
- Gateway publishes every `/api/*` request to `request-logs` queue ✅
- LogConsumer persists to `logsdb` ✅
- Best-effort, no outbox ✅

**Opportunity stage_changed event** ✅
- `StageAuditService` publishes `StageChangedEvent` to `opportunity-events` queue after every stage transition ✅
- Payload: `{ opportunityId, fromStage, toStage, changedBy, timestamp }` ✅
- Best-effort — publish failures are logged and swallowed; stage transition is never blocked ✅
- `RabbitMQConfig` + `spring-boot-starter-amqp` + `jackson-databind` added to Opportunities service ✅
- RabbitMQ connection properties in `Config/src/main/resources/config/opportunities.properties` ✅

### Phase 6 — Deployment ✅ DONE

**Spring Cloud Config Server** ✅
- `Config/` service (port 8888) — classpath/native backend, single source of truth for all service config
- Shared properties in `Config/src/main/resources/config/application.properties` (JPA dialect, driver, JWK URI, actuator)
- Per-service files: `accounts.properties`, `contacts.properties`, `opportunities.properties`, `activities.properties`, `gateway.properties`, `customer.properties`, `log-consumer.properties`
- All 7 client services stripped to bootstrap-only `application.properties` (`spring.config.import=configserver:http://config-server:8888`)
- All 7 clients have `spring-cloud-starter-config` + `spring-retry` + `spring-boot-starter-aop` deps; Spring Cloud BOM 2024.0.1
- Verify config serving: `curl http://localhost:8888/accounts/default`

**Docker Compose** ✅
- `docker-compose.yml` with all 12 services (config-server + gateway, customer, accounts, contacts, opportunities, activities, log-consumer, keycloak, postgres, postgres-keycloak, postgres-logs, rabbitmq)
- `config-server` has healthcheck; all 7 app services `depends_on: config-server: condition: service_healthy`
- `scripts/docker/compose-up.ps1`, `compose-down.ps1`, `system-test.ps1`

**Kubernetes (Helm / Minikube)** ✅
- `deployment/templates/` has all service Deployments, Services, Ingress, ConfigMaps, Secrets, init Jobs
- `deployment/templates/config-deployment.yaml` — Deployment + ClusterIP Service on port 8888
- `deployment/values-dev.yaml` has `configServer` section; K8s clients use `fail-fast=true` + retry (no `depends_on` in K8s)
- Readiness/liveness probes on `/actuator/health/**`
- `scripts/kubernetes/env-up.ps1`, `reinstall.ps1`, `env-down.ps1`, `port-forward.ps1`, `system-test.ps1`

---

## Phase 7 — PMBOK Project Management Module

See [pmbok.md](pmbok.md) for the full domain model. This phase adds a PMBOK-aligned project
management bounded context on top of the existing CRM services.

### Architecture decision: new `Projects` microservice

All PMBOK entities live in a single new service (`Projects/`). Rationale:
- Clean separation from the CRM domain (accounts/contacts/opportunities are sales; projects are delivery)
- Own PostgreSQL database (`projectsdb`) — no cross-service DB joins
- Same tech pattern as every other service (Spring Boot 3, Flyway, JPA, port 8085)
- Gateway routes `/api/projects/**` → `projects:8085`

```
GET /api/projects/**
        │
   Gateway (port-forward :8080)
        │
   projects:8085  ──►  projectsdb (postgres)
```

### Project-level roles (app-level, not Keycloak)

PMBOK roles (SPONSOR, PM, TEAM_MEMBER, STAKEHOLDER, QA, FINANCE, PROCUREMENT) are
**per-project**, not global. They cannot map directly to Keycloak realm roles.

Implementation:
- `ProjectRoleAssignment(id, projectId, userId, role)` table in `projectsdb`
- `userId` = Keycloak JWT `sub` (UUID) — same linkage as `ownerId` in CRM services
- `ProjectPermissionService` bean checks project role from DB, not Keycloak authorities
- Global Keycloak roles stay unchanged: `crm_admin` bypasses project role checks; `crm_sales` must have an explicit assignment

```java
// Usage in controllers
@PreAuthorize("@projectPerm.hasRole(#projectId, 'PM', authentication)")
```

### Cross-cutting: Approval entity

One polymorphic approval record covers all approval workflows (charter, baseline, CR, deliverable, closure).
Implement early — every subsequent module depends on it.

```sql
approval(id, resource_type, resource_id, requested_by, approver_id, status, comment, timestamp)
-- resource_type: CHARTER | BASELINE | CHANGE_REQUEST | DELIVERABLE | CLOSURE
-- status: PENDING | APPROVED | REJECTED
```

---

### Implementation order

#### Step 7.1 — Scaffold + infrastructure ✅ DONE

- `Projects/` service with `build.gradle`, `settings.gradle`, `dockerfile` ✅
- Port 8085, datasource `projectsdb`, `jwk-set-uri`, Spring Cloud Config client ✅
- `projectsdb` in `docker/init-main-db.sql` ✅
- `projects` service in `docker-compose.yml` ✅
- `projects-deployment.yaml` Helm template ✅
- `/api/projects/**` route in `GatewayRoutingConfig.java` ✅
- `scripts/docker/compose-up.ps1` updated ✅

#### Step 7.2 — Identity & Access ✅ DONE

Flyway migration `V1__project_role_assignment.sql`:
```sql
CREATE TABLE project_role_assignment (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    user_id UUID NOT NULL,       -- keycloak sub
    role VARCHAR(20) NOT NULL,   -- SPONSOR|PM|TEAM_MEMBER|STAKEHOLDER|QA|FINANCE|PROCUREMENT
    UNIQUE (project_id, user_id, role)
);
```
- `ProjectRoleAssignmentRepository` + `ProjectPermissionService`
- Endpoints: `POST /api/projects/{id}/members`, `GET /api/projects/{id}/members`

#### Step 7.3 — Initiation ✅ DONE

Flyway migration `V2__initiation.sql` — tables: `project`, `project_charter`, `stakeholder_register`.

```sql
project(id, name, sponsor_id, pm_id, status, start_target, end_target, created_at)
-- status: DRAFT → ACTIVE → CLOSED

project_charter(id, project_id, objectives, high_level_scope, success_criteria,
                summary_budget, key_risks, status)
-- status: DRAFT → SUBMITTED → APPROVED

stakeholder_register(id, project_id, name, user_id, influence, interest, engagement_level)

approval(id, resource_type, resource_id, requested_by, approver_id,
         status, comment, created_at)
```

Workflow rules:
- Project status `ACTIVE` only after charter `APPROVED`
- Charter submit: any PM for this project; charter approve: Sponsor only
- Approval stored in `approval` table with `resource_type=CHARTER`

Endpoints: `POST /api/projects`, `GET /api/projects/{id}`, `POST /api/projects/{id}/charter`,
`POST /api/projects/{id}/charter/submit`, `POST /api/projects/{id}/charter/approve`

#### Step 7.4 — Planning (baselines) ✅ DONE

Flyway migration `V3__planning.sql` — tables: `wbs_item`, `schedule_task`, `cost_item`,
`risk`, `quality_checklist`, `comms_plan`, `procurement_item`, `baseline_set`.

```sql
wbs_item(id, project_id, parent_id, name, description, wbs_code)
schedule_task(id, project_id, wbs_item_id, name, start_date, end_date, assignee_id, status)
-- status: TODO | IN_PROGRESS | DONE | BLOCKED
cost_item(id, project_id, wbs_item_id, category, planned_cost, actual_cost)
risk(id, project_id, description, probability, impact, response, owner_id, status)
-- status: OPEN | MITIGATED | CLOSED
quality_checklist(id, project_id, name)
quality_checklist_item(id, checklist_id, description, checked)
comms_plan(id, project_id, audience, cadence, channel)
procurement_item(id, project_id, item, vendor, estimate, status)

baseline_set(id, project_id, version, scope_snapshot, schedule_snapshot,
             cost_snapshot, status, created_by, created_at)
-- status: DRAFT → SUBMITTED → APPROVED
-- snapshots: JSON blobs of WBS/tasks/costs at time of snapshot
-- approved baseline_set is immutable (no UPDATE allowed by app)
```

Workflow rules:
- Only one `APPROVED` baseline per version number
- Approving a baseline creates an `approval` record (`resource_type=BASELINE`)
- PM submits; Sponsor approves

#### Step 7.5 — Execution ✅ DONE

Flyway migration `V4__execution.sql` — tables: `deliverable`, `work_log`, `issue`.

```sql
deliverable(id, project_id, name, due_date, acceptance_criteria, status)
-- status: PLANNED → SUBMITTED → ACCEPTED | REJECTED
work_log(id, task_id, user_id, log_date, hours, note)
issue(id, project_id, title, severity, owner_id, status)
-- severity: LOW | MEDIUM | HIGH | CRITICAL
-- status: OPEN | IN_PROGRESS | RESOLVED | CLOSED
```

Workflow rules:
- Team members submit deliverables; Sponsor or QA role accepts/rejects
- Deliverable acceptance stored in `approval` table (`resource_type=DELIVERABLE`)
- Work log: any TEAM_MEMBER can log against a task assigned to them

#### Step 7.6 — Monitoring & Controlling ✅ DONE

Flyway migration `V5__monitoring.sql` — tables: `change_request`, `decision_log`, `status_report`.

```sql
change_request(id, project_id, type, description, impact_scope, impact_schedule_days,
               impact_cost, submitted_by, status, created_at)
-- type: SCOPE | SCHEDULE | COST | QUALITY | RISK
-- status: DRAFT → SUBMITTED → IN_REVIEW → APPROVED | REJECTED → IMPLEMENTED

decision_log(id, project_id, decision, decision_date, made_by)

status_report(id, project_id, period_start, period_end, summary,
              rag_scope, rag_schedule, rag_cost, key_risks, key_issues, created_by, created_at)
-- rag: RED | AMBER | GREEN
```

Workflow rules:
- CR approved → if type affects SCOPE/SCHEDULE/COST → service creates new `BaselineSet` at
  `DRAFT` status and links it to the CR (`baseline_set.change_request_id`)
- CR implementation: PM marks `IMPLEMENTED`; requires linked baseline to be `APPROVED`
- CR approval stored in `approval` table (`resource_type=CHANGE_REQUEST`)

#### Step 7.7 — Closing ✅ DONE

Flyway migration `V6__closing.sql` — tables: `closure_report`, `lessons_learned`.

```sql
closure_report(id, project_id, outcomes_summary, budget_actual, schedule_actual,
               acceptance_summary, status)
-- status: DRAFT → SUBMITTED → APPROVED

lessons_learned(id, project_id, category, what_happened, recommendation, created_by)
```

Workflow rules (gate conditions for `Project.status = CLOSED`):
- All deliverables `ACCEPTED` or explicitly waived (`closure_report.acceptance_summary` notes waivers)
- `closure_report.status = APPROVED` by Sponsor
- Approval stored in `approval` table (`resource_type=CLOSURE`)

---

### Full end-to-end PMBOK flow

```
POST /api/projects                          → Project DRAFT
POST /api/projects/{id}/charter             → Charter DRAFT
POST /api/projects/{id}/charter/submit      → Charter SUBMITTED
POST /api/projects/{id}/charter/approve     → Charter APPROVED → Project ACTIVE

POST /api/projects/{id}/wbs                 → WBS items
POST /api/projects/{id}/tasks               → Schedule tasks
POST /api/projects/{id}/cost-items          → Cost plan
POST /api/projects/{id}/risks               → Risk register
POST /api/projects/{id}/baselines           → BaselineSet DRAFT (snapshot)
POST /api/projects/{id}/baselines/{v}/submit → SUBMITTED
POST /api/projects/{id}/baselines/{v}/approve → APPROVED (immutable from here)

PATCH /api/projects/{id}/tasks/{t}          → task progress
POST  /api/projects/{id}/work-logs          → hours logged
POST  /api/projects/{id}/deliverables/{d}/submit → Deliverable SUBMITTED
POST  /api/projects/{id}/deliverables/{d}/accept → ACCEPTED

POST /api/projects/{id}/status-reports      → weekly RAG report
POST /api/projects/{id}/change-requests     → CR DRAFT
POST /api/projects/{id}/change-requests/{c}/approve → APPROVED → new BaselineSet DRAFT created

POST /api/projects/{id}/closure-report      → ClosureReport DRAFT
POST /api/projects/{id}/lessons-learned     → lessons
POST /api/projects/{id}/close               → gate check → Project CLOSED
```

---

### Infrastructure checklist for Phase 7

| Task | Status | File(s) |
|------|--------|---------|
| Create `Projects/` service scaffold | ✅ | `Projects/build.gradle`, `Projects/settings.gradle`, `Projects/dockerfile` |
| Add `projectsdb` init | ✅ | `docker/init-main-db.sql`, `deployment/templates/maindb_configmap_init_sql.yaml` |
| Add Gateway route | ✅ | `Gateway/.../config/GatewayRoutingConfig.java` |
| Add to docker-compose | ✅ | `docker-compose.yml` |
| Add Helm template | ✅ | `deployment/templates/projects-deployment.yaml` |
| Add to build scripts | ✅ | `scripts/docker/compose-up.ps1` |
| Add system-test cases (P01–P40) | ✅ | `scripts/docker/system-test.ps1` |
| Update architecture diagram | ✅ | `docs/architecture.puml`, `docs/database.puml` |

**System tests: 57 passed, 0 failed** (T01–T22 CRM + P01–P32 PMBOK + TRL rate-limit, 2026-03-01)
**P33–P40 added** for Phase 7.7 — pending run after Docker Desktop restart.

---

## Definition of Done

1. Login via Keycloak, obtain JWT
2. Create account + contact
3. Create opportunity, advance stages to `WON` (validation fires)
4. Access control: a second `crm_sales` user cannot read/write resources owned by the first
5. Swagger UI works and documents all endpoints
6. Everything runs on Kubernetes

---

## Environment — Minikube (Docker driver, Windows) — being replaced by Docker Compose

### Access method

Node IP `192.168.49.2` is NOT routable from the host on the Docker driver.
Use port-forward instead:

```bash
kubectl port-forward svc/ingress-nginx-controller 8080:80 -n ingress-nginx
# or
.\scripts\port-forward.ps1 start
```

All services reachable at `http://localhost:8080`.

### Scripts

| Script | Purpose |
|--------|---------|
| `.\scripts\kubernetes\env-up.ps1` | Start Minikube, build images, deploy, start port-forward |
| `.\scripts\kubernetes\reinstall.ps1` | Rebuild all images + helm upgrade |
| `.\scripts\kubernetes\reinstall.ps1 -SkipBuild` | Helm upgrade only (no image rebuild) |
| `.\scripts\kubernetes\env-down.ps1` | Stop port-forward + helm uninstall |
| `.\scripts\kubernetes\port-forward.ps1 start/stop/status` | Manage background port-forward |
| `.\scripts\kubernetes\system-test.ps1` | End-to-end system tests |
| `.\scripts\docker\compose-up.ps1` | Build JARs + images + start Docker Compose stack |
| `.\scripts\docker\compose-down.ps1` | Stop Docker Compose stack |
| `.\scripts\docker\system-test.ps1` | End-to-end system tests (Docker Compose) |

### Build commands (PowerShell)

```powershell
# Point Docker CLI at Minikube's daemon (required before every build)
# Note: pipe through Where-Object to filter bare 'false' token that crashes Invoke-Expression
& minikube -p minikube docker-env --shell powershell | Where-Object { $_ -match '^\$Env:' } | Invoke-Expression

# Build a service
Push-Location <ServiceDir>; .\gradlew.bat clean build -x test; docker build -t <name>:latest .; Pop-Location

# Apply Helm changes only (skip rebuild)
helm upgrade project-y ./deployment -f ./deployment/values-dev.yaml
```

### Key findings

- Keycloak 26+ health probes must use **port 9000** (management), path `/auth/health/ready`
- Customer API uses `jwk-set-uri` (not `issuer-uri`) to avoid issuer claim mismatch between external (`localhost`) and internal (`keycloak:8080`) URLs
- Use `@AuthenticationPrincipal Jwt jwt` in controllers — not `Principal principal` — to reliably extract JWT claims
- RabbitMQ `rabbitmq-diagnostics` commands need `timeoutSeconds: 10` in Kubernetes probes (default 1s is too short)
- Gateway liveness probe must use `/actuator/health/liveness` (ping only) so pod is not killed when RabbitMQ is temporarily down
- `minikube docker-env --shell powershell | Invoke-Expression` crashes on bare `false` token in output; fix: pipe through `Where-Object { $_ -match '^\$Env:' }` first

---

## Debug Log — T04/T05/T12 HTTP 500 (RESOLVED)

**Root cause: Images never built into Minikube's Docker daemon.**

`kubectl get pods` showed `accounts`, `contacts`, `opportunities`, `activities` all in `ErrImageNeverPull`.
With `imagePullPolicy: Never`, Kubernetes refuses to start pods if the image is not already present
in the local (Minikube) Docker daemon. Spring Cloud Gateway returned 500 when it could not reach
any running upstream pod.

T03 (no token → 401) passed because the **Gateway itself** rejects unauthenticated requests before
forwarding — it never needs to reach the Accounts pod for a 401.

**Postgres init job** was healthy: databases (`accountsdb`, `contactsdb`, `opportunitiesdb`,
`activitiesdb`) were all created successfully. The `ERROR: database already exists` lines in the
init log are expected on re-deploy (existing PVC keeps maindb; `\gexec` idiom avoids failures).

**Fix: build the 4 missing images into Minikube's daemon.**

```powershell
# Point Docker at Minikube's daemon
& minikube -p minikube docker-env --shell powershell | Where-Object { $_ -match '^\$Env:' } | Invoke-Expression

# Build each service (Gradle already ran; docker build is now fast with slim Dockerfile)
Push-Location Accounts;      .\gradlew.bat clean build -x test; docker build -t accounts:latest .;      Pop-Location
Push-Location Contacts;      .\gradlew.bat clean build -x test; docker build -t contacts:latest .;      Pop-Location
Push-Location Opportunities; .\gradlew.bat clean build -x test; docker build -t opportunities:latest .; Pop-Location
Push-Location Activities;    .\gradlew.bat clean build -x test; docker build -t activities:latest .;    Pop-Location

# Force pods to pick up the new images (ErrImageNeverPull pods do not restart automatically)
kubectl rollout restart deployment/accounts deployment/contacts deployment/opportunities deployment/activities
```

Or simply run `.\scripts\reinstall.ps1` which builds all images and does a Helm upgrade.

**Key lesson:** After adding a new service to the Helm chart, the image must be built into
Minikube's daemon **before** `helm install/upgrade`. `ErrImageNeverPull` + Gateway returning 500
(not 502/503) is the symptom when `imagePullPolicy: Never` is set and image is absent.

---

## Debug Log — compileJava FAILED on CRM services (RESOLVED)

**Symptom:** `reinstall.ps1` second run: Customer/Gateway build fine, all 4 CRM services fail:
```
> Toolchain installation 'C:\Program Files\Eclipse Adoptium\jre-17.0.14.7-hotspot'
  does not provide the required capabilities: [JAVA_COMPILER]
```
Docker build then fails: `ERROR [3/3] COPY build/libs/*-SNAPSHOT.jar app.jar — no such file or directory`
because Gradle never produced the JAR.

**Root cause:** CRM services had `sourceCompatibility = '21'`. Gradle's toolchain auto-detection
found the Eclipse Adoptium **JRE 17** installation at `C:\Program Files\Eclipse Adoptium\` and
tried to use it as the Java 21 compiler — but a JRE has no `javac`. Customer/Gateway use
`sourceCompatibility = '17'` and compile against the system JDK directly (no toolchain mismatch).

**Fix:** Changed `sourceCompatibility = '21'` → `'17'` in all 4 CRM service `build.gradle` files
and updated their Dockerfiles from `eclipse-temurin:21-jre` → `eclipse-temurin:17-jre`.
Spring Boot 3 is fully supported on Java 17.

**Key lesson:** On this dev machine the installed JDK is Java 17. All services must target Java 17.
If Java 21 is needed in future, install a JDK 21 (not JRE) and set `JAVA_HOME` accordingly.

**Secondary lesson:** `$ErrorActionPreference = "Stop"` does NOT abort on non-zero exit codes from
external programs (gradle, docker) in PowerShell 5. The script kept running after 4 failed builds,
deployed broken images, and the error was silent. Fix: explicitly check `$LASTEXITCODE` after each
external call and throw on failure. Fixed in `reinstall.ps1` via `Invoke-Build` helper function.

---

## Debug Log — Gateway CrashLoopBackOff: liveness probe returns 401 (RESOLVED)

**Symptom:** New gateway pod (`kubectl get pods`) stays in CrashLoopBackOff. Events show:
```
Liveness probe failed: HTTP probe failed with statuscode: 401
```
Old gateway pod continues serving traffic. `reinstall.ps1` reports `deployment "gateway" exceeded its progress deadline`.

**Root cause:** `SecurityConfig.java` had `.pathMatchers("/actuator/health").permitAll()` —
an exact-path match. Kubernetes probes call `/actuator/health/liveness` and
`/actuator/health/readiness` (sub-paths), which fell through to `.anyExchange().authenticated()`
and received 401 before the pod was ever considered ready.

**Fix:** Changed to `.pathMatchers("/actuator/health/**").permitAll()` in
`Gateway/src/main/java/.../gateway/config/SecurityConfig.java`.
**Requires gateway image rebuild:** `reinstall.ps1` or manual gradle build + docker build.

**Key lesson:** Kubernetes health probes hit sub-paths of `/actuator/health`. Always use
`/actuator/health/**` (wildcard) in security permit rules, not the bare path.

---

## Debug Log — log-consumer CrashLoopBackOff: logsdb pg_hba.conf + missing DB (RESOLVED)

**Symptom:** `log-consumer` in CrashLoopBackOff. Logs show:
```
FATAL: no pg_hba.conf entry for host "10.244.0.217", user "loguser", database "logsdb", SSL off
```
**Also:** `logsdb` database did not exist inside `postgres-logs`.

**Root causes (two compounding issues):**
1. `logsdb-deployment.yaml` did not set `POSTGRES_HOST_AUTH_METHOD=md5`. PostgreSQL initialised
   with a default `pg_hba.conf` that only allows `localhost` connections. Pod-network IPs
   (10.244.0.x) were rejected.
2. `logsdb-init-job` ran while the pg_hba.conf was still blocking remote connections, so it
   failed silently — `logsdb` database and `request_log` table were never created.

**Contrast:** Main postgres (`postgres` deployment) has `host all all all md5` in its
`pg_hba.conf` because it was initialized in an earlier session when the POSTGRES env may have
been different, or the PVC was recreated.

**Fix (immediate — no reinstall needed):**
```powershell
# 1. Add pod-network auth rule and reload postgres-logs
kubectl exec deployment/postgres-logs -- sh -c "echo 'host all all all md5' >> /var/lib/postgresql/data/pg_hba.conf"
kubectl exec deployment/postgres-logs -- sh -c "psql -U loguser -d postgres -c 'SELECT pg_reload_conf();'"

# 2. Create missing database and table
kubectl exec deployment/postgres-logs -- sh -c "psql -U loguser -d postgres -c 'CREATE DATABASE logsdb;'"
kubectl exec deployment/postgres-logs -- sh -c "PGPASSWORD=logpassword psql -h postgres-logs -U loguser -d logsdb -c \"CREATE TABLE IF NOT EXISTS request_log (id BIGSERIAL PRIMARY KEY, method VARCHAR(10), path TEXT, status INTEGER, duration_ms BIGINT, created_at TIMESTAMP DEFAULT now());\""

# 3. Restart log-consumer
kubectl rollout restart deployment/log-consumer
```

**Fix (permanent — Helm template):** Added `POSTGRES_HOST_AUTH_METHOD: md5` env var to
`deployment/templates/logsdb-deployment.yaml`. Takes effect on next `-HardReset` (PVC delete)
since PostgreSQL only reads this env var on first initialisation of an empty data directory.

**Key lesson:** PostgreSQL Docker image needs `POSTGRES_HOST_AUTH_METHOD=md5` (or `trust` for
dev) to allow pod-network connections. Without it, only `localhost` is permitted. Always set
this on every PostgreSQL deployment in Kubernetes.

---

## Debug Log — T13/T14/T19/T20 HTTP 404 after nested routing migration (RESOLVED)

**Symptom:** After migrating Contacts and Activities to nested URL routing, system tests T13, T14,
T19, T20 fail with HTTP 404 even after rebuilding the `contacts` and `activities` images.

```
[FAIL] POST /api/accounts/{id}/contacts -> 404
[FAIL] POST /api/opportunities/{id}/activities -> 404
```

**Root cause (two compounding issues):**

1. **Gateway route order:** Spring Cloud Gateway evaluates routes in declaration order. The route
   `accounts: /api/accounts/**` was declared before any contacts-specific route. When a request
   arrived for `/api/accounts/{id}/contacts`, the gateway matched `accounts` first and forwarded
   it to the Accounts service (port 8081), which has no `/contacts` endpoint → 404.
   Same issue for `/api/opportunities/{id}/activities` → forwarded to Opportunities service → 404.

2. **Gateway image not rebuilt:** After fixing `GatewayRoutingConfig.java`, the gateway container
   was not rebuilt — it continued running the old image with the old route table. Rebuilding only
   `contacts` and `activities` (without `gateway`) left the routing bug in place.

**Fix:** Added two nested-path routes in `GatewayRoutingConfig.java` **before** the parent service
routes, using `*` (single-segment wildcard) to match the UUID path segment:

```java
// Must come BEFORE accounts and opportunities routes
.route("contacts-nested", r -> r
    .path("/api/accounts/*/contacts", "/api/accounts/*/contacts/**")
    .uri(contactsUri))
.route("activities-nested", r -> r
    .path("/api/opportunities/*/activities", "/api/opportunities/*/activities/**")
    .uri(activitiesUri))
// Then the broader parent routes
.route("accounts", r -> r.path("/api/accounts", "/api/accounts/**").uri(accountsUri))
```

**Key lesson:** When adding nested REST routes (`/parent/{id}/child`) behind Spring Cloud Gateway,
the nested route must be declared **before** the parent's `/**` catch-all route. Both the affected
downstream service image AND the gateway image must be rebuilt together:

```powershell
docker compose up --build -d gateway contacts activities
```

Rebuilding only the downstream service without the gateway leaves the old routing in place.

---

## Debug Log — T13/T14/T19/T20 still 404 after image rebuild (RESOLVED)

**Symptom:** After fixing the gateway routing and running `docker compose up --build -d gateway contacts activities`,
the same 4 tests still fail with 404. The gateway routing fix had no apparent effect.

**Root cause: Single-stage Dockerfiles — `docker compose up --build` does NOT run Gradle.**

All service Dockerfiles are single-stage:
```dockerfile
FROM eclipse-temurin:17-jre
COPY build/libs/*-SNAPSHOT.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
```
`docker compose up --build` only re-executes the Dockerfile. It copies whatever JAR is already
in `build/libs/` on the host. If `gradlew clean build` has not been run since the source was
changed, the new image contains the **old compiled JAR** — and the new controller mapping is
never present in the running container.

**Contrast with `compose-up.ps1`:** The script explicitly runs `.\gradlew.bat clean build -x test`
for every service before `docker compose up --build`. Bypassing the script loses this step.

**Fix:** Always rebuild services through the script, not raw `docker compose`:

```powershell
# Partial rebuild — rebuilds JARs + Docker images for only the listed services
.\scripts\docker\compose-up.ps1 -Services gateway,contacts,activities

# Full rebuild (all services)
.\scripts\docker\compose-up.ps1
```

`compose-up.ps1` was updated to accept `-Services <name,...>` for targeted partial rebuilds.

**Key lesson:** Never run `docker compose up --build -d <service>` directly for these services.
The Dockerfiles are single-stage and depend on a pre-built JAR. Always use `compose-up.ps1`
(which runs Gradle first) or manually run `gradlew build` before `docker compose up --build`.

---

## Debug Log — All 7 services crash-loop after Config Server added: retry interval error (RESOLVED)

**Symptom:** After introducing Spring Cloud Config Server, all 7 client services crash immediately
on startup. `docker compose logs accounts` shows:
```
java.lang.IllegalArgumentException: Max interval should be > than initial interval
    at org.springframework.retry.support.RetryTemplateBuilder.exponentialBackoff
    at org.springframework.cloud.config.client.RetryTemplateFactory.create
    at org.springframework.cloud.config.client.ConfigClientRetryBootstrapper
```
Config server itself is healthy (`Up X hours (healthy)`). All JARs built successfully.

**Root cause:** `RetryTemplateBuilder.exponentialBackoff` requires `maxInterval > initialInterval`
strictly (not `>=`). Each client's `application.properties` had:
```properties
spring.cloud.config.retry.initial-interval=2000
spring.cloud.config.retry.max-attempts=10
# max-interval not set → defaults to 2000ms (same as initial-interval)
```
Since `2000` is NOT `> 2000`, `RetryTemplateFactory` throws `IllegalArgumentException` before
the application context can start.

**Fix:** Add `spring.cloud.config.retry.max-interval=10000` to all 7 client `application.properties`:
```properties
spring.cloud.config.retry.initial-interval=2000
spring.cloud.config.retry.max-interval=10000   # must be strictly > initial-interval
spring.cloud.config.retry.max-attempts=10
```

**Key lesson:** When configuring Spring Cloud Config retry, always set `max-interval` explicitly
to a value strictly greater than `initial-interval`. The default `max-interval` is 2000ms — if you
raise `initial-interval` to 2000ms or above without also raising `max-interval`, the exponential
backoff builder throws at startup and the service never starts.

---

## Debug Log — P01 HTTP 500: projectsdb does not exist (RESOLVED)

**Symptom:** `system-test.ps1` PMBOK section: P01 `POST /api/projects` returns HTTP 500. All 31
subsequent PMBOK tests skip because `$ProjectId` is null. CRM tests (T01–T22) pass fine.

**Root cause:** The Postgres volume predated the Projects service. Docker's postgres image only
runs `/docker-entrypoint-initdb.d/` scripts on first init (empty data directory). When the volume
already existed, `docker/init-main-db.sql` (which includes `CREATE DATABASE projectsdb;`) was
never re-executed. The Projects service crashed on startup with:
```
FATAL: database "projectsdb" does not exist
```

**Fix (one-time — running volume):**
```powershell
docker compose exec postgres psql -U postgres -c "CREATE DATABASE projectsdb;"
docker compose restart projects
```

**Permanent fix:** `docker/init-main-db.sql` already contains `CREATE DATABASE projectsdb;`.
A fresh `compose-down -Volumes` + `compose-up` will create it automatically.

**Key lesson:** When adding a new service + database to a project with a long-lived Postgres
volume, the new `CREATE DATABASE` line in the init script does NOT run automatically. Either
wipe the volume (`compose-down -Volumes`) or create the database manually on the running instance.

---

## Debug Log — database.puml render error at closing brace (RESOLVED)

**Symptom:** `.\scripts\render-diagrams.ps1` fails on `database.puml`:
```
Error line 603 in file: /data/database.puml
plantuml render failed for database.puml (exit 200)
```
Line 603 was `} ' end projectsdb` — the closing brace of the outer `projectsdb` package.
`architecture.puml` (no entity/ERD content) rendered fine.

**Root cause:** PlantUML v1.2026.1 (`plantuml/plantuml:latest`) has a bug where `note bottom/right
of <entity>` blocks inside nested packages crash the ERD parser when the enclosing package is not
the **first** top-level package in the file. The `postgres (main)` package came first — its 3 notes
rendered fine. The `projectsdb` block was second — all 6 of its notes failed silently, and
PlantUML reported the error at the outer package's closing brace.

**Attempted fix (partial):** Moving the 6 notes out of their inner packages to just outside
`} ' end projectsdb` moved the error line but did not resolve it (from 603 to 551).

**Full fix:** Removed the outer `package "projectsdb..." { }` wrapper entirely. The 6 inner
phase packages (`Identity & Access`, `Approvals`, `Initiation`, `Planning`, `Execution`,
`Monitoring & Controlling`) became top-level packages with `projectsdb ·` prefixed to their names.
All entities, relationships, and notes remain unchanged; only the extra nesting level is gone.

**Key lesson:** PlantUML v1.2026.1 does not reliably handle `note` blocks on entities inside
doubly-nested packages (`package > package > entity`) in ERD diagrams when the outer package is
not the first in the file. Workaround: keep entity packages at a single nesting level (flat),
using name prefixes (`"db · Phase"`) to convey grouping visually instead of structural nesting.

---

## Debug Log — PS5 .Count error on single-element JSON response (RESOLVED)

**Symptom:** `system-test.ps1` throws `The property 'Count' cannot be found on this object`
when a list endpoint returns exactly one item.

**Root cause:** PowerShell 5's `ConvertFrom-Json` returns a `PSCustomObject` (not an array) when
the JSON response is a single-element array `[{...}]`. Calling `.Count` on a `PSCustomObject`
throws instead of returning 1.

**Fix:** Wrap `ConvertFrom-Json` in `@()` to force array type regardless of element count:
```powershell
# Before (fails on single-item responses):
$count = ($r.Content | ConvertFrom-Json).Count

# After (PS5 safe):
$count = @($r.Content | ConvertFrom-Json).Count
```
Applied to 5 locations in `scripts/docker/system-test.ps1`.

**Key lesson:** In PowerShell 5, always wrap `ConvertFrom-Json` in `@()` before calling `.Count`
or iterating with index access. PS7 returns arrays consistently; PS5 does not.

---

## Debug Log — compose-up.ps1 exits with 1 despite stack starting successfully (RESOLVED)

**Symptom:** `compose-up.ps1` throws `docker compose up failed (exit 1)` but the Docker stack
is actually running fine. No docker compose output appears in the transcript log between
`"Starting Docker Compose stack"` and the error — the command fails silently.

**Root cause:** PowerShell 5 `Start-Transcript` interferes with native command stdout pipes in
non-interactive terminals (VS Code PowerShell). When the transcript is active, docker compose's
`--progress plain` output goes through a different Windows console channel that PS5 cannot capture
via transcript. This causes docker compose to report exit code 1 in the PS5 context even though it
actually succeeds (running the same command directly in bash returns exit 0 and all containers start).

**Fix:** Stop the transcript before `docker compose up` and re-attach with `-Append` afterward:
```powershell
Stop-Transcript -ErrorAction SilentlyContinue
& docker @upArgs
$dockerExit = $LASTEXITCODE
Start-Transcript -Path $LogFile -Append -ErrorAction SilentlyContinue
if ($dockerExit -ne 0) { throw "docker compose up failed (exit $dockerExit)" }
```
`-ErrorAction SilentlyContinue` on both calls handles direct invocations where no transcript is
active. `-Append` ensures the log file is not truncated when the transcript is re-attached.

**Key lesson:** In PS5, `Start-Transcript` can interfere with native command execution in
non-interactive terminals. For commands that produce high-volume output through Windows console APIs
(like docker compose), stop the transcript before the call and re-attach after. This applies
specifically to `docker compose up --build` — other docker commands are unaffected.

---

## Phase 8 — Frontend ✅ DONE

React + TypeScript + Vite SPA that talks to the Gateway (`http://localhost:8080`) and authenticates
via Keycloak. Minimal dependencies — no UI framework, no diagram library.

### Stack

| Layer | Choice |
|-------|--------|
| Build | Vite + TypeScript |
| Routing | `react-router-dom` |
| Auth | `keycloak-js` (PKCE flow) |
| Styles | Plain CSS (no framework) |
| Diagrams | Static PNG via `<img>` (already produced by PlantUML) |

### Environment (`.env`)

```
VITE_API_BASE=http://localhost:8080
VITE_KEYCLOAK_URL=http://localhost:8080/auth
VITE_KEYCLOAK_REALM=crm
VITE_KEYCLOAK_CLIENT_ID=crm-api
```

### Pages

| Route | Page | Notes |
|-------|------|-------|
| `/login` | Login | "Login with Keycloak" button; on success store token in memory, show username + roles |
| `/` | Dashboard | Quick links; `/actuator/health` status badges (green/red) for gateway + key services; current token info (username, roles, sub) |
| `/crm/accounts` | Accounts list | Create account; table of accounts |
| `/crm/accounts/:id` | Account detail | Contacts (nested list + create); Opportunities (list + create) |
| `/crm/opportunities` | Opportunities list | Filter by `mine=true`, stage, closingBefore |
| `/crm/opportunities/:id` | Opportunity detail | Edit fields; stage transition (forward-only, WON gate enforced); activities list (including auto-created NOTE audits) |
| `/projects` | Projects list | Create project; pick existing project |
| `/projects/:id` | Project workspace | Left sidebar per-module nav; modules listed below |
| `/docs/diagrams` | Diagrams | Architecture + Database schema PNGs with click-to-fullscreen and CSS zoom |

### Project workspace modules (`/projects/:id`)

| Module | Actions |
|--------|---------|
| Charter | Create (DRAFT) → Submit → Approve (SPONSOR) |
| WBS & Tasks | Add WBS items; add tasks linked to WBS; update task status |
| Cost Items | Add/list cost items |
| Baselines | Create snapshot → Submit → Approve (immutable after); show snapshot JSON |
| Deliverables | Create PLANNED → Submit → Accept/Reject (SPONSOR or QA) |
| Change Requests | Draft → Submit → Review (PM) → Approve/Reject; auto-linked baseline shown |
| Decision Log | Add entry; list |
| Status Reports | Create RAG report; list newest first |
| Closing | Create closure report → Submit → Approve (SPONSOR); add lessons learned; Close project (gate enforced) |

### Core frontend files

```
Frontend/
  public/
    diagrams/
      architecture.png    ← copy from docs/architecture.png on build
      database.png        ← copy from docs/database.png on build
  src/
    main.tsx
    App.tsx               ← router + KeycloakProvider
    keycloak.ts           ← keycloak-js init, getToken(), refreshToken()
    api.ts                ← fetch wrapper: attaches Bearer token, handles 401→redirect, error banner
    components/
      Layout.tsx          ← top nav (username, roles, logout button)
      DataTable.tsx       ← generic table
      ErrorBanner.tsx     ← inline error display (no toast lib)
    pages/
      Login.tsx
      Dashboard.tsx
      crm/
        AccountsList.tsx
        AccountDetail.tsx
        OpportunitiesList.tsx
        OpportunityDetail.tsx
      projects/
        ProjectsList.tsx
        ProjectWorkspace.tsx
        modules/
          Charter.tsx
          WbsTasks.tsx
          CostItems.tsx
          Baselines.tsx
          Deliverables.tsx
          ChangeRequests.tsx
          DecisionLog.tsx
          StatusReports.tsx
          Closing.tsx
      docs/
        Diagrams.tsx      ← <img> + fullscreen modal + CSS zoom
  .env
  vite.config.ts
  tsconfig.json
  package.json
```

### Key implementation rules

- All API calls go through `api.ts` — never call `fetch` directly in a component
- Token stored in memory only (not localStorage) — refreshed before expiry via `keycloak.updateToken()`
- 401 responses → `keycloak.login()` redirect
- 403 responses → show `ErrorBanner` with message ("Access denied — check your project role")
- Stage transitions: validate forward-only and WON gate client-side before sending the request to show instant feedback; server is the authoritative validator
- Project roles are per-project; fetch member list on workspace load to show/hide action buttons
- Diagrams page: images live in `public/diagrams/`; add a `scripts/copy-diagrams.ps1` that copies `docs/*.png` to `Frontend/public/diagrams/` as a pre-dev step

### Keycloak client setup (one-time)

The `crm-api` client in Keycloak realm `crm` needs:
- **Valid redirect URIs**: `http://localhost:5173/*`
- **Valid post-logout redirect URIs**: `http://localhost:5173/*`
- **Web origins**: `http://localhost:5173`

These can be added via Keycloak admin UI or by updating the realm JSON at
`deployment/files/realmconfig/keycloak-crm-realm-config.json`.

### Dev command

```powershell
cd Frontend
npm install
npm run dev   # http://localhost:5173
```

Requires backend stack running: `.\scripts\docker\compose-up.ps1`

### Infrastructure checklist for Phase 8

| Task | Status |
|------|--------|
| Create `Frontend/` scaffold (Vite + TS) | ✅ |
| Wire `keycloak-js` PKCE login/logout | ✅ |
| Implement `api.ts` with token attach + 401/403 handling | ✅ |
| Login page + Dashboard (health badges + token info) | ✅ |
| CRM pages: Accounts, Contacts, Opportunities, Activities | ✅ |
| Projects list + workspace shell with sidebar | ✅ |
| Project modules: Charter, WBS/Tasks, Cost Items, Baselines | ✅ |
| Project modules: Deliverables, CRs, Decision Log, Status Reports | ✅ |
| Project module: Closing (closure report + lessons + close) | ✅ |
| ~~Diagrams page (fullscreen + zoom)~~ | removed — replaced by Phase 9 Dynamic Diagrams |
| Update Keycloak realm JSON with frontend redirect URIs | ✅ (`"*"` wildcard already in realm config) |

---

## Phase 9 — Dynamic Diagrams

Interactive canvas where users can build diagrams from live database entities, draw connections
between them, and add free-form notes. Diagrams are persisted per-user.

### Architecture decision: new `Diagrams` microservice

All diagram data lives in a dedicated `Diagrams/` service on port 8086 backed by `diagramsdb`.
Rationale:
- Diagrams reference entities from every domain (CRM + Projects) — a cross-cutting concern
- Storing in any existing service would create implicit coupling
- Same scaffold pattern as the `Projects` service (Spring Boot 3, Flyway, JPA, port 8086)
- Gateway routes `/api/diagrams/**` → `diagrams:8086`

### Data model

```sql
-- V1__diagrams.sql
diagram(id UUID PK, name VARCHAR, owner_id VARCHAR, created_at, updated_at)

diagram_node(
  id UUID PK,
  diagram_id UUID FK → diagram,
  node_key  VARCHAR NOT NULL,      -- client-generated stable key (used in edge references)
  entity_type VARCHAR,             -- ACCOUNT | CONTACT | OPPORTUNITY | PROJECT |
                                   -- TASK | RISK | NOTE  (null = free node)
  entity_id UUID,                  -- FK to the referenced entity (null for NOTE/free nodes)
  label VARCHAR,                   -- display text; auto-filled on load from entity name
  x DOUBLE PRECISION,              -- canvas X position
  y DOUBLE PRECISION,              -- canvas Y position
  color VARCHAR,                   -- hex string, default per entity_type
  shape VARCHAR DEFAULT 'RECTANGLE' -- RECTANGLE | CIRCLE | DIAMOND | NOTE
)

diagram_edge(
  id UUID PK,
  diagram_id UUID FK → diagram,
  source_key VARCHAR NOT NULL,     -- references diagram_node.node_key
  target_key VARCHAR NOT NULL,
  label VARCHAR,
  style VARCHAR DEFAULT 'SOLID'    -- SOLID | DASHED | DOTTED
)
```

### API endpoints

```
GET    /api/diagrams                         list caller's diagrams (crm_admin sees all)
POST   /api/diagrams          {name}         create empty diagram
GET    /api/diagrams/{id}                    get diagram with all nodes and edges
PUT    /api/diagrams/{id}     {name}         rename
DELETE /api/diagrams/{id}                    delete diagram and all nodes/edges

PUT    /api/diagrams/{id}/canvas             full canvas save — body:
                                               { nodes: [...], edges: [...] }
                                             replaces all nodes and edges atomically
                                             (simple: one write per save, no fine-grained patch)
```

Canvas body shape:
```json
{
  "nodes": [
    { "nodeKey": "n1", "entityType": "ACCOUNT", "entityId": "uuid", "label": "Acme Corp",
      "x": 100, "y": 200, "color": "#3b82f6", "shape": "RECTANGLE" }
  ],
  "edges": [
    { "sourceKey": "n1", "targetKey": "n2", "label": "owns", "style": "SOLID" }
  ]
}
```

### Entity label resolution

On `GET /api/diagrams/{id}`, the Diagrams service returns raw DB data (no cross-service calls).
The frontend resolves entity labels at render time:
- On canvas load, collect all `(entityType, entityId)` pairs with a non-null entityId
- Batch-fetch names: `GET /api/accounts?ids=...`, `GET /api/projects?ids=...`, etc.
- If entity no longer exists, fall back to stored `label` field

### Frontend library: React Flow (reactflow)

```bash
npm install reactflow
```

React Flow handles pan/zoom, node drag, edge drawing, and selection out of the box.
Custom node types provide domain-specific visuals.

### Frontend pages

**`Frontend/src/pages/diagrams/DiagramsList.tsx`**
- Table of user's diagrams (name, created, node count)
- "New Diagram" button — prompts name, creates via POST, navigates to canvas
- Delete button per row

**`Frontend/src/pages/diagrams/DiagramCanvas.tsx`**
- Full-screen React Flow canvas (fills viewport below nav)
- **Left sidebar** — entity search panel:
  - Type selector: Account / Contact / Opportunity / Project / Task / Risk
  - Text search input → calls relevant API (e.g. `GET /api/accounts?search=foo`)
  - Result list — drag an item to the canvas to add it as a node
- **Toolbar** (top, floating):
  - Save button (PUT /canvas) with unsaved-changes indicator
  - Add Note button — adds a free NOTE node at center
  - Delete Selected button (removes highlighted nodes/edges)
  - Zoom in / Zoom out / Fit view buttons
- **Node types** (custom React Flow node components):
  - `EntityNode` — colored badge showing entity type, label below; color per type:
    - ACCOUNT → blue `#3b82f6`
    - CONTACT → purple `#8b5cf6`
    - OPPORTUNITY → green `#10b981`
    - PROJECT → orange `#f59e0b`
    - TASK → gray `#6b7280`
    - RISK → red `#ef4444`
  - `NoteNode` — yellow sticky-note style, editable textarea inline
- **Edge creation** — React Flow built-in: hover node → handle appears → drag to another node
- **Edge label** — double-click on edge to edit label inline
- **Auto-save** — debounce 2 s after any change, or explicit Save button
- **Load** — `GET /api/diagrams/{id}` on mount, then resolve entity labels

**Nav link**: Add `{ to: '/diagrams', label: 'Diagrams' }` to `Layout.tsx` NAV_LINKS
**Routes**: Add in `App.tsx`:
```tsx
<Route path="diagrams" element={<DiagramsList />} />
<Route path="diagrams/:id" element={<DiagramCanvas />} />
```

### Infrastructure checklist for Phase 9

| Task | Status | File(s) |
|------|--------|---------|
| Scaffold `Diagrams/` service (Spring Boot 3, port 8086) | ✅ | `Diagrams/build.gradle`, `dockerfile` |
| Add `diagramsdb` to postgres init | ✅ | `docker/init-main-db.sql` |
| Gateway route `/api/diagrams/**` → `diagrams:8086` | ✅ | `Gateway/.../GatewayRoutingConfig.java` |
| Add `diagrams` to docker-compose | ✅ | `docker-compose.yml` |
| Flyway V1: `diagram`, `diagram_node`, `diagram_edge` | ✅ | `Diagrams/.../V1__diagrams.sql` |
| CRUD endpoints for diagrams | ✅ | `DiagramController.java` |
| PUT /canvas — atomic node+edge replace | ✅ | `DiagramController.java` |
| `npm install reactflow` | ✅ | `Frontend/package.json` |
| `DiagramsList.tsx` | ✅ | `Frontend/src/pages/diagrams/` |
| `DiagramCanvas.tsx` + node types | ✅ | `Frontend/src/pages/diagrams/` |
| Entity search sidebar (calls CRM + Projects APIs) | ✅ | inside `DiagramCanvas.tsx` |
| Entity label resolution on canvas load | ✅ | inside `DiagramCanvas.tsx` |
| Nav link + routes | ✅ | `Layout.tsx`, `App.tsx` |
| Helm template `diagrams-deployment.yaml` | ✅ | `deployment/templates/diagrams-deployment.yaml` |
| Add `projectsdb` + `diagramsdb` to K8s postgres init | ✅ | `deployment/templates/maindb_configmap_init_sql.yaml` |
| Add `projects` + `diagrams` to values-dev.yaml | ✅ | `deployment/values-dev.yaml` |
| D01-D06 Diagrams system tests | ✅ | `scripts/docker/system-test.ps1` |
| Raise rate limiter: 5 → 20 req/s per user | ✅ | `Gateway/.../ratelimit/RateLimiterRegistry.java` |

---

## Known Issues & Improvement Backlog

### High Priority

#### Fix P38 system test flakiness ✅ DONE
Added `Start-Sleep -Seconds 1` before P38's first request. Rate limiter also raised from 5 → 20 req/s.

#### Rate limiter: raise capacity ✅ DONE
Was already per-user (keyed by JWT `preferred_username`). Raised from 5 → 20 req/s in
`Gateway/.../ratelimit/RateLimiterRegistry.java`.

### Medium Priority

#### System tests for Phase 9 ✅ DONE
D01–D06 tests added to `scripts/docker/system-test.ps1`.

#### Stage 2 — Kubernetes: update Helm chart for new services ✅ DONE
- `deployment/templates/projects-deployment.yaml` ✅
- `deployment/templates/diagrams-deployment.yaml` ✅
- `projectsdb` + `diagramsdb` in `maindb_configmap_init_sql.yaml` ✅
- `projects` + `diagrams` sections in `values-dev.yaml` ✅

#### Missing CRUD on frontend ✅ DONE
- **Contacts:** Edit (PUT) + Delete on AccountDetail ✅ (`AccountDetail.tsx`)
- **Opportunity activities:** Delete button on OpportunityDetail ✅ (`OpportunityDetail.tsx`)
- **Diagram nodes:** Double-click label → inline edit on `EntityNode` ✅ (`DiagramCanvas.tsx`)

### Low Priority

#### Observability
No distributed tracing across microservice calls. A failed frontend action may touch gateway →
projects → approval → baseline in sequence with no correlation ID visible.

**Minimal addition:** Micrometer Tracing + Zipkin sidecar. Spring Boot 3 supports this with
`spring-boot-starter-actuator` + `micrometer-tracing-bridge-otel` + `opentelemetry-exporter-zipkin`
(no code changes needed — auto-instrumented via `RestTemplate`/WebClient).

#### Frontend TypeScript build not validated ✅ DONE
`tsc --noEmit` added to `compose-up.ps1` — runs after Gradle builds, before docker compose.
Fails fast if any TypeScript type error is present.

#### Secrets management
Passwords are plaintext in committed files (`docker-compose.yml`, `Config/.../application.properties`):
`postgres/postgres`, `guest/guest`, `keycloak/keycloak`. Acceptable for dev/Stage 1.
For Stage 2+: move to Kubernetes Secrets (`kubectl create secret`) and reference via `secretKeyRef`
in Helm values. The `docker-compose.prod.yml` + `.env.prod` skeleton is already scaffolded.

