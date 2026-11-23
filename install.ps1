# install.ps1 - installs PG49WCD KVM switching for the current user (no admin needed).
#   pc       : hotkeys + background task "PG49 KVM Follow" (picture follows OSD KVM switch)
#   notebook : hotkeys only
# Hotkeys: Ctrl+Alt+N = picture + USB to notebook, Ctrl+Alt+P = picture + USB to PC.
param([ValidateSet('pc','notebook')][string]$Role)

$ErrorActionPreference = 'Stop'
if (-not $Role) {
  $r = Read-Host 'Install on this machine as [p]c or [n]otebook?'
  $Role = if ($r -match '^n') { 'notebook' } else { 'pc' }
}

$src  = $PSScriptRoot
$dst  = Join-Path $env:LOCALAPPDATA 'PG49-KVM'
$menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PG49 KVM'
$ps   = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

New-Item -ItemType Directory -Force $dst, $menu | Out-Null
Copy-Item (Join-Path $src 'kvm-switch.ps1') $dst -Force
if ($Role -eq 'pc') { Copy-Item (Join-Path $src 'kvm-follow.ps1') $dst -Force }

# Hotkeys only work for shortcuts in the Start Menu or on the Desktop.
$ws = New-Object -ComObject WScript.Shell
foreach ($t in @(@{ Name = 'Notebook'; Arg = 'notebook'; Key = 'CTRL+ALT+N' },
                 @{ Name = 'PC';       Arg = 'pc';       Key = 'CTRL+ALT+P' })) {
  $l = $ws.CreateShortcut((Join-Path $menu "KVM $($t.Name).lnk"))
  $l.TargetPath  = $ps
  $l.Arguments   = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dst\kvm-switch.ps1`" $($t.Arg)"
  $l.WindowStyle = 7
  $l.Hotkey      = $t.Key
  $l.Description = "PG49WCD: picture and USB to $($t.Name)"
  $l.Save()
}

if ($Role -eq 'pc') {
  $user = "$env:USERDOMAIN\$env:USERNAME"
  $a = New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dst\kvm-follow.ps1`""
  $t = New-ScheduledTaskTrigger -AtLogOn -User $user
  $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
  $p = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
  Stop-ScheduledTask 'PG49 KVM Follow' -ErrorAction SilentlyContinue
  Register-ScheduledTask -TaskName 'PG49 KVM Follow' -Action $a -Trigger $t -Settings $s -Principal $p -Description 'PG49WCD: picture follows KVM (keyboard gone = USB-C, back = DP)' -Force | Out-Null
  Start-ScheduledTask 'PG49 KVM Follow'
}

Write-Host "PG49 KVM installed as '$Role' in $dst"
Write-Host 'Hotkeys: Ctrl+Alt+N = notebook, Ctrl+Alt+P = PC (may need a re-login to become active).'
