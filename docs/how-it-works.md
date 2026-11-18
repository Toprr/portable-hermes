# How Portable Hermes works

Hermes Agent is built to be installed into a user profile. These are the places where that assumption
breaks on a removable drive, and what the scripts do about each one. Hermes' own code is never
patched: everything is done with environment variables, Hermes' own commands and its official
installer and updater.

## 1. Everything in one folder (`scripts\portable-env.ps1`)

Every script dot-sources `portable-env.ps1` first. It sets, for the current process only:

| Variable | Points to | Instead of |
|---|---|---|
| `HERMES_HOME` | `data\` | `%USERPROFILE%\.hermes` |
| `HERMES_INSTALL_DIR` | `hermes-agent\` | `%LOCALAPPDATA%\hermes\...` |
| `UV_PYTHON_INSTALL_DIR`, `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`, `UV_CACHE_DIR`, `UV_NO_CONFIG` | `data\tools\...`, `cache\uv` | uv's folders in the profile |
| `PIP_CACHE_DIR`, `npm_config_cache`, `npm_config_prefix`, `pnpm_config_store_dir`, `PNPM_HOME` | `cache\...`, `data\tools\...` | npm/pnpm/pip folders in the profile |
| `HF_HOME`, `XDG_CACHE_HOME`, `ELECTRON_CACHE`, `ELECTRON_BUILDER_CACHE` | `cache\...` | Hugging Face / Electron caches |
| `HERMES_GATEWAY_LOCK_DIR` | `data\state\gateway-locks` | `%USERPROFILE%\.local\state\hermes` |
| `TEMP`, `TMP` | `cache\tmp` | `%LOCALAPPDATA%\Temp` |
| `GIT_CONFIG_GLOBAL` | `data\gitconfig` | `~/.gitconfig` (it includes your normal one) |
| `PATH` | the tools Hermes' package manager installed (read from `data\tools\facts.json`) first | – |

`data\gitconfig` adds `safe.directory=*`. exFAT stores no file owner, so Git otherwise refuses the
Hermes checkout ("dubious ownership"). Your own `~/.gitconfig` is included and never changed.

## 2. Setup with the official installer (`scripts\setup.ps1`)

`setup.ps1` downloads the current official installer (`hermes-agent.nousresearch.com/install.ps1`)
and runs its stages one by one with `-HermesHome data -InstallDir hermes-agent`:
`prerequisites`, `repository`, `venv`, `python-deps`, `config`.

- **Skipped:** the installer's last step, which would add `hermes` to the user's PATH in the
  registry. The script runs the same tail itself (`hermes_cli/source_completion.py`) without the PATH
  registration.
- **exFAT retry:** on exFAT the `venv` stage fails once, because uv cannot create its "minor version"
  folder link (exFAT has no junctions). The Python itself is complete, so the second run passes.
- **Git:** the prerequisites stage downloads Git for Windows but does not record it.
  `hermes pm install git` records it, so the agent's terminal tool finds its bash.
- **Settings:** `webapp.enabled: true` (the gateway serves the Webapp) and
  `terminal.cwd: <folder>\workspace`.

## 3. Interfaces built off the drive (`scripts\build-ui.ps1`, `scripts\build-webapp.ps1`)

npm and pnpm workspaces need symlinks, and exFAT cannot store them, so Hermes' own Node build fails
there. The products are bundles, so at runtime only `ui-tui\dist`, `hermes_cli\web_dist` and
`apps\desktop\dist-webapp` are needed. The scripts:

1. copy the source to a temporary folder in the host's `%TEMP%` (NTFS),
2. build there with the portable Node from `data\tools`, using Hermes' own build scripts
   (`scripts\build\*.mjs`, `apps\desktop\scripts\build-webapp.mjs`),
3. copy the results back, and point the path in Hermes' build receipt at the real checkout,
4. delete the temporary copy.

Hermes' freshness check (`scripts\build\freshness.mjs`) then reports the interfaces as current. The
Webapp build is skipped when `data\.portable-webapp-build.json` already names the current commit.

## 4. Updates (`scripts\update.ps1`)

`hermes update --yes` (Hermes' transactional updater with its own backup), then
`hermes pm install git`, then the two builds above. Hermes' in-place Node build during the update
fails on exFAT; that warning is expected and the builds replace it.

## 5. Moving the folder (`scripts\relocate.ps1`)

Hermes stores a few absolute paths:

- `data\installs\<key>\...`, where `key = sha256(<source folder>)[:16]`
- `pyvenv.cfg` (`home = <python>`) of its Python environments
- `.project-root`, `facts.json`, `selected.json` inside the install state
- the build receipts of the interfaces
- the launchers in `data\bin`

`data\.portable-root` remembers the folder's last location. When it differs, `relocate.ps1` renames
the install state to the new key, rewrites the old root to the new one in those files (whole path
segments only), and re-creates the launchers with Hermes' own `ensure_install_launchers()`. Hermes
then does not rebuild its environment (which would need internet and minutes).

## 6. Chats and the drive letter (`scripts\launcher.ps1`)

This part cannot be solved by moving paths. Each chat keeps a launch policy (`state.db`,
`gateway.local_policy.v1:<session>`) that freezes its working folder, its profile and a reference to
the credentials, including the exact resolved data path. If that path differs, Hermes refuses the
chat with `launch_credentials_unavailable`. This is by design and protects saved credentials.
Things that do **not** work: `subst` (Python resolves it back to the real drive), or editing
`state.db`.

So the launcher keeps the path identical. `setup.ps1` writes the home drive letter to
`data\home-drive.txt`. When `Hermes.bat` runs from another letter, the launcher:

1. runs `Set-Partition -NewDriveLetter` elevated (one UAC prompt), with `mountvol` as fallback,
2. waits for the folder to appear under the home letter,
3. relaunches itself from there.

If the letter is taken or elevation is declined, it shows a message and does not start.

## 7. Nothing left on the host (`scripts\cleanup-host.ps1`)

Two things still land outside the folder; `start.ps1` and `stop.ps1` remove them:

- **Bot alias:** creating a profile ("bot") makes Hermes write `%USERPROFILE%\.local\bin\<bot>.bat`.
  The script removes only files whose content is exactly Hermes' alias for a bot of this folder.
- **pnpm locks:** pnpm 12 keeps empty lock files in
  `%USERPROFILE%\AppData\Local\pnpm-store-operation-locks`. No setting moves them. The folder is
  removed when pnpm is not running and it holds only empty `.lock` files.

## 8. The start window (`scripts\launcher.ps1`)

- Starts `start.ps1 -Background`: the gateway with the Webapp, plus Tailscale if enabled.
- Shows "Loading..." until `GET /api/status` reports `gateway_state: running`.
- **App window:** the installed Chrome, Edge or Brave in `--app` mode with its own profile in
  `data\app-window`. Hermes' portable Chromium is only a fallback; its sandbox does not work from
  exFAT (blank page), so it runs with `--no-sandbox` for the local Webapp only.
- **Host environment:** the browser is started with the PC's own environment, captured before
  `portable-env.ps1` runs. A browser that inherits Hermes' `TEMP` on the drive crashes its tabs when
  the drive goes away.
- When the app window is closed, Hermes is stopped.

## 9. Portable Tailscale (`scripts\tailscale.ps1`)

- **Install:** the official MSI is unpacked with `msiexec /a` (administrative install: files only,
  nothing registered). Only `tailscale.exe` and `tailscaled.exe` are kept in `tools\tailscale`.
- **Daemon:** `tailscaled.exe` runs by hand with
  `--tun=userspace-networking --windows-mode=dev --statedir=data\tailscale --socket=\\.\pipe\hermes-tailscaled`.
  That means no service and no network adapter.
- **Login:** `up --unattended --auto-update=false`. Without `--unattended` the node logs out when the
  CLI disconnects; without `--auto-update=false` Tailscale's updater would install the MSI.
- **Webapp:** `serve --bg 9120` publishes it inside the tailnet over HTTPS. `webapp.public_url` is set
  to the tailnet address, so the Webapp accepts requests for that host.
- **Another PC:** unattended mode ties the saved profile to the Windows account that created it, and
  another account gets "server mode ... not allowed". Before each start, `Set-StateOwner` hands the
  profile to the current account (it rewrites `LocalUserID` and the `_current/<SID>` key and keeps a
  `.bak`).

## 10. Webapp password (`scripts\set-webapp-password.ps1`)

Uses Hermes' own `dashboard.basic_auth` provider: only an scrypt hash
(`plugins.dashboard_auth.basic.hash_password`) is written to `config.yaml`, never the password.
