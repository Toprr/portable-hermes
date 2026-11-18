# Hermes launcher window (opened by Hermes.bat).
# - Starts Hermes in the background right away (gateway: Webapp, messaging bots, scheduled jobs; Tailscale
#   for remote access), so it is reachable even before a button is pressed.
# - "Open Hermes" (or, without any click, automatically after 60 s) opens the Webapp in its own app window
#   and this small window disappears. Closing the app window stops Hermes completely.
# - Closing this small window without opening Hermes stops Hermes again (not while an update or repair runs).
# - "Update" / "Repair" run Update.bat / Setup.bat in a console, then start Hermes again.
# The app window is a browser in app mode (no tabs) with its own profile in data\app-window: the browser
# installed on this PC (Chrome, Edge or Brave), else Hermes' portable Chromium. That Chromium cannot use
# its sandbox from an exFAT drive (renders blank), so it runs with --no-sandbox, for the local Webapp only.
# Drive letter: Hermes binds each chat to the data folder's exact path (e.g. E:\Hermes\data), so Hermes
# only starts from the drive letter it was set up on (the "home drive", saved in data\home-drive.txt). On a
# PC where this drive has another letter, the drive gets the home letter first (one Windows UAC
# confirmation; Windows then remembers the letter for this drive on that PC). Without administrator rights,
# or when that letter belongs to another drive there, Hermes does not start and says why.
$ErrorActionPreference = "Stop"
# This PC's own environment, before portable-env.ps1 points TEMP, PATH and caches into the Hermes folder:
# the browser is started with it, so it never depends on files on this drive (a browser started with
# Hermes' TEMP crashes its tabs when the drive goes away).
$hostEnv = [Environment]::GetEnvironmentVariables()
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
trap {
    [System.Windows.Forms.MessageBox]::Show("The Hermes window failed:`n`n$_", "Hermes Agent", "OK", "Error") | Out-Null
    exit 1
}
$here = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path.TrimEnd('\')
$have = (Split-Path $here -Qualifier).ToUpper()
# the home drive letter (written by setup.ps1; a folder set up before that keeps the letter it runs from)
$homeFile = Join-Path $here "data\home-drive.txt"
$homeDrive = if (Test-Path -LiteralPath $homeFile) { (Get-Content -LiteralPath $homeFile -TotalCount 1).Trim().ToUpper() } else { "" }
if ($homeDrive -notmatch '^[A-Z]:$') {
    $homeDrive = $have
    if (Test-Path -LiteralPath (Join-Path $here "data")) { [IO.File]::WriteAllText($homeFile, $homeDrive) }
}

function Show-DriveError([string]$why) {
    [System.Windows.Forms.MessageBox]::Show("Hermes cannot start on this PC.`n`n$why`n`nHermes needs this drive to be $homeDrive" +
        " (your chats are bound to $homeDrive$($here.Substring(2))\data).", "Hermes Agent", "OK", "Warning") | Out-Null
    exit 1
}
if ($have -ne $homeDrive) {
    if (Test-Path -LiteralPath "$homeDrive\") {
        Show-DriveError "This drive is $have here, and $homeDrive is already used by another drive on this PC."
    }
    $f = $have.Substring(0, 1); $t = $homeDrive.Substring(0, 1)
    # elevated: Set-Partition; mountvol for a volume without a partition object
    $cmd = "try { Get-Partition -DriveLetter $f -ErrorAction Stop | Set-Partition -NewDriveLetter $t -ErrorAction Stop } " +
           "catch { `$v = (Get-Volume -DriveLetter $f).UniqueId; mountvol ${f}: /D; mountvol ${t}: `$v }"
    Set-Location $env:SystemRoot   # do not hold the drive as the working directory
    try { Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList @("-NoProfile", "-Command", $cmd) }
    catch { Show-DriveError "This drive is $have here. Changing it to $homeDrive needs administrator rights, which were not given." }
    $moved = $homeDrive + $here.Substring(2)
    for ($i = 0; $i -lt 20 -and -not (Test-Path -LiteralPath "$moved\scripts\launcher.ps1"); $i++) { Start-Sleep -Milliseconds 500 }
    if (-not (Test-Path -LiteralPath "$moved\scripts\launcher.ps1")) {
        Show-DriveError "This drive is $have here, and Windows did not change it to $homeDrive."
    }
    Start-Process powershell -WorkingDirectory $moved -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA",
        "-WindowStyle", "Hidden", "-File", "$moved\scripts\launcher.ps1")
    exit 0
}

