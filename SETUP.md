# ISI — Setup Guide (single self-contained repo)

Everything needed to run the **ISI medical system** now lives in **this one repo**
(`prod-config`). All 8 Django microservices + the React SPA are vendored directly here as
plain folders — no submodules, no sibling clones. Run everything from the `prod-config`
root in **Windows PowerShell**.

There are **two ways to run** it:

| Path | Script | Speed | What it is |
|------|--------|-------|------------|
| **Demo (primary)** | `.\start_demo.ps1` | ~minutes | Each service via its own `docker-compose.yml` (service + Postgres), talking to LocalStack. Best for development & verification. |
| **Full cloud-like** | `.\scripts\run-all.ps1` | 20–40 min | API Gateway + ALB + ECS Fargate + RDS via Terraform/ECR (production-shaped). |

---

## 1. Layout

```
prod-config/
├── start_demo.ps1            # primary one-shot demo runner
├── docker-compose.yml        # LocalStack (emulated AWS)
├── localstack-init/          # Cognito/SQS/SNS bootstrap
├── terraform/                # IaC for the full ECS path
├── scripts/                  # run-all.ps1, deploy-localstack.ps1, ...
├── seed_data.py / seed_demo* # demo data seeders
├── api-test-commands.txt     # ready-made PowerShell API smoke tests
├── api-requests.http         # REST-client requests
├── auth-identity-service/    # ┐
├── appointment-service/      # │
├── schedule-service/         # │ 8 Django microservices (each has its
├── payment-service/          # │ own Dockerfile + docker-compose.yml + .env.example)
├── notification-service/     # │
├── facility-staff-service/   # │
├── medical-record-service/   # │
├── audit-logging-service/    # ┘
└── frontend-portal/          # React (Vite) SPA
```

Service host ports (demo path): auth `8003`, appointment `8001`, audit `8002`,
facility `8004`, medical `8005`, notification `8006`, payment `8007`, schedule `8008`.

---

## 2. Prerequisites

| Tool | Notes |
|------|-------|
| **Docker Desktop** | Must be running. |
| **LocalStack PRO token** | Required — set `LOCALSTACK_AUTH_TOKEN` in `prod-config/.env` (RDS/ECS/ECR/Cognito need PRO). |
| **Node.js 18+** | Only for the frontend dev server (`npm run dev`). |
| **Terraform ≥1.5 / AWS CLI v2** | Only for the full `run-all.ps1` path. |

```powershell
docker --version ; docker compose version
```

---

## 3. Quick start — Demo path

### 3a. Configure LocalStack token

```powershell
# from prod-config/
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
notepad .env          # set LOCALSTACK_AUTH_TOKEN=ls-xxxx
```

### 3b. Start LocalStack + bootstrap Cognito/SNS/SQS

```powershell
docker compose up -d
# wait until healthy:
docker inspect -f '{{.State.Health.Status}}' prod-localstack
# seed Cognito user pool + SQS/SNS + test user (test@example.com / Test1234):
Remove-Item .\localstack-init\ids.env -Force -ErrorAction SilentlyContinue
docker exec prod-localstack bash //etc/localstack/init/ready.d/00-bootstrap.sh
Get-Content .\localstack-init\ids.env   # note COGNITO_USER_POOL_ID / CLIENT_ID
```

### 3c. Create a `.env` for each service

Each service's `docker-compose.yml` has `env_file: - .env` (mandatory; `.env` is
git-ignored). DB settings are baked into compose; `.env` supplies AWS/Cognito wiring.
Services reach LocalStack and each other via `host.docker.internal`. Minimal per-service
`.env`:

```powershell
$svc = 'auth-identity-service','appointment-service','schedule-service',
       'facility-staff-service','medical-record-service','notification-service',
       'payment-service','audit-logging-service'
$ids = Get-Content .\localstack-init\ids.env | Out-String
$pool   = ([regex]'COGNITO_USER_POOL_ID=(.*)').Match($ids).Groups[1].Value.Trim()
$client = ([regex]'COGNITO_USER_POOL_CLIENT_ID=(.*)').Match($ids).Groups[1].Value.Trim()
foreach ($s in $svc) {
@"
DJANGO_SECRET_KEY=dev-not-secret-change-me
DEBUG=True
ALLOWED_HOSTS=*
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_ENDPOINT_URL=http://host.docker.internal:4566
COGNITO_USER_POOL_ID=$pool
COGNITO_APP_CLIENT_ID=$client
COGNITO_USER_POOL_CLIENT_ID=$client
SNS_TOPIC_ARN=arn:aws:sns:us-east-1:000000000000:notifications
APPOINTMENT_SNS_TOPIC_ARN=arn:aws:sns:us-east-1:000000000000:notifications
INTERNAL_SHARED_TOKEN=dev-internal-token
"@ | Set-Content -Encoding ascii (Join-Path $s '.env')
}
```

### 3d. Launch the stack

```powershell
.\start_demo.ps1
```

This builds & starts each service (+ its Postgres) via docker-compose, recreates the
SNS→SQS subscription, starts the notification consumer (`manage.py consume_events`), and
seeds demo data (`seed_demo.py`).

### 3e. Frontend (needs Node 18+)

```powershell
cd frontend-portal
npm install
npm run dev        # http://localhost:3000
```

> No Node installed? Either install it, or build the SPA in a throwaway container:
> `docker run --rm -v ${PWD}:/app -w /app node:20 sh -c "npm ci && npm run build"`.

---

## 4. Verify

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}"        # all *-service + postgres-* up
curl.exe http://localhost:4566/_localstack/health         # LocalStack
curl.exe http://localhost:8003/api/v2/health/             # auth
curl.exe http://localhost:8008/health/                    # schedule
```

For full API smoke tests (login, book appointment, etc.) see **`api-test-commands.txt`**.
Note: in the demo path services are at `http://localhost:<port>` (table above); in the
`run-all.ps1` path they're behind ALB DNS names (`*.elb.localhost.localstack.cloud:4566`).

---

## 5. Full cloud-like path (optional)

```powershell
.\scripts\run-all.ps1                 # build 8 images -> terraform apply -> ECS -> S3 SPA
.\scripts\run-all.ps1 -SkipBuild      # redeploy without rebuilding images
```
Module build contexts now resolve **inside** prod-config (`$Root = prod-config`).

---

## 6. Teardown

```powershell
.\start_demo.ps1 ; # to stop everything:
docker compose down                                       # LocalStack
$svc | ForEach-Object { Push-Location $_; docker compose down -v; Pop-Location }
```

Full reset (wipe emulated AWS + Terraform state):

```powershell
docker compose down
Remove-Item -Recurse -Force .\localstack-data -ErrorAction SilentlyContinue
Remove-Item -Force .\localstack-init\ids.env -ErrorAction SilentlyContinue
Remove-Item -Force .\terraform\terraform.tfstate*, .\terraform\tfplan -ErrorAction SilentlyContinue
```

---

## 7. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `LocalStack never became healthy` | Missing/invalid `LOCALSTACK_AUTH_TOKEN` in `prod-config/.env`. `docker logs prod-localstack`. |
| Service can't reach AWS / events don't flow | `AWS_ENDPOINT_URL` must be `http://host.docker.internal:4566` in the service `.env`. |
| `env file .env not found` on compose up | Create the service `.env` (step 3c). |
| Auth login fails | Cognito IDs in the service `.env` must match `localstack-init/ids.env` (re-run bootstrap if stale). |
| `terraform apply` fails first try (full path) | LocalStack-PRO RDS-SSL race — run it again. |
