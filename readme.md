# Project Y — CRM + Project Management

Project Y is a web application for managing sales pipelines and project delivery in one place.
The CRM tracks accounts, contacts, and opportunities through the sales funnel. The Projects module
guides project teams through a PMBOK-aligned lifecycle from initiation to formal closure.

---

## What you can do

### CRM

- Manage **accounts** (companies or organisations) and their **contacts**
- Track **opportunities** through a defined sales pipeline: Prospect → Qualify → Propose → Negotiate → Won / Lost
- Log **activities** (notes, calls, meetings, tasks) against opportunities
- Filter opportunities by stage, closing date, or "mine only"
- WON gate: closing an opportunity as Won requires both amount and close date to be recorded

### Projects

Project Y follows the PMBOK process groups — each project moves through five phases:

| Phase | What happens |
|-------|-------------|
| **Initiation** | Project charter is drafted, submitted, and approved by the Sponsor. Approval activates the project. |
| **Planning** | WBS, schedule tasks, cost items, and risks are entered. A baseline is submitted and approved to lock the plan. |
| **Execution** | Tasks are updated, hours logged, deliverables submitted and accepted by the Sponsor or QA. |
| **Monitoring & Controlling** | RAG status reports track health; change requests manage scope, schedule, or cost changes with a full approval trail. |
| **Closing** | Closure report approved, lessons learned recorded, project formally closed. |

See [docs/api.md](docs/api.md) for all API endpoints and role requirements.

### Diagrams *(Phase 9 — coming soon)*

Interactive canvas for building diagrams from live database entities — accounts, contacts,
opportunities, projects, tasks, and risks. Draw connections between items, add notes, and save
diagrams per user.

---

## User roles

### CRM roles (global, assigned in Keycloak)

| Role | Access |
|------|--------|
| `crm_admin` | Full access to all resources regardless of ownership |
| `crm_sales` | Only resources they created (`ownerId = token.sub`) |

### Project roles (per project, assigned in the application)

| Role | Key responsibilities |
|------|---------------------|
| **PM** | Manages the full lifecycle — charter, plan, tasks, baselines, change requests, status reports, closure |
| **SPONSOR** | Approves charter, baselines, change requests, deliverables, and closure report |
| **TEAM_MEMBER** | Updates task status, logs work, submits deliverables, raises change requests |
| **QA** | Accepts or rejects deliverables (same rights as Sponsor for deliverable approval) |
| **STAKEHOLDER / FINANCE / PROCUREMENT** | View project data |

When a project is created the creator becomes **PM** and the specified `sponsorId` user becomes
**SPONSOR**. Additional members are added via `POST /api/projects/{id}/members`.

`crm_admin` bypasses all project-role checks.

---

## Access

| URL | Purpose |
|-----|---------|
| `http://localhost:5173` | Web application (React frontend) |
| `http://localhost:8080/api/...` | REST API (via Gateway) |
| `http://localhost:8080/auth/admin` | Keycloak admin (`keycloak` / `keycloak`) |

### Test accounts

| Username | Password | Role |
|----------|----------|------|
| `testuser` | `testpassword` | `crm_sales` |
| `testuser2` | `testpassword2` | `crm_sales` |

---

## Quick start

```powershell
.\scripts\docker\compose-up.ps1
```

This builds all JARs and Docker images, starts the full stack, and runs the frontend dev server.
Navigate to `http://localhost:5173` — you will be redirected to the Keycloak login page.

---

## Documentation

| Document | Contents |
|----------|----------|
| [docs/setup.md](docs/setup.md) | Running the stack: Docker Compose (dev + prod) and Kubernetes |
| [docs/api.md](docs/api.md) | Full API reference for all endpoints |
| [docs/architecture.md](docs/architecture.md) | Services, traffic flow, authentication, business rules, messaging |
| [docs/decisions.md](docs/decisions.md) | Architecture Decision FAQ — why things are designed the way they are |
| [CLAUDE.md](CLAUDE.md) | Development guide, implementation phases, and debug log |
