$ErrorActionPreference='Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MHHud035 {
 [StructLayout(LayoutKind.Sequential)] public struct POINT {public int X,Y;public POINT(int x,int y){X=x;Y=y;}}
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int L,T,R,B;}
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a,uint b,bool x);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h,uint f);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
}
'@
$target=Get-Content outputs/assembly-035/input-target.json -Raw|ConvertFrom-Json
$main=(Get-Process -Id $target.pid).MainWindowHandle
$original=[MHHud035]::GetForegroundWindow();$oldPid=[uint32]0
$thread=[MHHud035]::GetWindowThreadProcessId($original,[ref]$oldPid);$caller=[MHHud035]::GetCurrentThreadId()
$cursor=New-Object MHHud035+POINT;$null=[MHHud035]::GetCursorPos([ref]$cursor)
try {
 $null=[MHHud035]::AttachThreadInput($caller,$thread,$true)
 $null=[MHHud035]::SetForegroundWindow($main)
 $null=[MHHud035]::AttachThreadInput($caller,$thread,$false)
 Start-Sleep -Milliseconds 200
 $activePid=[uint32]0;$null=[MHHud035]::GetWindowThreadProcessId([MHHud035]::GetForegroundWindow(),[ref]$activePid)
 if($activePid -ne $target.pid){throw 'Refuse click: SketchUp not foreground'}
 $point=[MHHud035+POINT]::new([int]$target.point[0],[int]$target.point[1])
 if([MHHud035]::GetAncestor([MHHud035]::WindowFromPoint($point),2) -ne $main){throw 'Refuse click: tree covered by another window'}
 $null=[MHHud035]::SetCursorPos($point.X,$point.Y)
 [MHHud035]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 [MHHud035]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 250
 [MHHud035]::mouse_event(2048,0,0,[uint32]4294967176,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 450
 Add-Type -AssemblyName System.Drawing
 $rect=New-Object MHHud035+RECT;$null=[MHHud035]::GetWindowRect($main,[ref]$rect)
 $bitmap=[Drawing.Bitmap]::new($rect.R-$rect.L,$rect.B-$rect.T)
 $graphics=[Drawing.Graphics]::FromImage($bitmap)
 try {$graphics.CopyFromScreen($rect.L,$rect.T,0,0,$bitmap.Size);$bitmap.Save((Join-Path $PWD 'outputs/assembly-035/native-hud.png'))} finally {$graphics.Dispose();$bitmap.Dispose()}
 'Physical viewport tree click sent to the pinned SketchUp process.'
} finally {
 $null=[MHHud035]::SetCursorPos($cursor.X,$cursor.Y)
 $null=[MHHud035]::SetForegroundWindow($original)
}
