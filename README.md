# ISI Production Config - Microservices Architecture

Multi-tenant medical record system with **unified dev/prod configuration**:
- **Development**: LocalStack emulates all AWS services locally (free, no AWS account needed)
- **Production**: Same code, same docker-compose.yml, switch via environment variables to real AWS

No code changes between dev and production - only configuration.

## Quick Start

### 1. Start LocalStack (AWS emulator)

```bash
docker-compose up -d
```

### 2. Initialize Cognito

```bash
cd localstack-init && ./00-bootstrap.sh
# Note the COGNITO_USER_POOL_ID and COGNITO_APP_CLIENT_ID output
```

### 3. Create .env with Cognito credentials

```bash
cp .env.example .env
# Edit .env and add Cognito IDs from step 2
```

### 4. Start Applications Locally

```bash
# Each in a separate terminal:

# Terminal 1: Auth service
cd auth-identity-service
export $(cat ../.env | grep -v '^#' | xargs)
python manage.py runserver 8001

# Terminal 2: Appointment service
cd appointment-service
export $(cat ../.env | grep -v '^#' | xargs)
python manage.py runserver 8002

# Terminal 3: Frontend
cd frontend-portal
export $(cat ../.env | grep -v '^#' | xargs)
npm start  # or: npm run dev
```

### 5. Open in Browser

```
http://localhost:3000  # Frontend
http://localhost:8001  # Auth API
http://localhost:8002  # Appointment API
http://localhost:4566  # LocalStack dashboard
```

**That's it!** All AWS services (Cognito, SNS, SQS, S3, DynamoDB, etc.) are emulated by LocalStack.

## Architecture

```
┌──────────────────┐
│   Frontend SPA   │
│  (Fargate/S3)    │
└────────┬─────────┘
         │
┌────────▼──────────────┐
│  API Gateway + WAF    │
│ (Cognito Auth)       │
└────────┬──────────────┘
         │
    ┌────┴────┬────────┬──────────┐
    │         │        │          │
    │    Microservices (Fargate)
    │         │        │          │
┌───▼──┐  ┌──▼───┐  ┌─▼──┐  ┌────▼────┐
│Auth  │  │ Appt │  │Sched│  │Payment  │
│ (min 2 replicas, auto-scaling)
└──────┴──────────────────────────────┘
    │
┌───┴──────────────────────────┐
│   Data Layer               │
├──────────────────────────────┤
│ RDS (PostgreSQL)            │
│  - Appointment DB           │
│  - Schedule DB              │
│  - Payment DB               │
│  - Medical Records DB       │
│                             │
│ DynamoDB                    │
│  - Notifications            │
│  - Facility Data            │
│  - Audit Logs               │
│                             │
│ S3                          │
│  - Medical Documents        │
│  - File Uploads             │
│                             │
│ SNS/SQS                     │
│  - Event Bus                │
│  - Async Processing         │
└─────────────────────────────┘
```

## Services

### Backend Microservices

#### 1. **Auth Identity Service**
- User authentication & authorization
- AWS Cognito integration
- JWT token management
- Port: 8001 (local) / ALB (production)

#### 2. **Appointment Service**
- Manage medical appointments
- Schedule integration
- Database: PostgreSQL (RDS)
- Port: 8002 (local)

#### 3. **Schedule Service**
- Doctor/facility schedules
- Time slot management
- Database: PostgreSQL (RDS)
- Port: 8003 (local)

#### 4. **Payment Service**
- Payment processing
- PayU integration
- Transaction history
- Database: PostgreSQL (RDS)
- Port: 8004 (local)

#### 5. **Notification Service**
- Email, SMS, push notifications
- AWS SNS integration
- History tracking (DynamoDB)
- Port: 8005 (local)

#### 6. **Facility Staff Service**
- Manage facilities and staff
- Staff roles & permissions
- Database: DynamoDB
- Port: 8006 (local)

#### 7. **Medical Record Service**
- Electronic health records
- Document storage (S3)
- Database: PostgreSQL (RDS)
- Port: 8007 (local)

#### 8. **Audit Logging Service**
- Compliance & audit trail
- All system events logged
- Database: DynamoDB + CloudWatch Logs
- Port: 8008 (local)

### Frontend

- React SPA with Vite/Webpack build
- Deployed to S3 + CloudFront
- Cognito authentication
- Port: 3000 (local) / CloudFront (production)

## Development

### Prerequisites

- Docker & Docker Compose
- Python 3.11+
- Node.js 18+
- AWS CLI (for production deployment)
- Terraform 1.5+

### Project Structure

```
.
├── auth-identity-service/          # Django service
├── appointment-service/            # Django service
├── schedule-service/               # Django service
├── payment-service/                # Django service
├── notification-service/           # Django service
├── facility-staff-service/         # Django service
├── medical-record-service/         # Django service
├── audit-logging-service/          # Django service
├── frontend-portal/                # React SPA
├── terraform/                      # IaC for AWS
│   ├── modules/
│   │   ├── network/               # VPC, subnets, security groups
│   │   ├── cognito/               # User pool, app client
│   │   ├── *-service/             # Service-specific (RDS, ECS, etc)
│   │   ├── api-gateway/           # API Gateway + integration
│   │   ├── frontend/              # S3 + CloudFront
│   │   └── sqs/                   # SQS queues
│   ├── main.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── envs/
│       ├── local.tfvars           # LocalStack dev config
│       └── prod.tfvars            # Production config
├── localstack-init/               # LocalStack initialization scripts
├── scripts/                       # Helper scripts
│   ├── local-dev-setup.sh
│   ├── build-and-push-ecr.sh
│   └── deploy-fargate.sh
├── docker-compose.yml             # Local dev (with LocalStack)
├── docker-compose.prod.yml        # Production reference (ECS task defs)
├── DEPLOYMENT.md                  # Detailed deployment guide
└── README.md                      # This file
```

