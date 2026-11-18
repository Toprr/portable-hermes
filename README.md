# Portable Hermes

Run the official **[Hermes Agent](https://github.com/NousResearch/hermes-agent)** by Nous Research
completely from a USB SSD, a USB stick or any folder on Windows. You can plug it into another PC and
keep working, and update it with Hermes' own updater.

**This is not Hermes itself.** It is a set of PowerShell/batch scripts around the unmodified official
Hermes Agent. The scripts download Hermes with Nous Research's official installer, keep everything
inside one folder and fix the things that break when Hermes lives on a removable exFAT drive. Hermes'
source code is never changed, so every official update works.

> Not affiliated with Nous Research, Tailscale or any app mentioned here. All credit for Hermes Agent
> goes to Nous Research and its contributors.

## What you get

- **One folder holds everything:** Hermes' source, Python, Node, Git, the browser it uses, settings,
  API keys, chats, memory, skills, plugins, caches and temp files. Nothing goes to `%APPDATA%`,
  `%LOCALAPPDATA%`, the registry or PATH, and no administrator rights are needed.
- **A small start window** (`Hermes.bat`): starts Hermes in the background, opens the Webapp in its
  own app window and has Update, Repair, Restart and Stop buttons. Closing the app window stops
  Hermes. Minimizing sends it to the tray.
- **Updates** with Hermes' own updater (`Update.bat`). Settings and chats stay where they are.
- **Works on exFAT** (the usual format of USB SSDs): the interfaces that cannot be built on exFAT are
  built in a temporary copy on the system drive and copied back.
- **Any PC:** a drive letter change on another PC is handled for you (see [Drive letters](#drive-letters)).
- **Optional remote access** from your phone or laptop over [Tailscale](https://tailscale.com),
  also fully portable: no Tailscale installation, no service, no network adapter.

## Requirements

- Windows 10 or 11, 64-bit (x64)
- About 8 GB of free space, more for local models
- Internet during setup and updates
- A drive formatted as **NTFS or exFAT**. FAT32 cannot hold files over 4 GB (local models).

Last tested with **Hermes Agent v0.23.2** (`main` channel, November 2026). Hermes changes quickly and
these scripts rely on its installer stages and build scripts, so a newer Hermes version can break setup
or updates. If that happens, please [open an issue](https://github.com/Toprr/portable-hermes/issues).

## Install

**Option A: one command.** Open PowerShell and run this (replace `E:\Hermes` with your folder).
It installs the newest [release](https://github.com/Toprr/portable-hermes/releases); add `-Ref main`
for the latest development state.

```powershell
powershell -ExecutionPolicy Bypass -c "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Toprr/portable-hermes/main/install.ps1))) -Path E:\Hermes"
```

**Option B: by hand.**

1. Download the newest release ZIP from [Releases](https://github.com/Toprr/portable-hermes/releases)
   and unpack it into an empty folder on your drive,
   for example `E:\Hermes`. Use a path without spaces.
2. Right-click the ZIP → Properties → **Unblock** before unpacking, or Windows may block the scripts.
3. Run `Setup.bat`.

Setup takes about 10 to 20 minutes. It runs the official Hermes installer stage by stage into this folder
and builds the interfaces. Then start Hermes with **`Hermes.bat`** and set up a model provider in the
Webapp, the same way as in a normal Hermes install.

## Files

| File | What it does |
|---|---|
| `Hermes.bat` | Opens the start window and starts Hermes in the background. After 60 s without a click, the Webapp opens by itself. |
| `Hermes-Terminal.bat` | Hermes in the terminal (TUI). |
| `Stop-Hermes.bat` | Stops Hermes (the background gateway and remote access). |
| `Update.bat` | Updates Hermes to the newest official version and rebuilds the interfaces. |
| `Setup.bat` | First-time setup, or repair (safe to run again). |
| `Remote-Access.bat` | Turns on remote access over Tailscale (optional). |
| `Webapp-Password.bat` | Sets the username and password the Webapp asks for on other devices. |

The Webapp runs at `http://127.0.0.1:9120`. Other interfaces: `scripts\start.ps1 -Ui dashboard` for
the admin dashboard, `-Ui cli` for the classic command line. `scripts\hermes.ps1 <args>` is the
portable `hermes` command, for example `scripts\hermes.ps1 doctor`.

## Drive letters

Hermes binds every chat to the exact path of its data folder, for example `E:\Hermes\data`. This is a
Hermes security feature that protects your saved credentials. If the same chats run from `F:\Hermes`
on another PC, Hermes refuses to continue them.

So Portable Hermes always runs from the drive letter it was set up on (the **home drive**, saved in
`data\home-drive.txt`):

- On a PC where your drive gets another letter, `Hermes.bat` asks once for administrator rights (UAC)
  and gives the drive its home letter. Windows remembers that letter for this drive on that PC.
- If you decline, or another drive already uses that letter on that PC, Hermes does not start and
  tells you why.

Tip: set it up on a letter that is rarely taken, such as `H:` or `P:`. `scripts\relocate.ps1` also
repairs Hermes' install paths when the folder is started from another location anyway.

## Remote access (optional)

Run `Remote-Access.bat` once:

1. It downloads the official Tailscale for Windows and unpacks only `tailscale.exe` and
   `tailscaled.exe` into `tools\tailscale`. Nothing is installed.
2. It prints a sign-in link. Sign in with your Tailscale account (free for personal use).
3. It publishes the Webapp inside your tailnet at `https://hermes.<your-tailnet>.ts.net` and asks for
   a Webapp password.
4. Restart Hermes.

On your phone or laptop, install the Tailscale app with the same account and open that address. Any
browser works. On iPhone/iPad, the third-party app [Hermex](https://hermexapp.com) can be used as a
client for the Hermes Webapp (not affiliated with this project or with Nous Research).

Tailscale only runs while Hermes runs. It uses userspace networking, so this PC itself cannot open the
`ts.net` address; test it from another device. Turn remote access off with
`scripts\tailscale.ps1 disable`, and update Tailscale with `scripts\tailscale.ps1 install`.
HTTPS certificates (and MagicDNS) must be enabled in your Tailscale admin console; `tailscale serve`
shows a link if they are not.

> If the phone shows the Webapp as offline: iOS allows only one VPN at a time. Other VPN apps turn
> Tailscale off.

## Local models

Hermes' built-in **Local Models** feature works as well (Settings → Providers → Local Models, or
`scripts\hermes.ps1 model` → Local models). With this setup it stays portable: the engine
(llama.cpp) goes to `data\tools`, models to `data\models`, server state to `data\runtimes`. The model
server starts when Hermes needs it and unloads idle models by itself. It needs a GPU with enough
memory; NVIDIA uses the CUDA build.

## Updates

`Update.bat` (or the Update button) runs the official `hermes update` on the channel chosen at setup
(`main` = every new commit of the official repository), then rebuilds the terminal UI, the dashboard
and the Webapp. Only check: `scripts\update.ps1 -Check`. To follow published releases instead:
`scripts\hermes.ps1 update --set-channel stable`.

On exFAT, Hermes' own in-place Node build reports a symlink error during the update. That is
expected: the scripts build the same interfaces in a temporary copy right after it.

An update does not touch `data\` (settings, `.env` with your keys, chats, memory, skills, plugins),
`workspace\`, `cache\` or `scripts\`. Hermes makes its own backup before every update.

## Folder layout

```
Hermes.bat, Setup.bat, Update.bat, ...  start/maintenance (from this repository)
scripts\        the portable scripts (from this repository)
hermes-agent\   the official Hermes source (git checkout, updated by Update.bat)
data\           HERMES_HOME: config.yaml, .env (API keys), chats, memory, skills, plugins, tools
workspace\      the agent's working folder
cache\          caches and temp files (safe to delete while Hermes is stopped)
tools\          portable Tailscale (only with remote access)
```

How it works in detail, and the problems it solves: [docs/how-it-works.md](docs/how-it-works.md).

## Security

- `data\.env` holds your API keys, and `data\` holds your chats. Anyone with the drive has them.
  Consider encrypting the drive (BitLocker To Go or VeraCrypt).
- The Webapp listens on `127.0.0.1` only. Remote access goes through your private tailnet and asks
  for the Webapp password, which is stored only as a hash.
- Hermes is an agent that runs commands on the PC it is plugged into. Use it on PCs where that is OK.

## Limitations

- Windows x64 only. Paths with spaces are not tested.
- The PC must allow running PowerShell scripts (the `.bat` files use `-ExecutionPolicy Bypass`
  for the scripts only).
- Only one Portable Hermes can run on a PC at a time (fixed Webapp port 9120).

## Credits

- **[Hermes Agent](https://github.com/NousResearch/hermes-agent)** © Nous Research, MIT License.
  This project only downloads and runs it with Nous Research's official installer and updater.
- **[Tailscale](https://tailscale.com)** © Tailscale Inc., under its own license. Downloaded from
  `pkgs.tailscale.com` only when you turn on remote access.
- Python, Node.js, Git for Windows, Chromium, llama.cpp and other tools are installed by Hermes'
  own package manager under their respective licenses.
- The scripts in this repository: MIT License, see [LICENSE](LICENSE). It covers only these scripts:
  Hermes Agent, Tailscale and every other program the scripts download keep their own licenses.
