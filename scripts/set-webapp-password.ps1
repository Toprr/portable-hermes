# Sets the username and password the Webapp asks for when it is opened from another device
# (e.g. a phone over Tailscale). Uses Hermes' own password provider (dashboard.basic_auth):
# only a scrypt hash is stored in data\config.yaml, never the password itself.
#   set-webapp-password.ps1             set or change the sign-in
#   set-webapp-password.ps1 -IfMissing  only when no password is set yet (used by Remote-Access.bat)
param([switch]$IfMissing)
. (Join-Path $PSScriptRoot "portable-env.ps1")
. (Join-Path $PSScriptRoot "relocate.ps1")
$src = $env:HERMES_INSTALL_DIR
$python = Get-ChildItem (Join-Path $env:HERMES_HOME "tools") -Directory -Filter "python-*" -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -Last 1
if (-not $python) { Write-Host "Hermes is not installed yet. Run Setup.bat first." -ForegroundColor Yellow; exit 1 }
$exe = Join-Path $python.FullName "python.exe"
$srcLiteral = $src.Replace("'", "\'")
$code = @"
import os, sys, getpass, secrets
os.environ.pop('PYTHONHOME', None); os.environ.pop('PYTHONPATH', None); os.environ.pop('VIRTUAL_ENV', None)
sys.path.insert(0, r'$srcLiteral')
import hermes_bootstrap
from plugins.dashboard_auth.basic import hash_password
from hermes_cli.config import load_config, set_config_value
basic = (load_config().get('dashboard') or {}).get('basic_auth') or {}
if $(if ($IfMissing) { 'True' } else { 'False' }) and str(basic.get('password_hash') or '').strip():
    print('  A Webapp password is already set (change it with Webapp-Password.bat).')
    sys.exit(0)
print('Webapp sign-in for other devices. The password is not shown while typing.')
user = input('  Username [admin]: ').strip() or 'admin'
pw = getpass.getpass('  Password: ')
if len(pw) < 10:
    sys.exit('  Password too short - use at least 10 characters. Nothing changed.')
if pw != getpass.getpass('  Confirm password: '):
    sys.exit('  Passwords do not match. Nothing changed.')
set_config_value('dashboard.basic_auth.username', user)
set_config_value('dashboard.basic_auth.password_hash', hash_password(pw))
set_config_value('dashboard.basic_auth.password', '')
if not str(basic.get('secret') or '').strip():
    set_config_value('dashboard.basic_auth.secret', secrets.token_urlsafe(32))
print('  Saved (as a hash). Restart Hermes (Stop-Hermes.bat, then Hermes.bat) to use it.')
"@
& $exe -I -c $code
exit $LASTEXITCODE
