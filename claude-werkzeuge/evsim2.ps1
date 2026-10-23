param([switch]$trace, [double]$Z0 = 210, [double]$X0 = 55, [double]$Y0 = 45, [double]$A = 36, [double]$B = 3, [double]$D = 24, [double]$dip = -8, [double]$G = 40, [double]$w = 3, [double]$k = 0.25, [double]$phi = 30)
# world-frame loop, plane tilted phi to the left; S loses k*sin(theta) a frame
function Run([double]$Z0, [double]$A, [double]$B, [double]$D, [double]$dip, [double]$G, [double]$wm, [double]$k, [double]$phi, [bool]$tr) {
  $vc = 13.75; $Z = $Z0; $Y = $Y0; $X = $X0; $S0 = $vc - 3; $S = $S0; $th = 0.0; $gm = 0.0; $ex = $null; $minD = 1e9
  $sp = [math]::Sin($phi * [math]::PI / 180); $cp = [math]::Cos($phi * [math]::PI / 180)
  for ($t = 0; $t -lt 500; $t++) {
    if ($t -lt $A) { $q = ($t + 1) / $A; $q = $q * $q * (3 - 2 * $q); $S = $S0 + ($vc + $B - $S0) * $q }
    elseif ($t -lt $A + $D) { $q = ($t - $A + 1) / $D; $q = $q * $q * (3 - 2 * $q); $th = $dip * $q }
    else { $q = [math]::Min(1, ($t - $A - $D + 1) / $G); $q = $q * $q * (3 - 2 * $q); $th += $wm * $q; $S -= $k * [math]::Sin($th * [math]::PI / 180) }
    $gm += ($th - $gm) / 4
    $r = $gm * [math]::PI / 180; $up = $S * [math]::Sin($r)
    $Y -= $up * $cp; $X -= $up * $sp; $Z += $S * [math]::Cos($r) - $vc
    if ($Z -gt 1) { $sy = 134 + 288 * ($Y + 10) / $Z; $sx = 177 + 288 * $X / $Z; if (-not $ex -and ($sy -lt 0 -or $sx -lt 0)) { $ex = "exit t$t th$([int]$th) Z$([int]$Z) size$([int](72*288/$Z)) sx$([int]$sx) sy$([int]$sy)" } }
    if ($tr -and ($t % 4 -eq 0)) { $zz = [math]::Max(1, $Z); "t$t th$([int]$th) S$([math]::Round($S,1)) X$([int]$X) Y$([int]$Y) Z$([int]$Z) sx$([int](177+288*$X/$zz)) sy$([int](134+288*$Y/$zz)) size$([int](72*288/$zz))" }
    if ($Z -lt 0) { return "$ex | CROSS t$t X$([int]$X) Y$([int]$Y) dist$([int][math]::Sqrt($X*$X+$Y*$Y)) th$([int]$th) S$([math]::Round($S,1))" }
  }
  "no cross Z$([int]$Z) th$([int]$th)"
}
if ($trace) { Run $Z0 $A $B $D $dip $G $w $k $phi $true; return }
$o = foreach ($z in 110, 140, 170) { foreach ($aa in 24, 36) { foreach ($dd in 16, 24) { foreach ($kk in 0.2, 0.35) { foreach ($wm in 2, 2.5, 3) { foreach ($bb in 1.5, 2.5) { "z$z A$aa D$dd k$kk w$wm B$bb : " + (Run $z $aa $bb $dd $dip $G $wm $kk $phi $false) } } } } } }; $o | Sort-Object { [int](($_ -split "dist")[1] -split " ")[0] } | Select-Object -First 20

