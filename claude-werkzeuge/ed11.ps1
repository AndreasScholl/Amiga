$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
Rep @"
		movem.w	(a7)+,d0/d1
		lea		morphPXY+7*4,a1
		lea		morphFlP,a2
		moveq	#4-1,d7
.p:		move.w	(a1)+,d2			; x = mid + (x - mid) * size
"@.Replace("`r`n","`n") @"
		movem.w	(a7)+,d0/d1
		move.w	d6,morphFlS
		bsr.s	.scale
"@.Replace("`r`n","`n")
Rep @"
		add.w	d1,d2
		move.w	d2,(a2)+
		dbf		d7,.p
		lea		morphFlP,a2
		moveq	#4-1,d7
.l:		movem.w	(a2),d0/d1			; the four sides
"@.Replace("`r`n","`n") @"
		lea		morphFlP,a2
		moveq	#4-1,d7
.l:		movem.w	(a2),d0/d1			; the four sides
"@.Replace("`r`n","`n")
Rep @"
		lea		morphFlP,a2			; the cross of fire
		movem.w	(a2),d0-d3/d4-d7	; (corners 0, 1 / 2, 3)
"@.Replace("`r`n","`n") @"
		move.w	morphFlS,d6			; the cross of fire: out beyond the
		add.w	d6,d6				; plate's corners (a flare)
		movem.w	morphFlC,d0/d1
		bsr.s	.scale
		lea		morphFlP,a2
		movem.w	(a2),d0-d3/d4-d7	; (corners 0, 1 / 2, 3)
"@.Replace("`r`n","`n")
Rep ".out:	rts`nmorphFlC:	ds.w	2`nmorphFlP:	ds.w	8`n" @"
.out:	rts
; d0/d1 the middle, d6 the size (256 = the plate) -> morphFlP
.scale:	lea		morphPXY+7*4,a1
		lea		morphFlP,a2
		moveq	#4-1,d7
.p:		move.w	(a1)+,d2			; x = mid + (x - mid) * size
		sub.w	d0,d2
		muls	d6,d2
		asr.l	#8,d2
		add.w	d0,d2
		move.w	d2,(a2)+
		move.w	(a1)+,d2
		sub.w	d1,d2
		muls	d6,d2
		asr.l	#8,d2
		add.w	d1,d2
		move.w	d2,(a2)+
		dbf		d7,.p
		rts
morphFlC:	ds.w	2
morphFlS:	dc.w	0
morphFlP:	ds.w	8
"@.Replace("`r`n","`n")
Rep "; the torpedoes into the draw table: a plasma ball - a diamond that; twinkles, its size by its distance - then a spark, then a dot; and its`n; engine's flare behind it once it burns. their glow: morphEngGlow`n" "; the torpedoes into the draw table: a plasma ball - a diamond that`n; twinkles, its size by its distance - then a spark, then a dot; and its`n; engine's flare behind it once it burns`n"
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
