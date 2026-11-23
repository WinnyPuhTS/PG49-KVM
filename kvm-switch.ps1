# kvm-switch.ps1 - PG49WCD: switch video input AND USB hub (KVM) together via DDC/CI.
# Usage: kvm-switch.ps1 notebook | pc
# Found in firmware MCM107: the KVM mode (VCP 0xF3) is only applied on the next
# input change. So: write F3 first, then change the input (VCP 0x60).
param([Parameter(Mandatory)][ValidateSet('notebook','pc')][string]$Target)

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

function Set-Vcp([byte]$code, [uint32]$v) {
  for ($i = 1; $i -le 15; $i++) { if ([KvmSw]::SetAndVerify($code, $v)) { return }; Start-Sleep 2 }
  throw ("VCP 0x{0:X2}=0x{1:X2} failed" -f $code, $v)
}

if ($Target -eq 'notebook') { Set-Vcp 0xF3 3; Start-Sleep 2; Set-Vcp 0x60 0x1A }   # KVM USB-C, input USB-C
else                        { Set-Vcp 0xF3 2; Start-Sleep 2; Set-Vcp 0x60 0x0F }   # KVM USB-B, input DP
