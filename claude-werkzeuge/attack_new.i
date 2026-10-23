.loop:	; it flies its loop behind us; we ease off a little meanwhile
		move.w	morphVz,d0
		cmp.w	#morphVzLoop*256,d0
		bls.s	.l0
		subq.w	#6,d0
		move.w	d0,morphVz
.l0:	cmp.w	#morphLoopT,morphPT
		blo		.out
		move.b	#MP_ATTACK,morphPhase
		clr.w	morphPT
		sf		morphOut
		sf		morphHide
		st		morphDirty
		clr.w	morphHeadD
		move.w	#90*16,morphPh+2	; (the bank: the weave's cos)
		move.w	#90*16,morphPh+4	; (the heading: so too)
		st		morphSnd			; its engine is heard from now on
		rts

.attack:
		st		morphDirty
		move.w	morphPT,d0
		cmp.w	#morphBreakAt,d0
		bhs		.brk
		cmp.w	#morphEntryT,d0
		bhs		.esc
		; --- the entry: up from the lower left corner, faster than we are,
		;     slowing down to our speed; we speed up with it
		move.w	#morphEntryT,d1
		bsr		morphUnit			; d0 u, d1 its smoothstep
		move.w	d1,d3
		move.w	#256,d1
		sub.w	d0,d1
		mulu	d1,d1
		lsr.l	#8,d1
		neg.w	d1
		add.w	#256,d1				; e = 1 - (1-u)^2
		move.w	#morphEX1-morphEX0,d0
		muls	d1,d0
		asr.l	#8,d0
		add.w	#morphEX0,d0
		move.w	d0,morphSX
		move.w	#morphEY1-morphEY0,d0
		muls	d1,d0
		asr.l	#8,d0
		add.w	#morphEY0,d0
		move.w	d0,morphSY
		move.l	#(morphEZ1-morphEZ0)/16,d0
		mulu	d1,d0
		lsr.l	#4,d0
		add.l	#morphEZ0,d0
		move.l	d0,morphSZ
		move.w	#-morphAtkRoll,d0	; rolling out of its loop
		muls	d3,d0
		asr.l	#8,d0
		add.w	#morphAtkRoll,d0
		move.w	d0,morphRollD
		move.w	#-90,morphPitchD
		move.w	#-90,morphYawD
		move.w	#morphEscTilt,morphTiltD
		move.w	morphVz,d0			; we speed up with it: top speed
		cmp.w	#morphVzMax*256,d0
		bhs		.tor
		add.w	#16,d0
		move.w	d0,morphVz
		bra		.tor
.esc:	; --- the escort: it flies ahead of us towards the logo, weaving,
		;     banking into its turns, rolling now and then; it pulls away a
		;     little and we catch up again - we do not let it get away
		moveq	#0,d0
		moveq	#morphWxS,d1
		move.w	#morphWxA,d2
		bsr		morphWave
		add.w	#morphEX1,d0
		move.w	d0,morphSX
		moveq	#1,d0				; the bank into it (the weave's cos)
		moveq	#morphWxS,d1
		moveq	#morphEscBank,d2
		bsr		morphWave
		move.w	d0,d3
		move.w	morphPT,d0			; and its rolls
		sub.w	#morphEntryT+morphRoll1At,d0
		move.w	#morphRollT,d1
		bsr		morphUnit
		mulu	#360,d1
		lsr.l	#8,d1
		cmp.w	#360,d1
		blo.s	.r1
		moveq	#0,d1
.r1:	add.w	d1,d3
		move.w	morphPT,d0
		sub.w	#morphEntryT+morphRoll2At,d0
		move.w	#morphRollT,d1
		bsr		morphUnit
		mulu	#360,d1
		lsr.l	#8,d1
		cmp.w	#360,d1
		blo.s	.r2
		moveq	#0,d1
.r2:	sub.w	d1,d3				; (the other way round)
		move.w	d3,morphRollD
		moveq	#2,d0				; the nose into its turns
		moveq	#morphWxS,d1
		moveq	#morphEscHead,d2
		bsr		morphWave
		neg.w	d0
		move.w	d0,morphHeadD
		moveq	#3,d0				; up and down
		moveq	#morphWyS,d1
		move.w	#morphWyA,d2
		bsr		morphWave
		add.w	#morphEY1,d0
		move.w	d0,morphSY
		moveq	#4,d0				; ahead: away a little, back again
		moveq	#morphWzS,d1
		move.w	#morphWzA,d2
		bsr		morphWave
		ext.l	d0
		add.l	#morphEZ1,d0
		move.l	d0,morphSZ
		move.w	#-90,morphPitchD
		move.w	#-90,morphYawD
		move.w	#morphEscTilt,morphTiltD
