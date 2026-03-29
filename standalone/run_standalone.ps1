param(
    [int]$Port = 8010
)

$root = $PSScriptRoot
Start-Process python -ArgumentList "-m http.server $Port --directory `"$root`"" -WorkingDirectory $root
Write-Host "Standalone build serving at http://localhost:$Port/"
