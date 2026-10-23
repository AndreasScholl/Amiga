;---------------------------------------------
; the sprites: every glow (the star planes are the stars' alone), from
; morphPlayDraw every frame. built in one of two buffers: the copper takes
; their pointers (clistElite elSpr) and colours (elSprCol) at the top of
; the next frame. sprites 0..3 only - the wide fetch (DDFSTRT $28) takes
; the higher ones' DMA slots:
;   torpedoes about: 0, 1, 2 their glows, 3 the ship's small flame - one
;     palette, rim, middle, core, in both pairs (morphTorpSpr)
;   none about: the afterburner - 0+1 attached (15 colours) the fireball,
;     2 and 3 tongues of flame round it, out behind it (morphAbSpr)
; the flame's size follows the plate (seen edge on: small) softly, from
; one to the other too (morphFlGeo). keeps all
morphSprFrame:
	ifne	sprTest
		rts
	endc
		movem.l	d0-d7/a0-a6,-(a7)
		not.b	morphSprB
		lea		morphSprBuf,a2
		tst.b	morphSprB
		beq.s	.b0
		lea		4*MSPR_LEN(a2),a2
.b0:	bsr		morphFlRand			; (the flicker's numbers)
		bsr		morphFlGeo
		lea		elSpr,a3
		tst.w	morphPTorpN
		beq.s	.ab
		bsr		morphTorpSpr
		lea		morphColTorp,a0
		bra.s	.col
.ab:	bsr		morphAbSpr
		lea		morphColAb,a0
.col:	lea		elSprCol+2,a1		; the colours 17..31
		moveq	#15-1,d0
.c:		move.w	(a0)+,(a1)
		addq.l	#4,a1
		dbf		d0,.c
		tst.w	morphPTorpN
		bne.s	.out
		lea		elSprCol+2,a1		; the afterburner's heat: its core
		move.w	morphFlRn,d0		; pulses, white to yellow
		and.w	#3*2,d0
		move.w	.core(pc,d0.w),14*4(a1)
		move.w	morphFlRn+2,d0
		and.w	#3*2,d0
		move.w	.core2(pc,d0.w),13*4(a1)
		tst.b	morphFlash			; (it fires: white hot all through)
		beq.s	.out
		subq.b	#1,morphFlash
		lea		7*4(a1),a1
		moveq	#8-1,d0
.f:		move.w	#$0fff,(a1)
		addq.l	#4,a1
		dbf		d0,.f
.out:	movem.l	(a7)+,d0-d7/a0-a6
		rts
.core:	dc.w	$0eff,$0fff,$0ffc,$0ff9
.core2:	dc.w	$0fff,$0ffd,$0ffa,$0fe8

; the torpedoes on sprites 0, 1, 2 (falling: none, a cold diamond; burning:
; a glow inside the diamond, in front of it - the lines show round it -
; smaller and smaller far off down to a spark; the frame it fires a flash
; bigger than the diamond), the ship's small flame on 3. a2 = the buffers,
; a3 = elSpr
morphTorpSpr:
		lea		morphPTorps,a4
		moveq	#0,d7
.t:		cmp.w	morphPTorpN,d7
		bhs.s	.null
		btst	#TF_BURN,5(a4)
		beq.s	.null
		moveq	#0,d6				; its R
		move.b	4(a4),d6
		subq.w	#1,d6
		btst	#TF_FLASH,5(a4)
		beq.s	.s0
		addq.w	#4,d6
.s0:	movem.w	(a4),d0/d1			; its middle
		bsr		morphGlowPut
		bra.s	.ptr
.null:	move.l	#s3Null,d0
.ptr:	bsr		morphSprPtr
		lea		MSPR_LEN(a2),a2
		addq.l	#8,a4
		addq.w	#1,d7
		cmp.w	#3,d7
		blo.s	.t
		move.w	morphFlR,d6			; the ship's small flame (as the
		beq.s	.n3					; afterburner was, as it goes)
		add.w	morphFlJ,d6
		movem.w	morphFlX,d0/d1
		bsr		morphGlowPut
		bra		morphSprPtr
.n3:	move.l	#s3Null,d0
		bra		morphSprPtr

; d0/d1 = the middle, d6 = R (clamped to 1..MSPR_RMAX): a glow (morphSprImg)
; into the sprite at a2 -> d0 = its pointer
morphGlowPut:
		cmp.w	#1,d6
		bge.s	.r0
		moveq	#1,d6
.r0:	cmp.w	#MSPR_RMAX,d6
		ble.s	.r1
		moveq	#MSPR_RMAX,d6
.r1:	move.w	d6,d2				; its rows: from (R^2 - 1) on
		mulu	d2,d2
		subq.w	#1,d2
		lsl.w	#2,d2
		lea		morphSprImg,a1
		add.w	d2,a1
		moveq	#4,d4
		moveq	#0,d3
		sub.w	d6,d1
		subq.w	#7,d0
		move.w	d6,d5
		add.w	d5,d5
		addq.w	#1,d5
		bra		morphSprPut

; d0 = a sprite's pointer -> into elSpr at a3, a3 on to the next
morphSprPtr:
		move.w	d0,6(a3)
		swap	d0
		move.w	d0,2(a3)
		addq.l	#8,a3
		rts

; d0/d1 = the image's left, top (game plane), a1 = its first row (plane A,
; B), d4 = from one row to the next (bytes), d5 = rows, d3 = $80 attached
; (the odd sprite of a pair), a2 = the sprite's buffer -> d0 = the sprite's
; pointer (s3Null: not on the screen). cut at the top and the bottom.
; uses d0-d2/d5/a1
morphSprPut:
		add.w	#96,d0				; HSTART
		bmi.s	.null
		cmp.w	#$1c0,d0
		bhs.s	.null
		tst.w	d1					; (rows above the plane: off)
		bpl.s	.y0
		add.w	d1,d5
		neg.w	d1
		mulu	d4,d1
		add.w	d1,a1
		moveq	#0,d1
