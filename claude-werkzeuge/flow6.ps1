param([string]$bin, [int]$frames = 9300, [string]$extra = "")
# the 6 seeds side by side on $bin: frame peaks, the stars' depth histogram
# (S3HIST) after the change, and $extra env settings (a=b;c=d)
$sp = $PSScriptRoot
$seeds = @("", "00001234", "c0ffee11", "5bd1e995", "9e3779b9", "00c0ffee")
$ps = @()
foreach ($s in $seeds) {
  $n = if ($s) { $s } else { "default" }
  $d = "$sp\cw_$n"
  New-Item -ItemType Directory -Force "$d\build" | Out-Null
  if (-not (Test-Path "$d\prof")) { Copy-Item -Recurse "$sp\prof" "$d\prof" }
  foreach ($c in "Emu.cs", "Seq.cs", "Den.cs", "Spr.cs", "Aud.cs", "seq.ps1") { Copy-Item -Force "$sp\prof\$c" "$d\prof\" }
  Copy-Item -Force $bin "$d\build\d"
  $ex = ""; foreach ($kv in $extra.Split(";")) { if ($kv) { $p = $kv.Split("="); $ex += "`$env:$($p[0])='$($p[1])'; " } }
  $cmd = "`$env:SEED='$s'; `$env:FRAMELOG='5000-9300'; `$env:S3HIST='5000-9300'; $ex pwsh -NoProfile -File '$d\prof\seq.ps1' -frames $frames *> '$d\out.txt'"
  $ps += Start-Process pwsh -ArgumentList "-NoProfile", "-Command", $cmd -PassThru -WindowStyle Hidden
}
$ps | Wait-Process
$all = 0
foreach ($s in $seeds) {
  $n = if ($s) { $s } else { "default" }
  $r = Get-Content "$sp\cw_$n\out.txt"
  $err = $r | ? { $_ -match '^ERROR' }
  $w = ($r | ? { $_ -match '^seq worst' }) -replace 'seq worst frame (\d+) at (\d+).*', '$1@$2'
  $ft = @{}; $r | ? { $_ -match '^FT ' } | % { $a = $_.Split(' '); $ft[[int]$a[1]] = [int]$a[2] }
  $ftMax = ($ft.Values | measure -Maximum).Maximum; if ($ftMax -gt $all) { $all = $ftMax }
  $h = $r | ? { $_ -match '^S3H ' }
  $sw = if ($h) { [int]($h[0].Split(' ')[1]) } else { 0 }
  $conv = ($ft.Keys | ? { $_ -ge $sw - 6 -and $_ -le $sw + 2 } | % { $ft[$_] } | measure -Maximum).Maximum
  $minBin = 999; $minAt = 0; $chgMax = 0; $chgAt = 0; $chgSum = 0; $cn = 0; $live = @()
  foreach ($l in $h) {
    $a = $l.Split(' '); $f = [int]$a[1]
    if ($f -lt $sw + 30 -or $f -gt $sw + 500) { continue }
    $bi = [array]::IndexOf($a, "bins"); $bins = $a[($bi + 1)..($bi + 18)] | % { [int]$_ }
    $m = ($bins[1..13] | measure -Minimum).Minimum
    if ($m -lt $minBin) { $minBin = $m; $minAt = $f }
    $ci = [array]::IndexOf($a, "chg"); $c = [int]$a[$ci + 1]; $chgSum += $c; $cn++
    if ($c -gt $chgMax) { $chgMax = $c; $chgAt = $f }
    $live += [int]$a[3]
  }
  "{0,-9} | worst {1} | peak FT {2} | switch {3}, conversion max {4} | bins 250..3500 (+30..+500): least {5} @{6} | colour changes/frame max {7} @{8}, avg {9:0.0} | stars {10}..{11} {12}" -f $n, $w, $ftMax, $sw, $conv, $minBin, $minAt, $chgMax, $chgAt, ($chgSum / [Math]::Max(1, $cn)), ($live | measure -Minimum).Minimum, ($live | measure -Maximum).Maximum, $err
}
"all seeds peak FT $all"
