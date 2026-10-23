param([string]$seed = "", [string]$dump = "", [int]$frames = 9300)
# runs runA\build\d and runB\build\d in the harness side by side (the same
# seed, the same frames dumped) and compares their pictures pixel by pixel
$sp = $PSScriptRoot
$ps = @()
foreach ($r in "runA", "runB") {
  Remove-Item "$sp\$r\prof\*.png", "$sp\$r\prof\*.raw" -ErrorAction SilentlyContinue
  $cmd = "`$env:SEED='$seed'; `$env:FRAMELOG='5270-9300'; pwsh -NoProfile -File '$sp\$r\prof\seq.ps1' -frames $frames -dump '$dump' *> '$sp\$r\out.txt'"
  $ps += Start-Process pwsh -ArgumentList "-NoProfile", "-Command", $cmd -PassThru -WindowStyle Hidden
}
$ps | Wait-Process
Add-Type -TypeDefinition @'
public static class RawCmp {
  public static string Cmp(string a, string b, int w) {
    var x = System.IO.File.ReadAllBytes(a); var y = System.IO.File.ReadAllBytes(b);
    if (x.Length != y.Length) return "size differs";
    int d = 0, x0 = 9999, x1 = -1, y0 = 9999, y1 = -1;
    for (int i = 0; i < x.Length; i += 4) if (x[i] != y[i] || x[i+1] != y[i+1] || x[i+2] != y[i+2]) { d++; int p = i / 4, px = p % w, py = p / w; if (px < x0) x0 = px; if (px > x1) x1 = px; if (py < y0) y0 = py; if (py > y1) y1 = py; }
    return d == 0 ? "identical" : d + " px differ, x " + x0 + ".." + x1 + " y " + y0 + ".." + y1;
  }
}
'@
foreach ($r in "runA", "runB") { "$r " + ((Get-Content "$sp\$r\out.txt" | ? { $_ -match '^(seq worst|ERROR)' }) -join ' | ') }
$n = 0; $same = 0
Get-ChildItem "$sp\runA\prof\*.raw" | sort Name | % {
  $res = [RawCmp]::Cmp($_.FullName, "$sp\runB\prof\$($_.Name)", 352); $n++
  if ($res -eq "identical") { $same++ } ; "  $($_.Name): $res"
}
"pictures $n, identical $same"
