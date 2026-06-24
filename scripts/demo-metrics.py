#!/usr/bin/env python3
"""
Demo metrics generator for ISI project.
Simulates real system activity: publishes CloudWatch metrics + sends SQS messages
to demonstrate the monitoring dashboard in action.

Run:  python scripts/demo-metrics.py
      (from prod-config/ with AWS creds: AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1)
"""

import boto3
import json
import time
import random
from datetime import datetime, timezone

AWS_ENDPOINT = "http://localhost:4566"
PROJECT = "prod-config"

cloudwatch = boto3.client("cloudwatch", endpoint_url=AWS_ENDPOINT)
sqs = boto3.client("sqs", endpoint_url=AWS_ENDPOINT)

LAMBDA_FUNCTIONS = ["list-appointments", "create-appointment", "cancel-appointment", "get-appointment"]
SQS_QUEUES = [
    f"{PROJECT}-schedule-inbox",
    f"{PROJECT}-core-inbox",
    f"{PROJECT}-app-events",
    f"{PROJECT}-notification-jobs",
]
DLQ_NAMES = [
    f"{PROJECT}-schedule-inbox-dlq",
    f"{PROJECT}-core-inbox-dlq",
    f"{PROJECT}-app-events-dlq",
    f"{PROJECT}-notification-jobs-dlq",
]

def publish_lambda_metrics():
    """Publish Lambda execution metrics."""
    for func in LAMBDA_FUNCTIONS:
        # Errors (1-3 random errors per cycle, roughly one every 10 min per function)
        if random.random() < 0.15:  # 15% chance of error
            cloudwatch.put_metric_data(
                Namespace="AWS/Lambda",
                MetricData=[{
                    "MetricName": "Errors",
                    "Value": 1,
                    "Unit": "Count",
                    "Timestamp": datetime.now(timezone.utc),
                    "Dimensions": [{"Name": "FunctionName", "Value": func}]
                }]
            )
            print(f"  Lambda {func}: 1 error")

        # Duration (p95, 500–2000 ms)
        duration = random.randint(500, 2000)
        cloudwatch.put_metric_data(
            Namespace="AWS/Lambda",
            MetricData=[{
                "MetricName": "Duration",
                "Value": duration,
                "Unit": "Milliseconds",
                "Timestamp": datetime.now(timezone.utc),
                "Dimensions": [{"Name": "FunctionName", "Value": func}]
            }]
        )
        print(f"  Lambda {func}: duration {duration}ms")

        # Throttles (rare, < 1%)
        if random.random() < 0.01:
            cloudwatch.put_metric_data(
                Namespace="AWS/Lambda",
                MetricData=[{
                    "MetricName": "Throttles",
                    "Value": 1,
                    "Unit": "Count",
                    "Timestamp": datetime.now(timezone.utc),
                    "Dimensions": [{"Name": "FunctionName", "Value": func}]
                }]
            )

def publish_sqs_metrics():
    """Publish SQS queue depth metrics."""
    for queue_name in SQS_QUEUES:
        # Random messages in queue (0–10)
        msg_count = random.randint(0, 10)
        cloudwatch.put_metric_data(
            Namespace="AWS/SQS",
            MetricData=[{
                "MetricName": "ApproximateNumberOfMessagesVisible",
                "Value": msg_count,
                "Unit": "Count",
                "Timestamp": datetime.now(timezone.utc),
                "Dimensions": [{"Name": "QueueName", "Value": queue_name}]
            }]
        )
        print(f"  SQS {queue_name}: {msg_count} messages")

def publish_dlq_metrics():
    """Publish Dead Letter Queue metrics (simulate failures)."""
    for dlq_name in DLQ_NAMES:
        # Every 5 cycles (~60 sec), simulate a failed message going to DLQ
        if random.random() < 0.2:  # 20% chance each cycle
            msg_count = random.randint(1, 3)
            cloudwatch.put_metric_data(
                Namespace="AWS/SQS",
                MetricData=[{
                    "MetricName": "ApproximateNumberOfMessagesVisible",
                    "Value": msg_count,
                    "Unit": "Count",
                    "Timestamp": datetime.now(timezone.utc),
                    "Dimensions": [{"Name": "QueueName", "Value": dlq_name}]
                }]
            )
            print(f"  DLQ {dlq_name}: {msg_count} FAILED messages (alert!)")