.y0:	move.w	d1,d2				; (and below it)
		add.w	d5,d2
		sub.w	#game_height,d2
		bls.s	.y1
		sub.w	d2,d5
.y1:	tst.w	d5
		ble.s	.null
		add.w	#$20,d1				; VSTART, VSTOP: the control words
		move.w	d1,d2
		lsl.w	#8,d2
		move.b	d0,d2				; (HSTART >> 1)
		lsr.b	#1,d2
		btst	#8,d0
		beq.s	.h8
		bset	#7,d2
.h8:	move.w	d2,(a2)
		move.w	d1,d2
		add.w	d5,d2				; VSTOP
		lsl.w	#8,d2
		or.b	d3,d2				; (attached)
		btst	#8,d1
		beq.s	.c0
		bset	#2,d2
.c0:	move.w	d1,-(a7)
		add.w	d5,d1
		btst	#8,d1
		beq.s	.c1
		bset	#1,d2
.c1:	move.w	(a7)+,d1
		btst	#0,d0
		beq.s	.c2
		bset	#0,d2
.c2:	move.w	d2,2(a2)
		lea		4(a2),a0
		subq.w	#1,d5
.r:		move.l	(a1),(a0)+
		add.w	d4,a1
		dbf		d5,.r
		clr.l	(a0)
		move.l	a2,d0
		rts
.null:	move.l	#s3Null,d0
		rts

; the afterburner (no torpedoes about): the fireball, 0+1 attached, and two
; tongues of flame, 2 and 3 - round its rim when it is seen from behind,
; out behind it in a stream when it is seen from the side; the flash the
; frame it fires: all of it at its biggest. a2 = the buffers, a3 = elSpr
morphAbSpr:
		move.w	morphFlR,d6
		beq		.none
		add.w	morphFlJ,d6
		tst.b	morphFlash
		beq.s	.r0
		moveq	#MSPR_RMAX,d6
.r0:	cmp.w	#1,d6
		bge.s	.r1
		moveq	#1,d6
.r1:	cmp.w	#MSPR_RMAX,d6
		ble.s	.r2
		moveq	#MSPR_RMAX,d6
