# Environment Setup

## Docker Compose — Development (default)

All services including PostgreSQL and Keycloak run as Docker containers.
The Gateway and frontend dev server are exposed to the host.

### Prerequisites

- Docker Desktop (running)
- Java 17 JDK on `PATH` (for Gradle builds)

### How it works

```
localhost:5173  (Frontend — Vite dev server, HMR enabled)
localhost:8080  (Gateway — routes /auth to Keycloak, /api to services)
localhost:8888  (Config Server — not normally accessed directly)
localhost:15672 (RabbitMQ management UI)
```

Three PostgreSQL instances:

| Container | Databases | Used by |
|-----------|-----------|---------|
| `postgres` | accountsdb, contactsdb, opportunitiesdb, activitiesdb, projectsdb, maindb | CRM + Projects services |
| `postgres-keycloak` | keycloak | Keycloak |
| `postgres-logs` | logsdb | Log Consumer |

### Scripts

| Script | Purpose |
|--------|---------|
| `.\scripts\docker\compose-up.ps1` | Build JARs + images, start all containers |
| `.\scripts\docker\compose-up.ps1 -SkipBuild` | Skip Gradle, rebuild images only |
| `.\scripts\docker\compose-up.ps1 -Foreground` | Stream logs (blocks terminal) |
| `.\scripts\docker\compose-up.ps1 -Services gateway,accounts` | Partial rebuild — listed services only |
| `.\scripts\docker\compose-down.ps1` | Stop and remove all containers |
| `.\scripts\docker\compose-down.ps1 -Volumes` | Also wipe all data volumes (full reset) |
| `.\scripts\docker\system-test.ps1` | End-to-end smoke tests (CRM + PMBOK) |

### Quick start

```powershell
# Build everything and start (takes ~3–5 min on first run)
.\scripts\docker\compose-up.ps1

# Then open:  http://localhost:5173

# Run smoke tests (wait for all services healthy first)
.\scripts\docker\system-test.ps1
```

### Watch logs

```powershell
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f gateway
```

### Check container status

```powershell
docker compose -f docker-compose.yml -f docker-compose.dev.yml ps
```

### Inspect the request audit log

```powershell
docker compose -f docker-compose.yml -f docker-compose.dev.yml exec postgres-logs `
  psql -U loguser -d logsdb -c "SELECT * FROM request_log ORDER BY id DESC LIMIT 10;"
```

### Full reset

```powershell
.\scripts\docker\compose-down.ps1 -Volumes
.\scripts\docker\compose-up.ps1
```

### Keycloak admin

```
http://localhost:8080/auth/admin
Username: keycloak  |  Password: keycloak  |  Realm: crm
```

Test users (`testuser`, `testuser2`) are created automatically by the `keycloak-init` container
on first startup.

---

## Docker Compose — Production (external databases)

Production mode runs all app services and Keycloak in Docker but connects to **externally managed
databases** — no database containers are started.

Compose files: `docker-compose.yml` + `docker-compose.prod.yml`

`docker-compose.prod.yml` adds:
- `SPRING_DATASOURCE_*` env vars on each service to override Config Server's DB properties
- `restart: always` on all services
- Memory limits per container

### Prerequisites

- Docker (Engine or Desktop) running
- Java 17 JDK on `PATH`
- External PostgreSQL server(s) provisioned (see below)

### Database setup

Run once on your external PostgreSQL server before first deploy:

**App databases:**
```sql
CREATE DATABASE maindb;
CREATE DATABASE accountsdb;
CREATE DATABASE contactsdb;
CREATE DATABASE opportunitiesdb;
CREATE DATABASE activitiesdb;
CREATE DATABASE projectsdb;
```

**Logs database:**
```sql
CREATE DATABASE logsdb;
CREATE USER loguser WITH PASSWORD 'yourpassword';
GRANT ALL PRIVILEGES ON DATABASE logsdb TO loguser;
```

**Keycloak database:**
```sql
CREATE DATABASE keycloak;
CREATE USER keycloak WITH PASSWORD 'yourpassword';
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;
```

Flyway creates all table schemas automatically on first service startup.

### Configuration

```powershell
Copy-Item .env.prod.example .env.prod
# Edit .env.prod and fill in all values
```

`.env.prod` keys:

```ini
APP_DB_HOST=your-postgres.example.com
APP_DB_PORT=5432
APP_DB_USER=postgres
APP_DB_PASSWORD=strongpassword

