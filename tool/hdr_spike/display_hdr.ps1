# display_hdr.ps1 - each active display's HDR state, as Windows reports it.
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class D {
  [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint f, out uint p, out uint m);
  [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint f, ref uint p, IntPtr paths, ref uint m, IntPtr modes, IntPtr t);
  [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(IntPtr packet);
}
"@
$Mar = [Runtime.InteropServices.Marshal]
$p = 0; $m = 0
[D]::GetDisplayConfigBufferSizes(2, [ref]$p, [ref]$m) | Out-Null
$paths = $Mar::AllocHGlobal(72 * $p); $modes = $Mar::AllocHGlobal(64 * $m)
[D]::QueryDisplayConfig(2, [ref]$p, $paths, [ref]$m, $modes, [IntPtr]::Zero) | Out-Null

# A DISPLAYCONFIG packet for the path's target: header {type, size, adapter LUID, id}.
function Packet($index, $type, $size) {
  $buf = $Mar::AllocHGlobal($size)
  for ($o = 0; $o -lt $size; $o += 4) { $Mar::WriteInt32($buf, $o, 0) }
  $base = 72 * $index
  $Mar::WriteInt32($buf, 0, $type); $Mar::WriteInt32($buf, 4, $size)
  $Mar::WriteInt32($buf, 8, $Mar::ReadInt32($paths, $base + 20))   # target adapter LowPart
  $Mar::WriteInt32($buf, 12, $Mar::ReadInt32($paths, $base + 24))  # target adapter HighPart
  $Mar::WriteInt32($buf, 16, $Mar::ReadInt32($paths, $base + 28))  # target id
  $buf
}
for ($i = 0; $i -lt $p; $i++) {
  $name = Packet $i 2 420          # GET_TARGET_NAME
  [D]::DisplayConfigGetDeviceInfo($name) | Out-Null
  $monitor = $Mar::PtrToStringUni([IntPtr]($name.ToInt64() + 36))
  $color = Packet $i 15 36         # GET_ADVANCED_COLOR_INFO_2
  $r = [D]::DisplayConfigGetDeviceInfo($color)
  $flags = $Mar::ReadInt32($color, 20); $active = $Mar::ReadInt32($color, 32)
  $white = Packet $i 11 24         # GET_SDR_WHITE_LEVEL
  [D]::DisplayConfigGetDeviceInfo($white) | Out-Null
  "{0}: HDR supported {1}, HDR switch on {2}, active mode {3}, SDR white {4} nits{5}" -f `
    $monitor, [bool]($flags -band 16), [bool]($flags -band 32), @('SDR', 'WCG', 'HDR')[$active], `
    ($Mar::ReadInt32($white, 20) / 1000 * 80), $(if ($r) { " (query error $r)" } else { '' })
}
