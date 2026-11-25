# Build Cinemakom for Windows: release bundle, portable zip, and Inno Setup installer.
# Usage:
#   .\tool\build_windows_installer.ps1
#   .\tool\build_windows_installer.ps1 -Version "1.0.0" -SkipFlutterBuild

param(
  [string]$Version = "",
  [string]$BuildNumber = "",
  [switch]$SkipFlutterBuild
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot

try {
  $pubspec = Get-Content (Join-Path $RepoRoot "pubspec.yaml") -Raw
  if ([string]::IsNullOrWhiteSpace($Version)) {
    if ($pubspec -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?') {
      $Version = $Matches[1]
      if ([string]::IsNullOrWhiteSpace($BuildNumber) -and $Matches[2]) {
        $BuildNumber = $Matches[2]
      }
    } else {
      $Version = "1.0.0"
    }
  }

  if (-not $SkipFlutterBuild) {
    Write-Host "Building Flutter Windows release ($Version)..."
    $buildArgs = @("flutter", "build", "windows", "--release", "--build-name=$Version")
    if (-not [string]::IsNullOrWhiteSpace($BuildNumber)) {
      $buildArgs += "--build-number=$BuildNumber"
    }
    & fvm @buildArgs
    if ($LASTEXITCODE -ne 0) {
      throw "fvm flutter build windows failed with exit code $LASTEXITCODE"
    }
  }

  $ReleaseDir = Join-Path $RepoRoot "build\windows\x64\runner\Release"
  if (-not (Test-Path (Join-Path $ReleaseDir "cinemakom.exe"))) {
    throw "Release executable not found at $ReleaseDir\cinemakom.exe"
  }

  $DistDir = Join-Path $RepoRoot "dist"
  New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

  $ZipPath = Join-Path $DistDir "cinemakom-v$Version-windows-x64.zip"
  Write-Host "Packaging portable zip: $ZipPath"
  Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipPath -Force

  $IsccCandidates = @(
    (Get-Command iscc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
  ) | Where-Object { $_ -and (Test-Path $_) }

  $Iscc = $IsccCandidates | Select-Object -First 1
  if (-not $Iscc) {
    throw "Inno Setup (ISCC.exe) not found. Install it with: winget install JRSoftware.InnoSetup"
  }

  $IssPath = Join-Path $RepoRoot "windows\packaging\cinemakom.iss"
  $InstallerBase = "cinemakom-v$Version-windows-x64-setup"
  Write-Host "Building Inno Setup installer with $Iscc..."
  & $Iscc `
    "/DMyAppVersion=$Version" `
    "/DSourceDir=$ReleaseDir" `
    "/DOutputDir=$DistDir" `
    "/DOutputBaseFilename=$InstallerBase" `
    $IssPath

  if ($LASTEXITCODE -ne 0) {
    throw "ISCC failed with exit code $LASTEXITCODE"
  }

  Write-Host ""
  Write-Host "Done:"
  Write-Host "  Portable zip: $ZipPath"
  Write-Host "  Installer:    $(Join-Path $DistDir "$InstallerBase.exe")"
} finally {
  Pop-Location
}
