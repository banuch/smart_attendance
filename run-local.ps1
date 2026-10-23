<#
  Smart Attendance - run everything locally from one script.

  HOW TO RUN (from the project folder, in PowerShell):
      powershell -ExecutionPolicy Bypass -File .\run-local.ps1           # shows a menu
      powershell -ExecutionPolicy Bypass -File .\run-local.ps1 start     # API + admin panel

  ACTIONS
      start      Start the API (if not already running) and the admin web panel.
      api        Start only the API server        -> http://localhost:8080
      admin      Start only the admin web panel   -> http://localhost:5000
      employee   Run the employee app on the Android emulator / phone (USB).
                 Add -Phone to use this PC's Wi-Fi IP (for a real phone).
      setup      First-time setup: npm install, .env, database tables, admin user.
      test       Run all tests (server unit + API, Flutter).
      status     Show what is running.

  Each server opens in its own window. Close that window (or press Ctrl+C in it)
  to stop it.
#>
param(
    [ValidateSet('menu', 'start', 'api', 'admin', 'employee', 'setup', 'test', 'status')]
    [string]$Action = 'menu',
    [switch]$Phone
)

$ErrorActionPreference = 'Stop'

# ---- Settings you might change ------------------------------------------------
$ApiPort   = 8080
$AdminPort = 5000
# -------------------------------------------------------------------------------

$Root      = $PSScriptRoot
$ServerDir = Join-Path $Root 'server'
$ApiUrl    = "http://localhost:$ApiPort"

function Say($text, $color = 'Cyan') { Write-Host $text -ForegroundColor $color }
function Fail($text) { Write-Host "ERROR: $text" -ForegroundColor Red; exit 1 }

# Finds flutter on PATH, else the usual install folder.
function Get-Flutter {
    $cmd = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = Join-Path $env:USERPROFILE 'tools\flutter\bin\flutter.bat'
    if (Test-Path $fallback) { return $fallback }
    Fail 'Flutter not found. Install it or add flutter\bin to PATH.'
}

function Test-Api {
    try {
        $r = Invoke-RestMethod "$ApiUrl/api/health" -TimeoutSec 3
        return [bool]$r.ok
    } catch { return $false }
}

function Test-PortInUse($port) {
    return [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

# Opens a new PowerShell window titled $title that runs $command in $dir.
function Start-Window($title, $dir, $command) {
    $script = "`$Host.UI.RawUI.WindowTitle = '$title'; Set-Location '$dir'; $command"
    Start-Process powershell -ArgumentList '-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $script
}

function Assert-ServerReady {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Fail 'Node.js not found. Install Node 22+.' }
    if (-not (Test-Path (Join-Path $ServerDir 'node_modules'))) { Fail "Server packages missing. Run: .\run-local.ps1 setup" }
    if (-not (Test-Path (Join-Path $ServerDir '.env'))) { Fail "server\.env missing. Run: .\run-local.ps1 setup" }
}

# ---- Actions -------------------------------------------------------------------

function Start-Api {
    if (Test-Api) { Say "API already running at $ApiUrl" 'Green'; return }
    if (Test-PortInUse $ApiPort) { Fail "Port $ApiPort is used by another program." }
    Assert-ServerReady
    Say "Starting API in a new window..."
    Start-Window 'Smart Attendance API' $ServerDir 'npm run dev'

    # Wait up to 30 s for the health check (it also proves MySQL is reachable).
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Api) { Say "API is up: $ApiUrl/api/health" 'Green'; return }
    }
    Say 'API did not answer within 30 s. Check its window (MySQL running? server\.env correct?).' 'Yellow'
}

function Start-Admin {
    if (Test-PortInUse $AdminPort) { Say "Port $AdminPort is busy - admin panel may already be running: http://localhost:$AdminPort" 'Yellow'; return }
    if (-not (Test-Api)) { Say "Warning: API is not running at $ApiUrl - the panel will not be able to sign in." 'Yellow' }
    $flutter = Get-Flutter
    Say "Starting admin panel in a new window (first build takes a minute)..."
    Say "It opens Chrome at http://localhost:$AdminPort. Press 'r' in its window to hot-reload." 'Gray'
    Start-Window 'Smart Attendance Admin' $Root "& '$flutter' run -d chrome --web-port $AdminPort -t lib/main_admin.dart --dart-define=API_URL=$ApiUrl"
}

