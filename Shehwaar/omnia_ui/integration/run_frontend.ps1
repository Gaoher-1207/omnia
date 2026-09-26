<#
.SYNOPSIS
  Runs the OMNIA frontend on mock data, or against any compatible OMNIA backend.

.DESCRIPTION
  A thin wrapper around `flutter run`. It only builds the command line; the
  app itself decides the backend URL (lib/core/api/api_config.dart).
  In API mode it first checks the backend's /health endpoint and warns if it
  can't be reached. See integration/README.md.

.EXAMPLE
  .\integration\run_frontend.ps1
  Mock mode: no backend, no sign-in.

.EXAMPLE
  .\integration\run_frontend.ps1 -Api -Device emulator-5554
  API mode against the local dev server (the emulator reaches it at 10.0.2.2).

.EXAMPLE
  .\integration\run_frontend.ps1 -Api -BaseUrl http://192.168.1.20:8000/api
  API mode against a backend on another machine.

.EXAMPLE
  .\integration\run_frontend.ps1 -EnvFile integration\omnia.env -DryRun
  Settings from a file; print the command instead of running it.
#>
param(
  # Sign in against a backend instead of using mock data.
  [switch]$Api,
  # The backend's API root, e.g. http://192.168.1.20:8000/api.
  [string]$BaseUrl,
  # A Flutter device id (see `flutter devices`).
  [string]$Device,
  # A .env file of OMNIA_* settings (see omnia.env.example).
  [string]$EnvFile,
  # Don't probe the backend before running.
  [switch]$SkipHealthCheck,
  # Print the flutter command and exit.
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Settings from the env file; explicit parameters win, as with --dart-define.
$fileSettings = @{}
if ($EnvFile) {
  $EnvFile = (Resolve-Path $EnvFile).Path
  foreach ($line in Get-Content $EnvFile) {
    if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*?)\s*$') {
      $fileSettings[$Matches[1]] = $Matches[2]
    }
  }
}
$apiMode = $Api -or $fileSettings['OMNIA_DATA'] -eq 'api'
$url = if ($BaseUrl) { $BaseUrl.TrimEnd('/') } else { $fileSettings['OMNIA_API_BASE_URL'] }

$flutterArgs = @('run')
if ($Device) { $flutterArgs += @('-d', $Device) }
if ($EnvFile) { $flutterArgs += "--dart-define-from-file=$EnvFile" }
if ($Api) { $flutterArgs += '--dart-define=OMNIA_DATA=api' }
if ($BaseUrl) { $flutterArgs += "--dart-define=OMNIA_API_BASE_URL=$url" }

if ($apiMode -and -not $SkipHealthCheck) {
  # Probe from this computer: the emulator's 10.0.2.2 is this computer's
  # localhost, and no URL means the debug default on port 8000.
  $probe = if ($url) { $url -replace '//10\.0\.2\.2', '//localhost' } else { 'http://localhost:8000/api' }
  try {
    Invoke-RestMethod -Uri "$probe/health" -TimeoutSec 3 | Out-Null
    Write-Host "Backend OK: $probe/health"
  } catch {
    Write-Warning "No answer from $probe/health. Is the backend running? The app will show 'Couldn't reach OMNIA' until it is."
  }
}

Write-Host "flutter $($flutterArgs -join ' ')"
if ($DryRun) { exit 0 }

Push-Location $root
try {
  & flutter @flutterArgs
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
