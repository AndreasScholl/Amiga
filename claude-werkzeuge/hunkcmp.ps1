param([string]$a, [string]$b)
# compares two Amiga hunk executables without their symbol and debug hunks
function Parts([string]$f) {
  $d = [IO.File]::ReadAllBytes($f)
  function L($o) { return ([uint32]$d[$o] -shl 24) -bor ([uint32]$d[$o+1] -shl 16) -bor ([uint32]$d[$o+2] -shl 8) -bor [uint32]$d[$o+3] }
  $o = 4; while ((L $o) -ne 0) { $o += 4 * ((L $o) + 1) }; $o += 4
  $n = L $o; $fi = L ($o+4); $la = L ($o+8); $o += 12 + 4 * ($la - $fi + 1)
  $ms = New-Object IO.MemoryStream
  while ($o -lt $d.Length) {
    $t = (L $o) -band 0x3fffffff; $o += 4
    switch ($t) {
      0x3e9 { $c = L $o; $ms.Write($d, $o - 4, 4 * $c + 8); $o += 4 + 4 * $c }
      0x3ea { $c = L $o; $ms.Write($d, $o - 4, 4 * $c + 8); $o += 4 + 4 * $c }
      0x3eb { $ms.Write($d, $o - 4, 8); $o += 4 }
      0x3ec { $s = $o; while ((L $o) -ne 0) { $o += 8 + 4 * (L $o) }; $o += 4; $ms.Write($d, $s - 4, $o - $s + 4) }
      0x3f0 { while ((L $o) -ne 0) { $o += 4 * ((L $o) + 2) }; $o += 4 }
      0x3f1 { $c = L $o; $o += 4 + 4 * $c }
      0x3f2 { $ms.Write($d, $o - 4, 4) }
      default { throw "hunk type $t at $o" }
    }
  }
  return ,$ms.ToArray()
}
$x = Parts $a; $y = Parts $b
if ($x.Length -ne $y.Length) { "different length: $($x.Length) vs $($y.Length)"; exit }
$n = 0; for ($i = 0; $i -lt $x.Length; $i++) { if ($x[$i] -ne $y[$i]) { $n++ } }
if ($n -eq 0) { "program hunks identical ($($x.Length) bytes)" } else { "program hunks differ: $n bytes" }
