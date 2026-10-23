param([string]$dir, [int]$from = 30, [int]$to = 500)
# the stars' depth histograms of a 6-seed run (S3H lines): per seed, frames
# switch+from .. switch+to - empty bins in the visible bands (500 .. the far
# band's bound: nearer than that the field thins by itself, stars leave the
# screen sideways), the spread there (fullest / emptiest bin), the near bin
# (250..500) empty, colour changes per frame
foreach ($f in Get-ChildItem "$dir\*.txt" | sort Name) {
  $h = Get-Content $f | ? { $_ -match '^S3H ' }
  if (-not $h) { continue }
  $sw = [int]($h[0].Split(' ')[1])
  $emptyF = 0; $nearE = 0; $n = 0; $ratioMax = 0; $ratioAt = 0; $chgMax = 0; $chgOver6 = 0; $firstEmpty = -1; $lastEmpty = -1
  foreach ($l in $h) {
    $a = $l.Split(' '); $fr = [int]$a[1]
    if ($fr -lt $sw + $from -or $fr -gt $sw + $to) { continue }
    $n++
    $bi = [array]::IndexOf($a, "bins"); $bins = $a[($bi + 1)..($bi + 18)] | % { [int]$_ }
    $b5 = [int](($l -split '\| b ')[1].Split(',')[5].Split(' ')[0])
    $top = [Math]::Min(13, [int][Math]::Floor($b5 / 250) - 1)
    $vis = $bins[2..$top]
    if (($vis | ? { $_ -eq 0 }).Count -gt 0) { $emptyF++; if ($firstEmpty -lt 0) { $firstEmpty = $fr - $sw }; $lastEmpty = $fr - $sw }
    if ($bins[1] -eq 0) { $nearE++ }
    $mid = $bins[5..$top]; $mn = ($mid | measure -Minimum).Minimum; $mx = ($mid | measure -Maximum).Maximum
    $r = if ($mn -gt 0) { $mx / $mn } else { 99 }
    if ($r -gt $ratioMax) { $ratioMax = $r; $ratioAt = $fr - $sw }
    $ci = [array]::IndexOf($a, "chg"); $c = [int]$a[$ci + 1]
    if ($c -gt $chgMax) { $chgMax = $c }; if ($c -gt 6) { $chgOver6++ }
  }
  "{0,-9} switch {1}: frames {2} | visible bands (500..far bound): frames with an empty bin {3} (first +{4}, last +{5}) | spread 1250..far bound max {6:0.0}x (+{7}) | near bin 250..500 empty in {8} frames | colour changes/frame max {9}, frames > 6: {10}" -f $f.BaseName, $sw, $n, $emptyF, $firstEmpty, $lastEmpty, $ratioMax, $ratioAt, $nearE, $chgMax, $chgOver6
}
