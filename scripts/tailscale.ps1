# Portable Tailscale for remote access (phone, tablet, laptop - any device in your tailnet).
# Runs tools\tailscale\tailscaled.exe by hand (no Windows service, no network adapter:
# userspace networking), state and logs in data\tailscale. Only active after "login" was done once
# (marker data\tailscale\enabled).
#   tailscale.ps1 install  download the newest official Tailscale for Windows and unpack only its two
#                          programs into tools\tailscale (also updates them; nothing is installed)
#   tailscale.ps1 start    start tailscaled if remote access is enabled (called by start.ps1)
#   tailscale.ps1 stop     stop it (called by stop.ps1)
#   tailscale.ps1 status   show tailnet status and the Serve address
#   tailscale.ps1 login    (install if needed,) start, sign in (prints a link), publish the Webapp at
#                          https://<name>.<tailnet>.ts.net, enable remote access
#   tailscale.ps1 disable  stop it and turn remote access off (state is kept)
#   tailscale.ps1 <args>   any other "tailscale" command, e.g.  tailscale.ps1 serve status
param([Parameter(Position = 0)][string]$Action = "status", [Parameter(ValueFromRemainingArguments = $true)]$Rest)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "portable-env.ps1")
$root = $env:HERMES_PORTABLE_ROOT
$bin = Join-Path $root "tools\tailscale"
$state = Join-Path $env:HERMES_HOME "tailscale"
$logs = Join-Path $state "logs"
$marker = Join-Path $state "enabled"
$socket = "\\.\pipe\hermes-tailscaled"
$daemon = Join-Path $bin "tailscaled.exe"
$cli = Join-Path $bin "tailscale.exe"
$webPort = 9120   # the gateway-served Webapp

function Get-Daemon {
    Get-Process tailscaled -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $daemon }
}
function Invoke-TS { & $cli "--socket=$socket" @args }

# Unattended mode ties the saved Tailscale profile to the Windows account that set it up; on another
# PC (another account) tailscaled refuses that account ("server mode ... not allowed"). Before the
# daemon starts, hand the profile to the current account: its LocalUserID and the "_current/<SID>" key.
function Set-StateOwner {
    $file = Join-Path $state "tailscaled.state"
    if (-not (Test-Path -LiteralPath $file)) { return }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $raw = [IO.File]::ReadAllText($file)
    $json = $raw | ConvertFrom-Json
    if (-not $json._profiles) { return }
    $profilesText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($json._profiles))
    $owners = @([regex]::Matches($profilesText, '"LocalUserID"\s*:\s*"([^"]*)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $currentKeys = @($json.PSObject.Properties.Name | Where-Object { $_ -like "_current/*" })
    if (-not ($owners | Where-Object { $_ -ne $sid }) -and -not ($currentKeys | Where-Object { $_ -ne "_current/$sid" })) { return }
    Copy-Item -LiteralPath $file -Destination "$file.bak" -Force
    $newProfiles = [regex]::Replace($profilesText, '("LocalUserID"\s*:\s*")[^"]*(")', "`${1}$sid`${2}")
    $fixed = $raw.Replace('"' + $json._profiles + '"', '"' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($newProfiles)) + '"')
    foreach ($k in $currentKeys) { $fixed = $fixed.Replace('"' + $k + '"', '"_current/' + $sid + '"') }
    [IO.File]::WriteAllText($file, $fixed, (New-Object Text.UTF8Encoding $false))
    Write-Host "Tailscale: profile handed to this Windows account."
}

function Start-Daemon {
    if (Get-Daemon) { return }
    if (-not (Test-Path $daemon)) { throw "Tailscale is missing: $daemon" }
    Set-StateOwner
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    $env:TS_LOGS_DIR = $logs
    Start-Process $daemon -WindowStyle Hidden `
        -ArgumentList @("--tun=userspace-networking", "--statedir=$state", "--socket=$socket", "--windows-mode=dev", "--no-logs-no-support") `
        -RedirectStandardError (Join-Path $logs "tailscaled.err.log") -RedirectStandardOutput (Join-Path $logs "tailscaled.out.log") | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        Invoke-TS version --daemon *> $null   # answers once the daemon listens
        if ($LASTEXITCODE -eq 0) { break }
    }
}

