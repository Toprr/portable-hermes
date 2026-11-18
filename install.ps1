# One-step installer for Portable Hermes: downloads this repository into a folder of your choice
# (for example on a USB SSD) and runs the setup there.
#
#   powershell -ExecutionPolicy Bypass -c "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Toprr/portable-hermes/main/install.ps1))) -Path E:\Hermes"
#
# Without -Path it asks for the folder. The folder must be empty or not exist yet.
# It installs the newest release; -Ref main (or a tag like -Ref v1.0.0) installs that state instead.
param([string]$Path, [string]$Ref)
$ErrorActionPreference = "Stop"
if (-not $Ref) {
    try { $Ref = (Invoke-RestMethod "https://api.github.com/repos/Toprr/portable-hermes/releases/latest" -UseBasicParsing).tag_name }
    catch { Write-Warning "Could not look up the newest release, using main."; $Ref = "main" }
}
$repoZip = if ($Ref -eq "main") { "https://github.com/Toprr/portable-hermes/archive/refs/heads/main.zip" }
           else { "https://github.com/Toprr/portable-hermes/archive/refs/tags/$Ref.zip" }

if (-not $Path) { $Path = Read-Host "Folder for Portable Hermes (e.g. E:\Hermes)" }
if (-not $Path) { throw "No folder given." }
$Path = [IO.Path]::GetFullPath($Path).TrimEnd('\')
if ($Path.Length -le 3) { throw "Use a folder, not the root of a drive (e.g. $($Path.TrimEnd('\'))\Hermes)." }
if ($Path -match '\s') { throw "Use a folder path without spaces (paths with spaces are not tested)." }
if ((Test-Path -LiteralPath $Path) -and (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)) {
    throw "$Path is not empty. Choose a new or empty folder."
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("portable-hermes-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    Write-Host "Downloading Portable Hermes ($Ref)..."
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest $repoZip -OutFile "$tmp\repo.zip" -UseBasicParsing
    Expand-Archive -LiteralPath "$tmp\repo.zip" -DestinationPath "$tmp\x" -Force
    $src = Get-ChildItem "$tmp\x" -Directory | Select-Object -First 1
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Copy-Item -Path (Join-Path $src.FullName "*") -Destination $Path -Recurse -Force
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Get-ChildItem -LiteralPath $Path -Recurse -File | Unblock-File
Write-Host "Files are in $Path. Starting the setup (downloads Hermes Agent and its tools, ~10-20 minutes)..."
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Path "scripts\setup.ps1")
if ($LASTEXITCODE) { Write-Warning "Setup did not finish. Run Setup.bat in $Path again." }
else { Write-Host "Done. Start Hermes with $Path\Hermes.bat" -ForegroundColor Green }
