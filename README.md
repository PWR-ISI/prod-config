# ISI — Medical System (microservices on LocalStack)

A multi-service medical-appointment system: **8 Django REST microservices + a React (Vite)
SPA**, deployed to **AWS services emulated by LocalStack PRO** in a production-shaped layout
(ECS Fargate + RDS + ALB + API Gateway + S3 + SNS/SQS + Cognito).

Everything lives in this one repo (`prod-config/`). The whole stack is brought up from
scratch with a single script — see **[SETUP.md](./SETUP.md)** for the exact steps.

> The deployment model is **ECS/Fargate emulated by LocalStack**. Each microservice runs as
> an ECS task (container `ls-ecs-prod-config-<svc>-cluster-…`) behind its own ALB; the SPA is
> static files served from an S3 website bucket. There is no docker-compose-per-service path.

---

## 1. Architecture

```text
                          Browser
                             │
        ┌────────────────────┼─────────────────────────────────────┐
        │ (the SPA calls each service's ALB directly via its         │
        │  VITE_*_SERVICE_URL — see frontend-portal/.env.production)  │
        ▼                                                            ▼
 ┌──────────────┐                                          ┌──────────────────┐
 │  S3 website  │  prod-config-frontend                     │   API Gateway    │
 │  (React SPA) │  *.s3-website.localhost.localstack.cloud  │ (HTTP API, opt.) │
 └──────────────┘                                          └──────────────────┘
        │
        │  HTTP (Bearer JWT) to per-service Application Load Balancers
        │  http://prod-config-<svc>-alb.elb.localhost.localstack.cloud:4566
        ▼
 ┌───────────────────────────────────────────────────────────────────────────┐
 │                       ECS Fargate services (one per microservice)           │
 │  auth │ core(appointment) │ schedule │ payment │ notification │ facility │  │
 │       │                   │          │         │              │ medical  │  │
 │       │                   │          │         │              │ audit    │  │
 └───────────────────────────────────────────────────────────────────────────┘
        │              │                 │                    │
        ▼              ▼                 ▼                    ▼
   RDS Postgres   SNS / SQS          S3 buckets           Cognito
   (per service)  (domain events)    medical-records,     (user pool —
                                     user-avatars         auth-identity)
```

**Request path:** the SPA holds a JWT (from auth-identity) in `localStorage` and sends it as
`Authorization: Bearer …` to each service's ALB. Every service validates the token with a
shared **JWT stub** that reads the `sub` / `custom:role` / `email` claims and exposes
`request.user_id` / `request.user_role` (no per-service Cognito round-trip).

---

## 2. Microservices

All eight are Django + Django REST Framework. Each has a `Dockerfile` and an
`entrypoint.sh` that runs migrations on start, then `gunicorn`.

| Folder | ECS cluster base | ECR repo | ALB host (`…elb.localhost.localstack.cloud:4566`) | Responsibility |
|---|---|---|---|---|
| `auth-identity-service` | `prod-config-auth` | `prod-config-auth` | `prod-config-auth-alb` | Cognito sign-up/sign-in, users, JWT issuance, `admin/staff` provisioning, profile avatars (S3) |
| `appointment-service` | `prod-config-core` | `prod-config-core-repo` | `prod-config-core-alb` | "Core" appointment domain + event consumer (not called directly by the SPA) |
| `schedule-service` | `prod-config-schedule` | `prod-config-schedule-repo` | `prod-config-schedule-alb` | **The SPA's booking backend**: time-slots + appointments; publishes domain events |
| `payment-service` | `prod-config-payment` | `prod-config-payment-repo` | `prod-config-payment-alb` | PayU payments + refunds (gated by `PAYMENTS_ENABLED`, off by default) |
| `notification-service` | `prod-config-notification` | `prod-config-notification` | `prod-config-notification-alb` | In-app notifications; internal `/api/v2/events/` ingest endpoint |
| `facility-staff-service` | `prod-config-facility` | `prod-config-facility` | `prod-config-facility-alb` | Facilities + the **doctor catalog** (specialization, photo, license) |
| `medical-record-service` | `prod-config-medical` | `prod-config-medical` | `prod-config-medical-alb` | Patient medical documents, uploaded to S3 |
| `audit-logging-service` | `prod-config-audit` | `prod-config-audit` | `prod-config-audit-alb` | Audit trail |

