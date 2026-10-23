param([string]$path)
# lists an AmigaDOS executable's hunks: type, size, relocations, debug bytes
$b = [IO.File]::ReadAllBytes($path)
function L([int]$o) { ([uint32]$b[$o] -shl 24) -bor ([uint32]$b[$o+1] -shl 16) -bor ([uint32]$b[$o+2] -shl 8) -bor [uint32]$b[$o+3] }
$p = 0
if ((L 0) -ne 0x3f3) { "kein Hunk-Header"; return }
$p = 4; while ((L $p) -ne 0) { $p += 4 + 4 * (L $p) }; $p += 4
$n = L $p; $first = L ($p+4); $last = L ($p+8); $p += 12 + 4 * ($last - $first + 1)
$tot = @{ code=0; data=0; bss=0; reloc=0; relocN=0; debug=0; symbol=0 }
while ($p -lt $b.Length) {
  $t = (L $p) -band 0x3fffffff; $p += 4
  switch ($t) {
    0x3e9 { $s = L $p; $tot.code += 4*$s; $p += 4 + 4*$s }
    0x3ea { $s = L $p; $tot.data += 4*$s; $p += 4 + 4*$s }
    0x3eb { $tot.bss += 4*(L $p); $p += 4 }
    0x3ec { $p0 = $p; while (($c = L $p) -ne 0) { $tot.relocN += $c; $p += 8 + 4*$c }; $p += 4; $tot.reloc += $p - $p0 }
    0x3f0 { $p0 = $p; while (($c = L $p) -ne 0) { $p += 4 + 4*$c + 4 }; $p += 4; $tot.symbol += $p - $p0 }
    0x3f1 { $s = L $p; $tot.debug += 4*$s; $p += 4 + 4*$s }
    0x3f2 { }
    default { "unbekannter Hunk {0:x} bei {1}" -f $t, $p; break }
  }
}
"{0}: {1:N0} B, Hunks {2}; code {3:N0}, data {4:N0}, bss {5:N0}, reloc {6:N0} B ({7:N0} Eintraege), symbol {8:N0}, debug {9:N0}" -f (Split-Path $path -Leaf), $b.Length, $n, $tot.code, $tot.data, $tot.bss, $tot.reloc, $tot.relocN, $tot.symbol, $tot.debug
