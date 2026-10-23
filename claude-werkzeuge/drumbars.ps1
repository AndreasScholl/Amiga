param([string]$f)
$ev = Get-Content $f | ? { $_ -match '^N ' } | % { $a = $_ -split ' '; [pscustomobject]@{ t = [int]$a[1]; c = [int]$a[2]; s = [int]$a[3]; p = [int]$a[5]; v = [int]$a[6] } }
$bars = @{}
foreach ($e in $ev) {
  if ($e.c -ne 3) { continue }
  $b = [int][math]::Floor($e.t / 96); $pos = [int][math]::Floor(($e.t % 96) / 2)
  if (-not $bars.ContainsKey($b)) { $bars[$b] = [char[]]('-' * 48) }
  $ch = switch ($e.s) { 6440 { 'K' } 3480 { 'S' } 15634 { if ($e.v -ge 50) { 'H' } elseif ($e.v -ge 20) { 'h' } else { '.' } } default { 'x' } }
  $bars[$b][$pos] = $ch
}
$out = @()
for ($b = 0; $b -lt 128; $b++) { $s = if ($bars.ContainsKey($b)) { -join $bars[$b] } else { '(none)' }; $out += ('{0,3} {1}' -f $b, $s) }
$out

