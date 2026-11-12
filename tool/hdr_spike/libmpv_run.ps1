# libmpv_run.ps1 -Build <dir under builds> -OutDir <dir> -Files "a;b;c"
# Runs libmpv_probe over the files (key n advances) and float-captures each
# once media_kit has logged the HDR switch the file should cause.
param([string]$Build, [string]$OutDir, [string]$Files, [int]$Wait = 8)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class L {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
}
"@ -ErrorAction SilentlyContinue
[L]::SetProcessDPIAware() | Out-Null
New-Item -ItemType Directory -Force $OutDir | Out-Null
$log = Join-Path $OutDir 'run.log'
$env:CHUDDER_PROBE_FILES = $Files
$exe = Join-Path $PSScriptRoot "builds\$Build\chudder.exe"
$p = Start-Process $exe -PassThru -RedirectStandardOutput $log -RedirectStandardError (Join-Path $OutDir 'run.err')
$cap = Join-Path $PSScriptRoot 'hdrcap\hdrcap.exe'
function Count($pattern) { @(Select-String -Path $log -Pattern $pattern).Count }
try {
  for ($i = 0; $i -lt 50 -and $p.MainWindowHandle -eq 0; $i++) { Start-Sleep -Milliseconds 200; $p.Refresh() }
  $h = $p.MainWindowHandle
  [L]::MoveWindow($h, 100, 100, 1600, 900, $true) | Out-Null
  Start-Sleep -Seconds $Wait
  [L]::MoveWindow($h, 100, 100, 1600, 900, $true) | Out-Null
  Start-Sleep -Seconds 2
  $list = $Files.Split(';')
  for ($n = 0; $n -lt $list.Count; $n++) {
    if ($n -gt 0) {
      $before = Count 'probe: playing'
      for ($try = 0; $try -lt 10 -and (Count 'probe: playing') -eq $before; $try++) {
        [L]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 300
        [L]::keybd_event(0x4E, 0, 0, [UIntPtr]::Zero); [L]::keybd_event(0x4E, 0, 2, [UIntPtr]::Zero)
        Start-Sleep -Seconds 1
      }
      # Let the file report its parameters and the switch settle.
      Start-Sleep -Seconds 4
    }
    & $cap ([int64]$h) (Join-Path $OutDir ("{0}.f16" -f $n))
  }
} finally {
  Stop-Process -Id $p.Id -ErrorAction SilentlyContinue
  Remove-Item env:CHUDDER_PROBE_FILES
}
Start-Sleep -Milliseconds 500
Get-Content $log, (Join-Path $OutDir 'run.err') | Select-String "probe:|HDR|View switched|rror"
