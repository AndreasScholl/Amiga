param([string]$a, [string]$b)
# compares two AmigaDOS executables' program hunks (code/data/bss/reloc), ignoring symbol and debug hunks
function Prog([string]$path) {
  $d = [IO.File]::ReadAllBytes($path)
  function L([int]$o) { ([uint32]$d[$o] -shl 24) -bor ([uint32]$d[$o+1] -shl 16) -bor ([uint32]$d[$o+2] -shl 8) -bor [uint32]$d[$o+3] }
  $p = 4; while ((L $p) -ne 0) { $p += 4 + 4 * (L $p) }; $p += 4
  $first = L ($p+4); $last = L ($p+8); $p += 12 + 4 * ($last - $first + 1)
  $ms = New-Object IO.MemoryStream
  while ($p -lt $d.Length) {
    $t = (L $p) -band 0x3fffffff; $s0 = $p; $p += 4
    switch ($t) {
      { $_ -in 0x3e9, 0x3ea } { $p += 4 + 4 * (L $p) }
      0x3eb { $p += 4 }
      0x3ec { while (($c = L $p) -ne 0) { $p += 8 + 4*$c }; $p += 4 }
      0x3f0 { while (($c = L $p) -ne 0) { $p += 4 + 4*$c + 4 }; $p += 4; continue }
      0x3f1 { $p += 4 + 4 * (L $p); continue }
      0x3f2 { }
    }
    if ($t -ne 0x3f0 -and $t -ne 0x3f1) { $ms.Write($d, $s0, $p - $s0) }
  }
  , $ms.ToArray()
}
$x = Prog $a; $y = Prog $b
if ($x.Length -eq $y.Length -and [Linq.Enumerable]::SequenceEqual([byte[]]$x, [byte[]]$y)) { "gleich ({0:N0} B Programm-Hunks)" -f $x.Length } else { "VERSCHIEDEN ({0} / {1} B)" -f $x.Length, $y.Length }
