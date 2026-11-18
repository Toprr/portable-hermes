# Builds Hermes' two Node interfaces (terminal UI "hermes --tui" and the web dashboard) for a
# checkout on a drive without symlink support (exFAT USB drives).
#
# Why: npm links its workspaces with symlinks, which exFAT cannot store, so Hermes' own build fails
# there. The products are bundled (esbuild/vite): at runtime only ui-tui\dist and
# hermes_cli\web_dist are needed. This script builds them in a temporary copy of the source on the
# NTFS system drive, using the portable Node/npm from data\tools, copies the two results back and
# deletes the copy. Hermes' build receipts hash files relative to the source root, so the copied
# products are recognised as current by "hermes" and "hermes update".
#
# Usage: build-ui.ps1 [-Force]   (-Force rebuilds even when the products are current)
param([switch]$Force)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "portable-env.ps1")

$src  = $env:HERMES_INSTALL_DIR
$node = (Get-Command node -ErrorAction Stop).Source
if ($node -notlike "$env:HERMES_HOME*") { throw "Portable Node not found (got $node). Run Setup first." }

function Test-Current([string]$product, [string]$out) {
    $r = & $node (Join-Path $src "scripts\build\freshness.mjs") --source $src --product $product --out $out 2>$null
    return ("$r".Trim() -eq "true")
}
$tuiOut = Join-Path $src "ui-tui\dist"
$webOut = Join-Path $src "hermes_cli\web_dist"
if (-not $Force -and (Test-Current "tui" $tuiOut) -and (Test-Current "web" $webOut)) {
    Write-Host "[OK] Terminal UI and web dashboard are up to date."
    exit 0
}

# temporary build copy on the system drive (NTFS); the host temp folder, not the portable one
$hostTemp = Join-Path $env:SystemDrive "Users\$env:USERNAME\AppData\Local\Temp"
if (-not (Test-Path $hostTemp)) { $hostTemp = Join-Path $env:SystemDrive "Windows\Temp" }
$stage = Join-Path $hostTemp ("hermes-ui-build-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
Write-Host "-> Copying the source to a temporary build folder: $stage"
robocopy $src $stage /MIR /NFL /NDL /NJH /NJS /NP /XD .git node_modules .hermes dist web_dist __pycache__ | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }

try {
    $env:CI = "1"
    $py = Get-ChildItem (Join-Path $env:HERMES_HOME "tools") -Directory -Filter "python-*" | Select-Object -Last 1
    if ($py) { $env:HERMES_PYTHON = Join-Path $py.FullName "python.exe"; $env:PYTHON = $env:HERMES_PYTHON }
    Push-Location $stage
    try {
        Write-Host "-> Installing Node dependencies (npm ci, from the lock file)"
        & $node scripts\build\node-deps.mjs --source $stage --reuse --workspace ui-tui --workspace web
        if ($LASTEXITCODE) { throw "Node dependencies failed ($LASTEXITCODE)" }
        Write-Host "-> Building the terminal UI"
        & $node scripts\build\tui.mjs
        if ($LASTEXITCODE) { throw "TUI build failed ($LASTEXITCODE)" }
        Write-Host "-> Building the web dashboard"
        & $node scripts\build\web.mjs --source $stage --icons $stage --out (Join-Path $stage "hermes_cli\web_dist")
        if ($LASTEXITCODE) { throw "web build failed ($LASTEXITCODE)" }
    } finally { Pop-Location }

    foreach ($pair in @(@("ui-tui\dist", $tuiOut), @("hermes_cli\web_dist", $webOut))) {
        $from = Join-Path $stage $pair[0]
        if (-not (Test-Path $from)) { throw "build output missing: $from" }
        robocopy $from $pair[1] /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "copying $($pair[0]) back failed ($LASTEXITCODE)" }
        # The web receipt records the absolute path of a prepared input (web\public icons). Its
        # content is identical in the copy; point the path at the real checkout.
        $receipt = Join-Path $pair[1] "hermes-build.json"
        if (Test-Path -LiteralPath $receipt) {
            $text = [IO.File]::ReadAllText($receipt)
            $fixed = $text.Replace(($stage.Replace('\', '\\')), ($src.Replace('\', '\\')))
            if ($fixed -ne $text) { [IO.File]::WriteAllText($receipt, $fixed, (New-Object Text.UTF8Encoding $false)) }
        }
    }
} finally {
    Write-Host "-> Removing the temporary build folder"
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}

$ok = (Test-Current "tui" $tuiOut) -and (Test-Current "web" $webOut)
if ($ok) { Write-Host "[OK] Terminal UI and web dashboard built." } else { Write-Warning "Products were copied, but Hermes does not report them as current." }
exit ([int](-not $ok))

