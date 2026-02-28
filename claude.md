# CRM MVP — Project Guide

## Goal

API-first CRM with Accounts, Contacts, Opportunities, stage workflow,
and resource-based access control via Keycloak JWT.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Language | Java 21 |
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

**TODO:** Add Flyway migration for indexes on `owner_id`, `account_id`, `opportunity_id` — currently missing.

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

### Phase 4 — Business Rules ⚠️ PARTIAL

**Stage transition validation** ✅
- `OpportunityStage.allowedTransitions()` enforced in controller — forward only, backward to `LOST` ✅
- Invalid transition returns HTTP 400 ✅

**WON gate validation** ❌ NOT IMPLEMENTED
- Transitioning to `WON` must require `amount != null` AND `closeDate != null`
- Currently accepted without these checks

**Audit trail on stage change** ❌ NOT IMPLEMENTED
- Stage transitions do NOT auto-create an `Activity(type=NOTE, text="Stage changed X→Y by user")`
- No cross-service call from Opportunities to Activities on stage change

**TODO:**
1. Add WON validation in `OpportunityController.updateStage()` — check `amount` and `closeDate` before allowing
2. After successful stage transition, POST to Activities service (or use a shared internal call) to create `Activity(type=NOTE, text="Stage changed X→Y by <username>", opportunityId, createdBy)`

### Phase 5 — RabbitMQ ⚠️ PARTIAL

**Request logging via RabbitMQ** ✅ DONE (implemented beyond original spec scope)
- Gateway publishes every `/api/*` request to `request-logs` queue ✅
- LogConsumer persists to `logsdb` ✅
- Best-effort, no outbox ✅

**Opportunity stage_changed event** ❌ NOT IMPLEMENTED
- `opportunity.stage_changed` event not published from Opportunities service
- Infrastructure already exists (RabbitMQ running, pattern established in Gateway)
- Optional per spec — implement when audit trail (Phase 4) is done

**TODO (optional):**
- Add `RabbitMQConfig` + `RabbitTemplate` to Opportunities service
- Publish `{ opportunityId, fromStage, toStage, changedBy, timestamp }` to `opportunity-events` exchange after stage transition

### Phase 6 — Deployment ✅ DONE

**Docker Compose** ✅
- `docker-compose.yml` with all 11 services (gateway, customer, accounts, contacts, opportunities, activities, log-consumer, keycloak, postgres, postgres-keycloak, postgres-logs, rabbitmq)
- `scripts/docker/compose-up.ps1`, `compose-down.ps1`, `system-test.ps1`

**Kubernetes (Helm / Minikube)** ✅
- `deployment/templates/` has all service Deployments, Services, Ingress, ConfigMaps, Secrets, init Jobs
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

#### Step 7.1 — Scaffold + infrastructure

- Create `Projects/` with `build.gradle`, `settings.gradle`, `dockerfile` (same pattern as `Accounts/`)
- `application.properties`: port 8085, datasource `projectsdb`, `jwk-set-uri` same as other services
- Add `projectsdb` to `docker/init-main-db.sql` and the Kubernetes `maindb_configmap_init_sql.yaml`
- Add `projects` service to `docker-compose.yml` (port 8085 internal, env vars same pattern)
- Add `projects-deployment.yaml` Helm template
- Add `/api/projects/**` route to `Gateway/src/main/java/.../gateway/config/GatewayRoutingConfig.java`
- Add `projects` build block to `scripts/docker/compose-up.ps1` and `scripts/kubernetes/reinstall.ps1`

#### Step 7.2 — Identity & Access

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

#### Step 7.3 — Initiation

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

#### Step 7.4 — Planning (baselines)

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

#### Step 7.5 — Execution

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

#### Step 7.6 — Monitoring & Controlling

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

#### Step 7.7 — Closing

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

| Task | File(s) |
|------|---------|
| Create `Projects/` service scaffold | `Projects/build.gradle`, `Projects/settings.gradle`, `Projects/dockerfile` |
| Add `projectsdb` init | `docker/init-main-db.sql`, `deployment/templates/maindb_configmap_init_sql.yaml` |
| Add Gateway route | `Gateway/.../config/GatewayRoutingConfig.java` |
| Add to docker-compose | `docker-compose.yml` |
| Add Helm template | `deployment/templates/projects-deployment.yaml` |
| Add to build scripts | `scripts/docker/compose-up.ps1`, `scripts/kubernetes/reinstall.ps1` |
| Add system-test cases | `scripts/docker/system-test.ps1`, `scripts/kubernetes/system-test.ps1` |

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

