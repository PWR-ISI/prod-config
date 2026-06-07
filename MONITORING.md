# Monitoring and Observability Guide

This guide covers setting up and using monitoring for the ISI prod-config system.

## Overview

The system uses multiple monitoring and observability tools:

- **CloudWatch** - AWS native logs, metrics, and alarms
- **Structured JSON Logging** - Application logs in JSON format
- **Sentry** - Error tracking and performance monitoring (optional)
- **Datadog** - APM and infrastructure monitoring (optional)

## CloudWatch

CloudWatch is the primary monitoring system integrated into AWS.

### Log Groups

Three log groups are automatically created:

1. `/ecs/schedule-service` - Schedule service application logs
2. `/ecs/file-upload-service` - File upload service application logs
3. `/aws/apigateway/isi-prod-api` - API Gateway access logs

### Viewing Logs

#### AWS Console
1. Go to CloudWatch > Log Groups
2. Select the log group
3. View log streams and events

#### AWS CLI
```bash
# Real-time tail
aws logs tail /ecs/schedule-service --follow

# View specific stream
aws logs tail /ecs/schedule-service --log-stream-names <stream-name> --follow

# Search for errors
aws logs filter-log-events \
  --log-group-name /ecs/schedule-service \
  --filter-pattern "ERROR" \
  --query 'events[].message'
```

### CloudWatch Insights

CloudWatch Insights allows querying logs with a custom query language.

#### View Available Queries

The system automatically creates saved queries:
- `isi-prod-api-errors` - Find API errors
- `isi-prod-slow-requests` - Find slow requests (>1s)

#### Run Custom Queries

```bash
# API errors by service
aws logs start-query \
  --log-group-name /ecs/schedule-service \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message, level | filter level like /ERROR|EXCEPTION/ | stats count() by @logStream'
```

#### Common Queries

**HTTP Status Codes**
```
fields @timestamp, method, path, status_code
| stats count() as request_count by status_code
| sort request_count desc
```

**Error Rate by Service**
```
fields @timestamp, level, @logStream
| filter level = "ERROR"
| stats count() as errors by @logStream
```

**Response Times**
```
fields @timestamp, duration_ms
| filter ispresent(duration_ms)
| stats avg(duration_ms) as avg, pct(duration_ms, 95) as p95, pct(duration_ms, 99) as p99
```

**User Activity**
```
fields @timestamp, user_id, method, path, status_code
| filter ispresent(user_id)
| stats count() as requests by user_id
```

**Database Query Performance**
```
fields @timestamp, query_time_ms
| filter ispresent(query_time_ms)
| stats avg(query_time_ms), max(query_time_ms), pct(query_time_ms, 95)
```

### CloudWatch Metrics

Metrics are published from ECS:
- CPU Utilization
- Memory Utilization
- Network In/Out
- Container Count

Custom metrics from application:
- Request Count
- Error Count
- Response Time (in logs)

### CloudWatch Alarms

Automatic alarms are configured:

#### Schedule Service
- CPU > 80% for 10 minutes → SNS notification
- Memory > 85% for 10 minutes → SNS notification
- 4xx errors > 10 per minute → SNS notification

#### File Upload Service
- CPU > 80% for 10 minutes → SNS notification

#### Managing Alarms

```bash
# List all alarms
aws cloudwatch describe-alarms

# Get alarm details
aws cloudwatch describe-alarms \
  --alarm-names isi-prod-schedule-cpu-high \
  --query 'MetricAlarms[0]'

# Disable alarm
aws cloudwatch disable-alarm-actions \
  --alarm-names isi-prod-schedule-cpu-high

# Enable alarm
aws cloudwatch enable-alarm-actions \
  --alarm-names isi-prod-schedule-cpu-high
```

### CloudWatch Dashboard

A monitoring dashboard is automatically created showing:
- ECS Services Health (CPU and Memory)
- Schedule Service Logs
- API Gateway Errors

Access the dashboard:
```bash
cd terraform
terraform output cloudwatch_dashboard_url
```

## Application Logging

### Log Format

The application uses structured JSON logging:

```json
{
  "timestamp": "2026-05-31 10:30:45,123",
  "level": "INFO",
  "logger": "apps.scheduling.views",
  "message": "Request started",
  "module": "views",
  "function": "__call__",
  "line": 25,
  "request_id": "123e4567-e89b-12d3-a456-426614174000",
  "user_id": "user-uuid",
  "method": "POST",
  "path": "/api/v1/appointments/"
}
```

### Log Levels

- **DEBUG** - Detailed information for debugging
- **INFO** - General informational messages
- **WARNING** - Warning messages for potential issues
- **ERROR** - Error messages for issues
- **CRITICAL** - Critical errors requiring immediate attention

### Configuring Log Level

Update environment variable `LOG_LEVEL` in `.env`:

```bash
LOG_LEVEL=INFO
LOG_FORMAT=json
```

Supported values: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`

## Sentry Integration (Error Tracking)

Sentry provides error tracking, performance monitoring, and alerting.

### Setup

1. Create Sentry account at https://sentry.io
2. Create projects for each service
3. Copy the DSN (Data Source Name)

### Configuration

Update `.env` files:

```bash
# schedule-service/.env
SENTRY_DSN=https://key@sentry.io/project-id

# file-upload-service/.env
SENTRY_DSN=https://key@sentry.io/project-id

