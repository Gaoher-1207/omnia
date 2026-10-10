param(
    [ValidateSet('Launch', 'Ollama', 'Backend', 'Emulator', 'Flutter', 'Check')]
    [string]$Role = 'Launch',
    [string]$Device
)
$ErrorActionPreference = 'Stop'
$frontend = Split-Path $PSScriptRoot -Parent
$repo = Split-Path (Split-Path $frontend -Parent) -Parent
$backend = Join-Path $repo 'Fawaz\backend'
$python = Join-Path $backend '.venv\Scripts\python.exe'
$mutex = $null
$ownsMutex = $false

function Require-Path([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing required path: $Path. Nothing will be installed automatically." }
}
function Probe([string]$Url) {
    try { return Invoke-RestMethod -Uri $Url -TimeoutSec 3 } catch { return $null }
}
function Wait-Ready([scriptblock]$Test, [int]$Seconds, [string]$Description) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $result = & $Test
        if ($result) { return $result }
        Start-Sleep -Seconds 2
    }
    throw "Timed out waiting for $Description ($Seconds seconds). Check the named OMNIA service window, fix its error, then run START_OMNIA.bat again."
}
function Open-Service([string]$Name, [string]$Serial = '') {
    $arguments = '-NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -File "{0}" -Role {1}' -f $PSCommandPath, $Name
    if ($Serial) { $arguments += ' -Device "{0}"' -f $Serial }
    # Visible windows are intentional: service logs and Flutter hot reload.
    Start-Process powershell.exe -ArgumentList $arguments -WorkingDirectory $repo | Out-Null
}
function Find-Emulator {
    $devices = & $adb devices
    if ($LASTEXITCODE -ne 0) { throw 'ADB could not list devices.' }
    foreach ($line in $devices) {
        if ($line -match '^(emulator-\d+)\s+device\b') {
            $serial = $Matches[1]
            $name = & $adb -s $serial emu avd name 2>$null
            if ($LASTEXITCODE -eq 0 -and $name -contains $settings.ANDROID_AVD) { return $serial }
        }
    }
    return $null
}
function Emulator-Starting {
    $avdPattern = '(?:-avd\s+"?' + [regex]::Escape($settings.ANDROID_AVD) + '"?(?:\s|$)|@' + [regex]::Escape($settings.ANDROID_AVD) + '(?:\s|$))'
    return @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match '^(emulator|qemu-system-.+)\.exe$' -and $_.CommandLine -match $avdPattern
    }).Count -gt 0
}
try {
    $Host.UI.RawUI.WindowTitle = "OMNIA - $Role"
    $settings = @{}
    $config = Join-Path $PSScriptRoot '.env.launcher'
    if (-not (Test-Path -LiteralPath $config)) { $config = Join-Path $PSScriptRoot 'launcher.env.example' }
    foreach ($line in Get-Content -LiteralPath $config) {
        if ($line -match '^\s*(#|$)') { continue }
        if ($line -notmatch '^([A-Z_]+)=(.*)$') { throw "Invalid KEY=value line in $config" }
        $settings[$Matches[1]] = $Matches[2].Trim()
    }
    foreach ($key in 'OLLAMA_EXE','OLLAMA_MODELS','ANDROID_AVD','ASSISTANT_PROVIDER','ASSISTANT_BASE_URL','ASSISTANT_MODEL','ASSISTANT_TIMEOUT_SECONDS') {
        if (-not $settings[$key]) { throw "Missing $key in $config" }
    }
    if ($settings.ASSISTANT_PROVIDER -ne 'ollama' -or $settings.ASSISTANT_BASE_URL -ne 'http://127.0.0.1:11434') {
        throw 'This local launcher requires ASSISTANT_PROVIDER=ollama and ASSISTANT_BASE_URL=http://127.0.0.1:11434.'
    }
    # Read the canonical Flutter project's actual SDK path, not a second hard-coded SDK location.
    $properties = Get-Content -LiteralPath (Join-Path $frontend 'android\local.properties')
    $sdkLine = $properties | Where-Object { $_ -match '^sdk.dir=' } | Select-Object -First 1
    if (-not $sdkLine) { throw 'android/local.properties needs sdk.dir pointing to the existing Android SDK.' }
    $sdk = $sdkLine.Substring(8).Replace('\\', '\').Replace('\:', ':')
    $adb = Join-Path $sdk 'platform-tools\adb.exe'
    $emulator = Join-Path $sdk 'emulator\emulator.exe'
    foreach ($path in @($python, $adb, $emulator, $settings.OLLAMA_EXE, $settings.OLLAMA_MODELS, (Join-Path $PSScriptRoot 'run_frontend.ps1'))) { Require-Path $path }
    Get-Command flutter -ErrorAction Stop | Out-Null
    if ($Role -eq 'Check') {
        $avds = & $emulator -list-avds
        if ($LASTEXITCODE -ne 0 -or $avds -notcontains $settings.ANDROID_AVD) { throw "AVD not found: $($settings.ANDROID_AVD)" }
        Write-Host "Preflight OK. Repository: $repo`nBackend: $backend`nFrontend: $frontend`nAndroid SDK: $sdk`nConfig: $config`nModel: $($settings.ASSISTANT_MODEL)"
        return
    }
    $mutex = New-Object System.Threading.Mutex($false, "Local\OMNIA.Dev.$Role")
    try { $ownsMutex = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { Write-Host "$Role is already managed by another OMNIA window. Reusing it; configuration changes require restarting that service."; return }
    switch ($Role) {
        'Ollama' {
            if (Probe 'http://127.0.0.1:11434/api/tags') { Write-Host 'Using existing Ollama server; its model directory and binding remain unchanged.'; return }
            $env:OLLAMA_HOST = '127.0.0.1:11434'
            $env:OLLAMA_MODELS = $settings.OLLAMA_MODELS
            & $settings.OLLAMA_EXE serve
            throw "Ollama stopped (exit $LASTEXITCODE)."
        }
        'Backend' {
            if (Get-NetTCPConnection -State Listen -LocalPort 8000 -ErrorAction SilentlyContinue) {
                throw 'Port 8000 is already in use by a server outside this launcher. Stop it and retry so the assistant configuration can be applied reliably.'
            }
            foreach ($key in $settings.Keys | Where-Object { $_ -like 'ASSISTANT_*' }) { [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process') }
            Set-Location -LiteralPath $backend
            & $python -m alembic upgrade head
            if ($LASTEXITCODE -ne 0) { throw 'Backend database migration failed; Uvicorn was not started.' }
            & $python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
            throw "Backend stopped (exit $LASTEXITCODE)."
        }
        'Emulator' {
            if ((Find-Emulator) -or (Emulator-Starting)) { Write-Host 'Pixel AVD is already running or starting.'; return }
            & $emulator -avd $settings.ANDROID_AVD
            if ($LASTEXITCODE -ne 0) { throw "Emulator failed (exit $LASTEXITCODE)." }
        }
        'Flutter' {
            if (-not $Device) { throw 'Flutter role requires the detected emulator serial.' }
            & (Join-Path $PSScriptRoot 'run_frontend.ps1') -Api -Device $Device
            if ($LASTEXITCODE -ne 0) { throw "Flutter failed (exit $LASTEXITCODE)." }
        }
        'Launch' {
            $avds = & $emulator -list-avds
            if ($LASTEXITCODE -ne 0 -or $avds -notcontains $settings.ANDROID_AVD) { throw "AVD not found: $($settings.ANDROID_AVD)" }
            Open-Service 'Ollama'
            $tags = Wait-Ready { Probe 'http://127.0.0.1:11434/api/tags' } 60 'Ollama'
            if ($tags.models.name -notcontains $settings.ASSISTANT_MODEL) { throw "Model '$($settings.ASSISTANT_MODEL)' is not installed in the running Ollama server. No model will be downloaded automatically." }
            if (Get-NetTCPConnection -State Listen -LocalPort 8000 -ErrorAction SilentlyContinue) {
                $existingBackend = $null
                try { $existingBackend = [System.Threading.Mutex]::OpenExisting('Local\OMNIA.Dev.Backend') }
                catch { throw 'Port 8000 is already occupied outside this launcher. Stop that backend first, then retry to apply the local assistant settings.' }
                finally { if ($existingBackend) { $existingBackend.Dispose() } }
            }
            Open-Service 'Backend'
            $null = Wait-Ready { $r = Probe 'http://127.0.0.1:8000/api/health/ready'; if ($r.status -eq 'ok' -and $r.database -eq 'ok') { $r } } 120 'backend and database readiness'
            # Do not accept an unrelated service that happens to implement a health endpoint.
            $schema = Probe 'http://127.0.0.1:8000/api/openapi.json'
            if ($schema.info.title -ne 'OMNIA API') { throw 'Port 8000 did not identify itself as the OMNIA API.' }
            Open-Service 'Emulator'
            $serial = Wait-Ready { Find-Emulator } 180 'the configured AVD to connect to ADB'
            $null = Wait-Ready {
                $boot = & $adb -s $serial shell getprop sys.boot_completed 2>$null
                if ($LASTEXITCODE -eq 0 -and "$boot".Trim() -eq '1') {
                    $pm = & $adb -s $serial shell pm path android 2>$null
                    if ($LASTEXITCODE -eq 0 -and "$pm" -match 'package:') { $true }
                }
            } 300 'Android boot and package manager'
            Open-Service 'Flutter' $serial
            Write-Host "Startup handed to OMNIA - Flutter on $serial. Use that window for logs, r (hot reload), R (restart), and q (quit)."
        }
    }
} catch {
    Write-Host "OMNIA startup error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'This window stays open. Services already running are left running.'
    if ($Role -ne 'Check') { Read-Host 'Press Enter after reading the error' | Out-Null }
    exit 1
} finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}