Cluster = `<base>-cluster`, service = `<base>-svc` (e.g. `prod-config-schedule-cluster` /
`prod-config-schedule-svc`).

### Frontend — `frontend-portal/`
React + Vite SPA. Built with a multi-stage Docker build (`--target build` → `/app/dist`),
then the `dist/` is synced to the **`prod-config-frontend`** S3 website bucket. Service URLs
are baked in at build time from **`frontend-portal/.env.production`** (`VITE_AUTH_SERVICE_URL`,
`VITE_SCHEDULE_SERVICE_URL`, `VITE_FACILITY_SERVICE_URL`, `VITE_MEDICAL_RECORD_SERVICE_URL`,
`VITE_NOTIFICATION_SERVICE_URL`, `VITE_API_URL`).

---

## 3. Roles

`patient`, `doctor`, `staff` (receptionist — shown in the UI as *Recepcjonista*), `admin`.
The role travels in the JWT and gates both UI panels and server-side permissions.

| Panel | Can do |
|---|---|
| **Patient** | Search doctors, book/cancel a visit, "Opłać" (payment placeholder), view own medical documents, notifications |
| **Doctor** | See today/upcoming/cancelled visits, finish a visit (summary), cancel (reason), **self-service free slots**, attach medical documents, notifications |
| **Receptionist** (`staff`) | Book on behalf of a patient, cancel, register doctors/patients |
| **Admin** | All users (create/edit/delete), doctors, facilities, **all appointments**, create accounts (incl. doctor with specialization/license/photo, receptionist with photo) |

---

## 4. Key cross-service flows

- **Auth / identity.** `auth-identity-service` provisions accounts in Cognito + its own RDS,
  and issues a JWT carrying `sub` (the stable user id used as `patient_id`/`doctor_id`
  everywhere), `role`, and `email`. `POST /admin/staff/` creates doctor/staff/patient
  accounts (admin/receptionist only); it optionally accepts a multipart `photo` that is
  uploaded to the `user-avatars` S3 bucket and stored on the user profile.

- **Doctor catalog linkage.** A doctor is two records kept in sync by id:
  `auth user.cognito_sub` **==** `facility Doctor.user_id` **==** `schedule slot.doctor_id`.
  Creating a doctor (admin "Dodaj lekarza" or "Utwórz użytkownika") makes the auth account
  **and** the facility catalog profile (with specialization). Deleting the user from the admin
  panel also removes the matching facility profile.

- **Booking.** SPA → `schedule-service` reserves the chosen slot and creates the appointment.
  The patient view fetches *all* of a doctor's available slots and filters to the selected
  local day (avoids UTC/local date-boundary issues).

- **Notifications.** When `schedule-service` creates/cancels/completes an appointment it
  publishes a domain event to SNS **and** posts it directly to
  `notification-service` `POST /api/v2/events/` (shared internal token). That endpoint reuses
  the same handlers the SQS consumer would and writes an in-app notification for the patient
  (and doctor). The 🔔 in the SPA polls unread count + lists notifications.
  > The SNS→SQS `consume_events` worker exists but is **not** run in the ECS deployment;
  > the direct `/events/` call is the active path (reliable inter-task call via the ALB).

- **Medical documents.** Doctor/clerk uploads a file via `medical-record-service`, stored in
  the `medical-records` S3 bucket; the patient sees it under their documentation.

- **Payments.** `payment-service` wraps PayU. `PAYMENTS_ENABLED` defaults to **false**
  (no credentials), so booking confirms immediately and the patient's "Opłać" button is a
  placeholder until real PayU keys are supplied.

---

## 5. Data stores (emulated by LocalStack PRO)

- **RDS PostgreSQL** — one database per service (auth, core, schedule, payment, facility,
  medical, notification, audit). Provisioned by Terraform; each service migrates on startup.