. (Join-Path $PSScriptRoot "portable-env.ps1")
$root = $env:HERMES_PORTABLE_ROOT
$scripts = $PSScriptRoot
$url = "http://127.0.0.1:9120/"
$appProfile = Join-Path $env:HERMES_HOME "app-window"
$logDir = Join-Path $env:HERMES_HOME "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$autoOpenSeconds = 60
$iconFile = Join-Path $env:HERMES_INSTALL_DIR "apps\desktop\assets\icon.ico"   # Hermes' own icon (repo file)
$appIcon = if (Test-Path $iconFile) { New-Object System.Drawing.Icon($iconFile) } else { [System.Drawing.SystemIcons]::Application }

Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class HermesWin {
  delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  // the browser's top-level window(s) owned by one of these processes
  public static IntPtr[] Find(uint[] pids) {
    var set = new HashSet<uint>(pids); var found = new List<IntPtr>();
    EnumWindows((h, p) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (!set.Contains(pid) || GetWindowTextLength(h) == 0) return true;
      var c = new StringBuilder(64); GetClassName(h, c, 64);
      if (c.ToString() == "Chrome_WidgetWin_1") found.Add(h);
      return true;
    }, IntPtr.Zero);
    return found.ToArray();
  }
}
"@

function Get-HermesState {
    # "ready" only when the gateway reports itself running; the port opens earlier ("starting")
    $client = New-Object System.Net.Sockets.TcpClient
    try { $open = $client.ConnectAsync("127.0.0.1", 9120).Wait(300) -and $client.Connected } catch { $open = $false }
    finally { $client.Close() }
    if (-not $open) { return "down" }
    try {
        $req = [System.Net.HttpWebRequest]::Create("${url}api/status"); $req.Timeout = 2000; $req.ReadWriteTimeout = 2000
        $resp = $req.GetResponse()
        try { $body = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd() } finally { $resp.Close() }
        if ($body -match '"gateway_state"\s*:\s*"running"') { return "ready" }
    } catch { }
    "starting"
}
function Test-Hermes { (Get-HermesState) -eq "ready" }
function Test-Remote {
    $daemon = Join-Path $root "tools\tailscale\tailscaled.exe"
    [bool](Get-Process tailscaled -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $daemon })
}
function Get-AppProcesses {
    $marker = [regex]::Escape($appProfile)
    @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe' OR Name='brave.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match $marker })
}
function Get-AppBrowser {
    foreach ($name in "chrome.exe", "msedge.exe", "brave.exe") {
        foreach ($hive in "HKLM:", "HKCU:") {
            $exe = (Get-ItemProperty "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$name" -ErrorAction SilentlyContinue).'(default)'
            if ($exe -and (Test-Path $exe.Trim('"'))) { return @{ Exe = $exe.Trim('"'); Extra = @() } }
        }
    }
    $chromium = Get-ChildItem (Join-Path $env:HERMES_HOME "tools") -Directory -Filter "chromium-*" -ErrorAction SilentlyContinue |
        Sort-Object { [int]($_.Name -replace '\D', '') } | Select-Object -Last 1 |
        ForEach-Object { Join-Path $_.FullName "chrome-win64\chrome.exe" } | Where-Object { Test-Path $_ }
    if ($chromium) { return @{ Exe = $chromium; Extra = @("--no-sandbox", "--test-type") } }
    $null
}
function Open-App {
    $browser = Get-AppBrowser
    if (-not $browser) { Start-Process explorer.exe -ArgumentList $url | Out-Null; return $false }   # the shell opens a plain tab
    $argList = @("--app=$url", "--user-data-dir=`"$appProfile`"", "--no-first-run", "--no-default-browser-check",
                 "--window-size=1400,900") + $browser.Extra
    $psi = New-Object System.Diagnostics.ProcessStartInfo $browser.Exe
    $psi.Arguments = $argList -join " "
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $hostEnv["USERPROFILE"]
    $psi.EnvironmentVariables.Clear()
    foreach ($name in $hostEnv.Keys) { $psi.EnvironmentVariables[$name] = $hostEnv[$name] }
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    $true
}
function Start-Hidden([string]$file, [string[]]$extra, [string]$log) {
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $scripts $file)) + $extra
    $p = Start-Process powershell -ArgumentList $argList -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $logDir "$log.log") -RedirectStandardError (Join-Path $logDir "$log.err.log")
    $null = $p.Handle   # keep the handle so ExitCode is readable after the process ends
    $p
}
function Stop-Hermes { (Start-Hidden "stop.ps1" @("-Yes") "launcher-stop").WaitForExit(180000) | Out-Null }

# A second Hermes.bat while the app window is open just opens another Hermes window.
$mutex = New-Object System.Threading.Mutex($false, "Local\HermesPortableLauncher")
if (-not $mutex.WaitOne(0)) {
    if ((Get-AppProcesses).Count -and (Test-Hermes)) { Open-App | Out-Null }
    else { [System.Windows.Forms.MessageBox]::Show("The Hermes window is already open.", "Hermes Agent") | Out-Null }
    exit 0
}

# --- state ---
$script:busy = $null; $script:busyKind = ""; $script:afterBusy = $null   # running helper (start|stop|update|repair)
$script:pendingOpen = $false   # open the app window as soon as Hermes answers
$script:autoOpenAt = $null     # without a click, "Open Hermes" runs by itself at this time
$script:appMode = $false       # app window open, this window hidden: watch it, stop Hermes when it closes
$script:appSeenAt = $null; $script:appMissing = 0
$script:leaving = $false       # this window is closing because the app window took over

function Start-Busy([string]$kind, $process, [scriptblock]$after) {
    $script:busy = $process; $script:busyKind = $kind; $script:afterBusy = $after
}
function Start-Background {
    $script:startError = $null
    Start-Busy "start" (Start-Hidden "start.ps1" @("-Background") "launcher-start") $null
}
function Invoke-Open {
    $script:autoOpenAt = $null
    if (Test-Hermes) { Enter-AppMode }
    else {
        $script:pendingOpen = $true
        if (-not $script:busyKind) { Start-Background }
    }
}
function Enter-AppMode {
    $script:pendingOpen = $false
    if (-not (Open-App)) { return }   # plain browser tab: nothing to watch, keep this window
    $script:appMode = $true; $script:appSeenAt = Get-Date; $script:appMissing = 0
    $script:leaving = $true
    $tray.Visible = $true
    $form.Hide()
}

# --- the app window and the tray icon (minimize = hide to the tray) ---
$script:hiddenWindows = @()
$script:trayTipShown = $false
function Get-AppWindows {
    $pids = [uint32[]]@(Get-AppProcesses | ForEach-Object { [uint32]$_.ProcessId })
    if (-not $pids.Count) { return @() }
    @([HermesWin]::Find($pids))
}
function Hide-AppWindows {
    foreach ($h in (Get-AppWindows | Where-Object { [HermesWin]::IsWindowVisible($_) })) {
        [HermesWin]::ShowWindow($h, 0) | Out-Null   # SW_HIDE: gone from the taskbar too
        $script:hiddenWindows += $h
    }
    if (-not $script:trayTipShown) {
        $script:trayTipShown = $true
        $tray.ShowBalloonTip(4000, "Hermes is still running", "Double-click the Hermes icon to open it. Right-click it to quit Hermes.", "Info")
    }
}
function Show-AppWindows {
    $shown = $false
    foreach ($h in $script:hiddenWindows) {
        if ([HermesWin]::IsWindow($h)) { [HermesWin]::ShowWindow($h, 9) | Out-Null; [HermesWin]::SetForegroundWindow($h) | Out-Null; $shown = $true }
    }
    $script:hiddenWindows = @()
    if (-not $shown) {
        $visible = @(Get-AppWindows | Where-Object { [HermesWin]::IsWindowVisible($_) })
        if ($visible.Count) { foreach ($h in $visible) { [HermesWin]::ShowWindow($h, 9) | Out-Null; [HermesWin]::SetForegroundWindow($h) | Out-Null } }
        else { Open-App | Out-Null; $script:appSeenAt = Get-Date }
    }
}
function Exit-Hermes {
    $timer.Stop()
    $tray.Text = "Hermes Agent - stopping..."
    foreach ($h in (Get-AppWindows)) { [HermesWin]::PostMessage($h, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null }   # WM_CLOSE
    for ($i = 0; $i -lt 20 -and (Get-AppProcesses).Count; $i++) { Start-Sleep -Milliseconds 250 }
    Get-AppProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Hermes
    $tray.Visible = $false
    $form.Close()
}

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $appIcon; $tray.Text = "Hermes Agent"
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Items.Add("Open Hermes", $null, { Show-AppWindows }) | Out-Null
$menu.Items.Add("Hide to tray", $null, { Hide-AppWindows }) | Out-Null
$menu.Items.Add("-") | Out-Null
$menu.Items.Add("Quit Hermes", $null, { Exit-Hermes }) | Out-Null
$tray.ContextMenuStrip = $menu
$tray.Add_DoubleClick({ Show-AppWindows })

# --- window ---
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = "Hermes Agent"
$form.FormBorderStyle = "FixedDialog"; $form.MaximizeBox = $false
$form.StartPosition = "CenterScreen"
$form.ClientSize = New-Object System.Drawing.Size(400, 250)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 27)
$form.ForeColor = [System.Drawing.Color]::FromArgb(244, 244, 245)
$muted = [System.Drawing.Color]::FromArgb(161, 161, 170)
$yellow = [System.Drawing.Color]::FromArgb(250, 204, 21)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Hermes Agent"; $title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 15)
$title.Location = New-Object System.Drawing.Point(20, 14); $title.AutoSize = $true
$form.Controls.Add($title)
$countdown = New-Object System.Windows.Forms.Label
$countdown.Location = New-Object System.Drawing.Point(200, 22); $countdown.Size = New-Object System.Drawing.Size(180, 20)
$countdown.TextAlign = "MiddleRight"; $countdown.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$countdown.ForeColor = $yellow
$form.Controls.Add($countdown)
$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(22, 52); $status.Size = New-Object System.Drawing.Size(360, 22)
$form.Controls.Add($status)
$remote = New-Object System.Windows.Forms.Label
$remote.Location = New-Object System.Drawing.Point(22, 74); $remote.Size = New-Object System.Drawing.Size(360, 22)
$remote.ForeColor = $muted
$form.Controls.Add($remote)

function New-Button([string]$text, [int]$x, [int]$y, [int]$w, [System.Drawing.Color]$color, [System.Drawing.Color]$textColor) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size($w, 38)
    $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderSize = 0
    $b.ForeColor = $textColor
    $b.Tag = $color   # full color when enabled, a dimmed one when disabled (see Set-ButtonLook)
    $b.BackColor = $color
    $form.Controls.Add($b); $b
}
function Set-ButtonLook($b) {
    $c = [System.Drawing.Color]$b.Tag
    $b.BackColor = if ($b.Enabled) { $c } else {
        [System.Drawing.Color]::FromArgb([int]($c.R * 0.45 + 24 * 0.55), [int]($c.G * 0.45 + 24 * 0.55), [int]($c.B * 0.45 + 27 * 0.55))
    }
}
$white = [System.Drawing.Color]::White
$dark = [System.Drawing.Color]::FromArgb(24, 24, 27)
$btnOpen   = New-Button "Open Hermes" 20 108 360 ([System.Drawing.Color]::FromArgb(22, 163, 74)) $white
$btnUpdate  = New-Button "Update"   20 154 86 ([System.Drawing.Color]::FromArgb(37, 99, 235)) $white
$btnRepair  = New-Button "Repair"  111 154 86 $yellow $dark
$btnRestart = New-Button "Restart" 202 154 86 ([System.Drawing.Color]::FromArgb(13, 148, 136)) $white
$btnStop    = New-Button "Stop"    293 154 87 ([System.Drawing.Color]::FromArgb(220, 38, 38)) $white
foreach ($b in $btnUpdate, $btnRepair, $btnRestart, $btnStop) { $b.Font = New-Object System.Drawing.Font("Segoe UI", 9.5) }

$hint = New-Object System.Windows.Forms.Label
$hint.Location = New-Object System.Drawing.Point(22, 202); $hint.Size = New-Object System.Drawing.Size(360, 40)
$hint.ForeColor = $muted; $hint.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$hintText = "Hermes (with its messaging bots and remote access) runs while its window is open. Closing it stops Hermes. Minimize sends it to the tray."
$hint.Text = $hintText
$form.Controls.Add($hint)

function Update-View {
    $state = Get-HermesState
    $running = $state -eq "ready"
    $label = switch ($script:busyKind) {
        "start"   { "Starting Hermes..." }
        "stop"    { "Stopping Hermes..." }
        "restart" { "Restarting Hermes..." }
        "update"  { "Updating - see the update window..." }
        "repair"  { "Repairing - see the setup window..." }
        default   { if ($running) { "Hermes is running" } elseif ($state -eq "starting") { "Starting Hermes..." }
                    elseif ($script:startError) { "Start failed - try Restart or Repair" } else { "Hermes is stopped" } }
    }
    if ($script:startError -and -not $running -and -not $script:busyKind) {
        $hint.Text = "Error: $($script:startError)"; $hint.ForeColor = [System.Drawing.Color]::FromArgb(248, 113, 113)
    } else {
        $hint.Text = $hintText; $hint.ForeColor = $muted
    }
    $starting = $label -eq "Starting Hermes..."
    $status.Text = "$([char]0x25CF)  $label"
    $status.ForeColor = if ($script:busyKind -or $starting) { $yellow }
                        elseif ($running) { [System.Drawing.Color]::FromArgb(74, 222, 128) }
                        else { [System.Drawing.Color]::FromArgb(248, 113, 113) }
    $remote.Text = if (Test-Remote) { "Remote access (Tailscale): on" } else { "Remote access (Tailscale): off" }
    $left = if ($script:autoOpenAt) { [math]::Max(0, [int][math]::Ceiling(($script:autoOpenAt - (Get-Date)).TotalSeconds)) } else { $null }
    $countdown.Text = if ($null -ne $left) { "$([char]0x23F1) Auto-open in $left s" } else { "" }
    $idle = -not $script:busyKind
    $btnUpdate.Enabled = $idle; $btnRepair.Enabled = $idle; $btnRestart.Enabled = $idle; $btnStop.Enabled = $idle -and $running
    # "Open Hermes" only once Hermes is ready (or stopped: then it starts it and opens when ready)
    $btnOpen.Enabled = (-not $script:busyKind -and -not $starting -and -not $script:pendingOpen)
    $btnOpen.Text = if ($script:pendingOpen -or $starting) { "Loading..." } else { "Open Hermes" }
    foreach ($b in $btnOpen, $btnUpdate, $btnRepair, $btnRestart, $btnStop) { Set-ButtonLook $b }
    if ($script:pendingOpen -and $running) { Enter-AppMode }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    if ($script:appMode) {
        # watch the app window; give the browser a few seconds to come up
        if ((Get-AppProcesses).Count) {
            $script:appMissing = 0
            # minimized -> hide to the tray
            if (Get-AppWindows | Where-Object { [HermesWin]::IsWindowVisible($_) -and [HermesWin]::IsIconic($_) }) { Hide-AppWindows }
            return
        }
        if (((Get-Date) - $script:appSeenAt).TotalSeconds -lt 15) { return }
        $script:appMissing++
        if ($script:appMissing -lt 3) { return }
        Exit-Hermes   # the app window was closed: stop Hermes completely
        return
    }
    if ($script:busy -and $script:busy.HasExited) {
        $after = $script:afterBusy; $kind = $script:busyKind; $exitCode = $script:busy.ExitCode
        $script:busy = $null; $script:busyKind = ""; $script:afterBusy = $null
        if ($kind -eq "start" -and $exitCode) {
            # show why instead of just "stopped"; no auto-open of a Hermes that is not there
            $errLog = Join-Path $logDir "launcher-start.err.log"
            $last = @(Get-Content -LiteralPath $errLog -ErrorAction SilentlyContinue | Where-Object { $_.Trim() }) | Select-Object -Last 1
            $script:startError = if ($last) { "$last".Trim() } else { "exit code $exitCode (see data\logs\launcher-start.err.log)" }
            if ($script:startError.Length -gt 150) { $script:startError = $script:startError.Substring(0, 150) + "..." }
            $script:autoOpenAt = $null; $script:pendingOpen = $false
        }
        if ($after) { & $after }
    }
    if ($script:autoOpenAt -and (Get-Date) -ge $script:autoOpenAt) { Invoke-Open }
    if (-not $script:appMode) { Update-View }
})

$btnOpen.Add_Click({ Invoke-Open; if (-not $script:appMode) { Update-View } })
$btnUpdate.Add_Click({
    $script:autoOpenAt = $null
    Start-Busy "update" (Start-Process (Join-Path $root "Update.bat") -PassThru) { Start-Background }
    Update-View
})
$btnRepair.Add_Click({
    $script:autoOpenAt = $null
    Start-Busy "stop" (Start-Hidden "stop.ps1" @("-Yes") "launcher-stop") {
        Start-Busy "repair" (Start-Process (Join-Path $root "Setup.bat") -PassThru) { Start-Background }
    }
    Update-View
})
$btnRestart.Add_Click({
    $script:autoOpenAt = $null; $script:pendingOpen = $false
    Start-Busy "restart" (Start-Hidden "stop.ps1" @("-Yes") "launcher-stop") { Start-Background }
    Update-View
})
$btnStop.Add_Click({
    $script:pendingOpen = $false; $script:autoOpenAt = $null
    Start-Busy "stop" (Start-Hidden "stop.ps1" @("-Yes") "launcher-stop") $null
    Update-View
})

$form.Add_FormClosing({
    if ($script:appMode -and -not $script:leaving) { return }
    if ($script:appMode) { return }   # closed by the watcher after stopping Hermes
    $timer.Stop()
    if ($script:busyKind -in @("update", "repair")) { return }   # leave the console running
    $status.Text = "$([char]0x25CF)  Stopping Hermes..."; $status.ForeColor = $yellow; $form.Refresh()
    if ($script:busy -and -not $script:busy.HasExited) { $script:busy.WaitForExit(120000) | Out-Null }
    Stop-Hermes
})

$form.Add_Shown({
    if (-not (Test-Path (Join-Path $env:HERMES_HOME "tools\facts.json"))) {
        Start-Busy "repair" (Start-Process (Join-Path $root "Setup.bat") -PassThru) { Start-Background }   # first run
    } else {
        Start-Background
        $script:autoOpenAt = (Get-Date).AddSeconds($autoOpenSeconds)
    }
    Update-View
    $timer.Start()
})

$form.Icon = $appIcon
[System.Windows.Forms.Application]::Run($form)
$tray.Visible = $false; $tray.Dispose()
$mutex.ReleaseMutex()
