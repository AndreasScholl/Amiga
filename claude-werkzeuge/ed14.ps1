$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
Rep "		add.w	#32768,d5			; e (32768 = 1: the bit pattern of -32768,`n		move.w	#morphEX1-morphEX0,d2	; so used as unsigned below)`n" "		add.w	#32768,d5			; e`n		bpl.s	.e0					; (1 is one too many for a word: 32767)`n		move.w	#32767,d5`n.e0:	move.w	#morphEX1-morphEX0,d2`n"
Rep "		move.l	simZ,d0`n		sub.l	simZo,d0`n		move.l	d0,simVZ`n.out:	rts`n`n; --- the escort" "		move.l	simZ,d0`n		sub.l	simZo,d0`n		move.l	d0,simVZ`n.out:	rts`n; d2 = a way (1/16 units), d5 = e (Q15) -> d2.l = way * e (1/4096 units)`n.mul:	muls	d5,d2`n		asr.l	#7,d2`n		rts`n`n; --- the escort"
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