- **S3** — `prod-config-frontend` (SPA website), `medical-records` (documents),
  `user-avatars` (profile photos). Document/photo URLs are rewritten to the browser-reachable
  `http://localhost:4566/<bucket>/<key>`.
- **Cognito** — user pool/client provisioned by the Terraform `cognito` module; IDs injected
  into the auth task definition.
- **SNS / SQS** — domain-event topic + queues (created by `localstack-init/00-bootstrap.sh`).

---

## 6. Repository layout

```text
prod-config/
├── docker-compose.yml          # LocalStack PRO (the only long-running compose file)
├── README.md                   # this file
├── SETUP.md                    # from-scratch run instructions
├── localstack-init/            # runs inside LocalStack on startup
│   ├── 00-bootstrap.sh         #   SQS queues + SNS topic + (optional) Cognito pool
│   ├── 01-api-gateway.sh
│   └── ids.env                 #   generated IDs (git-ignored content)
├── terraform/                  # Infrastructure-as-Code (the real deploy)
│   ├── main.tf, provider.tf, variables.tf, outputs.tf
│   └── modules/                #   network, cognito, api-gateway, frontend, sqs,
│                               #   and one module per microservice (ECR+RDS+ECS+ALB)
├── scripts/
│   ├── run-all.ps1             # ★ one-shot deploy (LocalStack→TF→ECR→ECS→S3)
│   └── deploy-*.ps1 / *.bat    # helper/older scripts
├── auth-identity-service/      # ┐
├── appointment-service/        # │
├── schedule-service/           # │ 8 Django microservices
├── payment-service/            # │ (each: Dockerfile, entrypoint.sh, manage.py,
├── notification-service/       # │  requirements.txt, app code, migrations)
├── facility-staff-service/     # │
├── medical-record-service/     # │
├── audit-logging-service/      # ┘
└── frontend-portal/            # React (Vite) SPA  + .env.production
```

---

## 7. Running it

One command from `prod-config/` (Windows PowerShell, Docker Desktop running, LocalStack PRO
token in `.env`):

```powershell
.\scripts\run-all.ps1
```

It performs, in order: **(1)** start LocalStack → **(2)** bootstrap Cognito/SQS/SNS →
**(3)** build 8 service images → **(4)** `terraform apply` (network, RDS, ECS, ALBs, API
Gateway, S3, Cognito) → **(5)** push images to ECR → **(6)** roll the ECS services →
**(7)** seed schedule slots → **(8)** build + sync the SPA to S3.

Re-deploy after code changes without rebuilding infra:

```powershell
.\scripts\run-all.ps1 -SkipBuild          # reuse images
.\scripts\run-all.ps1 -SkipSeed -SkipFrontend
```

Full step-by-step (prerequisites, demo accounts, verification, teardown, troubleshooting) is
in **[SETUP.md](./SETUP.md)**.

### Endpoints after a run
- **SPA:** `http://prod-config-frontend.s3-website.localhost.localstack.cloud:4566`
- **Auth ALB:** `http://prod-config-auth-alb.elb.localhost.localstack.cloud:4566/api/v2/health/`
- **Schedule ALB:** `http://prod-config-schedule-alb.elb.localhost.localstack.cloud:4566/health/`
- **LocalStack health:** `http://localhost:4566/_localstack/health`

---

## 8. Notes

- **Single image deploy.** To redeploy one service: build & tag to
  `000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566/<repo>:latest`, `docker push`,
  then `aws ecs update-service --cluster <base>-cluster --service <base>-svc --force-new-deployment`.
- **Inter-service calls** use the ALB DNS (resolves to the LocalStack edge, reachable from
  inside tasks). They do **not** use host ports.
- **Migrations** run from each service's `entrypoint.sh` on container start; new columns added
  to an already-applied `0001` migration are not picked up automatically — add a real
  migration or `ALTER TABLE` once.
- **LocalStack PRO is required** (RDS, ECS, ECR, Cognito, ALB are PRO features); set
  `LOCALSTACK_AUTH_TOKEN` in `prod-config/.env`.