### Local Development Workflow

```bash
# 1. Start services
./scripts/local-dev-setup.sh start

# 2. View logs
./scripts/local-dev-setup.sh logs appointment-service

# 3. Make code changes
# (Services will auto-reload in development)

# 4. Test API
curl http://localhost:8002/appointments/

# 5. Stop when done
./scripts/local-dev-setup.sh stop

# 6. Clean local data (optional)
./scripts/local-dev-setup.sh clean
```

### Environment Variables

#### Local Development (.env)

```bash
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_ENDPOINT_URL=http://localhost:4566
LOCALSTACK_AUTH_TOKEN=your-token
COGNITO_USER_POOL_ID=...
COGNITO_APP_CLIENT_ID=...
```

#### Production (.env.prod)

```bash
AWS_ACCOUNT_ID=123456789012
AWS_REGION=us-east-1
PROJECT_NAME=isi-prod-config
RDS_APPOINTMENT_ENDPOINT=...
RDS_SCHEDULE_ENDPOINT=...
... (see .env.prod.example for all variables)
```

## Database

### RDS Instances (PostgreSQL)

- **Appointment DB**: `appointment_db`
- **Schedule DB**: `schedule_db`
- **Payment DB**: `payment_db`
- **Medical Records DB**: `medical_db`

All in same DB subnet group in private subnets.

### DynamoDB Tables

- `isi-prod-notifications` - Notification history
- `isi-prod-facility` - Facility & staff data
- `isi-prod-audit-logs` - Audit trail

### S3 Buckets

- `isi-prod-medical-records` - Electronic health records
- `isi-prod-files` - General file uploads

## Deployment

### To LocalStack (Development)

```bash
./scripts/local-dev-setup.sh start
```

### To AWS Fargate (Production)

Full guide: see [DEPLOYMENT.md](./DEPLOYMENT.md)

```bash
# Prepare
cp .env.prod.example .env.prod
# ... edit .env.prod ...

# Build images
./scripts/build-and-push-ecr.sh prod all

# Deploy
ENVIRONMENT=prod ./scripts/deploy-fargate.sh apply
```

## Auto-Scaling

Each service is configured with:
- **Minimum tasks**: 2 (for redundancy)
- **Maximum tasks**: 5-10 (depends on service)
- **Scale-out trigger**: CPU >70% or Memory >80%
- **Scale-in trigger**: CPU <30% or Memory <40%

Scaling policies are defined in Terraform modules.

## Monitoring & Logging

### CloudWatch

```bash
# View logs for a service
aws logs tail /ecs/isi-prod-appointment-service --follow

# View metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=appointment-service \
  --start-time 2024-05-23T10:00:00Z \
  --end-time 2024-05-23T11:00:00Z \
  --period 300 \
  --statistics Average
```

### Health Checks

Each service has `/health` endpoint for:
- ECS task health checks
- Load balancer target health
- Manual monitoring

## Security

### Authentication
- AWS Cognito for user management
- JWT tokens for API calls
- API Gateway authorizer

### Database
- RDS in private subnets (no internet access)
- Secrets Manager for credentials
- Encrypted backups

### Network
- VPC with private/public subnets
- Security groups for each layer
- WAF on API Gateway (optional)

### Secrets Management

Store sensitive credentials in AWS Secrets Manager:

```bash
# Create a secret
aws secretsmanager create-secret \
  --name prod/appointment/db \
  --secret-string '{"username":"user","password":"pass"}'

# Reference in Fargate task definition
# (automatically handled by Terraform)
```

## Contributing

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Make changes to your service
3. Test locally: `./scripts/local-dev-setup.sh start`
4. Commit with clear messages
5. Push and create pull request

### Running Tests

```bash
# Local (with docker-compose running)
docker-compose exec appointment-service python manage.py test

# Or manually:
cd appointment-service
python manage.py test
```

## Troubleshooting

### Services Not Starting

```bash
# Check logs
./scripts/local-dev-setup.sh logs

# Restart all
./scripts/local-dev-setup.sh stop
./scripts/local-dev-setup.sh start
```

### Database Connection Error

```bash
# Check if postgres containers are healthy
docker-compose ps

# Check connection string in .env
cat .env | grep DJANGO_DB
```

### Frontend Not Loading

```bash
# Check if frontend service is running
curl http://localhost:3000

# Check frontend logs
./scripts/local-dev-setup.sh logs frontend-portal
```

### Production Issues

See [DEPLOYMENT.md](./DEPLOYMENT.md) troubleshooting section.

## Cost Estimation

### Development (LocalStack)
- Free (all local)

### Production (Fargate + RDS)
Approximate monthly costs:

| Resource | Estimate |
|----------|----------|
| Fargate (9 services × 2-4 tasks) | $500-1500 |
| RDS (4 instances, multi-AZ) | $1500-3000 |
| DynamoDB (on-demand) | $200-500 |
| S3 (storage + CDN) | $50-200 |
| NAT Gateway | $45 |
| API Gateway | $50-200 |
| **Total** | **~$2500-5500/month** |

*Use Reserved Instances and Savings Plans for 20-40% savings*

## Support & Documentation

- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [LocalStack Documentation](https://docs.localstack.cloud/)
- [Django Documentation](https://docs.djangoproject.com/)
- [React Documentation](https://react.dev/)

## License

[Your License Here]

## Team

- **Architecture**: WhiteStorm
- **DevOps/Infrastructure**: Team
- **Backend Services**: Team
- **Frontend**: Team
