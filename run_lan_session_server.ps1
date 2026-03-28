param(
    [int]$Port = 8765
)

$ErrorActionPreference = "Stop"

$project_root = $PSScriptRoot
$venv_python = Join-Path $project_root ".venv\bin\python.exe"
$server_script = Join-Path $project_root "server\lan_session_server.py"
$pfx_path = Join-Path $project_root "zork-local-https.pfx"
$password_path = Join-Path $project_root "zork-local-https.password.txt"
$cert_pem = Join-Path $project_root "zork-local-https-cert.pem"
$key_pem = Join-Path $project_root "zork-local-https-key.pem"
$openssl = "C:\Program Files\Git\mingw64\bin\openssl.exe"
$rule_name = "Zork LAN Session $Port"

if (-not (Test-Path $venv_python)) {
    Write-Error "Virtual environment Python not found at $venv_python"
    exit 1
}

if (-not (Test-Path $server_script)) {
    Write-Error "Server script not found at $server_script"
    exit 1
}

if (-not (Test-Path $pfx_path) -or -not (Test-Path $password_path)) {
    Write-Error "HTTPS certificate files are missing. Run setup_https_dev.ps1 first."
    exit 1
}

if (-not (Test-Path $openssl)) {
    Write-Error "OpenSSL not found at $openssl"
    exit 1
}

$plain_password = (Get-Content $password_path -Raw).Trim()

if (-not (Test-Path $cert_pem) -or -not (Test-Path $key_pem)) {
    & $openssl pkcs12 -in $pfx_path -clcerts -nokeys -out $cert_pem -passin "pass:$plain_password" | Out-Null
    & $openssl pkcs12 -in $pfx_path -nocerts -nodes -out $key_pem -passin "pass:$plain_password" | Out-Null
}

try {
    if (-not (Get-NetFirewallRule -DisplayName $rule_name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $rule_name -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
    }
} catch {
    Write-Warning "Couldn't create the Windows Firewall rule automatically. If a device can't connect, add an inbound TCP rule for port $Port."
}

$ipv4_addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -ne "127.0.0.1" -and
        $_.IPAddress -notlike "169.254.*"
    } |
    Select-Object -ExpandProperty IPAddress -Unique

Write-Host "Starting LAN session server on:"
Write-Host "  wss://localhost:$Port"
foreach ($ip in $ipv4_addresses) {
    Write-Host "  wss://${ip}:$Port"
}
Write-Host "Press Ctrl+C to stop."

& $venv_python $server_script
