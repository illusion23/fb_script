<#
.SYNOPSIS
  Build FB Group Poster for Windows x64 with guaranteed Windows 7 SP1 x64,
  Windows 10, and Windows 11 compatibility.

.DESCRIPTION
  Verifies that Flutter 3.19.x (the final Flutter release supporting Windows 7)
  is active, compiles the Windows x64 Release build, bundles MSVC + Universal C
  Runtime (UCRT) DLLs for portable out-of-the-box execution, audits PE imports
  for Windows 7 compatibility, and packages a portable ZIP into `dist\`.

.PARAMETER AllowNewerFlutter
  Bypass the Flutter 3.19.x guard (produces a Windows 10 & 11 ONLY build).

.PARAMETER SkipTests
  Skip `flutter analyze` and `flutter test` before building.
#>
[CmdletBinding()]
param(
    [switch]$AllowNewerFlutter,
    [switch]$SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$AppDir = Join-Path $RepoRoot "mobile_app"
$DistDir = Join-Path $RepoRoot "dist"
$VerifyScript = Join-Path $RepoRoot "scripts\verify_win7_pe.py"

Write-Host "=== Checking Flutter SDK version ===" -ForegroundColor Cyan
$versionOutput = (& flutter --version 2>&1) | Out-String
Write-Host $versionOutput

if ($versionOutput -match "Flutter\s+(\d+)\.(\d+)\.(\d+)") {
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    if (($major -gt 3 -or ($major -eq 3 -and $minor -gt 19)) -and -not $AllowNewerFlutter) {
        throw @"
Flutter $($Matches[1]).$($Matches[2]).$($Matches[3]) detected, which DROPPED Windows 7 support!
To guarantee Windows 7 SP1 x64 + Windows 10 + Windows 11 compatibility, switch to Flutter 3.19.6:
  - With FVM:   fvm install 3.19.6 && fvm use 3.19.6
  - Or download Flutter 3.19.6 from https://docs.flutter.dev/release/archive
Or re-run with -AllowNewerFlutter if you only need Windows 10 & 11.
"@
    }
} else {
    throw "Could not determine Flutter version. Ensure `flutter` is in your PATH."
}

Push-Location $AppDir
try {
    Write-Host "=== Enabling Windows desktop & fetching packages ===" -ForegroundColor Cyan
    flutter config --enable-windows-desktop
    flutter pub get

    if (-not $SkipTests) {
        Write-Host "=== Running flutter analyze & flutter test ===" -ForegroundColor Cyan
        flutter analyze
        flutter test
    }

    Write-Host "=== Building Windows x64 Release ===" -ForegroundColor Cyan
    flutter build windows --release
} finally {
    Pop-Location
}

$ReleaseDir = Join-Path $AppDir "build\windows\x64\runner\Release"
if (-not (Test-Path $ReleaseDir)) {
    $ReleaseDir = Join-Path $AppDir "build\windows\runner\Release"
}
if (-not (Test-Path $ReleaseDir)) {
    throw "Build succeeded but Release directory was not found."
}

Write-Host "=== Bundling MSVC & UCRT runtime DLLs ===" -ForegroundColor Cyan
$vcRedistPatterns = @(
    "C:\Program Files\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\*\VC\Redist\MSVC\*\x64\Microsoft.VC142.CRT"
)
$vcRedistDir = $vcRedistPatterns | ForEach-Object { Get-ChildItem -Path $_ -ErrorAction SilentlyContinue } | Sort-Object FullName -Descending | Select-Object -First 1
if ($vcRedistDir) {
    Write-Host "Using VC++ Redist from: $($vcRedistDir.FullName)"
    foreach ($dll in @("vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll", "concrt140.dll")) {
        $src = Join-Path $vcRedistDir.FullName $dll
        $dst = Join-Path $ReleaseDir $dll
        if ((Test-Path $src) -and -not (Test-Path $dst)) {
            Copy-Item -Path $src -Destination $dst -Force
        }
    }
} else {
    Write-Warning "Could not locate VC++ Redistributable folder automatically; ensure vcruntime140.dll and msvcp140.dll are bundled."
}

$ucrtDir = Get-ChildItem -Path "C:\Program Files (x86)\Windows Kits\10\Redist\*\ucrt\DLLs\x64" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
if ($ucrtDir) {
    Write-Host "Using UCRT DLLs from: $($ucrtDir.FullName)"
    Get-ChildItem -Path $ucrtDir.FullName -Filter "*.dll" | ForEach-Object {
        $dst = Join-Path $ReleaseDir $_.Name
        if (-not (Test-Path $dst)) {
            Copy-Item -Path $_.FullName -Destination $dst -Force
        }
    }
} else {
    Write-Warning "Could not locate Windows 10 SDK UCRT DLLs folder; Windows 7 machines without KB2999226 will need the UCRT update."
}

$readmeWin = @"
FB Group Poster - Windows Portable Release (x64)
================================================
Supported OS:
  - Windows 7 SP1 (64-bit, with Platform Update KB2670838)
  - Windows 10 (64-bit)
  - Windows 11 (64-bit)

Quick Start:
  1. Extract the entire ZIP folder (keep all DLLs and the ``data`` folder next to fb_group_poster.exe).
  2. Run ``fb_group_poster.exe``.
  3. Open the side menu -> FB Account -> set your Python Bridge Server URL
     (run ``python bridge_server.py --host 0.0.0.0 --port 8765`` on a Windows 10/11 or Linux host).
"@
Set-Content -Path (Join-Path $ReleaseDir "README-WINDOWS.txt") -Value $readmeWin -Encoding UTF8

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) { $pythonCmd = Get-Command py -ErrorAction SilentlyContinue }
if ($pythonCmd -and -not $AllowNewerFlutter) {
    Write-Host "=== Auditing PE headers & imports for Windows 7 / 10 / 11 compatibility ===" -ForegroundColor Cyan
    & $pythonCmd.Source $VerifyScript $ReleaseDir
    if ($LASTEXITCODE -ne 0) {
        throw "PE compatibility audit failed!"
    }
}

Write-Host "=== Packaging portable ZIP ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
$ZipName = if ($AllowNewerFlutter) {
    "fb_group_poster-windows-x64-win10-11.zip"
} else {
    "fb_group_poster-windows-x64-win7-10-11.zip"
}
$ZipPath = Join-Path $DistDir $ZipName
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path (Join-Path $ReleaseDir "*") -DestinationPath $ZipPath -CompressionLevel Optimal

Write-Host "`n[SUCCESS] Portable Windows package created: $ZipPath" -ForegroundColor Green
