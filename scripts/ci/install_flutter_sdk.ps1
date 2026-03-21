param(
  [Parameter(Mandatory = $true)]
  [string]$FlutterVersion
)

$ErrorActionPreference = "Stop"

$installRoot = Join-Path ($env:RUNNER_TEMP ?? $env:TEMP) "flutter-sdk"
$flutterRoot = Join-Path $installRoot "flutter"
$archiveName = "flutter_windows_${FlutterVersion}-stable.zip"
$archivePath = Join-Path ($env:RUNNER_TEMP ?? $env:TEMP) $archiveName
$downloadUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/$archiveName"

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null

if (-not (Test-Path (Join-Path $flutterRoot "bin/flutter.bat"))) {
  Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath
  if (Test-Path $flutterRoot) {
    Remove-Item -Recurse -Force $flutterRoot
  }
  Expand-Archive -Path $archivePath -DestinationPath $installRoot -Force
}

"$flutterRoot\bin" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
& "$flutterRoot\bin\flutter.bat" --disable-analytics
& "$flutterRoot\bin\flutter.bat" config --no-analytics
& "$flutterRoot\bin\flutter.bat" --version
