<#
.SYNOPSIS
  Packages lambda/appointment/ into a zip for Terraform's source_code_hash.
  psycopg2-binary is bundled inline; no Lambda layer needed for LocalStack.
#>

$ErrorActionPreference = "Stop"
$root  = Split-Path $PSScriptRoot -Parent
$src   = Join-Path $root "lambda\appointment"
$out   = Join-Path $src "function.zip"

Remove-Item $out -ErrorAction SilentlyContinue

$tmp = [System.IO.Path]::GetTempPath() + [System.IO.Path]::GetRandomFileName()
New-Item -ItemType Directory -Path $tmp | Out-Null

Write-Host "Installing dependencies into $tmp (linux/x86_64 target) ..."
# --platform + --only-binary ensures a manylinux wheel is downloaded even on Windows.
# Lambda runtime is python3.12 on linux_x86_64.
pip install -r "$src\requirements.txt" `
  --platform manylinux2014_x86_64 `
  --python-version 312 `
  --only-binary=:all: `
  --target $tmp -q

Write-Host "Copying handler ..."
Copy-Item "$src\index.py" "$tmp\"

Write-Host "Zipping to $out ..."
Compress-Archive -Path "$tmp\*" -DestinationPath $out

Remove-Item -Recurse -Force $tmp

$size = [math]::Round((Get-Item $out).Length / 1MB, 1)
Write-Host "Built $out ($size MB)"
