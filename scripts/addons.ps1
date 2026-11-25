# Keeps the add-ons that Hermes' own updater does not cover up to date, for every bot (profile):
#   agent-desktop  Vercel's CLI that the agent-desktop skill drives (desktop apps through the Windows
#                  accessibility tree, no screenshots, no mouse): always the newest GitHub release,
#                  checked against the sha256 GitHub publishes for it, in tools\agent-desktop (where
#                  its temporary state goes: AGENT_DESKTOP_HOME in portable-env.ps1).
#   skills         the official agent-desktop skill is installed on every bot; every registry (hub)
#                  skill is updated with Hermes' own "skills update" (security scan included).
#   plugins        catalog and Git plugins: Hermes' own "plugins update" (security scan included), and
#                  Hermes' daily unattended plugin update (plugins.auto_apply) is switched on.
#   hermex-push    only when a local patch for the Hermex push plugin is kept in
#                  data\addons\hermex-push.patch (a git diff relative to the plugin folder; the plugin
#                  imports fcntl, which Windows lacks, upstream issue #36): a new upstream version is
#                  patched, checked with "hermes plugins doctor" and staged; it goes live at the next
#                  start, before the gateway runs. When the patch no longer fits a new version, the
#                  working version stays and a warning is printed.
#   addons.ps1                update now (update.ps1)
#   addons.ps1 -Auto          daily background run from start.ps1 (skipped when the last run is < 20 h old)
#   addons.ps1 -ApplyStaged   start.ps1, before the gateway starts: puts a staged plugin version live
param([switch]$Auto, [switch]$ApplyStaged)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # PowerShell 5's progress bar slows downloads down a lot
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot "portable-env.ps1")
$root = $env:HERMES_PORTABLE_ROOT
$hermes = Join-Path $PSScriptRoot "hermes.ps1"
$state = Join-Path $env:HERMES_HOME "addons"
$staged = Join-Path $state "staged"
$hxRepo = "https://github.com/uzairansaruzi/hermex-push.git"
$hxPatch = Join-Path $state "hermex-push.patch"
$hxRev = Join-Path $state "hermex-push.rev"          # upstream commit the live copies are built from
$adSkill = "skills-sh/vercel-labs/agent-desktop/agent-desktop"
New-Item -ItemType Directory -Force -Path $state | Out-Null

$bots = @(@{ Name = "default"; Args = @(); Dir = $env:HERMES_HOME }) +
        @(Get-ChildItem (Join-Path $env:HERMES_HOME "profiles") -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "config.yaml") } |
            ForEach-Object { @{ Name = $_.Name; Args = @("-p", $_.Name); Dir = $_.FullName } })

function Test-GatewayUp {
    $client = New-Object System.Net.Sockets.TcpClient
    try { $client.ConnectAsync("127.0.0.1", 9120).Wait(300) -and $client.Connected } catch { $false } finally { $client.Close() }
}

if ($ApplyStaged) {
    $new = Join-Path $staged "hermex-push"
    if (-not (Test-Path -LiteralPath $new) -or (Test-GatewayUp)) { exit 0 }
    $swapNew = Join-Path $state "swap-new"; $swapOld = Join-Path $state "swap-old"
    foreach ($bot in $bots) {
        $dest = Join-Path $bot.Dir "plugins\hermex-push"
        if (-not (Test-Path -LiteralPath $dest)) { continue }
        foreach ($d in $swapNew, $swapOld) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
        Copy-Item -LiteralPath $new -Destination $swapNew -Recurse
        Move-Item -LiteralPath $dest -Destination $swapOld
        Move-Item -LiteralPath $swapNew -Destination $dest
        Remove-Item -LiteralPath $swapOld -Recurse -Force
        Write-Host "hermex-push: new version live for $($bot.Name)"
    }
    Move-Item -LiteralPath (Join-Path $staged "hermex-push.rev") -Destination $hxRev -Force
    Remove-Item -LiteralPath $staged -Recurse -Force
    exit 0
}

$mutex = New-Object System.Threading.Mutex($false, "Local\HermesPortableAddons")
if (-not $mutex.WaitOne(0)) { Write-Host "Add-on update is already running."; exit 0 }
$marker = Join-Path $state "last-run"
if ($Auto) {
    if ((Test-Path -LiteralPath $marker) -and ((Get-Date) - (Get-Item -LiteralPath $marker).LastWriteTime).TotalHours -lt 20) { exit 0 }
    Start-Sleep -Seconds 90   # let the gateway finish starting first
}
Write-Host "Add-on update $(Get-Date -Format s)"

