param([string]$file, [string]$name)
$t = Get-Content $file
$ft = $t | ? { $_ -match '^FT (\d+) (\d+)' } | % { $a = $_ -split ' '; [pscustomobject]@{ f = [int]$a[1]; c = [int]$a[2] } }
$sim = $t | ? { $_ -match '^SIM frames' } | select -First 1
$ps = [int]($sim -replace '.*playStart (\d+).*', '$1')
$wins = @(@('Break..Warten', ($ps + 1536), ($ps + 1632)), @('Warten..Umschalten', ($ps + 1632), ($ps + 1656)), @('mager: bis 1. Treffer', ($ps + 1656), ($ps + 1919)), @('mager: Treffer', ($ps + 1919), ($ps + 1992)), @('danach (200 Frames)', ($ps + 1992), ($ps + 2192)))
foreach ($w in $wins) {
  $s = $ft | ? { $_.f -ge $w[1] -and $_.f -lt $w[2] }
  if ($s) { '{0} | {1} | {2}-{3} | max {4} | avg {5:0}' -f $name, $w[0], $w[1], $w[2], ($s | measure c -Maximum).Maximum, ($s | measure c -Average).Average }
}