.r2:	move.w	d6,d2				; the fireball's rows: its phase's, from
		mulu	d2,d2				; (R^2 - 1) on
		subq.w	#1,d2
		moveq	#0,d0
		move.b	morphFlPh,d0
		mulu	#63,d0
		add.w	d0,d2
		lsl.w	#3,d2
		lea		morphFbImg,a5
		add.w	d2,a5
		move.w	d6,d5				; rows: 2R+1
		add.w	d5,d5
		addq.w	#1,d5
		movem.w	morphFlX,d0/d1		; sprite 0: planes 0, 1
		subq.w	#7,d0
		sub.w	d6,d1
		move.l	a5,a1
		moveq	#8,d4
		moveq	#0,d3
		movem.w	d0/d1/d5,-(a7)
		bsr		morphSprPut
		bsr		morphSprPtr
		movem.w	(a7)+,d0/d1/d5
		lea		MSPR_LEN(a2),a2		; sprite 1: planes 2, 3 (attached)
		lea		4(a5),a1
		move.w	#$80,d3
		bsr		morphSprPut
		bsr		morphSprPtr
		lea		MSPR_LEN(a2),a2
		; the tongues: where (d0/d1 a, then b) and how big (d6)
		move.w	morphFlVX,d2		; the way out behind it (the nose to
		move.w	morphFlVY,d3		; the plate, on the screen)
		move.w	d2,d4
		bpl.s	.a0
		neg.w	d4
.a0:	move.w	d3,d5
		bpl.s	.a1
		neg.w	d5
.a1:	add.w	d5,d4				; |v| (about)
		tst.b	morphFlash
		bne.s	.fl
		cmp.w	d6,d4
		bhi.s	.st
		; seen from behind: round its rim, here and there
		movem.w	morphFlX,d0/d1
		add.w	morphFlTX,d0
		add.w	morphFlTY,d1
		movem.w	d0/d1,.ta
		movem.w	morphFlX,d0/d1
		sub.w	morphFlTY,d0
		add.w	morphFlTX,d1
		movem.w	d0/d1,.tb
		move.w	d6,d0
		subq.w	#1,d0
		move.w	d0,.sa
		lsr.w	#1,d0
		move.w	d0,.sb
		bra.s	.tg
.fl:	movem.w	morphFlX,d0/d1		; the flash: wide to both sides
		sub.w	#10,d0
		movem.w	d0/d1,.ta
		add.w	#20,d0
		movem.w	d0/d1,.tb
		move.w	#MSPR_RMAX,.sa
		move.w	#MSPR_RMAX,.sb
		bra.s	.tg
.st:	; seen from the side: a stream out behind it, R+2 and 2R+4 on
		move.w	d6,d5
		addq.w	#2,d5
		move.w	d2,d0
		muls	d5,d0
		divs	d4,d0
		move.w	d3,d1
		muls	d5,d1
		divs	d4,d1
		add.w	morphFlX,d0
		add.w	morphFlY,d1
		movem.w	d0/d1,.ta
		add.w	d5,d5
		move.w	d2,d0
		muls	d5,d0
		divs	d4,d0
		move.w	d3,d1
		muls	d5,d1
		divs	d4,d1
		add.w	morphFlX,d0
		add.w	morphFlY,d1
		move.w	morphFlTX,d2		; (it flickers)
		asr.w	#1,d2
		add.w	d2,d0
		move.w	morphFlTY,d2
		asr.w	#1,d2
		add.w	d2,d1
		movem.w	d0/d1,.tb
		move.w	d6,.sa
		move.w	d6,d0
		lsr.w	#1,d0
		addq.w	#1,d0
		move.w	d0,.sb
.tg:	moveq	#0,d7				; tongue a (sprite 2), b (sprite 3)
		lea		.ta(pc),a4
.tl:	movem.w	(a4),d0/d1
		move.w	4*2(a4),d6
		cmp.w	#1,d6
		bge.s	.t0
		moveq	#1,d6
.t0:	cmp.w	#MSPR_RMAX,d6
		ble.s	.t1
		moveq	#MSPR_RMAX,d6
.t1:	move.w	d6,d2				; its rows (its own phase: the next)
		mulu	d2,d2
		subq.w	#1,d2
		moveq	#0,d3
		move.b	morphFlPh,d3
		add.w	d7,d3
		and.w	#3,d3
		mulu	#63,d3
		add.w	d3,d2
		lsl.w	#2,d2
		lea		morphTgImg,a1
		add.w	d2,a1
		subq.w	#7,d0
		sub.w	d6,d1
		move.w	d6,d5
		add.w	d5,d5
		addq.w	#1,d5
		moveq	#4,d4
		moveq	#0,d3
		bsr		morphSprPut
		bsr		morphSprPtr
		lea		MSPR_LEN(a2),a2
		addq.l	#4,a4
		addq.w	#1,d7
		cmp.w	#2,d7
		blo.s	.tl
		rts
