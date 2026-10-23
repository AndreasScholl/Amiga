$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
$sp="C:\Users\konta\AppData\Local\Temp\claude\D--Thrust---Quadlite-Amiga-Projekt-Demo2023\43b28c74-8c82-4140-adc7-790e8fda5229\scratchpad"
$i0=$m.IndexOf("		; into the list, top down`n"); $e="		movem.l	(a7)+,a0/a5/a6`n		rts`n"; $i1=$m.IndexOf($e,$i0)
if($i0 -lt 0 -or $i1 -lt 0){throw "glow"}
$m=$m.Substring(0,$i0)+[IO.File]::ReadAllText("$sp\glow2.txt").Replace("`r`n","`n")+$m.Substring($i1+$e.Length)
Rep @"
		lea		morphGlowL4a,a2
		tst.b	morphGlowBuf
		beq.s	.b0
		lea		morphGlowL4b,a2
.b0:	move.l	warpSpr,a1			; the copper's sprite pointer 4
		move.l	a2,d0
		move.w	d0,32+6(a1)
		swap	d0
		move.w	d0,32+2(a1)
"@.Replace("`r`n","`n") @"
		lea		morphGlowL4a,a2
		lea		morphGlowL5a,a4
		tst.b	morphGlowBuf
		beq.s	.b0
		lea		morphGlowL4b,a2
		lea		morphGlowL5b,a4
.b0:	move.l	warpSpr,a1			; the copper's sprite pointers 4 and 5
		move.l	a2,d0
		move.w	d0,32+6(a1)
		swap	d0
		move.w	d0,32+2(a1)
		move.l	a4,d0
		move.w	d0,40+6(a1)
		swap	d0
		move.w	d0,40+2(a1)
"@.Replace("`r`n","`n")
Rep "morphGlowW:		ds.w	3*(1+morphTorpN)	; (the glows wanted: x, y, radius)`n" "morphGlowL5a:	ds.l	4*(1+15)+1`nmorphGlowL5b:	ds.l	4*(1+15)+1`nmorphGlowW:		ds.w	3*(1+morphTorpN)	; (the glows wanted: x, y, radius)`nmorphGlowP4:	dc.l	0		; (the lists as they fill: where, the last line)`nmorphGlowP5:	dc.l	0`nmorphGlowE4:	dc.w	0`nmorphGlowE5:	dc.w	0`n"
# canopy / guns
Rep "		move.w	d6,morphFMask`n		rts`n" @"
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
		rts
"@.Replace("`r`n","`n")
Rep "		dc.w	`$0040,`$0040,`$0040,`$0040,`$0001,`$0001,`$0001`n		dc.w	`$0012,`$0024`n" "		dc.w	`$0040,`$0040,`$0040,`$0040,`$0200,`$0200,`$0200	; (the canopy: 9)`n		dc.w	`$03ff,`$03ff		; (the guns stick out of the hull: always)`n"
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
