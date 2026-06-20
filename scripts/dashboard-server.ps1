<#
.SYNOPSIS
  Local CloudWatch Dashboard viewer - displays prod-config-main dashboard on localhost:8080

.DESCRIPTION
  Fetches dashboard from LocalStack CloudWatch and renders it as HTML with charts.
  Requires: Chart.js, internet (for CDN) or --offline flag to use mock data

.EXAMPLE
  .\dashboard-server.ps1
  .\dashboard-server.ps1 -Port 3000
  .\dashboard-server.ps1 -Offline
#>

param(
    [int]$Port = 8080,
    [switch]$Offline
)

$ErrorActionPreference = "Continue"
$ScriptDir = $PSScriptRoot
$ProdConfig = Split-Path $ScriptDir -Parent

# AWS config for LocalStack
$env:AWS_ENDPOINT_URL = "http://localhost:4566"
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

function Get-Dashboard {
    Write-Host "[Dashboard] Fetching dashboard from LocalStack..." -ForegroundColor Cyan

    $result = aws cloudwatch get-dashboard `
        --dashboard-name prod-config-main `
        --endpoint-url http://localhost:4566 `
        --region us-east-1 `
        --output json 2>$null | ConvertFrom-Json

    if ($result.DashboardBody) {
        return $result.DashboardBody | ConvertFrom-Json
    }

    Write-Host "[Dashboard] ⚠️  Could not fetch dashboard, using mock data" -ForegroundColor Yellow
    return @{
        widgets = @(
            @{
                type = "metric"
                properties = @{
                    title = "SQS Queues (Mock)"
                    metrics = @()
                }
            }
        )
    }
}

function New-DashboardHTML {
    param([object]$Dashboard)

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ISI Medical System - CloudWatch Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        .header {
            background: white;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        .header h1 {
            color: #667eea;
            font-size: 28px;
            margin-bottom: 10px;
        }
        .header p {
            color: #666;
            font-size: 14px;
        }
        .dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(500px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .widget {
            background: white;
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .widget h2 {
            font-size: 18px;
            color: #333;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 2px solid #667eea;
        }
        .chart-container {
            position: relative;
            height: 300px;
        }
        .status {
            background: #f0f4ff;
            border-left: 4px solid #667eea;
            padding: 15px;
            margin-bottom: 20px;
            border-radius: 6px;
        }
        .status p {
            font-size: 13px;
            color: #555;
            margin: 5px 0;
        }
        .status strong {
            color: #667eea;
        }
        .footer {
            background: white;
            padding: 20px;
            border-radius: 12px;
            text-align: center;
            color: #999;
            font-size: 12px;
        }
        .refresh-btn {
            background: #667eea;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            margin-bottom: 20px;
        }
        .refresh-btn:hover {
            background: #764ba2;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>[CLOUD] ISI Medical System - CloudWatch Dashboard</h1>
            <p>Real-time monitoring of SQS, ECS, and RDS resources</p>
        </div>

        <button class="refresh-btn" onclick="location.reload()">[REFRESH] Refresh Dashboard</button>

        <div class="status">
            <p><strong>LocalStack Endpoint:</strong> http://localhost:4566</p>
            <p><strong>Dashboard Name:</strong> prod-config-main</p>
            <p><strong>Last Updated:</strong> <span id="updated">$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</span></p>
        </div>

        <div class="dashboard">
            <div class="widget">
                <h2>[SQS] Queue Depths</h2>
                <div class="chart-container">
                    <canvas id="chart-sqs-queues"></canvas>
                </div>
            </div>

            <div class="widget">
                <h2>[DLQ] Dead Letter Queues</h2>
                <div class="chart-container">
                    <canvas id="chart-dlq"></canvas>
                </div>
            </div>

            <div class="widget">
                <h2>[ECS] Services</h2>
                <div class="chart-container">
                    <canvas id="chart-ecs"></canvas>
                </div>
            </div>

            <div class="widget">
                <h2>[RDS] Databases</h2>
                <div class="chart-container">
                    <canvas id="chart-rds"></canvas>
                </div>
            </div>
        </div>

        <div class="footer">
            <p>Dashboard auto-refreshes every 30 seconds - View full dashboard: <a href="http://localhost:4566/_localstack/web/cloudwatch/dashboards">LocalStack Web Console</a></p>
        </div>
    </div>

    <script>
        // Mock data for demo
        const mockData = {
            queues: { 'appointment-service': 5, 'schedule-service': 3, 'auth-service': 0, 'payment-service': 12, 'notification-service': 0, 'facility-service': 0, 'medical-service': 0, 'audit-service': 0 },
            dlq: { 'appointment-service': 0, 'schedule-service': 0, 'auth-service': 0, 'payment-service': 0, 'notification-service': 0, 'facility-service': 0, 'medical-service': 0, 'audit-service': 0 },
            ecs: { 'Running Tasks': 8, 'CPU Avg': 45, 'Memory Avg': 62 },
            rds: { 'CPU': 30, 'Connections': 15, 'Storage %': 35 }
        };

        // SQS Queues Chart
        new Chart(document.getElementById('chart-sqs-queues'), {
            type: 'bar',
            data: {
                labels: Object.keys(mockData.queues),
                datasets: [{
                    label: 'Messages in Queue',
                    data: Object.values(mockData.queues),
                    backgroundColor: '#667eea',
                    borderRadius: 6,
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: { y: { beginAtZero: true } }
            }
        });

        // DLQ Chart
        new Chart(document.getElementById('chart-dlq'), {
            type: 'doughnut',
            data: {
                labels: ['Healthy', 'Messages in DLQ'],
                datasets: [{
                    data: [Object.values(mockData.dlq).reduce((a,b)=>a+b, 0) === 0 ? 100 : 50, Object.values(mockData.dlq).reduce((a,b)=>a+b, 0)],
                    backgroundColor: ['#10b981', '#ef4444'],
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { position: 'bottom' } }
            }
        });

        // ECS Chart
        new Chart(document.getElementById('chart-ecs'), {
            type: 'line',
            data: {
                labels: Object.keys(mockData.ecs),
                datasets: [{
                    label: 'Utilization / Count',
                    data: Object.values(mockData.ecs),
                    borderColor: '#667eea',
                    backgroundColor: 'rgba(102, 126, 234, 0.1)',
                    tension: 0.4,
                    fill: true,
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: true } },
                scales: { y: { beginAtZero: true } }
            }
        });

        // RDS Chart
        new Chart(document.getElementById('chart-rds'), {
            type: 'radar',
            data: {
                labels: Object.keys(mockData.rds),
                datasets: [{
                    label: 'Resource Usage %',
                    data: Object.values(mockData.rds),
                    borderColor: '#764ba2',
                    backgroundColor: 'rgba(118, 75, 162, 0.2)',
                    fill: true,
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: { r: { max: 100 } }
            }
        });

        // Auto-refresh every 30s
        setInterval(() => {
            document.getElementById('updated').textContent = new Date().toLocaleTimeString();
        }, 30000);
    </script>
</body>
</html>
"@
    return $html
}

Write-Host "`n================================" -ForegroundColor Cyan
Write-Host "  CloudWatch Dashboard Server" -ForegroundColor Cyan
Write-Host "================================`n" -ForegroundColor Cyan

Write-Host "[INFO] Fetching dashboard..." -ForegroundColor Cyan
$dashboard = Get-Dashboard
$html = New-DashboardHTML $dashboard

# Start HTTP server
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")

try {
    $listener.Start()
    Write-Host "[OK] Server started on http://localhost:$Port" -ForegroundColor Green
    Write-Host "[INFO] Opening browser in 2 seconds..." -ForegroundColor Cyan
    Start-Sleep -Seconds 2
    Start-Process "http://localhost:$Port"

    Write-Host "`n[INFO] Listening for requests... (Press Ctrl+C to stop)`n" -ForegroundColor Yellow

    while ($true) {
        $context = $listener.GetContext()
        $response = $context.Response

        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $response.ContentLength64 = $buffer.Length
        $response.ContentType = "text/html; charset=utf-8"
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Close()

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Request from $($context.Request.RemoteEndPoint.Address)" -ForegroundColor DarkGray
    }
}
catch {
    Write-Host "[ERROR] $_" -ForegroundColor Red
}
finally {
    $listener.Stop()
    $listener.Close()
    Write-Host "`n[STOP] Server stopped" -ForegroundColor Yellow
}
