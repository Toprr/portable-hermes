# Portable environment for Hermes Agent.
# Dot-source this file (". .\portable-env.ps1") before running anything Hermes-related.
# Every folder Hermes, uv, pip, npm, Playwright or Hugging Face would normally put in the user
# profile (%APPDATA%, %LOCALAPPDATA%, %TEMP%) is redirected into this portable folder, and the
# portable tools come first on PATH, so the installation neither uses nor changes host programs
# and can be moved to another drive letter or computer.

# After a drive letter change (other PC) relocate.ps1 adapts the stored install paths. Chats stay
# bound to the data folder's path they were created under (Hermes' credential scope), so the
# launcher (Hermes.bat) always starts Hermes from the same drive letter (see launcher.ps1).
$script:HermesRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path.TrimEnd('\')
$root = $script:HermesRoot

$env:HERMES_PORTABLE_ROOT = $root
$env:HERMES_HOME          = Join-Path $root "data"            # config, keys, sessions, memory, skills, tools
$env:HERMES_INSTALL_DIR   = Join-Path $root "hermes-agent"    # official source checkout (git, updatable)
$store = Join-Path $env:HERMES_HOME "tools"                   # Hermes' package manager (PM) store

# uv (Python + packages) - never in the user profile
$env:UV_PYTHON_INSTALL_DIR = Join-Path $store "uv-python"
$env:UV_CACHE_DIR          = Join-Path $root "cache\uv"
$env:UV_TOOL_DIR           = Join-Path $store "uv-tools"
$env:UV_TOOL_BIN_DIR       = Join-Path $store "uv-tools\bin"
$env:UV_NO_CONFIG          = "1"                             # ignore uv.toml files of the host

# other caches
$env:PIP_CACHE_DIR    = Join-Path $root "cache\pip"
$env:npm_config_cache = Join-Path $root "cache\npm"
$env:npm_config_prefix = Join-Path $store "npm-global"        # "npm install -g" (some skills) lands here
$env:pnpm_config_store_dir = Join-Path $root "cache\pnpm-store"   # pnpm (Hermes' Node builds), default %LOCALAPPDATA%\pnpm
$env:npm_config_store_dir  = $env:pnpm_config_store_dir
$env:PNPM_HOME             = Join-Path $store "pnpm-home"
# the gateway's machine-wide lock/rendezvous files (default %USERPROFILE%\.local\state\hermes)
$env:HERMES_GATEWAY_LOCK_DIR = Join-Path $root "data\state\gateway-locks"
$env:HF_HOME          = Join-Path $root "cache\huggingface"
$env:XDG_CACHE_HOME   = Join-Path $root "cache"
$env:PYTHONUTF8       = "1"
# Electron runtime + electron-builder tools (desktop app build), default %LOCALAPPDATA%
$env:ELECTRON_CACHE         = Join-Path $root "cache\electron"
$env:electron_config_cache  = $env:ELECTRON_CACHE
$env:ELECTRON_BUILDER_CACHE = Join-Path $root "cache\electron-builder"

# exFAT/USB drives store no file owner, so Git refuses repositories there ("dubious ownership").
# Hermes processes use data\gitconfig as their global Git config: it includes the user's own
# ~/.gitconfig and adds safe.directory=*. The user's file is not changed.
$env:GIT_CONFIG_GLOBAL  = Join-Path $root "data\gitconfig"
$env:GIT_CONFIG_COUNT   = "1"
$env:GIT_CONFIG_KEY_0   = "safe.directory"
$env:GIT_CONFIG_VALUE_0 = "*"

# temporary files inside the portable folder as well
$tmp = Join-Path $root "cache\tmp"
$env:TEMP = $tmp
$env:TMP  = $tmp

foreach ($dir in @($env:HERMES_HOME, $env:UV_CACHE_DIR, $env:PIP_CACHE_DIR, $env:npm_config_cache, $env:HF_HOME, $tmp)) {
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
}
if (-not (Test-Path -LiteralPath $env:GIT_CONFIG_GLOBAL)) {
    $gitconfig = "# Git configuration used by the portable Hermes (GIT_CONFIG_GLOBAL, set in scripts\portable-env.ps1).`n" +
                 "# It reads the user's normal ~/.gitconfig (name, e-mail, aliases ...) and additionally trusts`n" +
                 "# repositories on drives that store no file owner (exFAT/USB). The user's own file is not changed.`n" +
                 "[include]`n`tpath = ~/.gitconfig`n[safe]`n`tdirectory = *`n"
    [IO.File]::WriteAllText($env:GIT_CONFIG_GLOBAL, $gitconfig, (New-Object Text.UTF8Encoding $false))
}

# PATH: Hermes' launchers + every tool PM installed (as PM itself declares them in facts.json,
# "{{store}}" = data\tools), ahead of everything on the host. Only for this process.
$pathParts = @((Join-Path $env:HERMES_HOME "bin"), (Join-Path $store "npm-global"))
$facts = Join-Path $store "facts.json"
if (Test-Path -LiteralPath $facts) {
    try {
        $packages = (Get-Content -LiteralPath $facts -Raw | ConvertFrom-Json).packages
        foreach ($pkg in $packages.PSObject.Properties) {
            $pkgEnv = $pkg.Value.env
            if (-not $pkgEnv) { continue }
            foreach ($var in $pkgEnv.PSObject.Properties) {
                $values = @($var.Value) | ForEach-Object { "$_".Replace("{{store}}", $store) }
                if ($var.Name -eq "PATH") { $pathParts += $values }
                else { Set-Item -Path "env:$($var.Name)" -Value ($values -join ';') }
            }
        }
    } catch {
        Write-Warning "Could not read $facts : $_"
    }
}
$env:Path = (($pathParts | Where-Object { $_ }) + @($env:Path)) -join ';'
