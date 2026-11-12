# Runs the HDR spike once: launch with a config, place the window, wait, grab
# the window, optionally drag it around while recording, then quit.
param(
  [string]$Placement = 'insideView',
  [string]$PropsJson = '{"vo":"gpu-next","gpu-api":"d3d11","target-colorspace-hint":"yes","hwdec":"auto-safe"}',
  [string]$File = "$PSScriptRoot\hdr10_test.mkv",
  [string]$Out = "$PSScriptRoot\out\run",
  [int]$Wait = 6,
  [switch]$Drag,
  [switch]$Opaque,
  [switch]$Fullscreen,
  [switch]$Keep,
  [switch]$SeeThrough
)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
[W]::SetProcessDPIAware() | Out-Null
New-Item -ItemType Directory -Force $Out | Out-Null
$exe = Join-Path $PSScriptRoot '..\..\build\windows\x64\runner\Release\chudder.exe'
$status = Join-Path $Out 'status.json'
Remove-Item $status -ErrorAction SilentlyContinue
$cfg = @{ seeThrough = [bool]$SeeThrough; file = $File; placement = $Placement; props = ($PropsJson | ConvertFrom-Json); status = $status }
$cfgPath = Join-Path $Out 'config.json'
$cfg | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $cfgPath
$env:CHUDDER_SPIKE_CONFIG = $cfgPath
$p = Start-Process $exe -PassThru
for ($i = 0; $i -lt 50 -and $p.MainWindowHandle -eq 0; $i++) { Start-Sleep -Milliseconds 200; $p.Refresh() }
$h = $p.MainWindowHandle
if ($Fullscreen) {
  $screen = [System.Windows.Forms.Screen]::PrimaryScreen 2>$null
  [W]::MoveWindow($h, 0, 0, 3840, 2160, $true) | Out-Null
} else {
  [W]::MoveWindow($h, 200, 150, 1600, 900, $true) | Out-Null
}
[W]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Seconds $Wait

function Grab($name) {
  $r = New-Object W+RECT
  [W]::DwmGetWindowAttribute($h, 9, [ref]$r, 16) | Out-Null
  $w = ($r.R - $r.L) - (($r.R - $r.L) % 2); $hh = ($r.B - $r.T) - (($r.B - $r.T) % 2)
  & ffmpeg -hide_banner -loglevel error -y -f gdigrab -draw_mouse 0 -offset_x $r.L -offset_y $r.T -video_size "${w}x${hh}" -i desktop -frames:v 1 (Join-Path $Out "$name.png")
}
Grab 'shot'

if ($Opaque) {
  [W]::SetForegroundWindow($h) | Out-Null
  [W]::keybd_event(0x4F, 0, 0, [UIntPtr]::Zero); [W]::keybd_event(0x4F, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 800
  Grab 'opaque'
  [W]::keybd_event(0x4F, 0, 0, [UIntPtr]::Zero); [W]::keybd_event(0x4F, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 800
  Grab 'back'
}

if ($Drag) {
  # Record the desktop around the window while it is moved in steps.
  $rec = Start-Process ffmpeg -ArgumentList "-hide_banner -loglevel error -y -f gdigrab -framerate 30 -draw_mouse 0 -offset_x 0 -offset_y 0 -video_size 2400x1400 -i desktop -t 6 `"$(Join-Path $Out 'drag.mp4')`"" -PassThru -WindowStyle Hidden
  Start-Sleep -Milliseconds 700
  for ($i = 0; $i -lt 120; $i++) {
    $x = 200 + [int](300 * [Math]::Sin($i / 10.0)); $y = 150 + [int](150 * [Math]::Cos($i / 13.0))
    [W]::MoveWindow($h, $x, $y, 1600, 900, $true) | Out-Null
    Start-Sleep -Milliseconds 16
  }
  for ($i = 0; $i -lt 60; $i++) {
    [W]::MoveWindow($h, 200, 150, 1200 + 8 * $i, 700 + 4 * $i, $true) | Out-Null
    Start-Sleep -Milliseconds 16
  }
  $rec.WaitForExit()
}

Start-Sleep -Seconds 1
Get-Content $status -ErrorAction SilentlyContinue
if (-not $Keep) { Stop-Process -Id $p.Id -ErrorAction SilentlyContinue }
