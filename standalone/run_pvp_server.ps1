param(
    [int]$Port = 8090
)

$root = $PSScriptRoot
Start-Process node -ArgumentList "server.js" -WorkingDirectory $root -NoNewWindow
Write-Host "PvP relay starting from $root on ws://localhost:$Port"
