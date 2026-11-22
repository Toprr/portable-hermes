# Removes stale Git lock files from the Hermes checkout before Setup/Update touch it.
# A Git command that was interrupted (drive unplugged, PC switched off, window closed) leaves
# .git\index.lock behind; every later Git command then fails with "Unable to create ...index.lock:
# File exists", so Update and Repair stop at the repository stage.
# A lock counts as stale only when no Git process from this folder is running and it is older than
# two minutes. Dot-source after portable-env.ps1 (needs HERMES_INSTALL_DIR and HERMES_PORTABLE_ROOT).
$gitDir = Join-Path $env:HERMES_INSTALL_DIR ".git"
if (Test-Path -LiteralPath $gitDir) {
    # only Git's own lock files; Hermes' kernel locks in .git (hermes-update.lock etc.) are not stale files
    $gitLocks = "index.lock", "HEAD.lock", "ORIG_HEAD.lock", "FETCH_HEAD.lock", "packed-refs.lock", "config.lock", "shallow.lock"
    $locks = @(Get-ChildItem -LiteralPath $gitDir -Filter "*.lock" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $gitLocks }) +
             @(Get-ChildItem -LiteralPath (Join-Path $gitDir "refs") -Filter "*.lock" -File -Recurse -ErrorAction SilentlyContinue)
    $locks = @($locks | Where-Object { $_ -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-2) })
    if ($locks.Count) {
        $prefix = $env:HERMES_PORTABLE_ROOT.TrimEnd('\') + '\'
        $gitBusy = @(Get-Process git, git-remote-https -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) })
        if ($gitBusy.Count) {
            Write-Warning "Git is still running from this folder; leaving its lock files alone."
        } else {
            foreach ($lock in $locks) {
                Remove-Item -LiteralPath $lock.FullName -Force
                Write-Host "-> Removed a stale Git lock left by an interrupted run: $($lock.Name)" -ForegroundColor Yellow
            }
        }
    }
}
