param([int]$target = 771812)
# baut, misst den Speicher und gleicht RECV2COST (morph.i) so ab, dass die
# Summe der Hunks genau $target bleibt (die Flugaufzeichnung gibt nach)
$ErrorActionPreference = 'Stop'
$w = $PSScriptRoot
$f = 'D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i'
for ($i = 0; $i -lt 3; $i++) {
    $o = & "$w\build.ps1" $w 2>&1
    if (($o -join "`n") -notmatch 'link exit 0') { $o; throw 'build failed' }
    $m = & "$w\hunkmem.ps1" "$w\build\d"
    $tot = [int]([regex]::Match($m, 'total (\d+)').Groups[1].Value)
    $d = $tot - $target
    if ($d -eq 0) { $m; return }
    $t = [IO.File]::ReadAllText($f)
    $mm = [regex]::Match($t, 'RECV2COST\t= (-?\d+)')
    $c = [int]$mm.Groups[1].Value + $d
    if ($c % 2) { $c++ }
    $t = $t.Substring(0, $mm.Groups[1].Index) + $c + $t.Substring($mm.Groups[1].Index + $mm.Groups[1].Length)
    [IO.File]::WriteAllText($f, $t)
    "RECV2COST -> $c"
}
$m
