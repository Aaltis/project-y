# API Reference

All endpoints require `Authorization: Bearer <JWT>` (except `/auth/**` and `/actuator/health/**`).

Get a token (password grant, dev only):

```
POST http://localhost:8080/auth/realms/crm/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=password&client_id=crm-api&username=testuser&password=testpassword
```

---

## CRM

### Accounts

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/accounts` | Create account (`ownerId` set to caller's `sub`) |
| `GET` | `/api/accounts?search=&page=` | List accounts |
| `GET` | `/api/accounts/{id}` | Get account |

### Contacts

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/accounts/{id}/contacts` | Create contact under account |
| `GET` | `/api/accounts/{id}/contacts` | List contacts |
| `GET` | `/api/accounts/{id}/contacts/{contactId}` | Get contact |
| `PUT` | `/api/accounts/{id}/contacts/{contactId}` | Update contact |
| `DELETE` | `/api/accounts/{id}/contacts/{contactId}` | Delete contact |

### Opportunities

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/opportunities` | Create opportunity (body includes `accountId`) |
| `GET` | `/api/opportunities?accountId=&stage=&closingBefore=&mine=true&page=` | List opportunities |
| `GET` | `/api/opportunities/{id}` | Get opportunity |
| `PUT` | `/api/opportunities/{id}` | Update fields (name, amount, closeDate) |
| `PATCH` | `/api/opportunities/{id}/stage` | Advance stage — body: `{ "stage": "PROPOSE" }` |
| `DELETE` | `/api/opportunities/{id}` | Delete opportunity |

Stage transitions: `PROSPECT → QUALIFY → PROPOSE → NEGOTIATE → WON / LOST`

`WON` requires both `amount` and `closeDate` to be set first — returns `HTTP 400` if missing.

### Activities

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/opportunities/{id}/activities` | Create activity (type: NOTE / CALL / MEETING / TASK) |
| `GET` | `/api/opportunities/{id}/activities` | List activities |
| `GET` | `/api/opportunities/{id}/activities/{activityId}` | Get activity |
| `DELETE` | `/api/opportunities/{id}/activities/{activityId}` | Delete activity |

---

## Projects (PMBOK module)

All project endpoints require the caller to have a row in `project_role_assignment` (i.e. be a
project member) unless otherwise noted. `crm_admin` bypasses all project-role checks.

### Project & Members

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/projects` | any JWT | Create project; caller → PM, `sponsorId` param → SPONSOR |
| `GET` | `/api/projects` | any JWT | List projects where caller is a member (`crm_admin` sees all) |
| `GET` | `/api/projects/{id}` | member | Get project |
| `GET` | `/api/projects/{id}/members` | member | List role assignments |
| `POST` | `/api/projects/{id}/members` | PM | Add member with role |

### Charter (Initiation)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/projects/{id}/charter` | PM | Create charter (DRAFT) |
| `POST` | `/api/projects/{id}/charter/submit` | PM | DRAFT → SUBMITTED |
| `POST` | `/api/projects/{id}/charter/approve` | SPONSOR | SUBMITTED → APPROVED; project status → ACTIVE |

### Planning

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/projects/{id}/wbs` | PM | Add WBS item |
| `GET` | `/api/projects/{id}/wbs` | member | List WBS items |
| `POST` | `/api/projects/{id}/tasks` | PM | Create schedule task |
| `GET` | `/api/projects/{id}/tasks` | member | List tasks |
| `PATCH` | `/api/projects/{id}/tasks/{taskId}` | member | Update task status (TODO / IN_PROGRESS / DONE / BLOCKED) |
| `POST` | `/api/projects/{id}/cost-items` | PM | Add cost item |
| `GET` | `/api/projects/{id}/cost-items` | member | List cost items |
| `POST` | `/api/projects/{id}/baselines` | PM | Create baseline — snapshots current WBS / tasks / costs as JSON |
| `GET` | `/api/projects/{id}/baselines` | member | List baselines |
| `POST` | `/api/projects/{id}/baselines/{version}/submit` | PM | DRAFT → SUBMITTED |
| `POST` | `/api/projects/{id}/baselines/{version}/approve` | SPONSOR | SUBMITTED → APPROVED (immutable after this) |

### Execution

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/projects/{id}/deliverables` | PM | Create deliverable (PLANNED) |
| `GET` | `/api/projects/{id}/deliverables` | member | List deliverables |
| `POST` | `/api/projects/{id}/deliverables/{did}/submit` | member | PLANNED → SUBMITTED |
| `POST` | `/api/projects/{id}/deliverables/{did}/accept` | SPONSOR or QA | SUBMITTED → ACCEPTED + approval record |
| `POST` | `/api/projects/{id}/deliverables/{did}/reject` | SPONSOR or QA | SUBMITTED → REJECTED + approval record |
| `POST` | `/api/projects/{id}/work-logs` | member | Log hours against a task |
| `GET` | `/api/projects/{id}/work-logs` | member | List work logs for project |
| `POST` | `/api/projects/{id}/issues` | member | Create issue |
| `GET` | `/api/projects/{id}/issues` | member | List issues |

