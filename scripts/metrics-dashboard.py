#!/usr/bin/env python3
"""
ISI Project 3: Real-time Metrics Dashboard
Fetches REAL data from LocalStack: SQS queues, CloudWatch Logs, ECS tasks, Lambda invocations.

Run:  python scripts/metrics-dashboard.py
      (from prod-config/ with AWS creds: AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1)

Open:  http://localhost:8888
"""

from flask import Flask, render_template_string, jsonify
import boto3
from datetime import datetime, timezone, timedelta
import threading
import time
import json
import re

app = Flask(__name__)

AWS_ENDPOINT = "http://localhost:4566"
PROJECT = "prod-config"
REGION = "us-east-1"

sqs = boto3.client("sqs", endpoint_url=AWS_ENDPOINT, region_name=REGION)
logs = boto3.client("logs", endpoint_url=AWS_ENDPOINT, region_name=REGION)
ecs = boto3.client("ecs", endpoint_url=AWS_ENDPOINT, region_name=REGION)
cloudwatch = boto3.client("cloudwatch", endpoint_url=AWS_ENDPOINT, region_name=REGION)

metrics_data = {
    "last_update": None,
    "sqs_queues": {},
    "dlq_queues": {},
    "lambda_logs": {},
    "ecs_services": {},
    "errors": [],
    "system_health": "🟢 OK"
}

def get_sqs_queue_stats():
    """Get REAL SQS queue depths."""
    queues = {
        "schedule-inbox": f"{PROJECT}-schedule-inbox",
        "appointment-inbox": f"{PROJECT}-core-inbox",
        "notification-events": f"{PROJECT}-app-events",
        "notification-jobs": f"{PROJECT}-notification-jobs",
    }

    dlqs = {
        "schedule-inbox-dlq": f"{PROJECT}-schedule-inbox-dlq",
        "appointment-inbox-dlq": f"{PROJECT}-core-inbox-dlq",
        "notification-events-dlq": f"{PROJECT}-app-events-dlq",
        "notification-jobs-dlq": f"{PROJECT}-notification-jobs-dlq",
    }

    sqs_data = {}
    dlq_data = {}

    # Regular queues
    for display_name, queue_name in queues.items():
        try:
            url = f"{AWS_ENDPOINT}/000000000000/{queue_name}"
            attrs = sqs.get_queue_attributes(
                QueueUrl=url,
                AttributeNames=["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible", "ApproximateNumberOfMessagesDelayed"]
            )
            attrs = attrs.get("Attributes", {})
            msg_count = int(attrs.get("ApproximateNumberOfMessages", 0))
            in_flight = int(attrs.get("ApproximateNumberOfMessagesNotVisible", 0))

            sqs_data[display_name] = {
                "message_count": msg_count,
                "in_flight": in_flight,
                "total": msg_count + in_flight,
                "status": "🟡 Backlog" if msg_count > 10 else ("✅ Processing" if in_flight > 0 else "✅ Idle")
            }
        except Exception as e:
            sqs_data[display_name] = {"error": str(e), "message_count": 0}

    # DLQs
    for display_name, dlq_name in dlqs.items():
        try:
            url = f"{AWS_ENDPOINT}/000000000000/{dlq_name}"
            attrs = sqs.get_queue_attributes(
                QueueUrl=url,
                AttributeNames=["ApproximateNumberOfMessages"]
            )
            dlq_count = int(attrs.get("Attributes", {}).get("ApproximateNumberOfMessages", 0))
            dlq_data[display_name] = {
                "message_count": dlq_count,
                "status": "🔴 FAILED" if dlq_count > 0 else "✅ OK"
            }
        except Exception as e:
            dlq_data[display_name] = {"error": str(e), "message_count": 0}

    return sqs_data, dlq_data