ENVIRONMENT=production
```

### Redeploy Services

After updating environment variables, redeploy:

```bash
aws ecs update-service \
  --cluster isi-prod-schedule-cluster \
  --service isi-prod-schedule-svc \
  --force-new-deployment
```

### Using Sentry

1. Access dashboard at https://sentry.io
2. View errors in real-time
3. Set up alerts for specific error patterns
4. Track release information and source maps
5. Monitor performance issues

## Datadog Integration (APM)

Datadog provides application performance monitoring and infrastructure metrics.

### Setup

1. Create Datadog account at https://www.datadoghq.com
2. Generate API key
3. Generate app key

### Configuration

Update `.env` files:

```bash
DATADOG_API_KEY=<your-api-key>
ENVIRONMENT=production
```

Install Datadog Python integration:

```bash
pip install datadog
```

### Redeploy Services

After updating environment variables, redeploy services.

### Using Datadog

1. Access dashboard at app.datadoghq.com
2. View metrics from CloudWatch
3. Set up custom dashboards
4. Create monitors for alerts
5. Track performance metrics

## Log Analysis

### Finding Issues

#### High Error Rate

```bash
aws logs filter-log-events \
  --log-group-name /ecs/schedule-service \
  --filter-pattern "level = ERROR" \
  --query 'events[].[timestamp, message]'
```

#### Slow Requests

```
fields @timestamp, method, path, duration_ms
| filter duration_ms > 5000
| stats count() as slow_requests, avg(duration_ms) as avg_duration by method, path
| sort slow_requests desc
```

#### Database Issues

```
fields @timestamp, message, duration_ms
| filter message like /database|db|query/i
| stats avg(duration_ms) as avg_duration by @logStream
```

#### Memory Leaks

Look for consistently increasing memory usage over time:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average \
  --dimensions Name=ServiceName,Value=schedule-service \
             Name=ClusterName,Value=isi-prod-schedule-cluster
```

## Performance Monitoring

### Key Metrics to Monitor

1. **Request Latency** - Response time for API requests
2. **Error Rate** - Percentage of failed requests
3. **Throughput** - Requests per second
4. **Resource Utilization** - CPU, memory, disk, network
5. **Database Performance** - Query times, connection pool
6. **Cache Hit Rate** - If using caching

### Setting Up Custom Metrics

To publish custom metrics from the application:

```python
import boto3

cloudwatch = boto3.client('cloudwatch')

cloudwatch.put_metric_data(
    Namespace='ISIProdConfig',
    MetricData=[
        {
            'MetricName': 'RequestLatency',
            'Value': response_time_ms,
            'Unit': 'Milliseconds',
            'Dimensions': [
                {'Name': 'Service', 'Value': 'schedule-service'},
                {'Name': 'Endpoint', 'Value': '/appointments/'},
            ]
        }
    ]
)
```

## Alerting

### SNS Notifications

CloudWatch alarms automatically publish to SNS. To receive notifications:

1. Go to SNS > Topics
2. Select the alarm topic
3. Create subscription (Email, SMS, Lambda, etc.)
4. Confirm subscription

### Email Alerts

```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789:isi-prod-appointments \
  --protocol email \
  --notification-endpoint your-email@example.com
```

### Slack Integration

Use Lambda + SNS to send alerts to Slack:

```bash
aws sns subscribe \
  --topic-arn <alarm-topic-arn> \
  --protocol lambda \
  --notification-endpoint <lambda-function-arn>
```

## Best Practices

1. **Log Retention** - Set appropriate retention periods
   - Development: 7 days
   - Staging: 14 days
   - Production: 30 days

2. **Cost Optimization** - Monitor CloudWatch costs
   - Filter logs to exclude verbose DEBUG messages
   - Archive old logs to S3
   - Set appropriate retention periods

3. **Security** - Protect sensitive data
   - Never log passwords or tokens
   - Redact PII (personal identifiable information)
   - Restrict access to logs

4. **Alerting** - Set up meaningful alerts
   - Avoid alert fatigue
   - Use appropriate thresholds
   - Include context in alert messages

5. **Dashboards** - Monitor key metrics
   - Create service dashboards
   - Include business metrics
   - Share with team

## Troubleshooting

### No Logs Appearing

1. Check if CloudWatch log group exists:
```bash
aws logs describe-log-groups --log-group-name-prefix /ecs/
```

2. Check ECS task logs:
```bash
aws ecs describe-tasks \
  --cluster isi-prod-schedule-cluster \
  --tasks <task-arn> \
  --query 'tasks[0].containers[0].logConfiguration'
```

3. Check IAM permissions:
```bash
aws iam get-role-policy \
  --role-name isi-prod-schedule-task-exec \
  --policy-name <policy-name>
```

### High CloudWatch Costs

1. Reduce log verbosity:
```bash
LOG_LEVEL=WARNING
```

2. Shorten retention period:
```bash
aws logs put-retention-policy \
  --log-group-name /ecs/schedule-service \
  --retention-in-days 7
```

3. Archive old logs to S3:
```bash
aws logs create-export-task \
  --log-group-name /ecs/schedule-service \
  --from $(date -d '30 days ago' +%s)000 \
  --to $(date +%s)000 \
  --destination <s3-bucket-name> \
  --destination-prefix schedule-service-logs
```

## Additional Resources

- [CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/)
- [CloudWatch Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Sentry Documentation](https://docs.sentry.io/)
- [Datadog Documentation](https://docs.datadoghq.com/)
- [Python Logging Best Practices](https://docs.python-guide.org/writing/logging/)
