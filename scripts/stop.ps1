# Stops the portable Hermes Agent's background gateway (Webapp, messaging bots, scheduled jobs) and
# the portable Tailscale (remote access).
#   stop.ps1        asks before stopping while chats are still running
#   stop.ps1 -Yes   stops without asking (used by the launcher window)
param([switch]$Yes)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "portable-env.ps1")
if ($Yes) { & (Join-Path $PSScriptRoot "hermes.ps1") gateway stop --yes }
else      { & (Join-Path $PSScriptRoot "hermes.ps1") gateway stop }
$code = $LASTEXITCODE
& (Join-Path $PSScriptRoot "tailscale.ps1") stop
& (Join-Path $PSScriptRoot "cleanup-host.ps1")
exit $code
