# uninstall.ps1 - removes everything install.ps1 created for the current user.
Unregister-ScheduledTask -TaskName 'PG49 KVM Follow' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PG49 KVM') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:LOCALAPPDATA 'PG49-KVM') -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'PG49 KVM removed.'
