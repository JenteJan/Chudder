# Places the running Chudder window. Sizes are physical pixels and include the
# window border, so a client area of W x H needs roughly (W+16) x (H+10).
#   window.ps1 -X 0 -Y 0 -W 2016 -H 1260
#   window.ps1 -Maximize
param([int]$X = 0, [int]$Y = 0, [int]$W = 1400, [int]$H = 900, [switch]$Maximize)
Add-Type @"
using System;using System.Runtime.InteropServices;
public class ChudderWindow{
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int hh,bool r);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out RECT r);
 [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
}
"@
[ChudderWindow]::SetProcessDPIAware() | Out-Null
$p = Get-Process chudder -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { "NO_WINDOW"; exit 1 }
# Not $h: PowerShell names are case-insensitive, and a $h here once shadowed -H.
$hw = $p.MainWindowHandle
if ($Maximize) { [ChudderWindow]::ShowWindow($hw, 3) | Out-Null; "maximized"; exit 0 }
[ChudderWindow]::ShowWindow($hw, 9) | Out-Null
Start-Sleep -Milliseconds 300
# The app restores its own saved size shortly after launch; retry until it sticks.
for ($i = 0; $i -lt 8; $i++) {
  [ChudderWindow]::MoveWindow($hw, $X, $Y, $W, $H, $true) | Out-Null
  Start-Sleep -Milliseconds 900
  $r = New-Object ChudderWindow+RECT
  [ChudderWindow]::GetWindowRect($hw, [ref]$r) | Out-Null
  if (($r.R - $r.L) -eq $W -and ($r.B - $r.T) -eq $H) { break }
}
$c = New-Object ChudderWindow+RECT
[ChudderWindow]::GetClientRect($hw, [ref]$c) | Out-Null
"window $($r.R - $r.L)x$($r.B - $r.T) at $($r.L),$($r.T); client $($c.R)x$($c.B); tries $i"
