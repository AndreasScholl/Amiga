$d="D:\Thrust & Quadlite\Amiga Projekt\Demo2023"; $sp="C:\Users\konta\AppData\Local\Temp\claude\D--Thrust---Quadlite-Amiga-Projekt-Demo2023\43b28c74-8c82-4140-adc7-790e8fda5229\scratchpad"
function RepF($f,$a,$b){ $t=[IO.File]::ReadAllText($f).Replace("`r`n","`n"); if(-not $t.Contains($a)){ throw "missing in $f : $a" }; $t=$t.Replace($a,$b); [IO.File]::WriteAllText($f,$t.Replace("`n","`r`n")) }
# stars3d.i: replace the old s3Spawn with the run code
$f="$d\stars3d.i"; $t=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
$i0=$t.IndexOf("; a3 = a star: a new one, far off"); $i1=$t.IndexOf("; -> d0 = a random long (xorshift)")
$t=$t.Substring(0,$i0)+[IO.File]::ReadAllText("$sp\s3run.txt").Replace("`r`n","`n")+$t.Substring($i1)
[IO.File]::WriteAllText($f,$t.Replace("`n","`r`n"))
[IO.File]::WriteAllText("$d\s3tabs.i",([IO.File]::ReadAllText("$sp\s3tabs.txt")).Replace("`r`n","`n").Replace("`n","`r`n"))
# asteroids.s include
RepF "$d\asteroids.s" "		include	`"morph.i`"`n" "		include	`"morph.i`"`n		include	`"stars3d.i`"`n"
# warp.i: hand over to stars3d
RepF "$d\warp.i" "warpStep:`n		movem.l	a2-a5,-(a7)`n" "warpStep:`n	ifne	elite3`n		tst.b	s3On				; (stars3d.i: the field in bitplanes)`n		bne		s3Field`n	endc`n		movem.l	a2-a5,-(a7)`n"
RepF "$d\warp.i" "		tst.w	d5`n		bne.s	.out`n		move.b	#2,warpState		; all there: the thinning`n" "		tst.w	d5`n		bne.s	.out`n	ifne	elite3`n		jsr		s3Begin				; all there: every star into 3D, in`n		move.b	#3,warpState		; bitplanes (stars3d.i)`n		rts`n	endc`n		move.b	#2,warpState		; all there: the thinning`n"
# morph.i: init + glow clear stub
RepF "$d\morph.i" "morphInit:`n" "morphInit:`n		jsr		s3Init				; (stars3d.i: its tables)`n"
RepF "$d\morph.i" "morphRcpN	= 2200" "; the engines' glows in the star planes: off again (stub for now)`nmorphGlowClear::`n		rts`n`nmorphRcpN	= 2200"
