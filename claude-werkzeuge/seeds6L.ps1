param([int]$frames = 7400)
$sp = $PSScriptRoot
$seeds = @("", "00001234", "c0ffee11", "5bd1e995", "9e3779b9", "00c0ffee")
$ps = @()
foreach ($s in $seeds) {
  $n = if ($s) { $s } else { "default" }
  $cmd = "`$env:SEED='$s'; `$env:FRAMELOG='5270-9300'; pwsh -NoProfile -File '$sp\prof\seq.ps1' -frames $frames *> '$sp\seed_$n.txt'"
  $ps += Start-Process pwsh -ArgumentList "-NoProfile", "-Command", $cmd -PassThru -WindowStyle Hidden
}
$ps | Wait-Process
foreach ($s in $seeds) {
  $n = if ($s) { $s } else { "default" }
  $r = Get-Content "$sp\seed_$n.txt"
  $w = ($r | ? { $_ -match '^seq worst' }) -replace 'seq worst frame ', ''
  $wf = ($r | ? { $_ -match '^WARP frames' }) -replace '^WARP frames \d+: ', ''
  $sim = ($r | ? { $_ -match '^SIM ' }) -replace '.*(stalls \d+).*(frame max in play \d+ at \d+).*(wobble [^|]*).*', '$1 $2 $3'
  $ft = $r | ? { $_ -match '^FT ' } | sort { [int]($_.Split(' ')[2]) } -Descending | select -First 1
  $err = $r | ? { $_ -match '^ERROR' }
  "$n | $w | $wf | $sim | top elite: $(if ($ft) { $ft.Split(' ')[1..2] -join ' ' }) $err"
}

