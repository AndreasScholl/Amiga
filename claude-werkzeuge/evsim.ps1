param([switch]$trace, [double]$Z0 = 160, [double]$A = 24, [double]$B = 3, [double]$D = 16, [double]$dip = -9, [double]$G = 16, [double]$w = 4)
# world-frame evade: S, theta; rel z += S cos - vc, y -= S sin
function Run([double]$Z0, [double]$A, [double]$B, [double]$D, [double]$dip, [double]$G, [double]$wm, [bool]$tr) {
  $vc = 13.75; $Z = $Z0; $Y = 7.0; $S0 = $vc - 3.6; $S = $S0; $th = 0.0; $ex = $null
  for ($t = 0; $t -lt 400; $t++) {
    if ($t -lt $A) { $q = ($t + 1) / $A; $q = $q * $q * (3 - 2 * $q); $S = $S0 + ($vc + $B - $S0) * $q }
    elseif ($t -lt $A + $D) { $q = ($t - $A + 1) / $D; $q = $q * $q * (3 - 2 * $q); $th = $dip * $q }
    else { $q = [math]::Min(1, ($t - $A - $D + 1) / $G); $q = $q * $q * (3 - 2 * $q); $th += $wm * $q; $S -= 0.05 * [math]::Sin($th * [math]::PI / 180) }
    $r = $th * [math]::PI / 180; $Y -= $S * [math]::Sin($r); $Z += $S * [math]::Cos($r) - $vc
    if ($Z -gt 1) { $sy = 134 + 288 * ($Y + 10) / $Z; if (-not $ex -and $sy -lt 0) { $ex = @($t, [int]$th, [int](72 * 288 / $Z), [int]$Z) } }
    if ($tr -and ($t % 4 -eq 0)) { "t$t th$([int]$th) S$([math]::Round($S,1)) Y$([int]$Y) Z$([int]$Z) sy$([int](134+288*$Y/[math]::Max(1,$Z))) size$([int](72*288/[math]::Max(1,$Z)))" }
    if ($Z -lt 0) { return [pscustomobject]@{ Z0 = $Z0; B = $B; D = $D; G = $G; w = $wm; crossY = [int]$Y; thX = $ex[1]; sizeX = $ex[2]; ZX = $ex[3]; tX = $ex[0]; tC = $t } }
  }
}
if ($trace) { Run $Z0 $A $B $D $dip $G $w $true; return }
$res = foreach ($z in 100, 130, 160, 200) { foreach ($b in 2, 3, 4) { foreach ($d in 12, 20) { foreach ($g in 10, 16) { foreach ($wm in 3, 4, 5, 6, 8) { Run $z 24 $b $d -9 $g $wm $false } } } } }
$res | Sort-Object crossY -Descending | Select-Object -First 15 | Format-Table -AutoSize

