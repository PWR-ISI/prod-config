#!/usr/bin/env bash
# LocalStack runs this script after it finishes initialising the requested
# services. It creates the SNS topics and SQS queues that appointment-service
# and schedule-service publish to and consume from, then cross-subscribes so
# each service's inbox receives the other's events.
set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT="000000000000"

echo "[bootstrap] Creating SNS topics..."
awslocal sns create-topic --name appointment-events >/dev/null
awslocal sns create-topic --name schedule-events >/dev/null

echo "[bootstrap] Creating SQS queues..."
awslocal sqs create-queue --queue-name appointment-inbox >/dev/null
awslocal sqs create-queue --queue-name schedule-inbox >/dev/null
# A queue payments will subscribe to once that service is implemented.
awslocal sqs create-queue --queue-name payment-events >/dev/null

APP_TOPIC="arn:aws:sns:${REGION}:${ACCOUNT}:appointment-events"
SCH_TOPIC="arn:aws:sns:${REGION}:${ACCOUNT}:schedule-events"

APP_Q_ARN="arn:aws:sqs:${REGION}:${ACCOUNT}:appointment-inbox"
SCH_Q_ARN="arn:aws:sqs:${REGION}:${ACCOUNT}:schedule-inbox"

echo "[bootstrap] Subscribing schedule-inbox to appointment-events..."
awslocal sns subscribe \
  --topic-arn "${APP_TOPIC}" \
  --protocol sqs \
  --notification-endpoint "${SCH_Q_ARN}" >/dev/null

echo "[bootstrap] Subscribing appointment-inbox to schedule-events..."
awslocal sns subscribe \
  --topic-arn "${SCH_TOPIC}" \
  --protocol sqs \
  --notification-endpoint "${APP_Q_ARN}" >/dev/null

echo "[bootstrap] Done. Topics and queues ready."