def get_lambda_logs():
    """Get Lambda execution logs from CloudWatch Logs — only last 15 minutes."""
    lambda_data = {}
    # Only active Lambda functions (appointment-* removed)
    functions = [
        "schedule-slots",
        "schedule-appointments",
        "schedule-doctor-schedules",
    ]

    cutoff_ms = int((datetime.now(timezone.utc) - timedelta(minutes=15)).timestamp() * 1000)

    for func in functions:
        log_group = f"/aws/lambda/prod-config-{func}"
        try:
            streams_response = logs.describe_log_streams(
                logGroupName=log_group,
                orderBy="LastEventTime",
                descending=True,
                limit=3
            )
            log_streams = streams_response.get("logStreams", [])

            errors = 0
            last_duration = None
            last_execution = None

            for stream in log_streams:
                stream_name = stream.get("logStreamName")
                # Skip streams older than cutoff
                if stream.get("lastEventTimestamp", 0) < cutoff_ms:
                    continue
                if not stream_name:
                    continue

                try:
                    events = logs.get_log_events(
                        logGroupName=log_group,
                        logStreamName=stream_name,
                        startTime=cutoff_ms,
                        limit=100
                    )

                    for event in events.get("events", []):
                        msg = event.get("message", "")

                        if "[ERROR]" in msg or "Traceback" in msg:
                            errors += 1

                        if "Duration:" in msg:
                            match = re.search(r"Duration: (\d+(?:\.\d+)?)\s*ms", msg)
                            if match:
                                last_duration = float(match.group(1))

                        if last_execution is None:
                            last_execution = datetime.fromtimestamp(
                                event.get("timestamp", 0) / 1000,
                                tz=timezone.utc
                            )
                except Exception:
                    continue

            lambda_data[func] = {
                "errors": errors,
                "duration_ms": last_duration or 0,
                "last_execution": last_execution.isoformat() if last_execution else "Never",
                "status": "🔴 Errors" if errors > 0 else "✅ OK" if last_execution else "⚠️ No data"
            }
        except Exception as e:
            lambda_data[func] = {
                "error": str(e),
                "errors": 0,
                "duration_ms": 0,
                "status": "⚠️ No data"
            }

    return lambda_data

def get_ecs_services():
    """Get REAL ECS task status."""
    services = [
        ("auth", f"{PROJECT}-auth-cluster", f"{PROJECT}-auth-svc"),
        ("payment", f"{PROJECT}-payment-cluster", f"{PROJECT}-payment-svc"),
        ("notification", f"{PROJECT}-notification-cluster", f"{PROJECT}-notification-svc"),
        ("facility", f"{PROJECT}-facility-cluster", f"{PROJECT}-facility-svc"),
        ("medical", f"{PROJECT}-medical-cluster", f"{PROJECT}-medical-svc"),
        ("audit", f"{PROJECT}-audit-cluster", f"{PROJECT}-audit-svc"),
    ]

    ecs_data = {}

    for svc_name, cluster, service in services:
        try:
            # Get service details
            response = ecs.describe_services(
                cluster=cluster,
                services=[service]
            )
            service_info = response.get("services", [{}])[0]

            running = service_info.get("runningCount", 0)
            desired = service_info.get("desiredCount", 0)
            pending = service_info.get("pendingCount", 0)

            status = "✅ OK"
            if running == 0:
                status = "🔴 DOWN"
            elif running < desired:
                status = "🟡 Scaling"

            ecs_data[svc_name] = {
                "running_tasks": running,
                "desired_tasks": desired,
                "pending_tasks": pending,
                "status": status
            }
        except Exception as e:
            ecs_data[svc_name] = {
                "error": str(e),
                "running_tasks": 0,
                "status": "⚠️ Error"
            }

    return ecs_data

