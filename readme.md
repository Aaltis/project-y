# Project Y — CRM + Project Management

Project Y is a web application for managing sales pipelines and project delivery in one place.
The CRM tracks accounts, contacts, and opportunities through the sales funnel.
The Projects module guides project teams through a PMBOK-aligned lifecycle from initiation
to formal closure. The Diagrams module provides an interactive canvas for visualising live
entities and their relationships.

---

## System overview

![Architecture](docs/architecture.png)

See [docs/architecture.md](docs/architecture.md) for the detailed service map, traffic flow,
authentication model, and business rules.

---

## What you can do

### CRM

- Manage **accounts** (companies or organisations) and their **contacts** (edit, delete)
- Track **opportunities** through a defined sales pipeline:
  `Prospect → Qualify → Propose → Negotiate → Won / Lost`
- Log **activities** (notes, calls, meetings, tasks) against opportunities; delete when no longer needed
- Filter opportunities by stage, closing date, or "mine only"
- **WON gate** — closing an opportunity as Won requires both amount and close date to be recorded first

### Projects

Follows the PMBOK process groups:

| Phase | What happens |
|-------|-------------|
| **Initiation** | Project charter drafted, submitted, and approved by the Sponsor — activates the project |
| **Planning** | WBS, schedule tasks, cost items, risks entered; baseline submitted and approved to lock the plan |
| **Execution** | Tasks updated, hours logged, deliverables submitted and accepted by Sponsor or QA |
| **Monitoring & Controlling** | RAG status reports track health; change requests manage scope/schedule/cost changes with full approval trail |
| **Closing** | Closure report approved, lessons learned recorded, project formally closed |

### Diagrams

Interactive canvas for building diagrams from live database entities:

- Search and add accounts, contacts, opportunities, projects, tasks, and risks as nodes
- Draw labelled connections between nodes
- Add free-form sticky notes
- Double-click any node label to rename it inline
- Auto-saves on every change (2 s debounce) — or use the explicit Save button
- Diagrams are private per user (access-controlled)

---

## User roles

### CRM roles (global, managed in Keycloak)

| Role | Access |
|------|--------|
| `crm_admin` | Full access to all resources regardless of ownership |
| `crm_sales` | Only resources they created (`ownerId = JWT sub`) |

### Project roles (per project, stored in the application)

| Role | Key responsibilities |
|------|---------------------|
| **PM** | Manages the full lifecycle — charter, plan, tasks, baselines, change requests, status reports, closure |
| **SPONSOR** | Approves charter, baselines, change requests, deliverables, and closure report |
| **TEAM_MEMBER** | Updates task status, logs work, submits deliverables, raises change requests |
| **QA** | Accepts or rejects deliverables |
| **STAKEHOLDER / FINANCE / PROCUREMENT** | Read-only view of project data |

When a project is created the creator becomes **PM** and the specified `sponsorId` user becomes
**SPONSOR**. Additional members are added via `POST /api/projects/{id}/members`.

`crm_admin` bypasses all project-role checks.

---

## Access

| URL | Purpose |
|-----|---------|
| `http://localhost:5173` | Web application (React frontend) |
| `http://localhost:8080/api/...` | REST API via Gateway |
| `http://localhost:8080/swagger-ui.html` | Swagger UI for any service (append after its internal port) |
| `http://localhost:8080/auth/admin` | Keycloak admin console (`keycloak` / `keycloak`) |
| `http://localhost:15672` | RabbitMQ management UI (`guest` / `guest`) |

### Test accounts (created automatically on first start)

| Username | Password | Role |
|----------|----------|------|
| `testuser` | `testpassword` | `crm_sales` |
| `testuser2` | `testpassword2` | `crm_sales` |

---

## Quick start

```powershell
# Build all JARs + Docker images and start the full stack (~3–5 min first time)
.\scripts\docker\compose-up.ps1

# Open in browser
start http://localhost:5173

# Run smoke tests (wait ~30 s for all services to become healthy first)
.\scripts\docker\system-test.ps1
```

After login you are redirected to Keycloak — use `testuser / testpassword`.

### Partial rebuild (after changing only one service)

```powershell
.\scripts\docker\compose-up.ps1 -Services gateway,accounts
```

### Stop the stack

```powershell
.\scripts\docker\compose-down.ps1          # stop containers, keep data
.\scripts\docker\compose-down.ps1 -Volumes # full reset (deletes all databases)
```

---

## Documentation

| Document | Contents |
|----------|----------|
| [docs/setup.md](docs/setup.md) | Running the stack: Docker Compose dev + prod, Kubernetes |
| [docs/api.md](docs/api.md) | Full API reference for all endpoints |
| [docs/architecture.md](docs/architecture.md) | Services, traffic flow, authentication, business rules, messaging |
| [docs/decisions.md](docs/decisions.md) | Architecture Decision FAQ — why things are designed the way they are |
| [CLAUDE.md](CLAUDE.md) | Developer guide, implementation phases, and debug log |

### Diagrams (PlantUML source in `docs/`)

| File | Contents |
|------|----------|
| [docs/architecture.puml](docs/architecture.puml) | Full service topology |
| [docs/flow.puml](docs/flow.puml) | Authenticated request flow (sequence diagram) |
| [docs/stages.puml](docs/stages.puml) | Opportunity stage + PMBOK project lifecycle (state diagrams) |
| [docs/database.puml](docs/database.puml) | Full database schema (all services) |

Render with PlantUML:
```powershell
docker run --rm -v "${PWD}/docs:/data" plantuml/plantuml /data/architecture.puml
docker run --rm -v "${PWD}/docs:/data" plantuml/plantuml /data/flow.puml
docker run --rm -v "${PWD}/docs:/data" plantuml/plantuml /data/stages.puml
```
