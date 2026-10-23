param($file)
$fired=@(); $hits=0; $shots=0; $spots=@{}
Select-String -Path $file -Pattern "^SHOT (\d+)( fired at x (-?\d+))?( HIT)? ship (-?\d+),(-?\d+)" | % { $m=$_.Matches[0]; if($m.Groups[2].Success){ $shots++; $x=[int]$m.Groups[3].Value; $sx=[int]$m.Groups[5].Value; $sy=[int]$m.Groups[6].Value; $fired += [math]::Sqrt(($x-$sx)*($x-$sx)+(184-$sy)*(184-$sy)); $k="{0},{1}" -f [int]($sx/24),[int]($sy/24); $spots[$k]=1 }; if($m.Groups[4].Success){$hits++} }
"shots $shots hits $hits  dist avg {0:n0} min {1:n0} max {2:n0}  distinct 24px cells {3}" -f ($fired|measure -Average).Average, ($fired|measure -Minimum).Minimum, ($fired|measure -Maximum).Maximum, $spots.Count