### Monitoring & Controlling

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/projects/{id}/change-requests` | member | Create CR (DRAFT) |
| `GET` | `/api/projects/{id}/change-requests` | member | List CRs |
| `GET` | `/api/projects/{id}/change-requests/{cid}` | member | Get CR |
| `POST` | `/api/projects/{id}/change-requests/{cid}/submit` | member | DRAFT → SUBMITTED |
| `POST` | `/api/projects/{id}/change-requests/{cid}/review` | PM | SUBMITTED → IN_REVIEW |
| `POST` | `/api/projects/{id}/change-requests/{cid}/approve` | SPONSOR or PM | IN_REVIEW → APPROVED (SCOPE / SCHEDULE / COST auto-creates a new baseline DRAFT) |
| `POST` | `/api/projects/{id}/change-requests/{cid}/reject` | SPONSOR or PM | IN_REVIEW → REJECTED |
| `POST` | `/api/projects/{id}/change-requests/{cid}/implement` | PM | APPROVED → IMPLEMENTED (linked baseline must be APPROVED first) |
| `POST` | `/api/projects/{id}/decisions` | PM | Add decision log entry |
| `GET` | `/api/projects/{id}/decisions` | member | List decision log |
| `POST` | `/api/projects/{id}/status-reports` | PM | Create RAG status report (scope / schedule / cost: RED / AMBER / GREEN) |
| `GET` | `/api/projects/{id}/status-reports` | member | List status reports (newest first) |

### Closing

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/projects/{id}/closure-report` | PM | Create closure report (DRAFT) |
| `GET` | `/api/projects/{id}/closure-report` | member | Get closure report |
| `POST` | `/api/projects/{id}/closure-report/submit` | PM | DRAFT → SUBMITTED |
| `POST` | `/api/projects/{id}/closure-report/approve` | SPONSOR | SUBMITTED → APPROVED + approval record |
| `POST` | `/api/projects/{id}/lessons-learned` | member | Add lesson learned |
| `GET` | `/api/projects/{id}/lessons-learned` | member | List lessons (newest first) |
| `POST` | `/api/projects/{id}/close` | PM | Close project — gate: closure APPROVED + all deliverables ACCEPTED |

---

## Diagrams

Diagrams are private per user — each caller only sees their own. `crm_admin` sees all.

### Diagram CRUD

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/diagrams` | Create diagram — body: `{ "name": "My diagram" }` → `201` with `id` |
| `GET` | `/api/diagrams` | List caller's diagrams |
| `GET` | `/api/diagrams/{id}` | Get diagram with all nodes and edges |
| `PUT` | `/api/diagrams/{id}` | Rename — body: `{ "name": "New name" }` |
| `DELETE` | `/api/diagrams/{id}` | Delete diagram and all its nodes/edges → `204` |

### Canvas save (atomic)

```
PUT /api/diagrams/{id}/canvas
```

Replaces all nodes and edges atomically. Send the full canvas state on every save.

Request body:
```json
{
  "nodes": [
    {
      "nodeKey": "n1",
      "entityType": "ACCOUNT",
      "entityId": "uuid-or-null",
      "label": "Acme Corp",
      "x": 100, "y": 200,
      "color": "#3b82f6",
      "shape": "RECTANGLE"
    }
  ],
  "edges": [
    { "sourceKey": "n1", "targetKey": "n2", "label": "owns", "style": "SOLID" }
  ]
}
```

`entityType` values: `ACCOUNT`, `CONTACT`, `OPPORTUNITY`, `PROJECT`, `TASK`, `RISK`, `NOTE`
`shape` values: `RECTANGLE`, `CIRCLE`, `DIAMOND`, `NOTE`
`style` values: `SOLID`, `DASHED`, `DOTTED`

`entityId` is `null` for free-form nodes and sticky notes.

---

## Customers (legacy)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/customers/create` | Create customer record |
| `PUT` | `/api/customers/edit/{id}` | Update customer (owner or `boss-credential` header only) |
