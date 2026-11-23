# kvm-switch.ps1 - PG49WCD: switch video input AND USB hub (KVM) together via DDC/CI.
# Usage:
#   kvm-switch.ps1 notebook                 # input USB-C, USB to USB-C
#   kvm-switch.ps1 pc [-PcInput dp|hdmi]    # input DP (default) or HDMI, USB to USB-B
#   kvm-switch.ps1 status                   # prints notebook / pc-dp / pc-hdmi / unknown
# Dot-sourced without a target it only defines the functions (used by kvm-tray.ps1).
# Firmware MCM107 applies the KVM mode (VCP 0xF3) only on the next input change,
# so: write F3 first, then change the input (VCP 0x60).
param(
  [ValidateSet('notebook', 'pc', 'status', '')][string]$Target = '',
  [ValidateSet('dp', 'hdmi')][string]$PcInput = 'dp'
)

if (-not ('KvmSw' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class KvmSw {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct PM { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string d; }
  public delegate bool EnumProc(IntPtr hMon, IntPtr hdc, IntPtr r, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, EnumProc cb, IntPtr p);
  [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, out uint n);
  [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint n, [Out] PM[] a);
  [DllImport("dxva2.dll")] static extern bool DestroyPhysicalMonitors(uint n, PM[] a);
  [DllImport("dxva2.dll")] static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, IntPtr t, out uint cur, out uint max);
  [DllImport("dxva2.dll")] static extern bool SetVCPFeature(IntPtr h, byte code, uint v);
  // Runs f on the PG49 physical monitor. Handle 0 is valid, so no zero check.
  static void OnPg49(Action<IntPtr> f) {
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hm,a,b,c) => {
      uint n; GetNumberOfPhysicalMonitorsFromHMONITOR(hm, out n); var arr = new PM[n];
      if (GetPhysicalMonitorsFromHMONITOR(hm, n, arr)) {
        foreach (var m in arr) if (m.d.Contains("PG49")) f(m.h);
        DestroyPhysicalMonitors(n, arr);
      }
      return true; }, IntPtr.Zero);
  }
  // -1 = monitor not found or no reply (e.g. while the OSD is open).
  public static int Get(byte code) {
    int r = -1;
    OnPg49(h => { uint cur, max; if (GetVCPFeatureAndVCPFeatureReply(h, code, IntPtr.Zero, out cur, out max)) r = (int)cur; });
    return r;
  }
  public static bool SetAndVerify(byte code, uint v) {
    bool ok = false;
    OnPg49(h => { uint cur, max; ok = SetVCPFeature(h, code, v) && GetVCPFeatureAndVCPFeatureReply(h, code, IntPtr.Zero, out cur, out max) && cur == v; });
    return ok;
  }
}
'@
}

$KvmInputs = @{ dp = 0x0F; hdmi = 0x11; usbc = 0x1A }

function Set-Vcp([byte]$code, [uint32]$v) {
  for ($i = 1; $i -le 15; $i++) { if ([KvmSw]::SetAndVerify($code, $v)) { return }; Start-Sleep 2 }
  throw ("VCP 0x{0:X2}=0x{1:X2} failed" -f $code, $v)
}

# After the switch, F3 is pre-set to the OTHER side. The hub stays, but any later input
# change (e.g. picking the input in the OSD while this side is off and the OSD hides the
# USB menu) takes the USB hub along.
function Switch-Kvm([string]$To, [string]$PcIn = 'dp') {
  if ($To -eq 'notebook') { Set-Vcp 0xF3 3; Start-Sleep 2; Set-Vcp 0x60 $KvmInputs.usbc; $next = 2 }      # KVM USB-C
  else                    { Set-Vcp 0xF3 2; Start-Sleep 2; Set-Vcp 0x60 $KvmInputs[$PcIn]; $next = 3 }   # KVM USB-B
  Start-Sleep 5   # let the hub finish switching first
  for ($i = 0; $i -lt 5 -and -not [KvmSw]::SetAndVerify(0xF3, $next); $i++) { Start-Sleep 2 }   # best effort
}

function Get-KvmStatus {
  switch ([KvmSw]::Get(0x60)) {
    0x1A    { 'notebook' }
    0x0F    { 'pc-dp' }
    0x11    { 'pc-hdmi' }
    default { 'unknown' }
  }
}

switch ($Target) {
  'status' { Get-KvmStatus }
  ''       { }
  default  { Switch-Kvm $Target $PcInput }
}
