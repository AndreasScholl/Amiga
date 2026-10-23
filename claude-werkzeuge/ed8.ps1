$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
Rep @"
		bsr		morphPTorpDraw
		bsr		morphEngGlow
		tst.b	morphPShip
		beq.s	.none
		move.l	a6,-(a7)
		lea		morphCache,a6
		lea		morphEdges,a4
		lea		morphEM,a3
		lea		morphPXY,a1
		move.w	morphPMask,d5
		moveq	#morphNE-1,d7
		bsr		morphEdgeLines
		move.l	a6,d0
"@.Replace("`r`n","`n") @"
		bsr		morphPTorpDraw
		tst.b	morphPShip
		beq.s	.none
		move.l	a6,-(a7)
		lea		morphCache,a6
		lea		morphEdges,a4
		lea		morphEM,a3
		lea		morphPXY,a1
		move.w	morphPMask,d5
		moveq	#morphNE-1,d7
		bsr		morphEdgeLines
		tst.b	morphPGlow			; the engine burning, its plate seen: the
		beq.s	.nf					; flame in it
		bsr		morphFlame
.nf:	move.l	a6,d0
"@.Replace("`r`n","`n")
Rep "; the torpedoes into the draw table: a plasma ball - a diamond that`n" @"
; the engine's flame: a second plate inside the engine plate, its size
; flickering frame by frame and bigger with the thrust - and when it pushes
; hard a cross of fire over it. lines like the ship's own (no sprites: they
; lose their DMA slots under the game plane's early fetch). a6 the table
morphFlame:
		lea		morphPXY+7*4,a1		; the middle of the plate's corners
		moveq	#0,d0
		moveq	#0,d1
		moveq	#4-1,d7
.c:		add.w	(a1)+,d0
		add.w	(a1)+,d1
		dbf		d7,.c
		asr.w	#2,d0
		asr.w	#2,d1
		move.w	d0,morphFlC
		move.w	d1,morphFlC+2
		moveq	#0,d6				; its size: 0.45 .. 0.9 of the plate
		move.b	morphPGP+1,d6		; (the thrust)
		lsr.w	#1,d6
		add.w	#115,d6
		btst	#0,morphT+1			; (the flicker)
		beq.s	.f0
		add.w	#26,d6
.f0:	lea		morphPXY+7*4,a1
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
		lea		morphFlP,a2
		moveq	#4-1,d7
.l:		movem.w	(a2),d0/d1			; the four sides
		cmp.w	#3,d7
		bne.s	.l0
		movem.w	12(a2),d2/d3
		bra.s	.l1
.l0:	movem.w	-4(a2),d2/d3
.l1:	move.w	d7,-(a7)
		jsr		set_line
		move.w	(a7)+,d7
		addq.l	#4,a2
		dbf		d7,.l
		cmp.b	#morphGlowHot,morphPGP+1	; pushing hard: the cross
		blo.s	.out
		lea		morphFlP,a2
		movem.w	(a2),d0-d3/d4-d7	; (corners 0, 1 / 2, 3)
		movem.w	d2/d3/d6/d7,-(a7)
		move.w	d4,d2
		move.w	d5,d3
		jsr		set_line			; 0 - 2
		movem.w	(a7)+,d0/d1/d2/d3
		jmp		set_line			; 1 - 3
.out:	rts
morphFlC:	ds.w	2
morphFlP:	ds.w	8

; the torpedoes into the draw table: a plasma ball - a diamond that
"@.Replace("`r`n","`n")
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
