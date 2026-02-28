Below is a concrete, tight backend element set (data + workflow) that’s realistic for an MVP and maps cleanly to PMBOK thinking.

## Core backend modules (bounded contexts)

### 1) Identity & Access

**Why:** PMBOK is role/authority heavy.

* **User** (from Keycloak `sub`)
* **ProjectRoleAssignment**: `projectId, userId, role`

  * roles: `SPONSOR, PM, TEAM_MEMBER, STAKEHOLDER, QA, FINANCE, PROCUREMENT`
* **Permissions rule** (resource-based):

  * PM can draft plans, submit baselines, raise CRs
  * Sponsor can approve baselines and changes
  * Team can update tasks/issues, submit deliverables

---

## Project lifecycle artifacts (minimum set)

### 2) Initiation

**Entities**

* **Project**

  * `id, name, sponsorId, pmId, status (DRAFT/ACTIVE/CLOSED), startTarget, endTarget`
* **BusinessCase** (optional but nice)
* **ProjectCharter**

  * `projectId, objectives, highLevelScope, successCriteria, summaryBudget, keyRisks`
* **StakeholderRegister**

  * `stakeholderId, name, influence, interest, engagementLevel`

**Workflow**

* Charter: `DRAFT → SUBMITTED → APPROVED`
* Project becomes `ACTIVE` only after charter approved.

---

### 3) Planning (the “baselines”)

You want 3 baselines + key subsidiary plans, but keep them simple.

**Entities**

* **WBSItem**

  * `id, projectId, parentId, name, description`
* **ScheduleTask**

  * `id, projectId, wbsItemId, name, start, end, assigneeId, status`
* **CostItem**

  * `id, projectId, wbsItemId, category, plannedCost`
* **Risk**

  * `id, projectId, description, probability, impact, response, ownerId, status`
* **QualityChecklist** (simple)

  * `id, projectId, name, items[]`
* **CommsPlan** (simple)

  * `audience, cadence, channel`
* **ProcurementItem** (optional)

  * `item, vendor, estimate, status`

**Baselines**

* **BaselineSet**

  * `projectId, version, scopeHash, scheduleHash, costHash, status (DRAFT/SUBMITTED/APPROVED)`
* Baseline “hashes” can just be snapshot references.

**Workflow**

* PM drafts plans continuously.
* When ready: create BaselineSet snapshot → `SUBMITTED` → Sponsor `APPROVED`.
* Approved baseline is immutable.

---

### 4) Execution (work + deliverables)

**Entities**

* **Deliverable**

  * `id, projectId, name, dueDate, acceptanceCriteria, status (PLANNED/SUBMITTED/ACCEPTED/REJECTED)`
* **WorkLog**

  * `taskId, userId, date, hours, note`
* **Issue**

  * `projectId, title, severity, ownerId, status`

**Workflow**

* Team updates tasks, logs hours, submits deliverables.
* Sponsor/QA can accept/reject deliverables.

---

### 5) Monitoring & Controlling (this is where PMBOK becomes real)

This is your “control system”: performance + changes.

**Entities**

* **ChangeRequest (CR)**

  * `id, projectId, type (SCOPE/SCHEDULE/COST/QUALITY/RISK), description, impactScope, impactScheduleDays, impactCost, status`
  * statuses: `DRAFT → SUBMITTED → IN_REVIEW → APPROVED/REJECTED → IMPLEMENTED`
* **DecisionLog**

  * `projectId, decision, date, madeBy`
* **StatusReport**

  * `projectId, periodStart, periodEnd, summary, rags (scope/schedule/cost), keyRisks, keyIssues`

**Key rules**

* If a CR is approved and affects scope/schedule/cost → system creates a **new BaselineSet** version (or marks “rebaseline required”).
* Approved CR links to updated WBS/tasks/cost items.

---

### 6) Closing

**Entities**

* **ClosureReport**

  * outcomes vs objectives, budget actuals, schedule actuals, acceptance summary
* **LessonsLearned**

  * `category, whatHappened, recommendation`

**Workflow**

* Project `CLOSED` requires:

  * all deliverables accepted (or waived)
  * closure report approved by sponsor

---

## Cross-cutting system elements (high value)

### Audit & approvals

* **Approval**

  * `resourceType, resourceId, requestedBy, approverId, status, timestamp`
    Used for: Charter approval, baseline approval, CR approval, deliverable acceptance, closure approval.

### Document store (optional)

* **Attachment**

  * `resourceType, resourceId, filename, url/blobRef`

---

## Minimal API surface (so it’s usable without UI)

* `/projects` create + get + status transitions
* `/projects/{id}/charter` draft/submit/approve
* `/projects/{id}/stakeholders`
* `/projects/{id}/wbs`, `/tasks`, `/cost-items`, `/risks`
* `/projects/{id}/baselines` create snapshot / submit / approve
* `/projects/{id}/deliverables` submit / accept
* `/projects/{id}/change-requests` submit / approve / implement
* `/projects/{id}/status-reports`
* `/projects/{id}/close` submit / approve

---

## The “PMBOK flow” you can actually run end-to-end

1. Create Project → draft Charter → Sponsor approves → Project ACTIVE
2. Build WBS + tasks + costs + risks → submit Baseline v1 → approve
3. Execute: update tasks, log hours, submit deliverables → accept/reject
4. Monitor: weekly status reports + issues
5. Change control: submit CR → approve → update plans → Baseline v2
6. Close: closure report + lessons learned → sponsor approves → CLOSED

If you want, I’ll translate this into:

* a **Postgres schema** (tables + keys),
* and a **backlog of implementation steps** in the order that won’t derail you.