LOGS_DB_HOST=your-logs-postgres.example.com
LOGS_DB_PORT=5432
LOGS_DB_USER=loguser
LOGS_DB_PASSWORD=strongpassword

KEYCLOAK_DB_HOST=your-keycloak-postgres.example.com
KEYCLOAK_DB_NAME=keycloak
KEYCLOAK_DB_USER=keycloak
KEYCLOAK_DB_PASSWORD=strongpassword
```

> **Never commit `.env.prod` to version control** — it is listed in `.gitignore`.

### Start

```powershell
.\scripts\docker\compose-up.ps1 -Env prod
```

### Reliability notes

| Concern | How it is handled |
|---------|------------------|
| Service crashes | `restart: always` on all containers |
| DB connection at startup | Spring Boot retries on `DataSourceConnectionException` |
| Config Server unavailability | `fail-fast=true` + 10 retry attempts with exponential backoff |
| RabbitMQ outage | Best-effort publish; failures logged but not fatal |
| Memory pressure | Memory limits in `docker-compose.prod.yml` |

---

## Kubernetes / Minikube (staging)

All services run as Kubernetes Deployments managed by a Helm chart. `ingress-nginx` routes
traffic to the Gateway. Port-forward is used because the Minikube Docker driver does not expose
the node IP to the host.

```
localhost:8080 (kubectl port-forward → ingress-nginx → Gateway → services)
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
| `.\scripts\kubernetes\reinstall.ps1 -SkipBuild` | `helm upgrade` only |
| `.\scripts\kubernetes\reinstall.ps1 -HardReset` | `helm uninstall` + `helm install` (clears PVCs) |
| `.\scripts\kubernetes\env-down.ps1` | Stop port-forward + `helm uninstall` |
| `.\scripts\kubernetes\env-down.ps1 -StopMinikube` | Also stop the Minikube VM |
| `.\scripts\kubernetes\port-forward.ps1 start/stop/status` | Manage background port-forward |
| `.\scripts\kubernetes\system-test.ps1` | End-to-end smoke tests |

### Quick start

```powershell
# First-time setup (~10–15 min)
.\scripts\kubernetes\env-up.ps1

# After code changes
.\scripts\kubernetes\reinstall.ps1

# After Helm/values changes only
.\scripts\kubernetes\reinstall.ps1 -SkipBuild

.\scripts\kubernetes\system-test.ps1
```

### Manual image build

```powershell
# Point Docker CLI at Minikube's daemon (required before every build)
& minikube -p minikube docker-env --shell powershell | Where-Object { $_ -match '^\$Env:' } | Invoke-Expression

Push-Location Gateway; .\gradlew.bat clean build -x test; docker build -t gateway:latest .; Pop-Location
```

### Watch pods

```powershell
kubectl get pods -w
```

Expected steady state: all Deployments `1/1 Running`, init Jobs `Completed`.

### Useful commands

```powershell
# Logs
kubectl logs -l app=gateway -f
kubectl logs -l app=keycloak -f

# Describe a failing pod
kubectl describe pod <pod-name>

# Helm
helm list
helm get values project-y
helm template project-y ./deployment -f ./deployment/values-dev.yaml --debug
helm rollback project-y

# RabbitMQ management UI (temporary)
kubectl port-forward svc/rabbitmq 15672:15672
# → http://localhost:15672  (guest / guest)

# Request audit log
kubectl exec deployment/postgres-logs -- psql -U loguser -d logsdb -c \
  "SELECT * FROM request_log ORDER BY id DESC LIMIT 10;"
```
