param([string]$bin)
$b = [IO.File]::ReadAllBytes($bin)
function L($o) { return ([uint32]$b[$o] -shl 24) -bor ([uint32]$b[$o+1] -shl 16) -bor ([uint32]$b[$o+2] -shl 8) -bor [uint32]$b[$o+3] }
$o = 4; while ((L $o) -ne 0) { $o += 4 * ((L $o) + 1) }; $o += 4
$n = L $o; $f = L ($o+4); $l = L ($o+8); $o += 12
$chip = 0; $other = 0
for ($i = $f; $i -le $l; $i++) { $v = L $o; $o += 4; $sz = ($v -band 0x3fffffff) * 4; if ($v -band 0x40000000) { $chip += $sz } else { $other += $sz } }
"chip $chip other $other total $($chip + $other)"
