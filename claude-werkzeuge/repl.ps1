param([string]$file, [string]$pairs)
# applies old/new text pairs to a source file (CRLF), each old text exactly once.
# $pairs: a file with blocks separated by lines "=====" (old) and "-----" (new)
$t = [IO.File]::ReadAllText($file)
$raw = [IO.File]::ReadAllText($pairs).Replace("`r`n", "`n")
$blocks = $raw -split "(?m)^=====\n"
$n = 0
foreach ($b in $blocks) {
  if ($b.Trim() -eq "") { continue }
  $p = $b -split "(?m)^-----\n", 2
  if ($p.Count -ne 2) { throw "bad block: $b" }
  $old = $p[0].TrimEnd("`n").Replace("`n", "`r`n"); $new = $p[1].TrimEnd("`n").Replace("`n", "`r`n")
  $i = $t.IndexOf($old)
  if ($i -lt 0) { throw "missing: $old" }
  if ($t.IndexOf($old, $i + 1) -ge 0) { throw "twice: $old" }
  $t = $t.Substring(0, $i) + $new + $t.Substring($i + $old.Length); $n++
}
[IO.File]::WriteAllText($file, $t)
"$n replaced in $file"
