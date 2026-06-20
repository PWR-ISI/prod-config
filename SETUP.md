# ISI — Setup (from zero on LocalStack)

This is the **exact way the system runs today**: all 8 Django microservices + the React SPA
deployed onto **AWS emulated by LocalStack PRO**, in a production-shaped layout (ECS Fargate +
RDS + ALB + API Gateway + S3 + SNS/SQS + Cognito). One script — `scripts/run-all.ps1` — brings
the whole stack up from scratch.

Run everything from the `prod-config/` folder in **Windows PowerShell**.
For the architecture and how the pieces fit together, see **[README.md](./README.md)**.

---

## 1. Prerequisites

| Tool | Why |
|------|-----|
| **Docker Desktop** (running) | LocalStack + every ECS task + RDS container run on the host Docker engine |
| **LocalStack PRO token** | RDS / ECS / ECR / Cognito / ALB are PRO-only features |
| **Terraform ≥ 1.5** | provisions the infrastructure |
| **AWS CLI v2** | ECR login/push, ECS rollouts, S3 sync |
| **Node.js 18+** *(optional)* | only if you want to rebuild the SPA outside Docker; `run-all.ps1` builds it in a container |

```powershell
docker --version ; terraform -version ; aws --version
```

Give Docker Desktop enough resources (≈ 6–8 GB RAM): a full run launches LocalStack + 8 ECS
tasks + 7–8 RDS containers.

---

## 2. One-time configuration

### 2a. LocalStack token (`prod-config/.env`)

```powershell
# from prod-config/
if (-not (Test-Path .env)) { "LOCALSTACK_AUTH_TOKEN=ls-REPLACE-ME" | Set-Content -Encoding ascii .env }
notepad .env     # set your real LOCALSTACK_AUTH_TOKEN
```

### 2b. SPA → service URLs (`frontend-portal/.env.production`)

Already present and correct — it points the SPA at the per-service ALBs and is baked into the
build. Only edit it if the `VITE_API_URL` API-Gateway id changes:

```ini
VITE_AUTH_SERVICE_URL=http://prod-config-auth-alb.elb.localhost.localstack.cloud:4566/api/v2
VITE_SCHEDULE_SERVICE_URL=http://prod-config-schedule-alb.elb.localhost.localstack.cloud:4566
VITE_FACILITY_SERVICE_URL=http://prod-config-facility-alb.elb.localhost.localstack.cloud:4566
VITE_MEDICAL_RECORD_SERVICE_URL=http://prod-config-medical-alb.elb.localhost.localstack.cloud:4566
VITE_NOTIFICATION_SERVICE_URL=http://prod-config-notification-alb.elb.localhost.localstack.cloud:4566
VITE_API_URL=http://<api-id>.execute-api.localhost.localstack.cloud:4566
```

---

## 3. Deploy everything (one command)

```powershell
cd "<...>\ISI\prod-config"
.\scripts\run-all.ps1
```

A full run is heavy (**~20–40 min**: 8 image builds + 7 RDS instances). It performs:

| Step | What happens |
|------|--------------|
| 1. Start LocalStack | `docker compose up -d` → waits for `prod-localstack` healthy |
| 2. Bootstrap | `localstack-init/00-bootstrap.sh` → SQS queues + SNS topic (+ Cognito if available) |
| 3. Build images | builds 8 service images, tagged to the LocalStack ECR registry |
| 4. `terraform apply` | network, **Cognito**, **RDS** (per service), **ECS** clusters/services, **ALBs**, **API Gateway**, **S3** |
| 5. ECR push | `aws ecr get-login-password … \| docker login` then pushes all 8 images |
| 6. Roll ECS | `aws ecs update-service --force-new-deployment` for each service; waits ~90 s for tasks to start + migrate |
| 7. Seed slots | runs `manage.py seed_slots` in the schedule task |
| 8. Frontend | builds the SPA (`--target build`), extracts `dist/`, `aws s3 sync … s3://prod-config-frontend` |

Re-deploy variants:

```powershell
.\scripts\run-all.ps1 -SkipBuild                 # reuse images (apply + push + roll only)
.\scripts\run-all.ps1 -SkipSeed -SkipFrontend    # backend infra only
```

> **First `terraform apply` may fail** with a LocalStack-PRO RDS/SSL race — the script retries
> once automatically; if you run terraform by hand, just run `terraform apply` again.

When it finishes it prints the URLs (see §6).

---

## 4. Seed demo data

`run-all.ps1` brings the stack up **empty** (only schedule slots for a placeholder doctor).
Create the demo accounts and catalog as follows.

### 4a. First admin + a patient (PowerShell, API)

