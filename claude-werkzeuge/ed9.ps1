$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
Rep "		MPT		8,0,0,16,0,6,3				; 11 canopy front`n		MPT		-6,0,0,-6,-6,13,3			; 12 canopy back left`n		MPT		-6,0,0,-6,6,13,3			; 13 canopy back right`n" "		MPT		8,0,0,16,0,3,3				; 11 canopy front (the canopy lies`n		MPT		-6,0,0,-6,-6,6,3			; 12 canopy back left  on the top face,`n		MPT		-6,0,0,-6,6,6,3				; 13 canopy back right a window in it)`n"
Rep "		MPF		16,0,6,11,11		; the canopy's front`n" "		MPF		16,0,3,11,11		; the canopy's front`n"
Rep "		MPF		-6,6,13,13,12		; the canopy's back`n" "		MPF		-6,6,6,13,12		; the canopy's back`n"
Rep "`$0200,`$0200,`$0200	; (the canopy: 9)`n" "`$0001,`$0001,`$0001	; (the canopy: on the top)`n"
Rep @"
		; the canopy stands up off the hull: seen with a top face, or from
		; behind - not from below (a bit of its own, 9)
		move.w	d6,d0
		and.w	#`$0007,d0
		bne.s	.cn
		btst	#6,d6
		beq.s	.cx
		move.w	d6,d0
		and.w	#`$0038,d0
		bne.s	.cx
.cn:	bset	#9,d6
.cx:	move.w	d6,morphFMask
"@.Replace("`r`n","`n") "		move.w	d6,morphFMask`n"
Rep "		dc.w	`$03ff,`$03ff		; (the guns stick out of the hull: always)`n" "		dc.w	`$01ff,`$01ff		; (the guns stick out of the hull: always)`n"
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
