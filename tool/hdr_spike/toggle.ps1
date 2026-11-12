# toggle.ps1 -Build <dir under builds> -OutDir <dir> [-Env "A=1;B=2"]
# One run of the video probe: float captures in SDR, after switching HDR on
# (key h), and after switching it off again.
param([string]$Build, [string]$OutDir, [string]$Env = '', [int]$Wait = 7)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class T {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
}
"@ -ErrorAction SilentlyContinue
[T]::SetProcessDPIAware() | Out-Null
New-Item -ItemType Directory -Force $OutDir | Out-Null
$log = Join-Path $OutDir 'run.log'
$setVars = @(); if ($Env) { foreach ($pair in $Env.Split(';')) { $k, $v = $pair.Split('=', 2); Set-Item "env:$k" $v; $setVars += $k } }
$exe = Join-Path $PSScriptRoot "builds\$Build\chudder.exe"
$p = Start-Process $exe -PassThru -RedirectStandardOutput $log -RedirectStandardError (Join-Path $OutDir 'run.err')
try {
  for ($i = 0; $i -lt 50 -and $p.MainWindowHandle -eq 0; $i++) { Start-Sleep -Milliseconds 200; $p.Refresh() }
  $h = $p.MainWindowHandle
  [T]::MoveWindow($h, 100, 100, 1600, 900, $true) | Out-Null
  Start-Sleep -Seconds $Wait
  [T]::MoveWindow($h, 100, 100, 1600, 900, $true) | Out-Null
  Start-Sleep -Milliseconds 1200
  $cap = Join-Path $PSScriptRoot 'hdrcap\hdrcap.exe'

  # Press h until the probe logs the switch (a press can land before the
  # window has the focus), then let a few frames through.
  function Press-H([string]$expect) {
    for ($try = 0; $try -lt 10; $try++) {
      [T]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 300
      [T]::keybd_event(0x48, 0, 0, [UIntPtr]::Zero); [T]::keybd_event(0x48, 0, 2, [UIntPtr]::Zero)
      for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 200
        if (Select-String -Path $log -Pattern $expect -Quiet) { Start-Sleep -Seconds 2; return }
      }
    }
    throw "probe never logged '$expect'"
  }

  & $cap ([int64]$h) (Join-Path $OutDir 'a_start.f16')
  Press-H 'probe: HDR on'
  & $cap ([int64]$h) (Join-Path $OutDir 'b_hdr.f16')
  Press-H 'probe: HDR off'
  & $cap ([int64]$h) (Join-Path $OutDir 'c_back.f16')
} finally {
  Stop-Process -Id $p.Id -ErrorAction SilentlyContinue
  foreach ($k in $setVars) { Remove-Item "env:$k" }
}
Start-Sleep -Milliseconds 500
Get-Content $log, (Join-Path $OutDir 'run.err') | Select-String "probe:|HDR|View switched|rror"
