param(
  [string]$Process = "chudder",
  [int]$ProcessId = 0,
  [string]$TitleMatch = "",
  [string]$Keys = "",
  [string]$Shot = "",
  [int]$Delay = 350,
  [int]$X = -1, [int]$Y = -1, [int]$W = 0, [int]$H = 0
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,IntPtr pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a,uint b,bool c);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public KEYBDINPUT ki; [FieldOffset(0)] public long pad1; [FieldOffset(8)] public long pad2; [FieldOffset(16)] public long pad3; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
  [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
  public static void TypeText(string text) {
    foreach (char c in text) {
      INPUT[] inputs = new INPUT[2];
      inputs[0].type = 1; inputs[0].u.ki.wScan = c; inputs[0].u.ki.dwFlags = 0x0004;
      inputs[1].type = 1; inputs[1].u.ki.wScan = c; inputs[1].u.ki.dwFlags = 0x0004 | 0x0002;
      SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
      System.Threading.Thread.Sleep(15);
    }
  }
}
"@
[Win32]::SetProcessDPIAware() | Out-Null
$proc = $(if ($ProcessId -gt 0) { Get-Process -Id $ProcessId -ErrorAction SilentlyContinue } else { Get-Process $Process -ErrorAction SilentlyContinue }) | Where-Object { $_.MainWindowHandle -ne 0 -and ($TitleMatch -eq "" -or $_.MainWindowTitle -like $TitleMatch) } | Select-Object -First 1
if (-not $proc) { Write-Output "NO_WINDOW $Process"; exit 1 }
$h = $proc.MainWindowHandle
[Win32]::ShowWindow($h, 9) | Out-Null
if ($W -gt 0) { [Win32]::ShowWindow($h, 1) | Out-Null; [Win32]::SetWindowPos($h, [IntPtr]::Zero, $X, $Y, $W, $H, 0x0404) | Out-Null; Start-Sleep -Milliseconds 300 }
$fg=[Win32]::GetForegroundWindow();$t1=[Win32]::GetWindowThreadProcessId($fg,[IntPtr]::Zero);$t2=[Win32]::GetCurrentThreadId()
[Win32]::AttachThreadInput($t1,$t2,$true)|Out-Null;[Win32]::BringWindowToTop($h)|Out-Null;[Win32]::SetForegroundWindow($h)|Out-Null;[Win32]::AttachThreadInput($t1,$t2,$false)|Out-Null
Start-Sleep -Milliseconds 300
if ([Win32]::GetForegroundWindow() -ne $h) { Write-Output "NOT_FOREGROUND $Process"; exit 2 }
if ($Keys -ne "") {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  foreach ($k in $Keys.Split(' ')) {
    if ($k -eq "") { continue }
    Write-Output ("T {0,7:F2} {1} {2}" -f ($sw.Elapsed.TotalSeconds), $k, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    if ($k -eq "space") { [System.Windows.Forms.SendKeys]::SendWait(" "); Start-Sleep -Milliseconds $Delay; continue }
    if ($k -like "wait*") { Start-Sleep -Milliseconds ([int]$k.Substring(4)); continue }
    if ($k -like "click:*") {
      $xy = $k.Substring(6).Split(',')
      [Win32]::SetCursorPos([int]$xy[0], [int]$xy[1]) | Out-Null
      Start-Sleep -Milliseconds 60
      [Win32]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40; [Win32]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
      Start-Sleep -Milliseconds $Delay
      continue
    }
    if ($k -like "wheel:*") {
      $p = $k.Substring(6).Split(',')
      [Win32]::SetCursorPos([int]$p[0], [int]$p[1]) | Out-Null
      Start-Sleep -Milliseconds 60
      $steps = [int]$p[2]
      $dir = if ($steps -lt 0) { [uint32]4294967176 } else { [uint32]120 }
      for ($i = 0; $i -lt [Math]::Abs($steps); $i++) { [Win32]::mouse_event(0x0800, 0, 0, $dir, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80 }
      Start-Sleep -Milliseconds $Delay
      continue
    }
    if ($k -like "type:*") {
      [Win32]::TypeText($k.Substring(5))
      Start-Sleep -Milliseconds $Delay
      continue
    }
    if ($k -like "paste:*") {
      Set-Clipboard -Value $k.Substring(6)
      Start-Sleep -Milliseconds 100
      [System.Windows.Forms.SendKeys]::SendWait("^v")
      Start-Sleep -Milliseconds $Delay
      continue
    }
    if ($k -like "move:*") {
      $xy = $k.Substring(5).Split(',')
      [Win32]::SetCursorPos([int]$xy[0], [int]$xy[1]) | Out-Null
      Start-Sleep -Milliseconds $Delay
      continue
    }
    [System.Windows.Forms.SendKeys]::SendWait($k)
    Start-Sleep -Milliseconds $Delay
  }
}
if ($Shot -ne "") {
  Start-Sleep -Milliseconds 400
  $r = New-Object Win32+RECT
  [Win32]::GetWindowRect($h, [ref]$r) | Out-Null
  $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
  $bmp = New-Object System.Drawing.Bitmap $w, $hh
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
  $bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Output "SHOT $w x $hh at $($r.Left),$($r.Top) -> $Shot"
}
$r2 = New-Object Win32+RECT
[Win32]::GetWindowRect($h, [ref]$r2) | Out-Null
Write-Output "OK title='$($proc.MainWindowTitle)' rect=$($r2.Left),$($r2.Top),$($r2.Right - $r2.Left)x$($r2.Bottom - $r2.Top)"
