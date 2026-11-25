# Starts the portable Hermes Agent.
#   start.ps1             the Webapp in the default browser (the gateway starts in the background and
#                         keeps running for the Webapp, Discord/Telegram and scheduled jobs)
#   start.ps1 -Ui tui     terminal UI        -Ui cli   classic command line
#   start.ps1 -Ui dashboard   admin dashboard (settings, skills, plugins, logs) in the browser
#   start.ps1 -Background     start the gateway (Webapp, messaging bots, Tailscale) without opening anything
param([ValidateSet("web", "tui", "cli", "dashboard")][string]$Ui = "web", [switch]$Background)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "portable-env.ps1")
. (Join-Path $PSScriptRoot "relocate.ps1")
$root = $env:HERMES_PORTABLE_ROOT
$hermes = Join-Path $PSScriptRoot "hermes.ps1"

if (-not (Test-Path (Join-Path $env:HERMES_HOME "tools\facts.json"))) {
    Write-Host "Hermes is not set up yet - starting Setup..." -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "setup.ps1")
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
}

# The agent works in workspace\ (terminal.cwd). "." would be wherever the gateway was started, often
# the user folder; keep it on workspace\ - also after a drive letter change, for every bot (profile).
$work = Join-Path $root "workspace"
New-Item -ItemType Directory -Force -Path $work | Out-Null
$bots = @(@{ Args = @(); Dir = $env:HERMES_HOME }) +
        @(Get-ChildItem (Join-Path $env:HERMES_HOME "profiles") -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "config.yaml") } |
            ForEach-Object { @{ Args = @("-p", $_.Name); Dir = $_.FullName } })
foreach ($bot in $bots) {
    $cfgText = Get-Content -Raw -LiteralPath (Join-Path $bot.Dir "config.yaml") -ErrorAction SilentlyContinue
    $m = [regex]::Match("$cfgText", '(?m)^terminal:\s*\r?\n(?:[ \t]+.*\r?\n|\s*\r?\n)*?[ \t]+cwd:[ \t]*(.*?)[ \t]*(#.*)?\r?$')
    $curCwd = if ($m.Success) { $m.Groups[1].Value.Trim().Trim('"', "'").Replace('\\', '\') } else { "" }
    $botArgs = $bot.Args
    if ($curCwd -ne $work) { & $hermes @botArgs config set terminal.cwd $work | Out-Null }
}
Set-Location $work
& (Join-Path $PSScriptRoot "cleanup-host.ps1")
# add-ons Hermes' updater does not cover (addons.ps1): a staged plugin update goes live now, before the
# gateway starts; the daily update check runs hidden in the background. Never blocks the start.
$addons = Join-Path $PSScriptRoot "addons.ps1"
try {
    & $addons -ApplyStaged
    $logDir = Join-Path $env:HERMES_HOME "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$addons`"", "-Auto") `
        -RedirectStandardOutput (Join-Path $logDir "addons.log") -RedirectStandardError (Join-Path $logDir "addons.err.log") | Out-Null
} catch { Write-Host "Add-ons: $_" -ForegroundColor Yellow }
# remote access (phone, other devices) via portable Tailscale - only when it was set up (tailscale.ps1 login)
try { & (Join-Path $PSScriptRoot "tailscale.ps1") start } catch { Write-Host "Tailscale: $_" -ForegroundColor Yellow }

switch ($Ui) {
    # builds are done by Setup/Update (on NTFS); never build in place on an exFAT drive
    # --no-open: with webapp.public_url set (Tailscale) Hermes would open that address, which this
    # PC itself cannot reach (userspace Tailscale); open the local address instead.
    "web"       {
        & $hermes webapp --skip-build --no-open
        # via the Windows shell: the browser gets the PC's own environment, not Hermes' TEMP/PATH on this drive
        if (-not $LASTEXITCODE -and -not $Background) { Start-Process explorer.exe -ArgumentList "http://127.0.0.1:9120/" }
    }
    "dashboard" { & $hermes dashboard --skip-build }
    "cli"       { & $hermes --cli }
    default     { & $hermes --tui }
}
exit $LASTEXITCODE
