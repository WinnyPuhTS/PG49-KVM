# kvm-tray.ps1 - tray icon for PG49WCD KVM switching.
# Left click: switch to the other side. Right click: menu.
# Icon: blue "P" = PC, green "N" = notebook, gray "?" = unknown, amber = switching.
# -Keyboard <USB instance id>: also follow an OSD KVM switch. The keyboard behind the
#   monitor hub appears -> picture to this machine (-Role), vanishes -> to the other one.
#   Works on the notebook while the PC is off. Leave empty to disable.
param(
  [ValidateSet('dp', 'hdmi')][string]$PcInput = 'dp',
  [string]$Keyboard = '',
  [ValidateSet('pc', 'notebook')][string]$Role = 'pc'
)

$mutex = New-Object System.Threading.Mutex($false, 'Local\PG49-KVM-Tray')
if (-not $mutex.WaitOne(0)) { exit }   # already running

. (Join-Path $PSScriptRoot 'kvm-switch.ps1') -PcInput $PcInput   # dot-source binds its params here; keep ours
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function New-KvmIcon([string]$Letter, [string]$Hex) {
  $bmp = New-Object System.Drawing.Bitmap 32, 32
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
  $color = [System.Drawing.ColorTranslator]::FromHtml($Hex)
  # monitor body (rounded) + stand
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $r = 6; $x = 1; $y = 2; $w = 30; $h = 22
  $path.AddArc($x, $y, $r, $r, 180, 90); $path.AddArc($x + $w - $r, $y, $r, $r, 270, 90)
  $path.AddArc($x + $w - $r, $y + $h - $r, $r, $r, 0, 90); $path.AddArc($x, $y + $h - $r, $r, $r, 90, 90)
  $path.CloseFigure()
  $g.FillPath((New-Object System.Drawing.SolidBrush $color), $path)
  $g.FillRectangle((New-Object System.Drawing.SolidBrush $color), 11, 26, 10, 4)
  $font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
  $g.DrawString($Letter, $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF($x, $y, $w, $h)), $fmt)
  $g.Dispose()
  [System.Drawing.Icon]::FromHandle($bmp.GetHicon())   # built once per state, no handle churn
}

$icons = @{
  'notebook' = New-KvmIcon 'N' '#10B981'
  'pc-dp'    = New-KvmIcon 'P' '#3B82F6'
  'pc-hdmi'  = New-KvmIcon 'P' '#3B82F6'
  'unknown'  = New-KvmIcon '?' '#6B7280'
  'busy'     = New-KvmIcon '~' '#F59E0B'
}
$labels = @{ 'notebook' = 'Notebook (USB-C)'; 'pc-dp' = 'PC (DisplayPort)'; 'pc-hdmi' = 'PC (HDMI)'; 'unknown' = 'unknown'; 'busy' = 'switching...' }
$pcLabel = if ($PcInput -eq 'hdmi') { 'PC (HDMI)' } else { 'PC (DisplayPort)' }

$script:state = 'unknown'
$script:job = $null          # running switch process
$script:jobStarted = [datetime]::MinValue

$tray = New-Object System.Windows.Forms.NotifyIcon
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$head = $menu.Items.Add('PG49WCD'); $head.Enabled = $false
[void]$menu.Items.Add('-')
$miNb = $menu.Items.Add('Notebook (USB-C)')
$miPc = $menu.Items.Add($pcLabel)
[void]$menu.Items.Add('-')
$miUpd = $menu.Items.Add('Check for updates')
$miExit = $menu.Items.Add('Exit')
$tray.ContextMenuStrip = $menu

function Show-State([string]$s) {
  $script:state = $s
  $tray.Icon = $icons[$s]
  $tray.Text = "PG49 KVM: $($labels[$s])"
  $head.Text = "PG49WCD: $($labels[$s])"
  $miNb.Checked = ($s -eq 'notebook')
  $miPc.Checked = ($s -like 'pc-*')
}

