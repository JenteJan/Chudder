# capture.ps1 -Build <dir under builds> -Out <png> [-Env "NAME=value"] [-Wait 4]
# Launches a build at a fixed window size, grabs the window, closes it.
param([string]$Build, [string]$Out, [string]$F16 = '', [string]$Env = '', [string]$Log = '', [int]$Wait = 4, [int]$Width = 1600, [int]$Height = 900)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class C {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@ -ErrorAction SilentlyContinue
[C]::SetProcessDPIAware() | Out-Null
$exe = Join-Path $PSScriptRoot "builds\$Build\chudder.exe"
$setVars = @(); if ($Env) { foreach ($pair in $Env.Split(';')) { $k, $v = $pair.Split('=', 2); Set-Item "env:$k" $v; $setVars += $k } }
if ($Log) { $p = Start-Process $exe -PassThru -RedirectStandardOutput $Log -RedirectStandardError "$Log.err" } else { $p = Start-Process $exe -PassThru }
for ($i = 0; $i -lt 50 -and $p.MainWindowHandle -eq 0; $i++) { Start-Sleep -Milliseconds 200; $p.Refresh() }
$h = $p.MainWindowHandle
[C]::MoveWindow($h, 100, 100, $Width, $Height, $true) | Out-Null
[C]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Seconds $Wait
[C]::MoveWindow($h, 100, 100, $Width, $Height, $true) | Out-Null
Start-Sleep -Milliseconds 1500
$r = New-Object C+RECT
[C]::DwmGetWindowAttribute($h, 9, [ref]$r, 16) | Out-Null
$w = ($r.R - $r.L) - (($r.R - $r.L) % 2); $hh = ($r.B - $r.T) - (($r.B - $r.T) % 2)
& ffmpeg -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -offset_x $r.L -offset_y $r.T -video_size "${w}x${hh}" -i desktop -frames:v 1 $Out
if ($F16) { & (Join-Path $PSScriptRoot 'hdrcap\hdrcap.exe') ([int64]$h) $F16 }
Stop-Process -Id $p.Id -ErrorAction SilentlyContinue
foreach ($k in $setVars) { Remove-Item "env:$k" }
"captured $Out ${w}x${hh}"