.tor:	; --- the torpedoes: one every morphTorpGap frames from the end of
		;     the entry
		move.w	morphTorpNext,d0
		cmp.w	#morphTorpN,d0
		bhs		.imp
		mulu	#morphTorpGap,d0
		add.w	#morphEntryT,d0
		cmp.w	morphPT,d0
		bne		.imp
		bsr		morphTorpFire
		bra		.imp
.brk:	; --- the break: like a fighter it turns hard to the right, down,
		;     and round - past us on the lower right and away behind us
		sub.w	#morphBreakAt,d0
		move.w	#morphBreakT,d1
		bsr		morphUnit			; d1 smooth
		move.w	d1,d3
		mulu	#morphBreakA,d1
		lsr.l	#8,d1				; the angle it has turned, degrees
		move.w	d1,morphHeadD
		move.w	d1,d0
		bsr		morphSinCos			; d0 sin, d1 cos
		; its way, less ours: v (sin, down sin, cos) - v (0, 0, 1)
		move.w	d0,d2
		muls	#morphBreakV,d2
		add.l	d2,d2
		swap	d2
		add.w	d2,morphSX
		move.w	d0,d2
		muls	#morphBreakV*45/100,d2
		add.l	d2,d2
		swap	d2
		add.w	d2,morphSY
		sub.w	#32767,d1
		muls	#morphBreakV,d1
		add.l	d1,d1
		swap	d1
		ext.l	d1
		add.l	d1,morphSZ
		move.w	#morphBreakRoll,d0	; banked hard over, the nose down
		muls	d3,d0
		asr.l	#8,d0
		move.w	d0,morphRollD
		move.w	#morphBreakTilt,d0
		muls	d3,d0
		asr.l	#8,d0
		add.w	#morphEscTilt,d0
		move.w	d0,morphTiltD
		cmp.l	#morphNear,morphSZ	; past us: gone (heard a while longer)
		bge.s	.imp
		st		morphHide
.imp:	; --- every torpedo there (the hits: the next scene): over
		tst.w	morphTorpLeft
		bne		.out
		move.b	#MP_GONE,morphPhase
		clr.w	morphPT
		st		morphHide
		rts

.gone:	; (the hits come here)
		sf		morphSnd
		rts

;---------------------------------------------
; a torpedo is dropped from the ship: it falls out below it, keeping our
; speed, then its engine fires and it speeds away, along the line that ends
; on its point of the logo
morphTorpFire:
		move.w	morphTorpNext,d0
		addq.w	#1,morphTorpNext
		addq.w	#1,morphTorpLeft
		move.w	d0,d2
		mulu	#tp_len,d0
		lea		morphTorps,a1
		add.w	d0,a1
		move.w	#1,tp_age(a1)
		move.w	morphSX,d0
		ext.l	d0
		lsl.l	#4,d0
		move.l	d0,tp_x(a1)
		move.w	morphSY,d0
		add.w	#morphTorpBelow,d0
		ext.l	d0
		lsl.l	#4,d0
		move.l	d0,tp_y(a1)
		move.l	morphSZ,d0
		lsl.l	#4,d0
		move.l	d0,tp_z(a1)
		clr.l	tp_vz(a1)
		lsl.w	#2,d2				; its point on the logo: the slope there
		lea		morphTorpAim,a2
		move.w	(a2,d2.w),d0		; x on the screen
		sub.w	#morphVX,d0
		muls	#4096,d0
		divs	#morphF,d0
		move.w	d0,tp_kx(a1)
		move.w	2(a2,d2.w),d0		; y
		sub.w	#morphVY,d0
		muls	#4096,d0
		divs	#morphF,d0
		move.w	d0,tp_ky(a1)
		move.l	(a2,d2.w),tp_ax(a1)	; (its aim on the screen too)
		moveq	#SFX_DROP,d0
		jmp		sfxPlay

; where they hit (the logo, screen x/y)
morphTorpAim:	dc.w	135,44, 177,54, 220,44

; the torpedoes on (x, y, z in 1/256 units)
morphTorpMove:
		lea		morphTorps,a1
		moveq	#morphTorpN-1,d7
.t:		move.w	tp_age(a1),d0
		ble.s	.n
		addq.w	#1,tp_age(a1)
		cmp.w	#morphTorpDropT,d0
		bhs.s	.burn
		add.l	#morphTorpDropV,tp_y(a1)	; falling out
		bra.s	.n
