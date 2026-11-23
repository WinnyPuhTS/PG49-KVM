# install.ps1 - installs PG49WCD KVM switching for the current user (no admin needed).
#   -Role pc|notebook : which machine this is
#   -PcInput dp|hdmi  : which monitor input the PC is connected to
# Both roles follow a KVM switch made in the monitor OSD (via a keyboard behind the hub).
# Installs a tray icon (autostart) and Start Menu hotkeys:
#   Ctrl+Alt+N = picture + USB to notebook, Ctrl+Alt+P = picture + USB to PC.
param(
  [ValidateSet('pc', 'notebook')][string]$Role,
  [ValidateSet('dp', 'hdmi')][string]$PcInput,
  [string]$Keyboard   # USB instance id of a keyboard behind the monitor hub (auto-detected)
)

$ErrorActionPreference = 'Stop'
if (-not $Role) {
  $r = Read-Host 'Install on this machine as [p]c or [n]otebook?'
  $Role = if ($r -match '^n') { 'notebook' } else { 'pc' }
}
if (-not $PcInput) {
  $r = Read-Host 'PC is connected to the monitor via [d]isplayPort or [h]DMI?'
  $PcInput = if ($r -match '^h') { 'hdmi' } else { 'dp' }
}

# Keyboard behind the monitor's USB hub (Realtek VID_0BDA&PID_541x): its USB device is
# the one whose parent is that hub. Only present while the KVM is on this machine.
if (-not $Keyboard) {
  foreach ($k in Get-PnpDevice -Class Keyboard -PresentOnly) {
    $id = $k.InstanceId
    for ($i = 0; $id -and $i -lt 10; $i++) {
      $parent = (Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_Parent -EA 0).Data
      if ($parent -match '^USB\\VID_0BDA&PID_541') { $Keyboard = $id; break }
      $id = $parent
    }
    if ($Keyboard) { break }
  }
  if ($Keyboard) { Write-Host "Following OSD KVM switch via keyboard $Keyboard" }
  else { Write-Warning 'No keyboard found behind the monitor hub (KVM on this machine?). OSD follow disabled; re-run install to retry.' }
}

$src  = $PSScriptRoot
$dst  = Join-Path $env:LOCALAPPDATA 'PG49-KVM'
$menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PG49 KVM'
$ps   = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$run  = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File"

# stop old instances (tray, former follow task) before overwriting files
foreach ($n in 'PG49 KVM', 'PG49 KVM Follow') { Stop-ScheduledTask $n -EA 0 }
Unregister-ScheduledTask 'PG49 KVM Follow' -Confirm:$false -EA 0
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? CommandLine -match 'kvm-tray\.ps1' | % { Stop-Process -Id $_.ProcessId -Force }

New-Item -ItemType Directory -Force $dst, $menu | Out-Null
Copy-Item (Join-Path $src 'kvm-switch.ps1'), (Join-Path $src 'kvm-tray.ps1') $dst -Force
Remove-Item (Join-Path $dst 'kvm-follow.ps1') -EA 0

# Hotkeys only work for shortcuts in the Start Menu or on the Desktop.
$ws = New-Object -ComObject WScript.Shell
foreach ($t in @(@{ Name = 'Notebook'; Arg = 'notebook'; Key = 'CTRL+ALT+N' },
                 @{ Name = 'PC';       Arg = 'pc';       Key = 'CTRL+ALT+P' })) {
  $l = $ws.CreateShortcut((Join-Path $menu "KVM $($t.Name).lnk"))
  $l.TargetPath  = $ps
  $l.Arguments   = "$run `"$dst\kvm-switch.ps1`" $($t.Arg) -PcInput $PcInput"
  $l.WindowStyle = 7
  $l.Hotkey      = $t.Key
  $l.Description = "PG49WCD: picture and USB to $($t.Name)"
  $l.Save()
}

$trayArgs = "$run `"$dst\kvm-tray.ps1`" -PcInput $PcInput -Role $Role"
if ($Keyboard) { $trayArgs += " -Keyboard `"$Keyboard`"" }
$l = $ws.CreateShortcut((Join-Path $menu 'PG49 KVM Tray.lnk'))
$l.TargetPath = $ps; $l.Arguments = $trayArgs; $l.WindowStyle = 7; $l.Description = 'PG49WCD KVM tray icon'; $l.Save()

$user = "$env:USERDOMAIN\$env:USERNAME"
$a = New-ScheduledTaskAction -Execute $ps -Argument $trayArgs
$t = New-ScheduledTaskTrigger -AtLogOn -User $user
$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
$p = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'PG49 KVM' -Action $a -Trigger $t -Settings $s -Principal $p -Description 'PG49WCD KVM tray icon' -Force | Out-Null
Start-ScheduledTask 'PG49 KVM'

Write-Host "PG49 KVM installed as '$Role' (PC input: $PcInput) in $dst"
Write-Host 'Tray icon started. Hotkeys: Ctrl+Alt+N = notebook, Ctrl+Alt+P = PC (may need a re-login).'
