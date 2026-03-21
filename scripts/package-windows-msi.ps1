param(
  [string]$Arch = "amd64"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$sourceDir = Join-Path $root "build\windows\x64\runner\Release"
$distDir = Join-Path $root "dist\windows"
$wxsPath = Join-Path $root "packaging\windows\main.wxs"
$versionLine = (Get-Content (Join-Path $root "pubspec.yaml") | Select-String '^version:\s*').ToString()
$versionValue = ($versionLine -replace '^version:\s*', '').Split('+')[0]
$msiPath = Join-Path $distDir "xworkmate-$versionValue-$Arch.msi"
$zipPath = Join-Path $distDir "xworkmate-windows-$Arch.zip"

if (-not (Test-Path $sourceDir)) {
  throw "Expected Windows release bundle not found: $sourceDir"
}

New-Item -ItemType Directory -Path $distDir -Force | Out-Null

if (Test-Path $zipPath) {
  Remove-Item -Force $zipPath
}
Compress-Archive -Path (Join-Path $sourceDir '*') -DestinationPath $zipPath

$wixVersion = $versionValue
if ($wixVersion -notmatch '^\d+\.\d+\.\d+$') {
  $wixVersion = "0.0.0"
}

& wix build $wxsPath `
  -arch x64 `
  -d SourceDir=$sourceDir `
  -d ProductVersion=$wixVersion `
  -o $msiPath

if ($env:WINDOWS_PFX_BASE64 -and $env:WINDOWS_PFX_PASSWORD) {
  $certDir = Join-Path $env:RUNNER_TEMP "windows-signing"
  $pfxPath = Join-Path $certDir "codesign.pfx"
  New-Item -ItemType Directory -Path $certDir -Force | Out-Null
  [IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($env:WINDOWS_PFX_BASE64))

  $signtool = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin" -Recurse -Filter signtool.exe |
    Sort-Object FullName -Descending |
    Select-Object -First 1
  if (-not $signtool) {
    throw "signtool.exe not found after Windows SDK discovery."
  }

  $subjectArgs = @()
  if ($env:WINDOWS_CODESIGN_SUBJECT) {
    $subjectArgs = @("/n", $env:WINDOWS_CODESIGN_SUBJECT)
  }

  & $signtool.FullName sign /fd SHA256 /f $pfxPath /p $env:WINDOWS_PFX_PASSWORD /tr http://timestamp.digicert.com /td SHA256 @subjectArgs $msiPath
}

Write-Host "MSI: $msiPath"
Write-Host "ZIP: $zipPath"
