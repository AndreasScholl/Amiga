param($sp,$binA,$binB,$frames=7400,$dumps="4400,5300,6000,6700")
$res=@()
foreach($bin in $binA,$binB){
  Copy-Item $bin "$sp\build\d" -Force
  $env:SEED=''; $env:FRAMELOG="1000-$frames"
  $o = pwsh -NoProfile -File "$sp\prof\seq.ps1" -frames $frames -dump $dumps
  $ft = ($o | ? { $_ -match '^FT ' } | % { ($_ -split ' ')[1..2] -join ' ' })
  $h = @{}; foreach($d in $dumps.Split(',')){ $h[$d]=(Get-FileHash "$sp\prof\cop$d.png").Hash }
  $res += ,@($ft,$h)
}
$fa=$res[0][0]; $fb=$res[1][0]; $diff=0; for($i=0;$i -lt [Math]::Min($fa.Count,$fb.Count);$i++){ if($fa[$i] -ne $fb[$i]){ $diff++; if($diff -le 3){ "cost diff: $($fa[$i]) vs $($fb[$i])" } } }
"frames compared $($fa.Count)/$($fb.Count), cost differences: $diff"
foreach($d in $dumps.Split(',')){ "image $d equal: " + ($res[0][1][$d] -eq $res[1][1][$d]) }
