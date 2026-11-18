# Builds the Hermes Webapp (the official Desktop workspace for a normal browser, served by the
# gateway, opened with "hermes webapp") into hermes-agent\apps\desktop\dist-webapp.
#
# Why a separate script: Hermes builds it with pnpm workspaces, which need symlinks, and exFAT USB
# drives cannot store symlinks ("hermes webapp" would try to build in place and fail). Like
# build-ui.ps1, this builds in a temporary copy of the source on the NTFS system drive with the
# portable Node from data\tools, using Hermes' own build script (apps\desktop\scripts\build-webapp.mjs),
# copies the finished bundle back and deletes the copy. Downloads go to cache\, never the user profile.
#
# Usage: build-webapp.ps1 [-Force]   (-Force rebuilds even when the bundle matches the source)
param([switch]$Force)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "portable-env.ps1")

$src   = $env:HERMES_INSTALL_DIR
$out   = Join-Path $src "apps\desktop\dist-webapp"
$stamp = Join-Path $env:HERMES_HOME ".portable-webapp-build.json"
$node  = (Get-Command node -ErrorAction Stop).Source
if ($node -notlike "$env:HERMES_HOME*") { throw "Portable Node not found (got $node). Run Setup first." }

$head = (& git -C $src rev-parse HEAD).Trim()
if ($LASTEXITCODE) { throw "Could not read the Hermes source version (git rev-parse)." }
if (-not $Force -and (Test-Path (Join-Path $out "index.html")) -and (Test-Path $stamp)) {
    $built = Get-Content -Raw $stamp | ConvertFrom-Json
    if ($built.commit -eq $head) { Write-Host "[OK] Webapp is up to date ($($head.Substring(0, 12)))."; exit 0 }
}

$hostTemp = Join-Path $env:SystemDrive "Users\$env:USERNAME\AppData\Local\Temp"
if (-not (Test-Path $hostTemp)) { $hostTemp = Join-Path $env:SystemDrive "Windows\Temp" }
$stage = Join-Path $hostTemp ("hermes-webapp-build-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
Write-Host "-> Copying the source to a temporary build folder: $stage"
robocopy $src $stage /MIR /NFL /NDL /NJH /NJS /NP /XD node_modules .hermes .build __pycache__ release dist dist-webapp | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }

try {
    $env:CI = "1"
    Push-Location $stage
    try {
        Write-Host "-> Installing the Webapp's dependencies and building it (Hermes' build-webapp.mjs)"
        & $node (Join-Path $stage "apps\desktop\scripts\build-webapp.mjs")
        if ($LASTEXITCODE) { throw "Webapp build failed ($LASTEXITCODE)" }
    } finally { Pop-Location }

    $from = Join-Path $stage "apps\desktop\dist-webapp"
    if (-not (Test-Path (Join-Path $from "index.html"))) { throw "Webapp output missing: $from" }
    robocopy $from $out /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copying the Webapp failed ($LASTEXITCODE)" }
    # the build receipt may name the build copy; point it at the real checkout (content is identical)
    Get-ChildItem $out -Filter "*.json" -File | ForEach-Object {
        $text = [IO.File]::ReadAllText($_.FullName)
        $fixed = $text.Replace($stage.Replace('\', '\\'), $src.Replace('\', '\\')).Replace($stage, $src)
        if ($fixed -ne $text) { [IO.File]::WriteAllText($_.FullName, $fixed, (New-Object Text.UTF8Encoding $false)) }
    }
    [IO.File]::WriteAllText($stamp, (@{ commit = $head; builtAt = (Get-Date).ToString("s") } | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
} finally {
    Write-Host "-> Removing the temporary build folder"
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "[OK] Webapp built: $out"
exit 0
