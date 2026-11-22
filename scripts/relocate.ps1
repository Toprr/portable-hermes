# Keeps the installation working after the folder moved (other drive letter, other computer).
# Dot-sourced by hermes.ps1 after portable-env.ps1; does nothing when the folder did not move.
#
# Hermes stores a few absolute paths:
#   data\installs\<key>\...           key = sha256(<source folder>)[:16] (pm/environments.py)
#   ...\pyvenv.cfg  "home = <python>" Python environments
#   ...\inputs\.project-root          the source folder
#   ui-tui\dist + hermes_cli\web_dist\hermes-build.json   build receipts (web: icons path)
# When the folder moved, the install state is renamed to the new key and the old root is replaced
# by the new one in those files - instead of Hermes rebuilding everything (network, minutes).
# Only string paths are used for the OLD location: its drive usually does not exist any more.

function Get-InstallKey([string]$sourceDir) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sourceDir))
    return (-join ($bytes | ForEach-Object { $_.ToString("x2") })).Substring(0, 16)
}

try {
    $marker  = [IO.Path]::Combine($env:HERMES_HOME, ".portable-root")
    $newRoot = $env:HERMES_PORTABLE_ROOT
    $oldRoot = if ([IO.File]::Exists($marker)) { ([IO.File]::ReadAllText($marker)).Trim() } else { "" }

    if ($oldRoot -and ($oldRoot -ne $newRoot)) {
        Write-Host "-> The Hermes folder moved: $oldRoot -> $newRoot. Updating stored paths..." -ForegroundColor Cyan
        $installs = [IO.Path]::Combine($env:HERMES_HOME, "installs")
        $oldKey = Get-InstallKey ($oldRoot + "\hermes-agent")
        $newKey = Get-InstallKey ($newRoot + "\hermes-agent")
        $oldDirHere = [IO.Path]::Combine($installs, $oldKey)                 # where the folder is now
        $oldDirText = $oldRoot + "\data\installs\" + $oldKey                  # how files still name it
        $newDir = [IO.Path]::Combine($installs, $newKey)
        if ([IO.Directory]::Exists($oldDirHere) -and -not [IO.Directory]::Exists($newDir)) {
            [IO.Directory]::Move($oldDirHere, $newDir)
        }
        $files = New-Object System.Collections.Generic.List[string]
        if ([IO.Directory]::Exists($newDir)) {
            # install facts (environment + lock paths, incl. the key), Python environments, source root
            foreach ($pattern in @("facts.json", "pyvenv.cfg", ".project-root", "selected.json")) {
                foreach ($f in [IO.Directory]::GetFiles($newDir, $pattern, [IO.SearchOption]::AllDirectories)) {
                    if ($f -notmatch '\\(Lib|site-packages|workspace)\\') { $files.Add($f) }
                }
            }
        }
        foreach ($receipt in @("ui-tui\dist\hermes-build.json", "hermes_cli\web_dist\hermes-build.json")) {
            $p = [IO.Path]::Combine($env:HERMES_INSTALL_DIR, $receipt)
            if ([IO.File]::Exists($p)) { $files.Add($p) }
        }
        # old -> new, first the install folder (its name is the key), then the root; plain and
        # JSON-escaped spelling; only whole path segments ("E:\Hermes" never matches "E:\Hermes2")
        $pairs = @(@($oldDirText, $newDir), @($oldDirHere, $newDir), @($oldRoot, $newRoot))
        $utf8 = New-Object Text.UTF8Encoding $false
        foreach ($f in $files) {
            $text = [IO.File]::ReadAllText($f)
            $fixed = $text
            foreach ($pair in $pairs) {
                foreach ($esc in @($false, $true)) {
                    $from = if ($esc) { $pair[0].Replace('\', '\\') } else { $pair[0] }
                    $to   = if ($esc) { $pair[1].Replace('\', '\\') } else { $pair[1] }
                    $fixed = [regex]::Replace($fixed, [regex]::Escape($from) + '(?=[\\/"\r\n]|$)', $to.Replace('$', '$$'),
                        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
                }
            }
            if ($fixed -ne $text) { [IO.File]::WriteAllText($f, $fixed, $utf8) }
        }
        # config.yaml (root + bots) keeps the update channel per install: update.installs.<key>.path.
        # Without the new key Hermes would treat the moved folder as unconfigured and switch to "stable".
        $configs = @([IO.Path]::Combine($env:HERMES_HOME, "config.yaml")) +
                   @(Get-ChildItem ([IO.Path]::Combine($env:HERMES_HOME, "profiles")) -Directory -ErrorAction SilentlyContinue |
                       ForEach-Object { [IO.Path]::Combine($_.FullName, "config.yaml") })
        foreach ($f in $configs) {
            if (-not [IO.File]::Exists($f)) { continue }
            $text = [IO.File]::ReadAllText($f)
            $fixed = [regex]::Replace($text, '(?m)^(\s+)' + $oldKey + ':', '${1}' + $newKey + ':')
            $fixed = [regex]::Replace($fixed, '(?m)^(\s+path:\s*)' + [regex]::Escape($oldRoot + "\hermes-agent") + '[ \t]*(?=\r?$)',
                '${1}' + ($newRoot + "\hermes-agent").Replace('$', '$$'), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($fixed -ne $text) { [IO.File]::WriteAllText($f, $fixed, $utf8) }
        }
        Write-Host "[OK] Paths updated ($($files.Count + $configs.Count) files checked)." -ForegroundColor Green
        # The official launchers (hermes-agent\.hermes\bin and data\bin, used by the desktop app,
        # the gateway and Hermes' own relaunches) embed the source path: re-create them with
        # Hermes' own function so they point at the new location.
        $pyDir = Get-ChildItem ([IO.Path]::Combine($env:HERMES_HOME, "tools")) -Directory -Filter "python-*" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
        if ($pyDir) {
            $srcLit = $env:HERMES_INSTALL_DIR
            $code = "import os, sys; os.environ.pop('PYTHONHOME', None); os.environ.pop('PYTHONPATH', None); " +
                    "sys.path.insert(0, r'$srcLit'); import hermes_bootstrap; from pathlib import Path; " +
                    "from hermes_cli._launchers import ensure_install_launchers; " +
                    "ensure_install_launchers(Path(r'$srcLit'), Path(os.environ['HERMES_HOME']) / 'bin')"
            & ([IO.Path]::Combine($pyDir.FullName, "python.exe")) -I -c $code
            if ($LASTEXITCODE) { Write-Warning "Could not re-create the Hermes launchers (exit $LASTEXITCODE)." }
        }
    }
    if ($oldRoot -ne $newRoot) {
        [IO.File]::WriteAllText($marker, $newRoot, (New-Object Text.UTF8Encoding $false))
    }
} catch {
    Write-Warning "Could not update stored paths after a move: $($_.Exception.Message). Hermes may rebuild its environment (needs internet)."
}

