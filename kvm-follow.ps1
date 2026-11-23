# kvm-follow.ps1 - PG49WCD: video input follows the KVM.
# Monitor KVM (OSD) moves keyboard to notebook -> PC sees keyboard vanish -> input = USB-C.
# KVM back -> keyboard reappears -> input = DisplayPort.
# DDC/CI cannot trigger the KVM itself on this monitor (tested), so the KVM stays the trigger.
param(
  [string]$Keyboard = 'USB\VID_1532&PID_021E\7&3A380C4C&0&1',  # Razer Ornata Chroma behind monitor hub
  [int]$InputPc = 0x0F,        # DisplayPort
  [int]$InputNotebook = 0x1A,  # USB-C
  [string]$Log = "$env:TEMP\kvm-follow.log"
)

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class KvmDdc {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct PM { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string d; }
  public delegate bool EnumProc(IntPtr hMon, IntPtr hdc, IntPtr r, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, EnumProc cb, IntPtr p);
  [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, out uint n);
  [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint n, [Out] PM[] a);
  [DllImport("dxva2.dll")] static extern bool DestroyPhysicalMonitors(uint n, PM[] a);
  [DllImport("dxva2.dll")] static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, IntPtr t, out uint cur, out uint max);
  [DllImport("dxva2.dll")] static extern bool SetVCPFeature(IntPtr h, byte code, uint v);
  // Set VCP on the PG49 and read it back. Handle 0 is valid, so no zero check.
  public static bool SetAndVerify(byte code, uint v) {
    bool ok = false;
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hm,a,b,c) => {
      uint n; GetNumberOfPhysicalMonitorsFromHMONITOR(hm, out n); var arr = new PM[n];
      if (GetPhysicalMonitorsFromHMONITOR(hm, n, arr)) {
        foreach (var m in arr) if (m.d.Contains("PG49")) { uint cur, max; ok = SetVCPFeature(m.h, code, v) && GetVCPFeatureAndVCPFeatureReply(m.h, code, IntPtr.Zero, out cur, out max) && cur == v; }
        DestroyPhysicalMonitors(n, arr);
      }
      return true; }, IntPtr.Zero);
    return ok;
  }
}
'@

function Write-Log($m) { "$(Get-Date -f 'yyyy-MM-dd HH:mm:ss') $m" | Add-Content $Log }
function Test-Keyboard { [bool](Get-CimInstance Win32_PnPEntity -Filter "DeviceID='$($Keyboard -replace '\\','\\')'" -EA 0) }
function Set-Input([int]$v) {
  for ($i = 1; $i -le 15; $i++) { if ([KvmDdc]::SetAndVerify(0x60, $v)) { Write-Log ("input 0x{0:X2} ok after {1}" -f $v, $i); return }; Start-Sleep 2 }
  Write-Log ("input 0x{0:X2} FAILED" -f $v)
}

$state = Test-Keyboard
Write-Log "start, keyboard present=$state"
while ($true) {
  Start-Sleep -Milliseconds 1000
  $now = Test-Keyboard
  if ($now -eq $state) { continue }
  Start-Sleep -Milliseconds 1500   # debounce: hub re-enumeration flickers
  if ((Test-Keyboard) -ne $now) { continue }
  $state = $now
  Write-Log "keyboard present=$state"
  if ($state) { Set-Input $InputPc } else { Set-Input $InputNotebook }
}