def publish_ecs_metrics():
    """Publish ECS task count + CPU/memory metrics."""
    services = [
        ("auth", "prod-config-auth-cluster", "prod-config-auth-svc"),
        ("payment", "prod-config-payment-cluster", "prod-config-payment-svc"),
        ("notification", "prod-config-notification-cluster", "prod-config-notification-svc"),
        ("facility", "prod-config-facility-cluster", "prod-config-facility-svc"),
        ("medical", "prod-config-medical-cluster", "prod-config-medical-svc"),
        ("audit", "prod-config-audit-cluster", "prod-config-audit-svc"),
    ]

    for name, cluster, service in services:
        # Running tasks (1–2, occasional 0 to trigger alarm)
        running_count = random.choices([0, 1, 2], weights=[5, 50, 45])[0]
        cloudwatch.put_metric_data(
            Namespace="AWS/ECS",
            MetricData=[{
                "MetricName": "RunningCount",
                "Value": running_count,
                "Unit": "Count",
                "Timestamp": datetime.now(timezone.utc),
                "Dimensions": [
                    {"Name": "ClusterName", "Value": cluster},
                    {"Name": "ServiceName", "Value": service}
                ]
            }]
        )
        if running_count == 0:
            print(f"  ECS {name}: {running_count} tasks running (ALERT!)")
        else:
            print(f"  ECS {name}: {running_count} tasks")

        # CPU utilization (20–60%, occasional spike to 85+ to trigger alarm)
        cpu = random.choices(range(20, 60), k=1)[0]
        if random.random() < 0.1:
            cpu = random.randint(85, 95)
        cloudwatch.put_metric_data(
            Namespace="AWS/ECS",
            MetricData=[{
                "MetricName": "CPUUtilization",
                "Value": cpu,
                "Unit": "Percent",
                "Timestamp": datetime.now(timezone.utc),
                "Dimensions": [
                    {"Name": "ClusterName", "Value": cluster},
                    {"Name": "ServiceName", "Value": service}
                ]
            }]
        )
        print(f"    CPU: {cpu}%")

        # Memory utilization (40–70%)
        mem = random.randint(40, 70)
        cloudwatch.put_metric_data(
            Namespace="AWS/ECS",
            MetricData=[{
                "MetricName": "MemoryUtilization",
                "Value": mem,
                "Unit": "Percent",
                "Timestamp": datetime.now(timezone.utc),
                "Dimensions": [
                    {"Name": "ClusterName", "Value": cluster},
                    {"Name": "ServiceName", "Value": service}
                ]
            }]
        )

def send_sample_sqs_messages():
    """Send test messages to SQS queues."""
    sample_events = [
        {"event": "appointment.created", "appointment_id": "apt-001", "patient": "jan@test.pl"},
        {"event": "appointment.cancelled", "appointment_id": "apt-002", "reason": "Rescheduled"},
        {"event": "payment.succeeded", "order_id": "PAY-123", "amount": 15000},
        {"event": "notification.sent", "type": "email", "recipient": "patient@test.pl"},
    ]

    for queue_name in SQS_QUEUES:
        if random.random() < 0.6:  # 60% chance to send a message
            event = random.choice(sample_events)
            try:
                sqs.send_message(
                    QueueUrl=f"{AWS_ENDPOINT}/000000000000/{queue_name}",
                    MessageBody=json.dumps(event),
                    MessageAttributes={
                        "source": {"StringValue": "demo", "DataType": "String"},
                    }
                )
                print(f"  → SQS {queue_name}: sent {event['event']}")
            except Exception as e:
                print(f"  ✗ SQS {queue_name}: {e}")

def main():
    print(f"[{datetime.now().strftime('%H:%M:%S')}] ISI Demo Metrics Cycle\n")

    print("📊 Lambda metrics:")
    publish_lambda_metrics()

    print("\n📦 SQS queue depths:")
    publish_sqs_metrics()

    print("\n🚨 Dead Letter Queues:")
    publish_dlq_metrics()

    print("\n🏗️  ECS task metrics:")
    publish_ecs_metrics()

    print("\n📨 Sending sample SQS messages:")
    send_sample_sqs_messages()

    print("\n✓ Metrics published. Check CloudWatch dashboard at:")
    print("  http://localhost:4566/ → CloudWatch → Dashboards → prod-config-main")

if __name__ == "__main__":
    import os
    os.environ.setdefault("AWS_ACCESS_KEY_ID", "test")
    os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")
    os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")

    print("=" * 70)
    print("ISI Project 3: Demo Metrics Generator")
    print("=" * 70 + "\n")

    try:
        while True:
            main()
            print("\n" + "—" * 70)
            print("Sleeping 15 seconds before next cycle... (Ctrl+C to stop)")
            print("—" * 70 + "\n")
            time.sleep(15)
    except KeyboardInterrupt:
        print("\n\n✓ Demo stopped.")
