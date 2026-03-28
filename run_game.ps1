param(
    [switch]$Editor,
    [switch]$Console
)

$ErrorActionPreference = "Stop"

$project_root = $PSScriptRoot
$godot_root = "C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
$gui_exe = Join-Path $godot_root "Godot_v4.6.1-stable_win64.exe"
$console_exe = Join-Path $godot_root "Godot_v4.6.1-stable_win64_console.exe"

if ($Console) {
    $godot_exe = $console_exe
} else {
    $godot_exe = $gui_exe
}

if (-not (Test-Path $godot_exe)) {
    Write-Error "Godot executable not found at $godot_exe"
    exit 1
}

$arguments = @("--path", $project_root)
if ($Editor) {
    $arguments += "--editor"
}

Start-Process -FilePath $godot_exe -ArgumentList $arguments -WorkingDirectory $project_root

