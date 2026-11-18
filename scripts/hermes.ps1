# Portable "hermes" command: runs the official Hermes CLI from this folder with all paths computed
# at start (the official launchers in data\bin store absolute paths, which break when the drive
# letter changes). Every argument is passed through, e.g.:
#   hermes.ps1                 interactive chat
#   hermes.ps1 --tui           terminal UI
#   hermes.ps1 dashboard       web dashboard
#   hermes.ps1 doctor          diagnostics
. (Join-Path $PSScriptRoot "portable-env.ps1")
. (Join-Path $PSScriptRoot "relocate.ps1")

$src = $env:HERMES_INSTALL_DIR
$python = Get-ChildItem (Join-Path $env:HERMES_HOME "tools") -Directory -Filter "python-*" -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -Last 1
if (-not $python -or -not (Test-Path (Join-Path $src "hermes_bootstrap.py"))) {
    Write-Host "Hermes is not installed yet. Run Setup.bat first." -ForegroundColor Yellow
    exit 1
}
$exe = Join-Path $python.FullName "python.exe"

# Same bootstrap as hermes_cli._launchers.runtime_command(): store Python, isolated mode, checkout
# on sys.path, HERMES_HOME pinned (here: the portable data folder), then hermes_cli.main.
$srcLiteral = $src.Replace("'", "\'")
$boot = "import os, sys, runpy; os.environ.pop('PYTHONHOME', None); os.environ.pop('PYTHONPATH', None); " +
        "os.environ.pop('VIRTUAL_ENV', None); sys.path.insert(0, r'$srcLiteral'); " +
        "import hermes_bootstrap; runpy.run_module('hermes_cli.main', run_name='__main__', alter_sys=True)"
& $exe -I -c $boot @args
exit $LASTEXITCODE
