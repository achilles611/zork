param(
    [int]$Port = 8443
)

$ErrorActionPreference = "Stop"

$project_root = $PSScriptRoot
$cert_export_path = Join-Path $project_root "zork-local-https.cer"
$pfx_export_path = Join-Path $project_root "zork-local-https.pfx"
$password_path = Join-Path $project_root "zork-local-https.password.txt"
$ca_subject = "CN=zork-local-dev-ca"
$server_subject = "CN=zork-local-dev"
$rule_name = "Zork Local HTTPS $Port"

$ipv4_addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -ne "127.0.0.1" -and
        $_.IPAddress -notlike "169.254.*"
    } |
    Select-Object -ExpandProperty IPAddress -Unique

$san_entries = [System.Collections.Generic.List[string]]::new()
$san_entries.Add("DNS=localhost")
foreach ($ip in $ipv4_addresses) {
    $san_entries.Add("IPAddress=$ip")
}

$san_extension = "2.5.29.17={text}" + ($san_entries -join "&")
$ca_extensions = @(
    "2.5.29.19={critical}{text}CA=true&pathlength=1"
)
$server_extensions = @(
    $san_extension
    "2.5.29.37={text}1.3.6.1.5.5.7.3.1"
)

foreach ($store_path in @("Cert:\CurrentUser\My", "Cert:\CurrentUser\Root")) {
    Get-ChildItem $store_path |
        Where-Object { $_.Subject -in @($ca_subject, $server_subject) } |
        ForEach-Object {
            Remove-Item $_.PSPath -Force -ErrorAction SilentlyContinue
        }
}

$ca_cert = New-SelfSignedCertificate `
    -Type Custom `
    -Subject $ca_subject `
    -FriendlyName "Zork Local Dev CA" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -KeyExportPolicy Exportable `
    -HashAlgorithm SHA256 `
    -KeyUsage CertSign, CRLSign, DigitalSignature `
    -NotAfter (Get-Date).AddYears(5) `
    -TextExtension $ca_extensions

$server_cert = New-SelfSignedCertificate `
    -Type SSLServerAuthentication `
    -Subject $server_subject `
    -FriendlyName "Zork Local HTTPS" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -Signer $ca_cert `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -KeyExportPolicy Exportable `
    -HashAlgorithm SHA256 `
    -KeyUsage DigitalSignature, KeyEncipherment `
    -NotAfter (Get-Date).AddYears(2) `
    -TextExtension $server_extensions

if (Test-Path $password_path) {
    $plain_password = (Get-Content $password_path -Raw).Trim()
} else {
    $plain_password = [guid]::NewGuid().ToString("N")
    Set-Content -Path $password_path -Value $plain_password -NoNewline
}

$secure_password = ConvertTo-SecureString $plain_password -AsPlainText -Force

Export-Certificate -Cert $ca_cert -FilePath $cert_export_path -Force | Out-Null
Import-Certificate -FilePath $cert_export_path -CertStoreLocation "Cert:\CurrentUser\Root" | Out-Null
Export-PfxCertificate -Cert $server_cert -FilePath $pfx_export_path -Password $secure_password -Force | Out-Null

try {
    if (-not (Get-NetFirewallRule -DisplayName $rule_name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $rule_name -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
    }
} catch {
    Write-Warning "Couldn't create the Windows Firewall rule automatically. If your phone can't connect, add an inbound TCP rule for port $Port."
}

Write-Host "HTTPS dev certificates prepared."
Write-Host "CA certificate for your phone/browser trust: $cert_export_path"
Write-Host "PFX file for the local server: $pfx_export_path"
Write-Host ""
Write-Host "Serve the game with:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$project_root\serve_web.ps1`" -Port $Port -Https"
Write-Host ""
Write-Host "Open from this PC:"
Write-Host "  https://localhost:$Port"
foreach ($ip in $ipv4_addresses) {
    Write-Host "  https://${ip}:$Port"
}
Write-Host ""
Write-Host "To make Android trust the local HTTPS site, install the exported .cer file on the phone as a CA certificate."
