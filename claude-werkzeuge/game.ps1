param($n,$tag,$seed,$frames=6000)
if($seed){$env:SEED=$seed}else{Remove-Item Env:SEED -ErrorAction SilentlyContinue}
pwsh -NoProfile -File "$n\prof\seq.ps1" -frames $frames -f10 -1 > "$n\g_$tag.txt"
$f="$n\g_$tag.txt"; $g=Select-String -Path $f -Pattern "^GAME" | % Line; $life=@(); $u=$null
Select-String -Path $f -Pattern "^\s*(\d+): word (up|gone)" | % { $fr=[int]$_.Matches[0].Groups[1].Value; if($_.Matches[0].Groups[2].Value -eq 'up'){$u=$fr}elseif($u){$life+=($fr-$u); $u=$null} }
$pre = Select-String -Path $f -Pattern "^PRE (\d+) (\d+)" | % { [int]$_.Matches[0].Groups[2].Value } | measure -Maximum
$en = Select-String -Path $f -Pattern "^ENTER" | % Line
"$tag : $g | words $($life.Count) avg $([int](($life|measure -Average).Average)) max $(($life|measure -Maximum).Maximum) | PREmax $($pre.Maximum) | $en"
Select-String -Path $f -Pattern "ERROR" | % Line

