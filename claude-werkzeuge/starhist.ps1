param([string]$dir, [string]$frames)
Add-Type -AssemblyName System.Drawing
$names = @(@('dunkel',0x114),@('blau',0x125),@('braun',0x631),@('gruen',0x371),@('orange',0x842),@('hell',0xc84),@('weiss',0xfdb))
$map = @{}
for ($i = 0; $i -lt $names.Count; $i++) {
  $c = $names[$i][1]
  $k = ((($c -shr 8) -band 15) * 17) * 65536 + ((($c -shr 4) -band 15) * 17) * 256 + ($c -band 15) * 17
  $map[$k] = $i
}
"frame  " + (($names | % { '{0,6}' -f $_[0] }) -join ' ')
foreach ($f in $frames -split ',') {
  $bm = New-Object System.Drawing.Bitmap "$dir\cop$f.png"
  $cnt = New-Object int[] 7
  $rect = New-Object System.Drawing.Rectangle 0, 0, $bm.Width, $bm.Height
  $bd = $bm.LockBits($rect, 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
  $n = $bd.Stride * $bm.Height; $buf = New-Object byte[] $n
  [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $buf, 0, $n)
  $bm.UnlockBits($bd)
  for ($y = [int]($bm.Height / 3); $y -lt $bm.Height; $y++) {
    $o = $y * $bd.Stride
    for ($x = 0; $x -lt $bm.Width; $x++) {
      $p = $o + $x * 4
      if ($buf[$p] -bor $buf[$p+1] -bor $buf[$p+2]) {
        $k = [int]$buf[$p+2] * 65536 + [int]$buf[$p+1] * 256 + $buf[$p]
        if ($map.ContainsKey($k)) { $cnt[$map[$k]]++ }
      }
    }
  }
  $bm.Dispose()
  ('{0,5}  ' -f $f) + (($cnt | % { '{0,6}' -f $_ }) -join ' ')
}