.none:	moveq	#4-1,d7
.n:		move.l	#s3Null,d0
		bsr		morphSprPtr
		dbf		d7,.n
		rts
.ta:	dc.w	0,0					; tongue a's middle, b's (x, y)
.tb:	dc.w	0,0
.sa:	dc.w	0					; ... their R
.sb:	dc.w	0

; the flame (both sizes): where the plate is, how big - its area (seen edge
; on: small) times the thrust, softly (morphFlR16), the way out behind it;
; the flicker: a new phase every 2..5 frames, the size a little up or down
morphFlGeo:
		subq.b	#1,morphFlPC
		bpl.s	.ph
		move.w	morphFlRn,d0
		moveq	#3,d1
		and.w	d0,d1
		cmp.b	morphFlPh,d1
		bne.s	.p0
		addq.w	#1,d1
		and.w	#3,d1
.p0:	move.b	d1,morphFlPh
		lsr.w	#2,d0
		moveq	#3,d1
		and.w	d0,d1
		addq.w	#2,d1
		move.b	d1,morphFlPC
		lsr.w	#2,d0
		moveq	#3,d1
		and.w	d0,d1
		subq.w	#1,d1				; -1 .. 2: (2 -> 0)
		cmp.w	#2,d1
		bne.s	.p1
		moveq	#0,d1
.p1:	move.w	d1,morphFlJ
		move.w	morphFlRn+2,d0
		moveq	#7,d1
		and.w	d0,d1
		subq.w	#4,d1
		move.w	d1,morphFlTX
		lsr.w	#3,d0
		moveq	#7,d1
		and.w	d0,d1
		subq.w	#4,d1
		move.w	d1,morphFlTY
.ph:	moveq	#0,d6				; the size wanted (R * 16): none ...
		tst.b	morphPShip
		beq		.sz
		tst.b	morphPGlow
		beq		.sz
		lea		morphPXY+7*4,a0		; ... or the plate's: its middle
		move.w	(a0),d0
		add.w	4(a0),d0
		add.w	8(a0),d0
		add.w	12(a0),d0
		asr.w	#2,d0
		move.w	d0,morphFlX
		move.w	2(a0),d1
		add.w	6(a0),d1
		add.w	10(a0),d1
		add.w	14(a0),d1
		asr.w	#2,d1
		move.w	d1,morphFlY
		sub.w	morphPXY,d0			; the way out behind it: from the nose
		move.w	d0,morphFlVX
		sub.w	morphPXY+2,d1
		move.w	d1,morphFlVY
		move.w	8(a0),d2			; its area: the diagonals' cross product
		sub.w	(a0),d2
		move.w	10(a0),d3
		sub.w	2(a0),d3
		move.w	12(a0),d4
		sub.w	4(a0),d4
		move.w	14(a0),d5
		sub.w	6(a0),d5
		muls	d5,d2
		muls	d4,d3
		sub.l	d3,d2
		bpl.s	.a0
		neg.l	d2
.a0:	moveq	#0,d6				; ... its root (the plate's size)
		move.w	#256,d1
.q:		move.w	d6,d3
		add.w	d1,d3
		move.w	d3,d4
		mulu	d4,d4
		cmp.l	d2,d4
		bhi.s	.q1
		move.w	d3,d6