function Update-AgentDesktop {
    $dir = Join-Path $root "tools\agent-desktop"
    $exe = Join-Path $dir "agent-desktop.exe"
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
    $rel = Invoke-RestMethod -UseBasicParsing -Headers @{ "User-Agent" = "portable-hermes" } `
        -Uri "https://api.github.com/repos/vercel-labs/agent-desktop/releases/latest"
    $tag = "$($rel.tag_name)"; $want = $tag.TrimStart("v")
    $have = ""
    if (Test-Path -LiteralPath $exe) { try { $have = (& $exe version | ConvertFrom-Json).data.version } catch { } }
    if ($have -eq $want) { Write-Host "agent-desktop: up to date ($want)"; return }
    $asset = $rel.assets | Where-Object { $_.name -eq "agent-desktop-$tag-$arch-pc-windows-msvc.tar.gz" }
    if (-not $asset -or "$($asset.digest)" -notmatch '^sha256:([0-9a-f]{64})$') {
        Write-Warning "agent-desktop ${tag}: no Windows archive with a published sha256, keeping '$have'"; return
    }
    $sha = $Matches[1]
    $tmp = Join-Path $env:TEMP "agent-desktop-$PID"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $tgz = Join-Path $tmp "agent-desktop.tar.gz"
        Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $tgz
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $tgz).Hash.ToLower() -ne $sha) { throw "sha256 of the download does not match GitHub's digest" }
        & (Join-Path $env:SystemRoot "System32\tar.exe") -xzf $tgz -C $tmp agent-desktop.exe
        if ($LASTEXITCODE) { throw "could not unpack the archive" }
        $got = (& (Join-Path $tmp "agent-desktop.exe") version | ConvertFrom-Json).data.version
        if ($got -ne $want) { throw "the new binary reports version '$got'" }
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        # a running agent-desktop.exe can be renamed but not overwritten
        if (Test-Path -LiteralPath $exe) { Move-Item -LiteralPath $exe -Destination (Join-Path $tmp "old.exe") }
        Move-Item -LiteralPath (Join-Path $tmp "agent-desktop.exe") -Destination $exe
        Write-Host "agent-desktop: '$have' -> $want"
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Update-SkillsAndPlugins {
    foreach ($bot in $bots) {
        $a = $bot.Args
        Write-Host "--- $($bot.Name)"
        $lock = Join-Path $bot.Dir "skills\.hub\lock.json"
        $hub = if (Test-Path -LiteralPath $lock) { @((Get-Content -Raw -LiteralPath $lock | ConvertFrom-Json).installed.PSObject.Properties.Name) } else { @() }
        if ($hub -notcontains "agent-desktop") { & $hermes @a skills install $adSkill --yes }
        & $hermes @a skills update
        $cfg = Get-Content -Raw -LiteralPath (Join-Path $bot.Dir "config.yaml")
        if ($cfg -notmatch '(?m)^\s+auto_apply:\s*true') { & $hermes @a plugins auto-update on }
        if (-not $Auto) { & $hermes @a plugins update --yes }   # the daily run leaves this to the gateway
    }
}

function Update-HermexPush {
    if (-not (Test-Path -LiteralPath $hxPatch)) { return }   # no local patch kept: nothing to maintain
    $live = @($bots | Where-Object { Test-Path -LiteralPath (Join-Path $_.Dir "plugins\hermex-push\plugin.yaml") })
    if (-not $live.Count) { return }
    $head = "$((& git ls-remote $hxRepo HEAD) -split '\s+' | Select-Object -First 1)"
    if ($head -notmatch '^[0-9a-f]{40}$') { throw "could not read the upstream version" }
    $current = if (Test-Path -LiteralPath $hxRev) { (Get-Content -Raw -LiteralPath $hxRev).Trim() } else { "" }
    # Hermex can reinstall the plugin itself: a copy the patch cannot be reversed on lacks it and counts as outdated
    $unpatched = @($live | Where-Object {
        $ErrorActionPreference = "Continue"   # PowerShell 5 turns redirected git stderr into errors
        Push-Location -LiteralPath (Join-Path $_.Dir "plugins\hermex-push")
        try { & git apply -R --check $hxPatch 2>$null; [bool]$LASTEXITCODE } finally { Pop-Location } })
    if ((Test-Path -LiteralPath (Join-Path $staged "hermex-push")) -and
        (Get-Content -Raw -LiteralPath (Join-Path $staged "hermex-push.rev")).Trim() -eq $head) {
        Write-Host "hermex-push: $($head.Substring(0, 7)) is staged and goes live at the next start"; return
    }
    if ($head -eq $current -and -not $unpatched.Count) { Write-Host "hermex-push: up to date ($($head.Substring(0, 7)))"; return }
    $work = Join-Path $env:TEMP "hermex-push-$PID"
    & git -c core.autocrlf=false clone --quiet $hxRepo $work
    if ($LASTEXITCODE) { throw "git clone failed" }
    Push-Location -LiteralPath $work
    try {
        & git -c core.autocrlf=false apply --3way --directory=plugin $hxPatch
        if ($LASTEXITCODE) {
            Write-Warning "hermex-push $($head.Substring(0, 7)): our Windows patch no longer fits this version; the working version stays. Merge data\addons\hermex-push.patch by hand."
            return
        }
        & $hermes plugins doctor --ci (Join-Path $work "plugin")
        if ($LASTEXITCODE) { Write-Warning "hermex-push $($head.Substring(0, 7)): the patched version fails Hermes' plugin check; the working version stays."; return }
        Get-ChildItem -LiteralPath (Join-Path $work "plugin") -Recurse -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force
        # the patch, rebased onto this version (keeps later merges small)
        & git -c core.autocrlf=false add plugin
        & git -c core.autocrlf=false diff --cached --relative=plugin "--output=$hxPatch"
        if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $staged | Out-Null
        Copy-Item -LiteralPath (Join-Path $work "plugin") -Destination (Join-Path $staged "hermex-push") -Recurse
        [IO.File]::WriteAllText((Join-Path $staged "hermex-push.rev"), $head)
        Write-Host "hermex-push: $($head.Substring(0, 7)) patched and staged; it goes live at the next start"
    } finally {
        Pop-Location
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$failed = $false
foreach ($step in "Update-AgentDesktop", "Update-SkillsAndPlugins", "Update-HermexPush") {
    try { & $step } catch { Write-Warning "${step}: $_"; $failed = $true }
}
if (-not $failed) { [IO.File]::WriteAllText($marker, (Get-Date -Format s)) }
exit [int]$failed
