# Build Script for Squad Protocol
# Creates a standalone Windows executable your friend can run

param(
    [string]$GodotPath = "",
    [string]$OutputDir = "builds"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Squad Protocol Build Script ===" -ForegroundColor Cyan
Write-Host ""

# Find Godot executable
if ($GodotPath -eq "") {
    # Common locations to check
    $possiblePaths = @(
        "C:\Program Files\Godot\Godot_v4.4-stable_win64.exe",
        "C:\Program Files\Godot\Godot.exe",
        "C:\Godot\Godot_v4.4-stable_win64.exe",
        "C:\Godot\Godot.exe",
        "$env:LOCALAPPDATA\Godot\Godot_v4.4-stable_win64.exe",
        "$env:USERPROFILE\Godot\Godot_v4.4-stable_win64.exe",
        "D:\Godot\Godot_v4.4-stable_win64.exe"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $GodotPath = $path
            break
        }
    }
    
    # Try to find any Godot executable
    if ($GodotPath -eq "") {
        $found = Get-ChildItem -Path "C:\", "D:\" -Filter "Godot*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $GodotPath = $found.FullName
        }
    }
}

if ($GodotPath -eq "" -or !(Test-Path $GodotPath)) {
    Write-Host "ERROR: Could not find Godot!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please either:" -ForegroundColor Yellow
    Write-Host "  1. Run this script with -GodotPath parameter:" -ForegroundColor Yellow
    Write-Host "     .\build_game.ps1 -GodotPath 'C:\path\to\Godot.exe'" -ForegroundColor White
    Write-Host ""
    Write-Host "  2. Or export manually from Godot Editor:" -ForegroundColor Yellow
    Write-Host "     - Open the project in Godot" -ForegroundColor White
    Write-Host "     - Go to Project > Export" -ForegroundColor White
    Write-Host "     - Select 'Windows Desktop'" -ForegroundColor White
    Write-Host "     - Click 'Export Project'" -ForegroundColor White
    exit 1
}

Write-Host "Found Godot at: $GodotPath" -ForegroundColor Green

# Create output directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$buildDir = Join-Path $projectRoot $OutputDir

if (!(Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
    Write-Host "Created build directory: $buildDir" -ForegroundColor Green
}

$outputExe = Join-Path $buildDir "SquadProtocol.exe"
$godotProject = Join-Path $projectRoot "godot"

Write-Host ""
Write-Host "Building game..." -ForegroundColor Cyan
Write-Host "  Project: $godotProject"
Write-Host "  Output:  $outputExe"
Write-Host ""

# Check if export templates are installed
$templatesDir = "$env:APPDATA\Godot\export_templates\4.4.stable"
if (!(Test-Path $templatesDir)) {
    Write-Host "WARNING: Export templates may not be installed!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "If the build fails, you need to install export templates:" -ForegroundColor Yellow
    Write-Host "  1. Open Godot Editor" -ForegroundColor White
    Write-Host "  2. Go to Editor > Manage Export Templates" -ForegroundColor White
    Write-Host "  3. Click 'Download and Install'" -ForegroundColor White
    Write-Host ""
}

# Run the export
try {
    & $GodotPath --headless --path $godotProject --export-release "Windows Desktop" $outputExe
    
    if (Test-Path $outputExe) {
        Write-Host ""
        Write-Host "=== BUILD SUCCESSFUL ===" -ForegroundColor Green
        Write-Host ""
        Write-Host "Your game is ready at:" -ForegroundColor Cyan
        Write-Host "  $outputExe" -ForegroundColor White
        Write-Host ""
        Write-Host "To share with your friend:" -ForegroundColor Yellow
        Write-Host "  1. Zip the entire '$OutputDir' folder" -ForegroundColor White
        Write-Host "  2. Send the zip to your friend" -ForegroundColor White
        Write-Host "  3. They extract and run SquadProtocol.exe" -ForegroundColor White
        Write-Host ""
        
        # Open the builds folder
        explorer.exe $buildDir
    } else {
        Write-Host "ERROR: Build may have failed - exe not found" -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR: Build failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

