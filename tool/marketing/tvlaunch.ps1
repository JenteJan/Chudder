# Starts the release build in television mode and puts it full screen on the
# primary monitor. Moving it to a monitor with a different scale makes Flutter
# resize it and the grabs come out the wrong size.
param([int]$W = 2560, [int]$H = 1440)
Add-Type @"
using System;using System.Runtime.InteropServices;
public class TvWindow{
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int hh,bool r);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
}
"@
[TvWindow]::SetProcessDPIAware() | Out-Null
if (Get-Process chudder -ErrorAction SilentlyContinue) { "Chudder is already running; close it first"; exit 1 }
$exe = Join-Path $PSScriptRoot "..\..\build\windows\x64\runner\Release\chudder.exe" | Resolve-Path
Start-Process -FilePath $exe -ArgumentList '--htpc' -WorkingDirectory (Split-Path $exe)
Start-Sleep -Seconds 7
$hw = (Get-Process chudder | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
for ($i = 0; $i -lt 8; $i++) {
  [TvWindow]::MoveWindow($hw, 0, 0, $W, $H, $true) | Out-Null
  Start-Sleep -Milliseconds 900
  $r = New-Object TvWindow+RECT
  [TvWindow]::GetWindowRect($hw, [ref]$r) | Out-Null
  if (($r.R - $r.L) -eq $W -and ($r.B - $r.T) -eq $H) { break }
}
[TvWindow]::SetForegroundWindow($hw) | Out-Null
"window $($r.R - $r.L)x$($r.B - $r.T) at $($r.L),$($r.T)"
