# First-time setup / repair of the portable Hermes Agent.
# Uses the OFFICIAL Hermes installer (hermes-agent.nousresearch.com/install.ps1) stage by stage, with
# all data in this folder, and skips only its "products" step's PATH registration (it would add
# "hermes" to the user's PATH in the registry). Afterwards the Node interfaces are built
# (build-ui.ps1: terminal UI + admin dashboard, build-webapp.ps1: the Webapp).
#   setup.ps1                 channel "main" (every new commit of the official repository)
#   setup.ps1 -Channel stable the newest published release instead
param([ValidateSet("main", "stable")][string]$Channel = "main")
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "portable-env.ps1")
$root = $env:HERMES_PORTABLE_ROOT
$installer = Join-Path $PSScriptRoot "hermes-install.ps1"

Write-Host ""
Write-Host "  Hermes Agent - portable setup" -ForegroundColor Magenta
Write-Host "  Folder: $root   Channel: $Channel"
Write-Host ""

# 1) the current official installer (the copy from the last setup is the fallback when offline)
try {
    $text = (Invoke-WebRequest -UseBasicParsing -Uri "https://hermes-agent.nousresearch.com/install.ps1" -TimeoutSec 60).Content
    if ($text -match 'function Stage-Repository' -and $text -match 'HermesHome') {
        [IO.File]::WriteAllText($installer, $text, (New-Object Text.UTF8Encoding $false))
        Write-Host "[OK] Downloaded the current official installer"
    }
} catch { Write-Warning "Could not download the installer ($($_.Exception.Message)); using the copy from the last setup." }
if (-not (Test-Path $installer)) { throw "The official installer could not be downloaded (internet needed for the first setup)." }

function Invoke-Stage([string]$name) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -HermesHome $env:HERMES_HOME `
        -InstallDir $env:HERMES_INSTALL_DIR -Channel $Channel -NonInteractive -Stage $name | Out-Host
    return $LASTEXITCODE
}

# 2) official stages (git, source, Python, dependencies, config)
foreach ($stage in @("prerequisites", "repository", "venv", "python-deps", "config")) {
    Write-Host "-> Stage: $stage" -ForegroundColor Cyan
    $code = Invoke-Stage $stage
    if ($code -and $stage -eq "venv") {
        # exFAT: uv installs Python but cannot create its "minor version" link folder (no junctions
        # on exFAT) and reports an error. The Python itself is complete; the second run finds it.
        Write-Host "   (retrying: exFAT has no folder links; the installed Python is used directly)"
        $code = Invoke-Stage $stage
    }
    if ($stage -eq "prerequisites" -or $stage -eq "repository") { . (Join-Path $PSScriptRoot "portable-env.ps1") }  # pick up the new Git
    if ($code) { throw "Setup stage '$stage' failed (exit $code). Run Setup.bat again; see the output above." }
}

# 3) the installer's "products" tail without the PATH registration: launchers inside the checkout,
#    skills, config migration (the Node build part fails on exFAT and is done in step 4)
$uv = Get-ChildItem (Join-Path $env:HERMES_HOME "tools") -Directory -Filter "uv-*" | Where-Object { $_.Name -match '^uv-\d' } | Sort-Object Name | Select-Object -Last 1
$lock = Get-Content (Join-Path $env:HERMES_INSTALL_DIR "pm\lock.json") -Raw | ConvertFrom-Json
$pyVersion = (($lock.packages.python.version -split '\+')[0]) -replace '^(\d+\.\d+).*', '$1'
$bootPy = (& (Join-Path $uv.FullName "uv.exe") python find --managed-python --no-project "cpython-$pyVersion-windows-x86_64-none" 2>$null | Select-Object -First 1)
if (-not $bootPy) { throw "Bootstrap Python $pyVersion not found" }
Write-Host "-> Publishing commands, skills and config" -ForegroundColor Cyan
Write-Host "   (on exFAT, Hermes' own Node build reports symlink errors here - expected, the next step builds it)"
Push-Location $env:HERMES_INSTALL_DIR
try { & $bootPy -I -B -X utf8 hermes_cli/source_completion.py --source $env:HERMES_INSTALL_DIR } finally { Pop-Location }
# (a non-zero exit here only means the Node build part failed - handled next)

$hermes = Join-Path $PSScriptRoot "hermes.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File $hermes update --set-channel $Channel | Out-Null
# Git for Windows from Hermes' package store: its bash runs the agent's terminal commands. The
# installer's prerequisites step downloads it without recording it; this records it.
& powershell -NoProfile -ExecutionPolicy Bypass -File $hermes pm install git | Out-Host

# 4) terminal UI + admin dashboard and the Webapp (built on the NTFS system drive, copied back)
Write-Host "-> Building the terminal UI and admin dashboard" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build-ui.ps1")
if ($LASTEXITCODE) { Write-Warning "Interface build failed - the classic CLI still works. Run Update.bat later to retry." }
Write-Host "-> Building the Webapp" -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build-webapp.ps1")
if ($LASTEXITCODE) { Write-Warning "Webapp build failed. Run Update.bat later to retry." }

# 5) settings for the portable folder: the Webapp is served by the gateway, the agent works in workspace\
$work = Join-Path $root "workspace"
New-Item -ItemType Directory -Force -Path $work | Out-Null
& powershell -NoProfile -ExecutionPolicy Bypass -File $hermes config set webapp.enabled true | Out-Null
& powershell -NoProfile -ExecutionPolicy Bypass -File $hermes config set terminal.cwd $work | Out-Null

[IO.File]::WriteAllText((Join-Path $env:HERMES_HOME ".portable-root"), $root, (New-Object Text.UTF8Encoding $false))
# the "home drive": chats are bound to this folder's exact path, so Hermes.bat always starts from this letter
$homeFile = Join-Path $env:HERMES_HOME "home-drive.txt"
if (-not (Test-Path -LiteralPath $homeFile)) { [IO.File]::WriteAllText($homeFile, (Split-Path $root -Qualifier).ToUpper()) }
Write-Host ""
Write-Host "[OK] Setup complete. Start Hermes with Hermes.bat." -ForegroundColor Green
Write-Host "     Home drive letter: $((Get-Content -LiteralPath $homeFile -TotalCount 1).Trim()) (see README: drive letters)"
exit 0
