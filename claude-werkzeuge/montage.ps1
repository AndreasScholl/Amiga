param([string]$dir, [string]$prefix, [int[]]$frames, [int]$cx, [int]$cy, [int]$cw, [int]$ch, [int]$scale, [int]$cols, [string]$out)
# a montage of harness pictures (raw dumps, 352 x 268) - a crop of each, scaled,
# its frame number above it
Add-Type -AssemblyName System.Drawing
$tw = $cw * $scale; $th = $ch * $scale; $pad = 4; $lab = 12
$rows = [Math]::Ceiling($frames.Count / $cols)
$W = $cols * ($tw + $pad) + $pad; $H = $rows * ($th + $pad + $lab) + $pad
$bm = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bm); $g.Clear([System.Drawing.Color]::FromArgb(64, 64, 64))
$font = New-Object System.Drawing.Font "Consolas", 8
for ($i = 0; $i -lt $frames.Count; $i++) {
  $f = $frames[$i]; $p = Join-Path $dir "$prefix$f.raw"
  if (-not (Test-Path $p)) { continue }
  $b = [IO.File]::ReadAllBytes($p)
  $ox = $pad + ($i % $cols) * ($tw + $pad); $oy = $pad + [Math]::Floor($i / $cols) * ($th + $pad + $lab)
  $g.DrawString("$f", $font, [System.Drawing.Brushes]::White, $ox, $oy)
  $oy += $lab
  $img = New-Object System.Drawing.Bitmap $cw, $ch
  for ($y = 0; $y -lt $ch; $y++) { for ($x = 0; $x -lt $cw; $x++) { $o = (($cy + $y) * 352 + $cx + $x) * 4; $img.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $b[$o + 2], $b[$o + 1], $b[$o])) } }
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
  $g.DrawImage($img, $ox, $oy, $tw, $th); $img.Dispose()
}
$bm.Save($out); $g.Dispose(); $bm.Dispose()
"saved $out"