The public `register` endpoint honours a `role`, so it can bootstrap the first admin
(the SPA's register page only makes patients).

```powershell
$AUTH = "http://prod-config-auth-alb.elb.localhost.localstack.cloud:4566/api/v2"
function Reg($email,$pw,$first,$last,$role) {
  $body = @{ email=$email; password=$pw; password_confirm=$pw;
            first_name=$first; last_name=$last; role=$role } | ConvertTo-Json
  Invoke-RestMethod -Uri "$AUTH/auth/register/" -Method Post -ContentType 'application/json' -Body $body | Out-Null
}
Reg "admin@isi.test"   "Admin123!"   "Admin" "ISI"      "admin"
Reg "patient@isi.test" "Patient123!" "Jan"   "Kowalski" "patient"
```

### 4b. Facility, doctors and receptionists (admin panel)

Log in to the SPA (§6) as **admin@isi.test / Admin123!** and use the admin panel — this is
the supported path and keeps the doctor catalog correctly linked
(`auth user.cognito_sub == facility Doctor.user_id == schedule doctor_id`):

1. **Placówki** tab → *Dodaj placówkę* → create a facility.
2. **Lekarze** tab → *Dodaj lekarza* (or **Użytkownicy** → *Utwórz użytkownika*, role *Lekarz*):
   set name, e-mail, password, **specjalizacja**, **placówka**, and optionally licence + photo.
   e.g. `kardiolog@isi.test / Doctor123!`, specjalizacja *Kardiolog*.
3. **Użytkownicy** → *Utwórz użytkownika*, role *Recepcjonista* (optionally a photo).

> Doctor accounts must be created here (not via raw API) because the catalog profile is a
> multipart upload that Windows PowerShell 5.1 cannot send easily, and the admin form wires
> the account ↔ catalog link for you.

### 4c. Free slots (doctor panel)

Log in as the doctor → **Mój grafik → + Dodaj wolne terminy** → pick a day and hours. These
become bookable for patients immediately.

### 4d. (optional) Demo medical records

```powershell
$mc = (docker ps --format "{{.Names}}" | Select-String "prod-config-medical-cluster" | Select-Object -First 1)
docker exec "$mc" python seed_demo.py
```

---

## 5. (optional) Redeploy a single service after a code change

```powershell
$Reg  = "000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566"
$repo = "prod-config-schedule-repo"      # see the table in README §2
$base = "prod-config-schedule"           # ECS cluster/service base
$env:AWS_ACCESS_KEY_ID="test"; $env:AWS_SECRET_ACCESS_KEY="test"; $env:AWS_DEFAULT_REGION="us-east-1"

docker build -t "$Reg/${repo}:latest" .\schedule-service
aws ecr get-login-password --endpoint-url http://localhost:4566 | docker login --username AWS --password-stdin $Reg
docker push "$Reg/${repo}:latest"
aws ecs update-service --cluster "$base-cluster" --service "$base-svc" --force-new-deployment --endpoint-url http://localhost:4566
```

Frontend only: rebuild + `aws s3 sync .\frontend-portal\dist s3://prod-config-frontend --delete --endpoint-url http://localhost:4566` (or just `.\scripts\run-all.ps1 -SkipBuild`).

---

## 6. Open & verify

```powershell
$env:AWS_ACCESS_KEY_ID="test"; $env:AWS_SECRET_ACCESS_KEY="test"; $env:AWS_DEFAULT_REGION="us-east-1"
docker ps --format "table {{.Names}}\t{{.Status}}"            # prod-localstack + ls-ecs-prod-config-*-cluster-* tasks
curl.exe http://localhost:4566/_localstack/health             # LocalStack
curl.exe http://prod-config-auth-alb.elb.localhost.localstack.cloud:4566/api/v2/health/      # auth
curl.exe http://prod-config-schedule-alb.elb.localhost.localstack.cloud:4566/health/         # schedule
```

- **SPA:** `http://prod-config-frontend.s3-website.localhost.localstack.cloud:4566`
- Log in as **patient@isi.test / Patient123!**, **kardiolog@isi.test / Doctor123!**, or
  **admin@isi.test / Admin123!** (whatever you seeded in §4).

More ready-made API checks are in **`api-test-commands.txt`**.

---

## 7. Teardown / reset

```powershell
# stop everything (keeps emulated AWS state on disk: localstack-data/, PERSISTENCE=1)
docker compose down

# FULL reset — wipe emulated AWS + Terraform state, then run-all.ps1 starts truly clean
docker compose down
Remove-Item -Recurse -Force .\localstack-data -ErrorAction SilentlyContinue
Remove-Item -Force .\localstack-init\ids.env -ErrorAction SilentlyContinue
Remove-Item -Force .\terraform\terraform.tfstate*, .\terraform\tfplan -ErrorAction SilentlyContinue
```

---

## 8. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `LocalStack never became healthy` | Missing/invalid `LOCALSTACK_AUTH_TOKEN` in `prod-config\.env`. Check `docker logs prod-localstack`. |
| `terraform apply` fails on first try | LocalStack-PRO RDS/SSL race — run it again (the script retries once). |
| `docker push` → `unexpected HTTP status: 200 OK` | Push to the ECR registry host after `docker login`, not to `localhost:4566`. (`run-all.ps1` does this.) |
| Login fails / `ResourceNotFoundException` right after deploy | The auth task is still rolling, or Cognito IDs are stale. Wait for the task, or re-run bootstrap and roll auth. |
| Transient `500` / `ConnectionError` right after a deploy | Under load LocalStack drops the occasional re-entrant call (task → LocalStack). Retry; if many ECS tasks piled up from repeated rolls, scale clean: `aws ecs update-service --cluster <base>-cluster --service <base>-svc --desired-count 0` then `--desired-count 1`. |
| Doctor's slots not visible to patients | The doctor must exist in the **Lekarze** catalog (created via the admin panel) so the patient can pick them; then their self-created slots show. |
| Schedule shows `column … does not exist` | A new field was added to an already-applied `0001` migration. Add a real migration or `ALTER TABLE … ADD COLUMN IF NOT EXISTS …` once. |
| Uploaded photo/document not loading in the browser | The URL must be `http://localhost:4566/<bucket>/<key>` (browser-reachable), never the internal `localstack` host. |