function Start-Switch([string]$To) {
  if ($script:job -and -not $script:job.HasExited) { return }
  Show-State 'busy'
  $script:jobStarted = Get-Date
  $script:job = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\kvm-switch.ps1`"", $To, '-PcInput', $PcInput)
}

# Self-update: compare installed scripts with GitHub main; on change overwrite and restart.
$repoRaw = 'https://raw.githubusercontent.com/WinnyPuhTS/PG49-KVM/main'
function Update-Kvm([bool]$Manual) {
  if ($script:job -and -not $script:job.HasExited) { return }
  if (Test-Path (Join-Path $PSScriptRoot '.git')) {   # never overwrite a dev checkout
    if ($Manual) { $tray.ShowBalloonTip(3000, 'PG49 KVM', 'Running from a git checkout: use git pull.', 'Info') }
    return
  }
  try {
    $new = @{}
    $tmp = Join-Path $env:TEMP 'pg49-kvm-update.tmp'
    foreach ($f in 'kvm-switch.ps1', 'kvm-tray.ps1') {
      # curl.exe ships with Windows 10 1803+; Invoke-WebRequest can hang on proxy detection
      & curl.exe -sfL -m 20 -o $tmp "$repoRaw/$f"
      if ($LASTEXITCODE) { throw "download of $f failed (curl $LASTEXITCODE)" }
      $c = Get-Content $tmp -Raw
      if ($c -notmatch '^# kvm-') { throw "unexpected content for $f" }
      $c = $c -replace "`r`n", "`n"
      $local = (Get-Content (Join-Path $PSScriptRoot $f) -Raw) -replace "`r`n", "`n"
      if ($c -ne $local) { $new[$f] = $c }
    }
  } catch {
    if ($Manual) { $tray.ShowBalloonTip(4000, 'PG49 KVM', "Update check failed: $($_.Exception.Message)", 'Warning') }
    return
  }
  if (-not $new.Count) {
    if ($Manual) { $tray.ShowBalloonTip(3000, 'PG49 KVM', 'Up to date.', 'Info') }
    return
  }
  foreach ($f in $new.Keys) { [IO.File]::WriteAllText((Join-Path $PSScriptRoot $f), $new[$f], (New-Object Text.UTF8Encoding $false)) }   # scripts are ASCII-only
  $tray.ShowBalloonTip(3000, 'PG49 KVM', "Updated: $($new.Keys -join ', '). Restarting.", 'Info')
  Start-Sleep 2
  $tray.Visible = $false
  $mutex.ReleaseMutex()
  $a = @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-PcInput', $PcInput, '-Role', $Role)
  if ($Keyboard) { $a += '-Keyboard', "`"$Keyboard`"" }
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $a
  [Environment]::Exit(0)
}
$miUpd.add_Click({ Update-Kvm $true })
$upd = New-Object System.Windows.Forms.Timer; $upd.Interval = 60000   # first check 1 min after start
$upd.add_Tick({ $upd.Interval = 86400000; Update-Kvm $false })          # then daily
$upd.Start()

$miNb.add_Click({ Start-Switch 'notebook' })
$miPc.add_Click({ Start-Switch 'pc' })
$miExit.add_Click({ $tray.Visible = $false; [System.Windows.Forms.Application]::Exit() })
$tray.add_MouseClick({
  param($s, $e)
  if ($e.Button -ne 'Left') { return }
  if ($script:state -eq 'notebook') { Start-Switch 'pc' } else { Start-Switch 'notebook' }
})

# Status poll: every 3 s; keep the last good state while DDC does not answer (OSD open).
$poll = New-Object System.Windows.Forms.Timer; $poll.Interval = 3000
$poll.add_Tick({
  if ($script:job -and -not $script:job.HasExited) { return }
  $s = Get-KvmStatus
  if ($s -ne 'unknown' -or $script:state -eq 'busy') { if ($s -ne $script:state) { Show-State $s } }
})

# Follow OSD KVM switch via keyboard presence (debounced: two equal reads in a row).
if ($Keyboard) {
  $kbFilter = "DeviceID='$($Keyboard -replace '\\', '\\')'"
  $script:kbState = [bool](Get-CimInstance Win32_PnPEntity -Filter $kbFilter -EA 0)
  $script:kbPending = $null
  $follow = New-Object System.Windows.Forms.Timer; $follow.Interval = 1000
  $follow.add_Tick({
    $now = [bool](Get-CimInstance Win32_PnPEntity -Filter $kbFilter -EA 0)
    if ($now -eq $script:kbState) { $script:kbPending = $null; return }
    if ($script:kbPending -ne $now) { $script:kbPending = $now; return }
    $script:kbState = $now; $script:kbPending = $null
    # ignore the keyboard change our own switch just caused
    if (((Get-Date) - $script:jobStarted).TotalSeconds -lt 20) { return }
    $other = if ($Role -eq 'pc') { 'notebook' } else { 'pc' }
    $to = if ($now) { $Role } else { $other }
    # the other machine may have switched already; rewriting the input would re-sync the picture
    # (e.g. OSD input change): only re-arm the KVM mode for the way back
    if ((Get-KvmStatus) -like "$to*") {
      [void][KvmSw]::SetAndVerify(0xF3, $(if ($to -eq 'notebook') { 2 } else { 3 }))
      return
    }
    Start-Switch $to
  })
  $follow.Start()
}

Show-State (Get-KvmStatus)
$tray.Visible = $true
$poll.Start()
[System.Windows.Forms.Application]::Run()
$tray.Dispose()
$mutex.ReleaseMutex()
