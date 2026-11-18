# Updates the portable Hermes Agent with Hermes' own updater ("hermes update": git, dependencies,
# skills, config migration, backup) on the channel chosen at setup (main = every new commit of the
# official repository, stable = published releases), then rebuilds the Node interfaces on the NTFS
# system drive when the new version changed them (Hermes' own Node build cannot run on exFAT).
# All data (data\: settings, keys, chats, memory, skills) stays where it is.
#   update.ps1           update
#   update.ps1 -Check    only report whether an update is available
param([switch]$Check)
$ErrorActionPreference = "Stop"
$hermes = Join-Path $PSScriptRoot "hermes.ps1"

if ($Check) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $hermes update --check
    exit $LASTEXITCODE
}

Write-Host "-> Updating Hermes Agent (official updater)" -ForegroundColor Cyan
Write-Host "   (on exFAT drives Hermes' own in-place Node build reports a symlink error; the builds below replace it)"
& powershell -NoProfile -ExecutionPolicy Bypass -File $hermes update --yes
$code = $LASTEXITCODE
# bash for the agent's terminal commands (Git for Windows from Hermes' package store, inside this folder)
& powershell -NoProfile -ExecutionPolicy Bypass -File $hermes pm install git | Out-Host
Write-Host "-> Checking the terminal UI and admin dashboard" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build-ui.ps1")
$ui = $LASTEXITCODE
Write-Host "-> Checking the Webapp" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build-webapp.ps1")
$web = $LASTEXITCODE

& powershell -NoProfile -ExecutionPolicy Bypass -File $hermes --version
# leftovers the Node builds put outside this folder (pnpm lock files)
. (Join-Path $PSScriptRoot "portable-env.ps1")
& (Join-Path $PSScriptRoot "cleanup-host.ps1")
if ($code -or $ui -or $web) {
    Write-Warning "The update finished with warnings (updater exit $code, interface build exit $ui, Webapp build exit $web). Hermes keeps working; see the output above."
}
Write-Host "Restart Hermes (Stop-Hermes.bat, then Hermes.bat) so the running gateway loads the new version."
exit 0
