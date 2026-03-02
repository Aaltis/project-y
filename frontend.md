Here’s a **frontend plan you can paste to Claude** that fits your current architecture (Gateway on `:8080`, Keycloak, Swagger-first APIs) and adds **diagrams** with **minimal extra libraries**. It’s based on what you described in README. 

---

## Prompt for Claude: Frontend plan (minimal libs, diagrams included)

Build a small frontend for “Project Y” that talks to the Gateway (`http://localhost:8080`) and uses Keycloak for login. Keep dependencies minimal.

### Stack

* React + TypeScript + Vite
* `react-router-dom` (routing)
* `keycloak-js` (OIDC login + PKCE)
* No UI framework (use plain CSS)

### Pages (MVP)

1. **Login**

* Button: “Login with Keycloak”
* After login, store token in memory, show username + roles.

2. **Home / Dashboard**

* Quick links + “system status” section:

  * show `/actuator/health` checks (gateway + a few services) as green/red
* Show “Current token” info (username, roles, sub)

3. **CRM**
   Tabs:

* Accounts
* Contacts (nested under account)
* Opportunities (list + detail)
* Activities (for an opportunity)

Required flows:

* Create account
* Create contact under account
* Create opportunity under account
* Update opportunity fields
* Stage transition (PROSPECT→…→WON/LOST)
* Show activities list (including auto-created NOTE audit)

4. **Projects (PMBOK)**
   Left sidebar: pick project → main content shows modules:

* Charter (create/submit/approve)
* WBS + Tasks + Cost Items
* Baselines (create/submit/approve + show snapshot JSON)
* Deliverables (submit/accept/reject)
* Change Requests (draft/submit/review/approve/implement)
* Status Reports (create + list newest first)
* Closing (closure report + approve + close project)

Keep UI simple: table lists + detail panel + forms.

5. **Docs / Diagrams**
   Add a page that displays diagrams already produced by PlantUML as images:

* `docs/architecture.png`
* `docs/database.png`

Implementation:

* Add these images into frontend `public/diagrams/` (copy from repo docs).
* Render them with `<img>` plus:

  * click to open fullscreen modal
  * basic zoom controls (CSS scale) and “Reset zoom”
    No extra diagram libs required.

Optional nice-to-have (still minimal): allow toggling between “Architecture” and “Database schema” images.

### API integration rules

* All calls go through Gateway: `/api/...`
* Add Authorization header: `Bearer <token>`
* Implement a small `api.ts` wrapper:

  * attaches token
  * handles 401 by redirecting to login
  * parses JSON + shows error toast (simple inline banner, no toast library)

### Keycloak integration

* Configure Keycloak client: `crm-api` realm `crm`
* Use `keycloak-js` init with PKCE, login/logout
* Expose helper `getToken()` and `refreshToken()` (refresh before expiry)

### UI components (keep few)

* `Layout` (top nav + logout)
* `DataTable` (simple table)
* `Form` components (controlled inputs)
* `DetailDrawer` or right-side panel
* `ErrorBanner`

### Route map

* `/login`
* `/` dashboard
* `/crm/accounts`, `/crm/accounts/:id`
* `/crm/opportunities`, `/crm/opportunities/:id`
* `/projects`, `/projects/:id`
* `/docs/diagrams`

### Deliverable

Provide:

* file structure
* full working code with mocked `.env` for:

  * `VITE_API_BASE=http://localhost:8080`
  * `VITE_KEYCLOAK_URL=http://localhost:8080/auth`
  * `VITE_KEYCLOAK_REALM=crm`
  * `VITE_KEYCLOAK_CLIENT_ID=crm-api`

Make it run with `npm install` + `npm run dev`.

---

### Notes (important constraints from backend)

* JWT is required for everything except `/auth/**` and Swagger/health. 
* Role/ownership matters: show 403 errors clearly (don’t hide them). 
* Stage transitions are forward-only, any→LOST, WON needs amount+closeDate. 
* Project roles are per-project; `crm_admin` bypasses checks. 

---

If you want the diagrams to be **manipulable** later without many libs, the next step would be: keep the image page now, and add a second “Interactive graph” page later using **one** library (Mermaid *or* React Flow). For MVP, the static PNG approach is the lowest friction and matches your existing PlantUML pipeline.
