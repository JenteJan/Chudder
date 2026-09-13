param([int]$Show=0)
Add-Type @"
using System;using System.Runtime.InteropServices;
public class HB{
 [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c,string w);
 [DllImport("user32.dll")] public static extern int ShowWindow(IntPtr h,int n);
}
"@
$tb=[HB]::FindWindow("Shell_TrayWnd",$null); [HB]::ShowWindow($tb,$Show)|Out-Null
"tb show=$Show"
