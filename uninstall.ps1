# uninstall.ps1 - removes everything install.ps1 created for the current user.
foreach ($n in 'PG49 KVM', 'PG49 KVM Follow') {
  Stop-ScheduledTask $n -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -match 'kvm-(tray|follow)\.ps1' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PG49 KVM') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:LOCALAPPDATA 'PG49-KVM') -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'PG49 KVM removed.'
