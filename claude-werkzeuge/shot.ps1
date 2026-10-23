param([string]$exe, [string[]]$a, [int[]]$at = @(10, 20), [string]$out)
# starts an emulator, screenshots its window at the given seconds, then kills it
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W { [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Ri, B; } }
"@
[void][W]::SetProcessDPIAware()
$p = Start-Process -FilePath $exe -ArgumentList ($a | % { '"' + $_ + '"' }) -WorkingDirectory (Split-Path $exe) -PassThru
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($s in $at) {
  while ($sw.Elapsed.TotalSeconds -lt $s) { Start-Sleep -Milliseconds 100; if ($p.HasExited) { break } }
  if ($p.HasExited) { "beendet nach {0:N1} s" -f $sw.Elapsed.TotalSeconds; break }
  $p.Refresh(); $h = $p.MainWindowHandle; $r = New-Object W+R
  if ($h -eq [IntPtr]::Zero -or -not [W]::GetWindowRect($h, [ref]$r)) { "kein Fenster bei $s s"; continue }
  [void][W]::SetForegroundWindow($h); Start-Sleep -Milliseconds 200
  $w = $r.Ri - $r.L; $hh = $r.B - $r.T
  $bm = New-Object Drawing.Bitmap $w, $hh; $g = [Drawing.Graphics]::FromImage($bm); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bm.Size); $bm.Save("$out`_$s.png"); $g.Dispose(); $bm.Dispose()
  "Bild bei $s s: $out`_$s.png"
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }

