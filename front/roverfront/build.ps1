# build.ps1 — build the Rover APK with Supabase credentials injected.
#
# The app reads SUPABASE_URL and SUPABASE_ANON_KEY at compile time via
# --dart-define (see lib/main.dart). Without them the app throws on launch.
# This script loads those values from the gitignored .env so a plain build
# can never ship empty credentials again.
#
# Usage:
#   ./build.ps1                # release APK (default)
#   ./build.ps1 -Mode debug    # debug APK
#   ./build.ps1 -Mode appbundle # Play Store .aab
#   ./build.ps1 -Run           # flutter run on a connected device instead

param(
  [string]$Mode = "release",
  [switch]$Run
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$envFile = Join-Path $PSScriptRoot ".env"
if (-not (Test-Path $envFile)) {
  throw ".env not found at $envFile. Copy ../.env.example and fill in your Supabase values."
}

# Parse KEY=VALUE lines (ignoring comments / blanks) into dart-define args.
$defines = @()
foreach ($line in Get-Content $envFile) {
  $trimmed = $line.Trim()
  if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
  $idx = $trimmed.IndexOf("=")
  if ($idx -lt 1) { continue }
  $key = $trimmed.Substring(0, $idx).Trim()
  $val = $trimmed.Substring($idx + 1).Trim()
  if ($key -eq "SUPABASE_URL" -or $key -eq "SUPABASE_ANON_KEY") {
    $defines += "--dart-define=$key=$val"
  }
}

if ($defines.Count -lt 2) {
  throw "SUPABASE_URL and/or SUPABASE_ANON_KEY missing from .env."
}

if ($Run) {
  Write-Host "Running app with injected Supabase credentials..." -ForegroundColor Cyan
  & flutter run @defines
} else {
  $target = switch ($Mode) {
    "appbundle" { "appbundle" }
    "debug"     { "apk --debug" }
    default     { "apk --release" }
  }
  Write-Host "Building $target with injected Supabase credentials..." -ForegroundColor Cyan
  & flutter build $target.Split(" ") @defines
  Write-Host "`nDone. Output under build/app/outputs/" -ForegroundColor Green
}
