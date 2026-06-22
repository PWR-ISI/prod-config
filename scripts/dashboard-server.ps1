<#
.SYNOPSIS
  Renders the prod-config-main CloudWatch dashboard from LocalStack Pro on localhost:8080.
  Fetches the dashboard definition, then queries CloudWatch for each widget's metrics.

.EXAMPLE
  .\dashboard-server.ps1
  .\dashboard-server.ps1 -Port 3000
#>

param([int]$Port = 8080)

$ErrorActionPreference = "Continue"
$env:AWS_ENDPOINT_URL      = "http://localhost:4566"
$env:AWS_ACCESS_KEY_ID     = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION    = "us-east-1"

$DASHBOARD_NAME = "prod-config-main"
$CW_ENDPOINT    = "http://localhost:4566"
$REGION         = "us-east-1"

# ── CloudWatch helpers ────────────────────────────────────────────────────────

function Get-CwMetric {
    param(
        [string]$Namespace,
        [string]$MetricName,
        [hashtable]$Dimensions,   # @{ Name = "QueueName"; Value = "foo" }
        [string]$Stat = "Average",
        [int]$PeriodSeconds = 300
    )
    $endTime   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $startTime = (Get-Date).AddHours(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $dimArgs = @()
    foreach ($kv in $Dimensions.GetEnumerator()) {
        $dimArgs += "Name=$($kv.Key),Value=$($kv.Value)"
    }

    try {
        $raw = aws cloudwatch get-metric-statistics `
            --namespace $Namespace `
            --metric-name $MetricName `
            --dimensions $dimArgs `
            --start-time $startTime `
            --end-time $endTime `
            --period $PeriodSeconds `
            --statistics $Stat `
            --endpoint-url $CW_ENDPOINT `
            --region $REGION `
            --output json 2>$null | ConvertFrom-Json

        $points = $raw.Datapoints | Sort-Object Timestamp
        if ($points -and $points.Count -gt 0) {
            return [math]::Round($points[-1].$Stat, 2)
        }
    } catch { }
    return 0
}

function Get-DashboardWidgets {
    try {
        $body = (aws cloudwatch get-dashboard `
            --dashboard-name $DASHBOARD_NAME `
            --endpoint-url $CW_ENDPOINT `
            --region $REGION `
            --output json 2>$null | ConvertFrom-Json).DashboardBody
        if ($body) { return ($body | ConvertFrom-Json).widgets }
    } catch { }
    return @()
}

# ── Fetch all widget data ─────────────────────────────────────────────────────

function Get-AllMetrics {
    param([array]$Widgets)

    $result = @()
    foreach ($w in $Widgets) {
        $props   = $w.properties
        $title   = $props.title
        $metrics = $props.metrics
        if (-not $metrics) { continue }

        $series = @()
        foreach ($m in $metrics) {
            # CloudWatch metric array format: [Namespace, MetricName, DimName, DimValue, {label,...}]
            # or: [Namespace, MetricName, {label,...}]
            if ($m.Count -lt 2) { continue }

            $ns        = $m[0]
            $metricName= $m[1]
            $dims      = @{}
            $label     = $metricName

            # Parse dimension pairs (index 2,3 / 4,5 / ...)
            $i = 2
            while ($i -lt $m.Count) {
                $item = $m[$i]
                if ($item -is [string] -and ($i + 1) -lt $m.Count -and $m[$i+1] -is [string]) {
                    $dims[$item] = $m[$i+1]
                    $i += 2
                } elseif ($item -is [PSCustomObject]) {
                    if ($item.label) { $label = $item.label }
                    $i++
                } else { $i++ }
            }

            $stat  = if ($props.stat) { $props.stat } else { "Average" }
            $value = Get-CwMetric -Namespace $ns -MetricName $metricName -Dimensions $dims -Stat $stat

            $series += @{ label = $label; value = $value }
        }

        $result += @{ title = $title; series = $series }
    }
    return $result
}

# ── Build HTML ────────────────────────────────────────────────────────────────

function New-HTML {
    param([array]$WidgetData, [string]$Updated)

    # Build JS for each widget
    $charts = ""
    $widgetCards = ""
    $idx = 0

    foreach ($w in $WidgetData) {
        $id      = "chart$idx"
        $title   = $w.title
        $labels  = ($w.series | ForEach-Object { "`"$($_.label)`"" }) -join ","
        $values  = ($w.series | ForEach-Object { $_.value }) -join ","

        # Color: red bars for DLQs with values > 0, blue otherwise
        $isDlq   = $title -like "*Dead Letter*" -or $title -like "*DLQ*"
        if ($isDlq) {
            $bgColors = ($w.series | ForEach-Object {
                if ($_.value -gt 0) { "'#ef4444'" } else { "'#10b981'" }
            }) -join ","
            $bgColor = "[$bgColors]"
        } else {
            $bgColor = "'#667eea'"
        }

        $chartType = if ($title -like "*CPU*" -or $title -like "*Connect*") { "line" } else { "bar" }

        $widgetCards += @"
        <div class="widget">
          <h2>$title</h2>
          <div class="chart-wrap"><canvas id="$id"></canvas></div>
        </div>
"@
        $charts += @"
        new Chart(document.getElementById('$id'), {
          type: '$chartType',
          data: {
            labels: [$labels],
            datasets: [{ label: '$title', data: [$values], backgroundColor: $bgColor,
                         borderColor: '#667eea', tension: 0.3, fill: false, borderRadius: 5 }]
          },
          options: { responsive: true, maintainAspectRatio: false,
                     plugins: { legend: { display: false } },
                     scales: { y: { beginAtZero: true } } }
        });
"@
        $idx++
    }

    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ISI Medical - CloudWatch Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
       background:linear-gradient(135deg,#667eea,#764ba2);padding:20px;min-height:100vh;color:#333}
  .container{max-width:1400px;margin:0 auto}
  .header{background:#fff;padding:22px 28px;border-radius:12px;
          box-shadow:0 4px 6px rgba(0,0,0,.1);margin-bottom:20px;
          display:flex;align-items:center;justify-content:space-between}
  .header h1{color:#667eea;font-size:22px}
  .header p{color:#888;font-size:12px;margin-top:4px}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(480px,1fr));gap:18px;margin-bottom:20px}
  .widget{background:#fff;border-radius:12px;padding:20px;box-shadow:0 4px 6px rgba(0,0,0,.1)}
  .widget h2{font-size:14px;color:#444;margin-bottom:14px;padding-bottom:8px;
             border-bottom:2px solid #667eea}
  .chart-wrap{position:relative;height:250px}
  .meta{background:#fff;padding:14px;border-radius:12px;font-size:12px;color:#999;text-align:center}
  button{background:#667eea;color:#fff;border:none;padding:8px 18px;border-radius:6px;
         cursor:pointer;font-size:13px;margin-bottom:18px}
  button:hover{background:#764ba2}
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <div>
      <h1>ISI Medical &mdash; CloudWatch Dashboard <em style="font-size:13px;color:#888">($DASHBOARD_NAME)</em></h1>
      <p>LocalStack Pro &bull; Metrics from last 1 hour &bull; Updated: $Updated</p>
    </div>
    <button onclick="location.reload()">Refresh</button>
  </div>

  <div class="grid">
$widgetCards
  </div>

  <div class="meta">Data sourced from CloudWatch API &bull; http://localhost:4566 &bull; Refresh to update</div>
</div>
<script>
$charts
</script>
</body>
</html>
"@
}

# ── HTTP Server ───────────────────────────────────────────────────────────────

Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "  ISI CloudWatch Dashboard Server" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Cyan

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")

try {
    $listener.Start()
    Write-Host "[OK] http://localhost:$Port" -ForegroundColor Green
    Start-Sleep -Seconds 1
    Start-Process "http://localhost:$Port"
    Write-Host "[INFO] Fetching data on each browser request. Press Ctrl+C to stop.`n" -ForegroundColor Yellow

    while ($true) {
        $context = $listener.GetContext()
        $ts      = Get-Date -Format "HH:mm:ss"

        Write-Host "[$ts] Fetching dashboard '$DASHBOARD_NAME' from CloudWatch..." -ForegroundColor Cyan
        $widgets     = Get-DashboardWidgets
        Write-Host "[$ts] Found $($widgets.Count) widget(s). Querying metrics..." -ForegroundColor DarkGray
        $widgetData  = Get-AllMetrics -Widgets $widgets
        $html        = New-HTML -WidgetData $widgetData -Updated (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

        $buf  = [System.Text.Encoding]::UTF8.GetBytes($html)
        $resp = $context.Response
        $resp.ContentLength64 = $buf.Length
        $resp.ContentType     = "text/html; charset=utf-8"
        $resp.OutputStream.Write($buf, 0, $buf.Length)
        $resp.OutputStream.Close()
        Write-Host "[$ts] Response sent ($($widgetData.Count) widgets rendered)" -ForegroundColor Green
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