function Install-Tailscale {
    # The official MSI unpacked with an administrative install (msiexec /a): extracts files, registers
    # nothing (no service, no driver, no registry). Only tailscale.exe and tailscaled.exe are kept.
    if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64") { throw "Only x64 Windows is supported by this script." }
    $info = Invoke-RestMethod "https://pkgs.tailscale.com/stable/?mode=json" -TimeoutSec 60
    $msiName = $info.MSIs.amd64
    if (-not $msiName) { throw "Could not find the current Tailscale MSI on pkgs.tailscale.com." }
    $work = Join-Path $root "cache\tailscale-install"
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path "$work\x" | Out-Null
    try {
        Write-Host "Downloading $msiName ..."
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest "https://pkgs.tailscale.com/stable/$msiName" -OutFile "$work\$msiName" -UseBasicParsing
        $p = Start-Process msiexec.exe -ArgumentList @("/a", "`"$work\$msiName`"", "/qn", "TARGETDIR=`"$work\x`"") -Wait -PassThru
        if ($p.ExitCode) { throw "Unpacking the MSI failed (msiexec exit $($p.ExitCode))." }
        $files = @{}
        foreach ($name in "tailscale.exe", "tailscaled.exe") {
            $f = Get-ChildItem "$work\x" -Recurse -Filter $name | Select-Object -First 1
            if (-not $f) { throw "$name not found in the MSI." }
            $files[$name] = $f.FullName
        }
        $wasRunning = [bool](Get-Daemon)
        Get-Daemon | Stop-Process -Force
        New-Item -ItemType Directory -Force -Path $bin | Out-Null
        foreach ($name in $files.Keys) { Copy-Item -LiteralPath $files[$name] -Destination (Join-Path $bin $name) -Force }
        if ($wasRunning) { Start-Daemon }
        Write-Host "[OK] Tailscale $($info.Version) in tools\tailscale" -ForegroundColor Green
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

switch ($Action) {
    "install" {
        Install-Tailscale
        exit 0
    }
    "start" {
        if (Test-Path $marker) { Start-Daemon }
    }
    "stop" {
        Get-Daemon | Stop-Process -Force
    }
    "disable" {
        Get-Daemon | Stop-Process -Force
        Remove-Item -LiteralPath $marker -ErrorAction SilentlyContinue
        Write-Host "Remote access is off. Run 'tailscale.ps1 login' to turn it on again."
    }
    "login" {
        if (-not (Test-Path $daemon)) { Install-Tailscale }
        Start-Daemon
        # --unattended: keep the node up when no CLI is attached (else Windows mode logs it out).
        # --auto-update=false: Tailscale's own updater would run the MSI and install a service on C:.
        Invoke-TS up --unattended --hostname=hermes --accept-dns=false --auto-update=false
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
        # HTTPS on the tailnet (needs MagicDNS + HTTPS certificates enabled in the Tailscale admin console)
        Invoke-TS serve --bg $webPort
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
        New-Item -ItemType File -Force -Path $marker | Out-Null
        # The Webapp only answers requests for the addresses it knows: register the tailnet address
        $dns = ((Invoke-TS status --json | Out-String | ConvertFrom-Json).Self.DNSName).TrimEnd('.')
        if ($dns) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "hermes.ps1") config set webapp.public_url "https://$dns" | Out-Null
            Write-Host ""
            Write-Host "[OK] Remote access is on. Address for your other devices: https://$dns" -ForegroundColor Green
            Write-Host "     Restart Hermes once so the Webapp accepts this address."
        }
        Invoke-TS serve status
    }
    "status" {
        if (-not (Get-Daemon)) { Write-Host "Tailscale is not running."; exit 0 }
        Invoke-TS status
        Invoke-TS serve status
    }
    default {
        Start-Daemon
        Invoke-TS $Action @Rest
    }
}
exit $LASTEXITCODE
