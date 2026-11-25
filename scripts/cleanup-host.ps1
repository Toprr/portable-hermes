# Removes what Hermes and its tools leave outside this folder (pnpm lock files, agent-desktop's
# temporary state) and the one file Hermes writes there by design: creating a bot (a profile)
# also writes a command alias %USERPROFILE%\.local\bin\<bot>.bat ("hermes -p <bot>"). The portable
# setup never puts "hermes" on the PATH, so the alias is useless here. Only files whose content is
# exactly Hermes' generated alias for a bot of THIS folder are removed; nothing else is touched.
# Called by start.ps1 and stop.ps1.
$ErrorActionPreference = "SilentlyContinue"

# pnpm 12 (Hermes' Node builds during updates) keeps empty store-operation lock files in
# %USERPROFILE%\AppData\Local\pnpm-store-operation-locks; no env var or pnpm setting moves them (only a
# fake user profile would). Remove the folder when no pnpm runs and it holds nothing but empty *.lock files.
$pnpmLocks = Join-Path $env:USERPROFILE "AppData\Local\pnpm-store-operation-locks"
if ((Test-Path -LiteralPath $pnpmLocks) -and -not (Get-Process pnpm -ErrorAction SilentlyContinue)) {
    $items = @(Get-ChildItem -LiteralPath $pnpmLocks -Force -Recurse)
    if (-not ($items | Where-Object { $_.PSIsContainer -or $_.Extension -ne ".lock" -or $_.Length -ne 0 })) {
        Remove-Item -LiteralPath $pnpmLocks -Recurse -Force
    }
}

# agent-desktop's temporary state on the PC's temp folder (only used when this drive is exFAT, see
# portable-env.ps1): remove it while no agent-desktop of this folder runs.
$adState = Join-Path $env:LOCALAPPDATA "Temp\hermes-portable-agent-desktop"
$adExe = Join-Path (Split-Path $PSScriptRoot -Parent) "tools\agent-desktop\agent-desktop.exe"
if ((Test-Path -LiteralPath $adState) -and -not (Get-Process agent-desktop -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $adExe })) {
    Remove-Item -LiteralPath $adState -Recurse -Force
}

$profiles = Join-Path $env:HERMES_HOME "profiles"
$aliasDir = Join-Path $env:USERPROFILE ".local\bin"
if (-not (Test-Path -LiteralPath $profiles) -or -not (Test-Path -LiteralPath $aliasDir)) { return }
foreach ($p in Get-ChildItem -LiteralPath $profiles -Directory | Where-Object { $_.Name -notlike ".*" }) {
    $alias = Join-Path $aliasDir ($p.Name + ".bat")
    if (-not (Test-Path -LiteralPath $alias)) { continue }
    # Hermes writes "\r\n" in text mode on Windows, so the file holds "\r\r\n": compare without \r
    $text = ([IO.File]::ReadAllText($alias)).Replace("`r", "")
    if ($text -eq "@echo off`nhermes -p $($p.Name) %*`n") {
        Remove-Item -LiteralPath $alias -Force
        Write-Host "Removed the bot alias $alias (portable: nothing outside this folder)"
    }
}
