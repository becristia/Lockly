param(
  [string]$IsccPath = "",
  [switch]$SkipFlutterBuild,
  [switch]$SkipLaunch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path -LiteralPath (Join-Path $scriptDir "..\..")
$installerScript = Join-Path $scriptDir "lockly.iss"
$installerOutputDir = Join-Path $projectRoot "build\windows\installer"
$installerExe = Join-Path $installerOutputDir "LocklyInstallerSetup.exe"
$installRoot = Join-Path $projectRoot "build\windows\install-smoke"
$installDir = Join-Path $installRoot "Lockly"

function Resolve-Iscc {
  param([string]$ExplicitPath)

  if ($ExplicitPath -ne "") {
    if (Test-Path -LiteralPath $ExplicitPath) {
      return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }
    throw "ISCC.exe was not found at '$ExplicitPath'."
  }

  $pathCommand = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
  if ($null -ne $pathCommand) {
    return $pathCommand.Source
  }

  $candidates = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  throw "ISCC.exe not found. Install Inno Setup 6 or pass -IsccPath."
}

function Assert-UnderProject {
  param([string]$Path)

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $rootPath = [System.IO.Path]::GetFullPath($projectRoot.Path)
  if (-not $fullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to operate outside project root: $fullPath"
  }
}

function Invoke-LoggedProcess {
  param(
    [string]$FilePath,
    [string[]]$ArgumentList,
    [string]$WorkingDirectory = $projectRoot.Path
  )

  $process = Start-Process `
    -FilePath $FilePath `
    -ArgumentList $ArgumentList `
    -WorkingDirectory $WorkingDirectory `
    -NoNewWindow `
    -Wait `
    -PassThru
  if ($process.ExitCode -ne 0) {
    throw "$FilePath failed with exit code $($process.ExitCode)."
  }
}

Assert-UnderProject $installerOutputDir
Assert-UnderProject $installRoot
Assert-UnderProject $installDir

$iscc = Resolve-Iscc -ExplicitPath $IsccPath
Write-Host "Using ISCC.exe: $iscc"

if (-not $SkipFlutterBuild) {
  $nugetDir = Join-Path $projectRoot "build\windows\x64\_deps\nuget-src"
  if (Test-Path -LiteralPath (Join-Path $nugetDir "nuget.exe")) {
    $env:PATH = "$nugetDir;$env:PATH"
  }
  Invoke-LoggedProcess -FilePath "flutter" -ArgumentList @("build", "windows", "--release")
}

New-Item -ItemType Directory -Force -Path $installerOutputDir | Out-Null
Invoke-LoggedProcess -FilePath $iscc -ArgumentList @($installerScript)

if (-not (Test-Path -LiteralPath $installerExe)) {
  throw "Installer was not generated: $installerExe"
}

if (Test-Path -LiteralPath $installRoot) {
  $existingUninstaller = Get-ChildItem -LiteralPath $installRoot -Filter "Unins*.exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $existingUninstaller) {
    Invoke-LoggedProcess -FilePath $existingUninstaller.FullName -ArgumentList @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART")
  }
  if (Test-Path -LiteralPath $installRoot) {
    Assert-UnderProject $installRoot
    Remove-Item -LiteralPath $installRoot -Recurse -Force
  }
}

New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Invoke-LoggedProcess `
  -FilePath $installerExe `
  -ArgumentList @(
    "/VERYSILENT",
    "/SUPPRESSMSGBOXES",
    "/NORESTART",
    "/CURRENTUSER",
    "/NOICONS",
    "/DIR=$installDir"
  )

$installedExe = Join-Path $installDir "Lockly.exe"
if (-not (Test-Path -LiteralPath $installedExe)) {
  throw "Installed executable not found: $installedExe"
}

if (-not $SkipLaunch) {
  $app = Start-Process -FilePath $installedExe -WindowStyle Hidden -PassThru
  Start-Sleep -Seconds 5
  if (-not $app.HasExited) {
    Stop-Process -Id $app.Id -Force
    Wait-Process -Id $app.Id -ErrorAction SilentlyContinue
  }
}

$uninstaller = Get-ChildItem -LiteralPath $installDir -Filter "Unins*.exe" -File -ErrorAction Stop | Select-Object -First 1
if ($null -eq $uninstaller) {
  throw "Uninstaller not found in $installDir"
}
Invoke-LoggedProcess -FilePath $uninstaller.FullName -ArgumentList @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART")

if (Test-Path -LiteralPath $installRoot) {
  Assert-UnderProject $installRoot
  Remove-Item -LiteralPath $installRoot -Recurse -Force
}

Write-Host "Windows installer smoke test passed."