.q1:	lsr.w	#1,d1
		bne.s	.q
		moveq	#0,d1				; the fireball: the plate, up to half as
		move.b	morphPGP+1,d1		; big again with the thrust (R * 16 =
		lsr.w	#1,d1				; root/2 * (256 + thrust/2) / 16)
		add.w	#256,d1
		mulu	d1,d6
		lsr.l	#5,d6
.sz:	move.w	morphFlR16,d0		; softly there
		sub.w	d0,d6
		asr.w	#2,d6
		add.w	d6,d0
		move.w	d0,morphFlR16
		addq.w	#8,d0
		lsr.w	#4,d0
		move.w	d0,morphFlR			; (0: none)
		rts

; -> morphFlRn (two words): the next random numbers (xorshift). uses d0/d1
morphFlRand:
		move.l	morphFlRn,d0
		move.l	d0,d1
		lsl.l	#8,d1
		lsl.l	#5,d1
		eor.l	d1,d0
		move.l	d0,d1
		clr.w	d1
		swap	d1
		lsr.l	#1,d1
		eor.l	d1,d0
		move.l	d0,d1
		lsl.l	#5,d1
		eor.l	d1,d0
		move.l	d0,morphFlRn
		rts
morphFlRn:	dc.l	$6c8e9cf5

; the sprite colours 17..31: the torpedoes' (17-19, 21-23: rim, middle,
; core) ...
morphColTorp:	dc.w	$0a20,$0f60,$0ffe,0,$0a20,$0f60,$0ffe,0,0,0,0,0,0,0,0
; ... the afterburner's (0+1 attached, 1..15: dark red, red, the tongues'
; three (5, 6, 7 = 21-23: sprites 2 and 3), orange, yellow, white, a
; bluish white core)
morphColAb:		dc.w	$0400,$0600,$0900,$0b20,$0d40,$0f70,$0fb3,$0e50
				dc.w	$0f80,$0fa2,$0fc4,$0fd7,$0ffa,$0fff,$0eff

; once (morphInit): the glows' rows - the torpedoes' and the small flame's
; (rim, middle, core: 1, 2, 3), the fireball's (0..15, four phases), the
; tongues' (1, 2, 3, four phases), by the distance from the middle and a
; ragged rim (morphFlRand)
morphSprMake:
		movem.l	d0-d7/a0,-(a7)
		lea		morphSprImg,a0		; the glows
		moveq	#1,d6				; R
		moveq	#MSPR_RMAX-1,d7
.sz:	move.w	d6,d5
		mulu	d5,d5				; R^2: the bounds (* 100) of the core,
		move.l	d5,d0				; the middle, the rim (R^2 + R/2: rounder)
		mulu	#16,d0
		move.l	d0,.thC
		move.l	d5,d0
		mulu	#49,d0
		move.l	d0,.thM
		mulu	#100,d5
		move.w	d6,d0
		mulu	#50,d0
		add.l	d0,d5
		move.l	d5,.thR
		move.w	d6,d4
		neg.w	d4					; dy
.row:	moveq	#0,d0				; plane A, B
		moveq	#0,d1
		moveq	#-7,d3				; dx
.px:	add.l	d0,d0				; (the next pixel)
		add.l	d1,d1
		bsr		morphSqD
		mulu	#100,d2				; d^2 * 100
		cmp.l	.thC(pc),d2
		bhi.s	.p1
		addq.l	#1,d0				; core: 3
		addq.l	#1,d1
		bra.s	.pn
.p1:	cmp.l	.thM(pc),d2
		bhi.s	.p2
		addq.l	#1,d1				; middle: 2
		bra.s	.pn
.p2:	cmp.l	.thR(pc),d2
		bhi.s	.pn
		addq.l	#1,d0				; rim: 1
.pn:	addq.w	#1,d3
		cmp.w	#9,d3
		blt.s	.px
		move.w	d0,(a0)+
		move.w	d1,(a0)+
		addq.w	#1,d4
		cmp.w	d6,d4
		ble.s	.row
		addq.w	#1,d6
		dbf		d7,.sz
		; the fireball: four phases, R 1..7, rows of A0 B0 A1 B1 (the colour's
		; bits 0..3)
		lea		morphFbImg,a0
		moveq	#0,d7				; the phase
.fph:	moveq	#1,d6				; R
.fsz:	move.w	d6,d5
		mulu	d6,d5
		add.w	d6,d5				; R^2 + R
		move.w	d6,d4
		neg.w	d4
		move.w	d4,.dy
.frw:	moveq	#0,d0				; A0 (high word), B0
		moveq	#0,d1				; A1, B1
		moveq	#-7,d3				; dx
.fpx:	add.w	d0,d0				; (the next pixel, in each word)
		swap	d0
		add.w	d0,d0
		swap	d0
		add.w	d1,d1
		swap	d1
		add.w	d1,d1
		swap	d1
		move.w	.dy(pc),d4
		bsr		morphSqD
		bsr		.rnd
		move.w	d2,.d
		moveq	#15,d4				; its rim ragged: inside if d^2 * 64 <=
		and.w	morphFlRn+2,d4		; (R^2 + R) * (48 + n)
		add.w	#48,d4
		mulu	d5,d4
		lsl.w	#6,d2
		cmp.w	d4,d2
		bhi.s	.fn
		move.w	.d(pc),d2			; its colour: d^2 * 12 / (R^2 + R), a
		mulu	#12,d2				; little noise
		divu	d5,d2
		moveq	#3,d4
		and.w	morphFlRn,d4
		add.w	d4,d2
		subq.w	#1,d2
		bpl.s	.f0
		moveq	#0,d2
