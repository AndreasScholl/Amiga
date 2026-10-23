param([string]$exe, [string[]]$a, [int]$timeout = 90, [string]$out = "")
# wall time from emulator start: window up, AmigaDOS blue screen seen, then the demo's dark screen
Add-Type -AssemblyName System.Drawing
if (-not ("W2" -as [type])) { Add-Type @"
using System; using System.Runtime.InteropServices;
public class W2 { [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out R r); [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref P p); [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Ri, B; } [StructLayout(LayoutKind.Sequential)] public struct P { public int X, Y; } }
"@ }
[void][W2]::SetProcessDPIAware()
$p = Start-Process -FilePath $exe -ArgumentList ($a | % { '"' + $_ + '"' }) -WorkingDirectory (Split-Path $exe) -PassThru
$sw = [Diagnostics.Stopwatch]::StartNew()
$tWin = $null; $tBlue = $null; $tDemo = $null
while ($sw.Elapsed.TotalSeconds -lt $timeout -and -not $p.HasExited) {
  Start-Sleep -Milliseconds 150
  $p.Refresh(); $h = $p.MainWindowHandle; if ($h -eq [IntPtr]::Zero) { continue }
  $r = New-Object W2+R; [void][W2]::GetClientRect($h, [ref]$r); $pt = New-Object W2+P; [void][W2]::ClientToScreen($h, [ref]$pt)
  $w = $r.Ri; $hh = $r.B; if ($w -lt 100 -or $hh -lt 100) { continue }
  if (-not $tWin) { $tWin = $sw.Elapsed.TotalSeconds }
  $bm = New-Object Drawing.Bitmap $w, $hh; $g = [Drawing.Graphics]::FromImage($bm); $g.CopyFromScreen($pt.X, $pt.Y, 0, 0, $bm.Size); $g.Dispose()
  $blue = 0; $dark = 0; $n = 0
  for ($y = [int]($hh*0.15); $y -lt $hh*0.85; $y += 8) { for ($x = [int]($w*0.1); $x -lt $w*0.9; $x += 8) { $c = $bm.GetPixel($x, $y); $n++; if ($c.B -gt 120 -and $c.R -lt 60) { $blue++ } elseif ($c.R + $c.G + $c.B -lt 90) { $dark++ } } }
  if (-not $tBlue -and $blue -gt $n * 0.5) { $tBlue = $sw.Elapsed.TotalSeconds }
  if ($tBlue -and $dark -gt $n * 0.8) { $tDemo = $sw.Elapsed.TotalSeconds; if ($out) { Start-Sleep -Milliseconds 1500; $g = [Drawing.Graphics]::FromImage($bm); $g.CopyFromScreen($pt.X, $pt.Y, 0, 0, $bm.Size); $g.Dispose(); $bm.Save($out) }; $bm.Dispose(); break }
  $bm.Dispose()
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
"Fenster {0:N1} s, AmigaDOS {1:N1} s, Demo dunkel {2:N1} s" -f $tWin, $tBlue, $tDemo
