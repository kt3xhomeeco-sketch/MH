$ErrorActionPreference='Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MHDrag021 {
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; public POINT(int x,int y){X=x;Y=y;} }
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int L,T,R,B;}
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p,EnumProc c,IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc c,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,System.Text.StringBuilder b,int n);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h,ref POINT p);
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h,uint f);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a,uint b,bool x);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
}
'@
$qaTarget=Get-Content outputs/drag-target-021.json -Raw | ConvertFrom-Json
$qaMain=(Get-Process -Id 26424).MainWindowHandle
$script:qaSource=[IntPtr]::Zero;$script:qaView=[IntPtr]::Zero
$qaEnum=[MHDrag021+EnumProc]{param($h,$l) $p=[uint32]0;$null=[MHDrag021]::GetWindowThreadProcessId($h,[ref]$p);$b=New-Object System.Text.StringBuilder 256;$null=[MHDrag021]::GetWindowText($h,$b,256);if($p -eq 26424 -and $b.ToString() -eq 'QA HUD Drag 021' -and [MHDrag021]::IsWindowVisible($h)){$script:qaSource=$h};return $true}
$null=[MHDrag021]::EnumWindows($qaEnum,[IntPtr]::Zero)
$qaChild=[MHDrag021+EnumProc]{param($h,$l) $r=New-Object MHDrag021+RECT;$null=[MHDrag021]::GetClientRect($h,[ref]$r);if([Math]::Abs($r.R-$qaTarget.view_width*$qaTarget.scale) -le 2 -and [Math]::Abs($r.B-$qaTarget.view_height*$qaTarget.scale) -le 2){$script:qaView=$h};return $true}
$null=[MHDrag021]::EnumChildWindows($qaMain,$qaChild,[IntPtr]::Zero)
if($qaSource -eq [IntPtr]::Zero -or $qaView -eq [IntPtr]::Zero){throw 'Source or model viewport missing'}
$qaOrigin=New-Object MHDrag021+POINT;$null=[MHDrag021]::ClientToScreen($qaView,[ref]$qaOrigin)
$qaRect=New-Object MHDrag021+RECT;$null=[MHDrag021]::GetClientRect($qaSource,[ref]$qaRect)
$qaStart=[MHDrag021+POINT]::new([int]($qaRect.R/2),65);$null=[MHDrag021]::ClientToScreen($qaSource,[ref]$qaStart)
$qaEnd=[MHDrag021+POINT]::new([int]($qaOrigin.X+$qaTarget.target[0]*$qaTarget.scale),[int]($qaOrigin.Y+$qaTarget.target[1]*$qaTarget.scale))
$qaSaved=New-Object MHDrag021+POINT;$null=[MHDrag021]::GetCursorPos([ref]$qaSaved);$qaForeground=[MHDrag021]::GetForegroundWindow();$qaOldPid=[uint32]0;$qaThread=[MHDrag021]::GetWindowThreadProcessId($qaForeground,[ref]$qaOldPid);$qaCaller=[MHDrag021]::GetCurrentThreadId();$qaHeld=$false
try {
 $null=[MHDrag021]::AttachThreadInput($qaCaller,$qaThread,$true)
 $null=[MHDrag021]::SetForegroundWindow($qaMain)
 $null=[MHDrag021]::SetForegroundWindow($qaSource)
 $null=[MHDrag021]::AttachThreadInput($qaCaller,$qaThread,$false)
 $qaCurrentPid=[uint32]0;$null=[MHDrag021]::GetWindowThreadProcessId([MHDrag021]::GetForegroundWindow(),[ref]$qaCurrentPid)
 if($qaCurrentPid -ne 26424){throw 'Mouse QA refused: target is not foreground'}
 $qaUnder=[MHDrag021]::GetAncestor([MHDrag021]::WindowFromPoint($qaEnd),2)
 if($qaUnder -ne $qaMain){throw 'Mouse QA refused: HUD point is covered by another window'}
 Start-Sleep -Milliseconds 140
 $qaSourceUnder=[MHDrag021]::GetAncestor([MHDrag021]::WindowFromPoint($qaStart),2)
 if($qaSourceUnder -ne $qaSource){throw "Mouse QA refused: source card is covered ($qaSourceUnder vs $qaSource)"}
 Add-Type -AssemblyName System.Drawing
 $qaBounds=New-Object MHDrag021+RECT;$null=[MHDrag021]::GetWindowRect($qaSource,[ref]$qaBounds)
 $qaBitmap=[System.Drawing.Bitmap]::new($qaBounds.R-$qaBounds.L,$qaBounds.B-$qaBounds.T)
 $qaGraphics=[System.Drawing.Graphics]::FromImage($qaBitmap)
 try {$qaGraphics.CopyFromScreen($qaBounds.L,$qaBounds.T,0,0,$qaBitmap.Size);$qaBitmap.Save((Join-Path (Get-Location).Path 'outputs/source-drag-021.png'))} finally {$qaGraphics.Dispose();$qaBitmap.Dispose()}
 $null=[MHDrag021]::SetCursorPos($qaStart.X,$qaStart.Y)
 [MHDrag021]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 [MHDrag021]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 100
 [MHDrag021]::mouse_event(2,0,0,0,[UIntPtr]::Zero);$qaHeld=$true
 Start-Sleep -Milliseconds 70
 for($i=1;$i -le 15;$i++){
  $qaCurrentPid=[uint32]0;$null=[MHDrag021]::GetWindowThreadProcessId([MHDrag021]::GetForegroundWindow(),[ref]$qaCurrentPid)
  if($qaCurrentPid -ne 26424){throw 'Mouse QA stopped because foreground changed'}
  $x=[int]($qaStart.X+($qaEnd.X-$qaStart.X)*$i/15);$y=[int]($qaStart.Y+($qaEnd.Y-$qaStart.Y)*$i/15)
  $null=[MHDrag021]::SetCursorPos($x,$y)
  Start-Sleep -Milliseconds 30
 }
 Start-Sleep -Milliseconds 120
 [MHDrag021]::mouse_event(4,0,0,0,[UIntPtr]::Zero);$qaHeld=$false
 Start-Sleep -Milliseconds 180
 Write-Output 'Physical HtmlDialog-to-native-HUD drag completed.'
} finally {
 if($qaHeld){[MHDrag021]::mouse_event(4,0,0,0,[UIntPtr]::Zero)}
 $null=[MHDrag021]::SetCursorPos($qaSaved.X,$qaSaved.Y)
 $null=[MHDrag021]::SetForegroundWindow($qaForeground)
}