def fetch_metrics():
    """Fetch all real metrics in background."""
    global metrics_data

    while True:
        try:
            errors = []

            # SQS data
            sqs_stats, dlq_stats = get_sqs_queue_stats()

            # Check for DLQ alerts
            dlq_alert_count = sum(1 for q in dlq_stats.values() if q.get("message_count", 0) > 0)
            if dlq_alert_count > 0:
                for name, stat in dlq_stats.items():
                    if stat.get("message_count", 0) > 0:
                        errors.append(f"🚨 {name}: {stat['message_count']} FAILED messages")

            # Lambda logs
            lambda_stats = get_lambda_logs()
            lambda_error_count = sum(1 for f in lambda_stats.values() if f.get("errors", 0) > 0)

            # ECS services
            ecs_stats = get_ecs_services()
            ecs_down = sum(1 for s in ecs_stats.values() if "DOWN" in s.get("status", ""))
            if ecs_down > 0:
                for name, stat in ecs_stats.items():
                    if "DOWN" in stat.get("status", ""):
                        errors.append(f"🚨 {name}-service: {stat['running_tasks']}/{stat['desired_tasks']} tasks")

            # System health
            if dlq_alert_count > 0 or ecs_down > 0:
                system_health = "🔴 ISSUES"
            elif lambda_error_count > 0:
                system_health = "🟡 WARNINGS"
            else:
                system_health = "🟢 OK"

            metrics_data = {
                "last_update": datetime.now(timezone.utc).isoformat(),
                "sqs_queues": sqs_stats,
                "dlq_queues": dlq_stats,
                "lambda_logs": lambda_stats,
                "ecs_services": ecs_stats,
                "errors": errors,
                "system_health": system_health
            }

        except Exception as e:
            metrics_data["errors"] = [f"Data fetch error: {str(e)}"]

        time.sleep(10)  # Update every 10 seconds

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ISI Project 3 - Real-time Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 1600px; margin: 0 auto; }
        .header {
            background: rgba(255, 255, 255, 0.95);
            padding: 25px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .header-left h1 { color: #333; font-size: 28px; margin-bottom: 10px; }
        .header-left p { color: #666; font-size: 14px; }
        .system-health {
            font-size: 36px;
            font-weight: bold;
            text-align: center;
        }
        .last-update { color: #999; font-size: 12px; margin-top: 10px; }
        .alert-section {
            background: #fee;
            border-left: 4px solid #f44;
            padding: 15px;
            border-radius: 4px;
            margin-bottom: 20px;
        }
        .alert-section h3 { color: #c33; margin-bottom: 10px; }
        .alert-item { color: #c33; font-size: 14px; margin: 5px 0; font-family: 'Courier New', monospace; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(350px, 1fr)); gap: 15px; }
        .card {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        .card h2 { font-size: 16px; color: #333; margin-bottom: 15px; border-bottom: 2px solid #eee; padding-bottom: 10px; }
        .metric-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px;
            border-bottom: 1px solid #eee;
            font-size: 14px;
        }
        .metric-row:last-child { border-bottom: none; }
        .metric-name { color: #666; font-weight: 500; max-width: 50%; word-break: break-word; }
        .metric-value { text-align: right; font-weight: 600; color: #333; max-width: 45%; }
        .metric-detail { color: #999; font-size: 12px; margin-top: 3px; }
        .status-ok { color: #4caf50; }
        .status-warn { color: #ff9800; }
        .status-error { color: #f44; }
        .loading { text-align: center; padding: 20px; color: #999; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 12px; font-size: 11px; font-weight: 600; }
        .badge-ok { background: #e8f5e9; color: #2e7d32; }
        .badge-warn { background: #fff3e0; color: #e65100; }
        .badge-error { background: #ffebee; color: #c62828; }
        @keyframes pulse { 0%, 100% { opacity: 0.6; } 50% { opacity: 1; } }
        .updating { animation: pulse 1.5s ease-in-out infinite; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="header-left">
                <h1>🏥 ISI Project 3 — Real-time Dashboard</h1>
                <p>Live monitoring: SQS, Lambda, ECS from LocalStack</p>
                <div class="last-update" id="last-update">Connecting...</div>
            </div>
            <div class="system-health" id="system-health">🔄</div>
        </div>

        <div id="alerts"></div>

        <div class="grid">
            <!-- SQS Queues -->
            <div class="card">
                <h2>📦 Event Queues (SQS)</h2>
                <div id="sqs-metrics" class="loading">Loading...</div>
            </div>

            <!-- Dead Letter Queues -->
            <div class="card">
                <h2>🚨 Failed Messages (DLQ)</h2>
                <div id="dlq-metrics" class="loading">Loading...</div>
            </div>

            <!-- Lambda Functions -->
            <div class="card">
                <h2>⚡ Lambda Executions</h2>
                <div id="lambda-metrics" class="loading">Loading...</div>
            </div>

            <!-- ECS Microservices -->
            <div class="card">
                <h2>🏗️ ECS Microservices</h2>
                <div id="ecs-metrics" class="loading">Loading...</div>
            </div>
        </div>
    </div>

    <script>
        async function updateDashboard() {
            try {
                const resp = await fetch('/api/metrics');
                const data = await resp.json();

                // Last update + health
                const date = new Date(data.last_update);
                document.getElementById('last-update').textContent =
                    `Last update: ${date.toLocaleTimeString()} — Auto-refresh: 10s`;

                const healthEl = document.getElementById('system-health');
                healthEl.textContent = data.system_health;
                healthEl.classList.remove('updating');

                // Alerts
                const alertDiv = document.getElementById('alerts');
                if (data.errors.length > 0) {
                    alertDiv.innerHTML = `
                        <div class="alert-section">
                            <h3>⚠️ Active Alerts (${data.errors.length})</h3>
                            ${data.errors.map(e => `<div class="alert-item">${e}</div>`).join('')}
                        </div>
                    `;
                } else {
                    alertDiv.innerHTML = '';
                }

                // SQS Queues
                let sqsHtml = '';
                for (const [name, m] of Object.entries(data.sqs_queues)) {
                    if (m.error) continue;
                    const status = m.status || '⚠️ Unknown';
                    const badgeClass = status.includes('Backlog') ? 'badge-warn' : 'badge-ok';
                    const waiting = m.message_count || 0;
                    const processing = m.in_flight || 0;
                    sqsHtml += `
                        <div class="metric-row">
                            <span class="metric-name">${name}</span>
                            <span class="metric-value">
                                <span class="badge ${badgeClass}">${status}</span>
                                <div class="metric-detail">${waiting} waiting | ${processing} processing</div>
                            </span>
                        </div>
                    `;
                }
                document.getElementById('sqs-metrics').innerHTML = sqsHtml || '<div class="loading">No queues</div>';

                // DLQ
                let dlqHtml = '';
                for (const [name, m] of Object.entries(data.dlq_queues)) {
                    if (m.error) continue;
                    const count = m.message_count || 0;
                    const status = m.status || '⚠️ Unknown';
                    const badgeClass = count > 0 ? 'badge-error' : 'badge-ok';
                    dlqHtml += `
                        <div class="metric-row">
                            <span class="metric-name">${name}</span>
                            <span class="metric-value">
                                <span class="badge ${badgeClass}">${status}</span>
                                <div class="metric-detail">${count} failed</div>
                            </span>
                        </div>
                    `;
                }
                document.getElementById('dlq-metrics').innerHTML = dlqHtml || '<div class="loading">No DLQs</div>';

                // Lambda
                let lambdaHtml = '';
                for (const [func, m] of Object.entries(data.lambda_logs)) {
                    if (m.error) continue;
                    const status = m.status || '⚠️ Unknown';
                    const errors = m.errors || 0;
                    const duration = m.duration_ms ? m.duration_ms.toFixed(0) : '0';
                    const badgeClass = errors > 0 ? 'badge-error' : 'badge-ok';
                    lambdaHtml += `
                        <div class="metric-row">
                            <span class="metric-name">${func}</span>
                            <span class="metric-value">
                                <span class="badge ${badgeClass}">${status}</span>
                                <div class="metric-detail">${duration}ms | ${errors} errors</div>
                            </span>
                        </div>
                    `;
                }
                document.getElementById('lambda-metrics').innerHTML = lambdaHtml || '<div class="loading">No logs</div>';

                // ECS
                let ecsHtml = '';
                for (const [svc, m] of Object.entries(data.ecs_services)) {
                    const status = m.status || '⚠️ Unknown';
                    const badgeClass = status.includes('DOWN') ? 'badge-error'
                                      : status.includes('Scaling') ? 'badge-warn' : 'badge-ok';
                    const running = m.running_tasks || 0;
                    const desired = m.desired_tasks || 0;
                    ecsHtml += `
                        <div class="metric-row">
                            <span class="metric-name">${svc}</span>
                            <span class="metric-value">
                                <span class="badge ${badgeClass}">${status}</span>
                                <div class="metric-detail">${running}/${desired} running</div>
                            </span>
                        </div>
                    `;
                }
                document.getElementById('ecs-metrics').innerHTML = ecsHtml || '<div class="loading">No services</div>';

            } catch (e) {
                console.error('Error:', e);
                document.getElementById('system-health').textContent = '❌';
            }
        }

        // Initial load
        updateDashboard();

        // Refresh every 5 seconds (data updates every 10 on server)
        setInterval(updateDashboard, 5000);
    </script>
</body>
</html>
"""

@app.route("/")
def dashboard():
    return render_template_string(HTML_TEMPLATE)

@app.route("/api/metrics")
def api_metrics():
    return jsonify(metrics_data)

if __name__ == "__main__":
    # Start metrics fetcher in background
    fetcher_thread = threading.Thread(target=fetch_metrics, daemon=True)
    fetcher_thread.start()

    print("=" * 70)
    print("ISI Project 3: Real-time Metrics Dashboard")
    print("=" * 70)
    print()
    print("📊 Dashboard: http://localhost:8888")
    print("📡 API:       http://localhost:8888/api/metrics")
    print()
    print("Fetching REAL data from LocalStack:")
    print("  • SQS queue depths (ApproximateNumberOfMessages)")
    print("  • DLQ messages (failures)")
    print("  • Lambda execution logs (CloudWatch Logs)")
    print("  • ECS task states (running/desired)")
    print()
    print("Press Ctrl+C to stop")
    print("=" * 70)

    app.run(host="0.0.0.0", port=8888, debug=False)