.burn:	bne.s	.b0
		movem.l	d7/a1,-(a7)			; its engine fires
		moveq	#SFX_IGNITE,d0
		jsr		sfxPlay
		movem.l	(a7)+,d7/a1
.b0:	add.l	#morphTorpAcc,tp_vz(a1)
		move.l	tp_vz(a1),d0
		add.l	d0,tp_z(a1)
		move.w	d0,d1				; (the way ahead this frame, a word)
		muls	tp_kx(a1),d0
		asr.l	#8,d0
		asr.l	#4,d0
		add.l	d0,tp_x(a1)
		muls	tp_ky(a1),d1
		asr.l	#8,d1
		asr.l	#4,d1
		add.l	d1,tp_y(a1)
		cmp.w	#morphTorpHitAge,tp_age(a1)
		blo.s	.n
		move.w	#-1,tp_age(a1)		; there (the hits: the next scene)
		subq.w	#1,morphTorpLeft
.n:		lea		tp_len(a1),a1
		dbf		d7,.t
		rts

; the torpedoes into the draw table: a plasma ball - a diamond that
; twinkles, its size by its distance - then a spark, then a dot; and its
; engine's flare behind it once it burns. their glow: morphGlow (sprites)
morphTorpDraw:
		lea		morphTorps,a4
		lea		morphTorpScr,a3
		moveq	#morphTorpN-1,d7
.t:		move.w	#-1,(a3)			; (not on the screen)
		move.w	tp_age(a4),d0
		ble		.n
		movem.l	d7/a3/a4,-(a7)
		; onto the screen: x = mid + x*lens/z (1/256 units; all halved till
		; z fits a word)
		move.l	tp_z(a4),d5
		move.l	tp_x(a4),d3
		move.l	tp_y(a4),d4
		moveq	#0,d6
.sh:	cmp.l	#32000,d5
		blt.s	.s0
		asr.l	#1,d5
		asr.l	#1,d3
		asr.l	#1,d4
		addq.w	#1,d6
		bra.s	.sh
.s0:		muls	#morphF,d3
		divs	d5,d3
		add.w	#morphVX,d3			; x
		muls	#morphF,d4
		divs	d5,d4
		add.w	#morphVY,d4			; y
		move.l	#morphTorpR*16*morphF,d0	; the radius
		lsr.l	d6,d0
		divu	d5,d0				; px
		move.w	d3,(a3)				; (for the glow and the sound)
		move.w	d4,2(a3)
		move.w	d0,4(a3)
		move.w	tp_age(a4),d1
		btst	#0,d1				; the twinkle
		beq.s	.tw
		addq.w	#1,d0
.tw:	cmp.w	#2,d0
		blo.s	.dot
		; a diamond of radius d0 round d3/d4
		movem.w	d0/d3/d4,-(a7)
		bsr		.line4
		movem.w	(a7)+,d0/d3/d4
		cmp.w	#5,d0				; big: a smaller one inside, every
		blo.s	.fl					; other frame (the plasma swirls)
		move.w	tp_age(a4),d1
		btst	#1,d1
		bne.s	.fl
		movem.w	d0/d3/d4,-(a7)
		lsr.w	#1,d0
		bsr		.line4
		movem.w	(a7)+,d0/d3/d4
.fl:	; its engine's flare: a line out behind it (away from where it goes),
		; flickering, once it burns
		cmp.w	#morphTorpDropT,tp_age(a4)
		blo.s	.nx
		move.w	tp_age(a4),d7
		and.w	#3,d7
		add.w	d0,d7
		add.w	d0,d7				; length: 2r + 0..3
		move.w	d3,d2				; direction: from its aim to the ball
		sub.w	tp_ax(a4),d2
		move.w	d4,d5
		sub.w	tp_ay(a4),d5
		move.w	d2,d6				; scaled to the length (by the bigger
		bpl.s	.f0					; of the two)
		neg.w	d6
.f0:	move.w	d5,d0
		bpl.s	.f1
		neg.w	d0
.f1:	cmp.w	d0,d6
		bhs.s	.f2
		move.w	d0,d6
.f2:	tst.w	d6
		beq.s	.nx
		muls	d7,d2
		divs	d6,d2
		muls	d7,d5
		divs	d6,d5
		move.w	d3,d0
		move.w	d4,d1
		add.w	d0,d2
		add.w	d1,d5
		move.w	d5,d3
		jsr		set_line
		bra.s	.nx
.dot:	move.w	d3,d0
		move.w	d4,d1
		jsr		set_point
.nx:	movem.l	(a7)+,d7/a3/a4
.n:		lea		tp_len(a4),a4
		addq.l	#6,a3
		dbf		d7,.t
		rts
