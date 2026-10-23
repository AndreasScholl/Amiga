param($sp)
$bin="$env:USERPROFILE\.vscode\extensions\prb28.amiga-assembly-1.8.13\resources\bin\win32"
$ok=$true
foreach($f in "main","scroller","asteroids","music"){ & "$bin\vasmm68k_mot.exe" -m68000 -Fhunk -phxass -quiet -o "$sp\buildnd\$f.o" "$f.s" 2>&1 | Where-Object { $_ -match 'error|warning' } ; if($LASTEXITCODE -ne 0){$ok=$false; "FAIL $f"} }
if($ok){ & "$bin\vlink.exe" -bamigahunk -Bstatic -o "$sp\buildnd\d" "$sp\buildnd\main.o" "$sp\buildnd\scroller.o" "$sp\buildnd\asteroids.o" "$sp\buildnd\music.o"; "link exit $LASTEXITCODE" }