function Start-Employee {
    $flutter = Get-Flutter
    $flutterArgs = @('run', '-t', 'lib/main_employee.dart')
    if ($Phone) {
        # The phone must reach this PC over Wi-Fi, so use the PC's LAN address.
        $ip = Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object { $_.PrefixOrigin -in 'Dhcp', 'Manual' -and $_.IPAddress -notlike '169.254*' } |
            Select-Object -First 1 -ExpandProperty IPAddress
        if (-not $ip) { Fail 'Could not find this PC''s Wi-Fi IP address.' }
        $flutterArgs += "--dart-define=API_URL=http://${ip}:$ApiPort"
        Say "Phone will call the API at http://${ip}:$ApiPort (allow it through Windows Firewall if asked)."
    } else {
        Say 'Emulator uses http://10.0.2.2:8080 to reach this PC (built into debug builds).'
    }
    if (-not (Test-Api)) { Say "Warning: API is not running at $ApiUrl." 'Yellow' }
    Set-Location $Root
    & $flutter @flutterArgs
}

function Invoke-Setup {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Fail 'Node.js not found. Install Node 22+.' }
    Set-Location $ServerDir

    Say '1/4  Installing server packages (npm install)...'
    npm install
    if ($LASTEXITCODE) { Fail 'npm install failed.' }

    $envFile = Join-Path $ServerDir '.env'
    if (-not (Test-Path $envFile)) {
        Copy-Item (Join-Path $ServerDir '.env.example') $envFile
        Say '2/4  Created server\.env from .env.example.' 'Yellow'
        Say '     Fill in DB_PASSWORD and JWT_SECRET (any long random text), then run setup again.' 'Yellow'
        notepad $envFile
        exit 0
    }
    Say '2/4  server\.env found.'

    Say '3/4  Creating / updating database tables (npm run migrate)...'
    npm run migrate
    if ($LASTEXITCODE) { Fail 'Migration failed. Is MySQL running and are the DB_* values in server\.env right?' }

    $answer = Read-Host '4/4  Create an admin login now? (y/N)'
    if ($answer -match '^[yY]') {
        $email = Read-Host '     Admin email'
        $name  = Read-Host '     Admin name'
        npm run create-admin -- --email $email --name $name
    }
    Say 'Setup done. Next: .\run-local.ps1 start' 'Green'
    Set-Location $Root
}

function Invoke-Tests {
    Assert-ServerReady
    Set-Location $ServerDir
    Say 'Server unit tests...'
    node --test test/unit.test.js
    if (Test-Path (Join-Path $ServerDir '.env.test')) {
        Say 'Server API tests (uses the throwaway sa_test database)...'
        npm run test:api
    } else {
        Say 'Skipping API tests: server\.env.test not found.' 'Yellow'
    }
    Set-Location $Root
    Say 'Flutter tests...'
    & (Get-Flutter) test
}

function Show-Status {
    if (Test-Api) { Say "API          running   $ApiUrl" 'Green' }
    elseif (Test-PortInUse $ApiPort) { Say "API          port $ApiPort busy but health check fails" 'Yellow' }
    else { Say 'API          stopped' 'Gray' }
    if (Test-PortInUse $AdminPort) { Say "Admin panel  running   http://localhost:$AdminPort" 'Green' }
    else { Say 'Admin panel  stopped' 'Gray' }
}

function Show-Menu {
    Say ''
    Say '  Smart Attendance - local runner'
    Say '  -------------------------------'
    Show-Status
    Say ''
    Say '  1) Start API + admin panel'
    Say '  2) Start API only'
    Say '  3) Start admin panel only'
    Say '  4) Run employee app (emulator / USB phone)'
    Say '  5) Run employee app on phone over Wi-Fi'
    Say '  6) First-time setup'
    Say '  7) Run tests'
    Say '  Q) Quit'
    switch ((Read-Host '  Choose').Trim()) {
        '1' { Start-Api; Start-Admin }
        '2' { Start-Api }
        '3' { Start-Admin }
        '4' { Start-Employee }
        '5' { $script:Phone = $true; Start-Employee }
        '6' { Invoke-Setup }
        '7' { Invoke-Tests }
        default { }
    }
}

switch ($Action) {
    'menu'     { Show-Menu }
    'start'    { Start-Api; Start-Admin }
    'api'      { Start-Api }
    'admin'    { Start-Admin }
    'employee' { Start-Employee }
    'setup'    { Invoke-Setup }
    'test'     { Invoke-Tests }
    'status'   { Show-Status }
}