.f0:	cmp.w	#12,d2
		bls.s	.f1
		moveq	#12,d2
.f1:	move.b	.ramp(pc,d2.w),d2
		lsr.b	#1,d2				; bit 0: A0
		bcc.s	.b1
		bset	#16,d0
.b1:	lsr.b	#1,d2				; bit 1: B0
		bcc.s	.b2
		bset	#0,d0
.b2:	lsr.b	#1,d2				; bit 2: A1
		bcc.s	.b3
		bset	#16,d1
.b3:	lsr.b	#1,d2				; bit 3: B1
		bcc.s	.fn
		bset	#0,d1
.fn:	addq.w	#1,d3
		cmp.w	#9,d3
		blt.s	.fpx
		move.l	d0,(a0)+
		move.l	d1,(a0)+
		move.w	.dy(pc),d4
		addq.w	#1,d4
		move.w	d4,.dy
		cmp.w	d6,d4
		ble.s	.frw
		addq.w	#1,d6
		cmp.w	#MSPR_RMAX,d6
		ble.s	.fsz
		addq.w	#1,d7
		cmp.w	#4,d7
		blo		.fph
		; the tongues: four phases, R 1..7, rows of A B - ragged blobs
		; (inside if d^2 * 64 <= (R^2 + R) * (24 + 2n)), yellow, orange,
		; orange-red outwards
		lea		morphTgImg,a0
		moveq	#0,d7
.tph:	moveq	#1,d6
.tsz:	move.w	d6,d5
		mulu	d6,d5
		add.w	d6,d5
		move.w	d6,d4
		neg.w	d4
		move.w	d4,.dy
.trw:	moveq	#0,d0
		moveq	#0,d1
		moveq	#-7,d3
.tpx:	add.w	d0,d0
		add.w	d1,d1
		move.w	.dy(pc),d4
		bsr		morphSqD
		bsr		.rnd
		move.w	d2,.d
		moveq	#15,d4
		and.w	morphFlRn+2,d4
		add.w	d4,d4
		add.w	#24,d4
		mulu	d5,d4
		lsl.w	#6,d2
		cmp.w	d4,d2
		bhi.s	.tn
		move.w	.d(pc),d2
		lsl.w	#2,d2				; d^2 * 4 <= R^2 + R: the core (3)
		cmp.w	d5,d2
		bhi.s	.t2
		addq.w	#1,d0
		addq.w	#1,d1
		bra.s	.tn
.t2:	lsr.w	#1,d2				; d^2 * 2 <= R^2 + R: the middle (2)
		cmp.w	d5,d2
		bhi.s	.t3
		addq.w	#1,d1
		bra.s	.tn
.t3:	addq.w	#1,d0				; else the rim (1)
.tn:	addq.w	#1,d3
		cmp.w	#9,d3
		blt.s	.tpx
		move.w	d0,(a0)+
		move.w	d1,(a0)+
		move.w	.dy(pc),d4
		addq.w	#1,d4
		move.w	d4,.dy
		cmp.w	d6,d4
		ble.s	.trw
		addq.w	#1,d6
		cmp.w	#MSPR_RMAX,d6
		ble.s	.tsz
		addq.w	#1,d7
		cmp.w	#4,d7
		blo		.tph
		movem.l	(a7)+,d0-d7/a0
		rts
.ramp:	dc.b	15,15,14,13,12,11,10,9,8,4,3,2,1
		even
.rnd:	movem.l	d0/d1,-(a7)
		bsr		morphFlRand
		movem.l	(a7)+,d0/d1
		rts
.thC:	dc.l	0
.thM:	dc.l	0
.thR:	dc.l	0
.dy:	dc.w	0
.d:		dc.w	0

; d3 = dx, d4 = dy -> d2 = dx^2 + dy^2. keeps the rest
morphSqD:
		move.w	d3,d2
		muls	d2,d2
		move.w	d4,-(a7)
		muls	d4,d4
		add.l	d4,d2
		move.w	(a7)+,d4
		rts
