;======================================================================
; stars3d.i - the Elite ending's starfield, in bitplanes. included at the
; end of asteroids.s after morph.i (switches.i elite3).
;
; the Defender stars are sprites, four of them used again and again on
; lists - fine for a few hundred stars going sideways, but going into
; depth a sprite star needs a free place on every line it comes to, and
; it costs ~450 cycles a frame. here the stars are dots in three bitplanes
; of their own (planes 1..3, the game's lines on plane 4 in front of
; them): no places, no beam to mind, ~170 cycles a star. the planes are
; the stars' alone - seven colours by the depth, far dark blue, blue,
; violet, dark red, red, orange, near green (s3Band); the glows are
; sprites (morph.i morphSprFrame).
;
; once the warp's colour fade (warp.i, state 1) is through, EVERY
; Defender star on the screen becomes a 3D star right where it is (four
; frames, a layer each: s3Begin): its depth from its layer (half as fast
; is twice as far), and it goes on sideways at its layer's speed while
; that dies away and the flight ahead takes over (S3BLENDT frames,
; smoothstep). then the field thins out to S3NLIVE stars - all of them
; on the screen. a star's colour is its depth band's: it changes only as
; the star comes into the next band (the four layers are on bands whose
; colours the warp faded them to: nothing changes at the switch).
;
; the perspective without a multiply (learnt from Planet Rocklobster's
; starfield, done our own way): a star keeps the log of its place times
; its depth, L(|x| z0) - its x on the screen is 2^(L - L(z)): a subtraction
; and a look-up, which gives the byte and the bit straight away (s3ExpX),
; and for a star off the screen a sum below 0 (S3OFF): it flies out and
; never comes back, so a new one takes its place far off (made in
; advance: s3SpTab) - every star is one you see. L is 256 log2. the planes
; (the colour by the depth) come with L(z) in the same look-up (s3ZTab).
; the dots of two frames ago are cleared from the buffer drawn
; next (double buffered, lists of their bytes), nothing else is touched.
;
; the copper: clistElite (scroller.s) from then on - the logo stays
; clist's own part (a jump there and back), the rest has the star planes
;======================================================================

		section "code",data,chip

S3N			= 320		; stars (all the Defender's fit in: up to ~315)
S3LI		= game_lineBytes	; 46
S3ROWS		= game_height+1	; 269 (a row to spare)
S3PL		= S3ROWS*S3LI	; a plane
S3BUF		= 3*S3PL
S3MID		= (S3BUF/2)&$fffe	; (the buffers by their middle: signed offsets)
S3VX		= morphVX	; the middle of the field (game plane x, y): where we fly
S3VY		= morphVY
S3BITC		= (S3VX+1)&7	; s3ExpX's bit: -px - this (its low 3 bits the bit)
S3ZNEAR		= 36		; quarter z: nearer than this a star is past us
S3ZMAX		= 4000		; ... the furthest (new stars: up to 3973)
S3SPAN8		= (S3ZMAX-S3ZNEAR)*8
S3DB		= 2016		; the logs' range: L(x z0) - L(z) from -S3DB on ...
S3HN		= 6144		; ... S3HN steps (a half of the tables: x >= 0, x < 0)
S3HX		= S3HN*4
S3HY		= S3HN*2
S3ZFAR		= 2950		; new stars come from this far (and up to 1023 more:
						; depth)
S3BLENDT	= 110		; frames from sideways to straight ahead
S3OFF		= -$4000	; off the screen (s3ExpX's byte, s3ExpY's row): the sum < 0
S3FOLDN		= 16		; stars folded a frame at the blend's end ...
S3FOLDT		= S3BLENDT-S3N/S3FOLDN+1	; ... from this frame on
S3ZSAFE		= 224-160-4	; (the blend: till the way ahead is this far - the
						; front layer from z 224 into the green band - every
						; star is in one plane: the quicker loop)
S3ADJ		= 4			; a layer's frames on at s3Begin (the front one: the
						; three more of the conversion, then the first frame
						; of the field - drawn as they are converted)
S3K0		= 8			; s3_k: no way sideways (s3XT's last entry)
S3NLIVE		= 190		; ... once the blend is over: those that go are not all
						; made again (the field's steady number)
S3SPMAX		= 24		; new ones a frame at most (the rest the next frame)

S3SPN		= 1024		; new stars made in advance (a power of 2)

; a star: L(|x| z0) * 4 and L(|y| z0) * 2 (their signs: which half of the
; tables), z * 8 (quarter z, with s3ZTot), its way sideways (its layer * 2:
; into s3XT, S3K0 none)
				rsreset
s3_lx:			rs.w	1
s3_ly:			rs.w	1
s3_z:			rs.w	1
s3_k:			rs.w	1
s3_len:			rs.b	0

s3On::			dc.b	0		; the bitplane field runs
s3Cop::			dc.b	0		; ... and the copper shows it (clistElite)
s3Blend:		dc.b	0		; still going sideways as well
s3Buf::			dc.b	0		; which buffer is drawn (0: A)
s3Back:			dc.b	0		; clist's logo part to jump back (s3Flip)
				even
s3T:			dc.w	0		; frames since it started
s3ZTot:			dc.w	0		; the way ahead (quarter z)
s3ZAcc:			dc.w	0		; ... its fraction (1/256)
s3XS:			dc.w	0		; the front layer's way sideways (px * 16)
s3XT:			dcb.w	5,S3VX-S3BITC	; ... a layer's x of the middle with it
							; (px, - S3BITC)
s3SpI:			dc.w	0		; the next new star (s3SpTab, * 8)

s3Live:			dc.w	S3N		; stars in the field (s3Stars, from the start)
s3LastP:		dc.l	0		; ... the last one
s3BgA:			dc.l	0,0	; s3Begin -> s3Begin2: a3/a4 ...
s3BgW:			dc.w	0,0,0	; ... d3/d6/d7
s3BgE:			dc.w	0		; (s3Conv: the layer to stop at)
s3V0:			dc.w	0		; starV at the start
s3Draw::		dc.l	0		; the buffer drawn this frame (by its middle)
s3Show::		dc.l	0		; ... the one shown
s3ErN:			dc.w	0,0		; dots to clear, a buffer each
s3ErP:			dc.l	0		; (s3Begin: buffer A's list, as it fills)

s3Seed:			dc.l	$1f2e3d4b
s3Null:			dc.l	0		; (chip) a sprite that is not there
; the depth bands, near to far: up to (quarter z), the first plane (its
; offset), the more (0: none, + another so far on, - two more, S3PL apart).
; the Defender layers are on orange (the front, z 256), red (the second and
; the third, z 512, 1024) and dark blue (the back, z 2048; the new stars
; too) - the warp's colours for them (warp.i warpColF..B) - each in one
; plane: so at the blend's start (all of them about) no star has more than
; one, and s3Field draws them all the quicker (S3ZSAFE). the colours:
; scroller.s ELC1..7
S3P1		= -S3MID
S3P2		= S3PL-S3MID
S3P3		= 2*S3PL-S3MID
s3Band:	dc.w	160,S3P1,-S3PL		; green (1, 2, 3: colour 7)
		dc.w	400,S3P3,0			; orange (3: 4)
		dc.w	1160,S3P2,0			; red (2: 2)
		dc.w	1350,S3P1,2*S3PL	; dark red (1, 3: 5)
		dc.w	1550,S3P2,S3PL		; violet (2, 3: 6)
		dc.w	1750,S3P1,S3PL		; blue (1, 2: 3)
		dc.w	$7fff,S3P1,0		; dark blue (1: 1)

;---------------------------------------------
; once, at the start (morph.i morphInit): the tables
s3Init::
		movem.l	d0-d7/a0-a6,-(a7)
		; the depths: L(z) * 4, * 2 and the planes of its band (s3Band:
		; the first as an offset from the buffer's middle, then the more),
		; from S3ZNEAR on
		lea		s3ZTab,a3
		move.w	#S3ZNEAR,d7
.z:		move.w	d7,d0
		bsr		s3Log2
		add.w	d0,d0
		move.w	d0,2(a3)			; * 2
		add.w	d0,d0
		move.w	d0,(a3)				; * 4
		lea		s3Band-6,a0			; the band
.zb:	addq.l	#6,a0
		cmp.w	(a0),d7
		bhs.s	.zb
		move.l	2(a0),4(a3)
		addq.l	#8,a3
		addq.w	#1,d7
		cmp.w	#S3ZMAX,d7
		bls.s	.z
		; the screen from the logs: 2^(d/256) px either side of the middle -
		; the byte and the bit (x: the bit as -px - S3BITC, whose low 3
		; bits are the bit and which gives the blend its px), the row (y);
		; off the screen: S3OFF (x: the byte, y: the row)
		lea		s3ExpX+S3HX,a3		; (by their middles: x >= 0 below,
		lea		s3ExpY+S3HY,a4		; x < 0 above)
		moveq	#0,d7				; j
.e:		move.w	d7,d0
		sub.w	#S3DB,d0
		bsr		s3Exp				; d0 = px
		move.w	d0,d6
		move.w	d7,d5				; (the entry's place in each half)
		lsl.w	#2,d5
		move.w	#S3VX,d0			; x >= 0
		add.w	d6,d0
		bsr		.xbb
		move.w	d6,d1
		neg.w	d1
		sub.w	#S3BITC,d1
		lea		-S3HX(a3),a0
		movem.w	d0/d1,(a0,d5.w)
		move.w	#S3VX,d0			; x < 0
		sub.w	d6,d0
		bsr		.xbb
		move.w	d6,d1
		sub.w	#S3BITC,d1
		movem.w	d0/d1,(a3,d5.w)
		lsr.w	#1,d5				; y
		move.w	#S3VY,d0
		add.w	d6,d0
		bsr		.row
		lea		-S3HY(a4),a0
		move.w	d0,(a0,d5.w)
		move.w	#S3VY,d0
		sub.w	d6,d0
		bsr		.row
		move.w	d0,(a4,d5.w)
		addq.w	#1,d7
		cmp.w	#S3HN,d7
		blo		.e
		; a place on the screen (-256..255 either way) -> its code
		lea		s3CodeX,a3
		lea		s3CodeY,a4
		move.w	#-256,d7
.c:		move.w	d7,d0
		bpl.s	.c0
		neg.w	d0
.c0:	bsr		s3Log2
		add.w	#S3DB,d0
		move.w	d0,d1
		add.w	d0,d0				; * 2 (y)
		add.w	d1,d1
		add.w	d1,d1				; * 4 (x)
		tst.w	d7
		bmi.s	.c1
		sub.w	#S3HX,d1			; >= 0: the lower half
		sub.w	#S3HY,d0
.c1:	move.w	d1,(a3)+
		move.w	d0,(a4)+
		addq.w	#1,d7
		cmp.w	#256,d7
		blt.s	.c
		; the new stars far off, made now (s3Spawn takes them in turn)
		lea		s3SpTab,a3
		move.w	#S3SPN-1,d7
.sp:	bsr		s3Rand
		move.l	d0,d4				; (two numbers in one long)
		move.w	d4,d0
		mulu	#game_width,d0
		swap	d0
		sub.w	#S3VX,d0			; x
		swap	d4
		move.w	d4,d1
		mulu	#game_height,d1
		swap	d1
		sub.w	#S3VY,d1			; y
		move.w	d0,d4
		bsr		s3Rand
		move.l	d0,d5
		and.w	#1023,d0
		move.w	d0,d2
		add.w	#S3ZFAR,d2
		swap	d5					; its place drawn in towards the middle
		and.w	#127,d5				; (0.16 .. 0.65): it leaves the screen
		add.w	#40,d5				; somewhere between far and near - so
		move.w	d4,d0				; every depth has its stars
		muls	d5,d0
		asr.l	#8,d0
		muls	d5,d1
		asr.l	#8,d1
		moveq	#S3K0,d3
		bsr		s3Make				; (s3ZTot is 0: z * 8 as it is ...
		sub.w	#S3ZNEAR*8,-4(a3)	; ... from the near end: s3Field's d6)
		dbf		d7,.sp

		movem.l	(a7)+,d0-d7/a0-a6
		rts
; d0 = x on the game plane -> d0 = byte (off the screen: S3OFF)
.xbb:	cmp.w	#352,d0
		bhs.s	.xoff
		lsr.w	#3,d0
		rts
.xoff:	move.w	#S3OFF,d0
		rts
; d0 = y -> d0 = the row's offset (off the screen: S3OFF)
.row:	cmp.w	#game_height,d0
		bhs.s	.roff
		mulu	#S3LI,d0
		rts
.roff:	move.w	#S3OFF,d0
		rts

; d0 = n (0..32767) -> d0 = 256 log2 n (0: -256, as half a px). uses d1/d2/a1
s3Log2:
		tst.w	d0
		bne.s	.n
		move.w	#-256,d0
		rts
.n:		moveq	#0,d1				; the top bit
		move.w	d0,d2
.l:		lsr.w	#1,d2
		beq.s	.e
		addq.w	#1,d1
		bra.s	.l
.e:		move.w	d1,d2				; the 8 bits after it
		subq.w	#8,d2
		bmi.s	.up
		lsr.w	d2,d0
		bra.s	.m
.up:	neg.w	d2
		lsl.w	d2,d0
.m:		and.w	#255,d0
		add.w	d0,d0
		lea		s3Log2Frac,a1
		move.w	(a1,d0.w),d0
		lsl.w	#8,d1
		add.w	d1,d0
		rts

; d0 = d -> d0 = 2^(d/256), rounded (at most 9999). uses d1/d2/a1
s3Exp:
		move.w	d0,d1
		asr.w	#8,d1				; the whole part
		and.w	#255,d0
		add.w	d0,d0
		lea		s3Exp2Frac,a1
		moveq	#0,d2
		move.w	(a1,d0.w),d2		; 2^fraction, Q15
		subq.w	#7,d1				; (to 8.8)
		bmi.s	.r
		cmp.w	#14,d1
		bhi.s	.big
		lsl.l	d1,d2
		bra.s	.q
.r:		neg.w	d1
		cmp.w	#24,d1
		bhi.s	.zero
		lsr.l	d1,d2
.q:		add.l	#128,d2
		lsr.l	#8,d2
		cmp.l	#9999,d2
		bls.s	.ok
.big:	move.w	#9999,d2
.ok:	move.w	d2,d0
		rts
.zero:	moveq	#0,d0
		rts

;---------------------------------------------
; a3 = a star; d0/d1 = its place on the screen from the middle (-256..255),
; d2 = its depth (quarter z, S3ZNEAR..S3ZMAX), d3 = the shift of its way
; sideways -> the star made, a3 on to the next. keeps the rest
s3Make:
		movem.l	d0-d2/d4/a1/a2,-(a7)
		lea		s3ZTab,a2
		move.w	d2,d4
		sub.w	#S3ZNEAR,d4
		lsl.w	#3,d4
		lea		s3CodeX+512,a1
		add.w	d0,d0
		move.w	(a1,d0.w),d0
		add.w	(a2,d4.w),d0		; + L(z0) * 4
		move.w	d0,(a3)+
		lea		s3CodeY+512,a1
		add.w	d1,d1
		move.w	(a1,d1.w),d1
		add.w	2(a2,d4.w),d1		; + L(z0) * 2
		move.w	d1,(a3)+
		add.w	s3ZTot,d2
		lsl.w	#3,d2
		move.w	d2,(a3)+
		move.w	d3,(a3)+
		movem.l	(a7)+,d0-d2/d4/a1/a2
		rts

; a3 = a star: a new one, far off, somewhere on the screen (the next one
; of s3SpTab). a3 on to the next. uses d0/d1
s3Spawn:
		move.l	a0,-(a7)
		move.w	s3SpI,d0
		addq.w	#s3_len,d0
		and.w	#(S3SPN-1)*s3_len,d0
		move.w	d0,s3SpI
		lea		s3SpTab,a0
		add.w	d0,a0
		move.l	(a0)+,(a3)+			; its logs and depth (warpPark, the
		move.w	(a0),d0				; sprite field's cost limit, is not
		move.w	s3ZTot,d1			; needed here: S3NLIVE is)
		add.w	#S3ZNEAR,d1
		lsl.w	#3,d1
		add.w	d1,d0
		move.w	d0,(a3)+
		move.w	#S3K0,(a3)+
		move.l	(a7)+,a0
		rts

;---------------------------------------------
; the end of the warp's colour fade (warp.i): every Defender star on the
; screen becomes a 3D star right there; the field's other places come from
; far off. four frames (the time it takes), a layer each, the front one
; first: from where it will be in the last of them (its way sideways
; added), the far ones with the back layer (s3Begin2). the sprites still
; show in all of them; the frame after them draws the field and puts the
; copper over to it
s3Begin::
		movem.l	d0-d7/a0-a6,-(a7)
		clr.w	s3T
		clr.w	s3ZTot
		clr.w	s3ZAcc
		clr.w	s3XS
		move.w	starV,s3V0
		clr.l	s3ErN
		move.l	#s3Er0,s3ErP
		move.w	#S3N,s3Live
		move.l	#s3Stars+(S3N-1)*s3_len,s3LastP
		sf		s3Buf
		move.l	#s3BufA+S3MID,s3Draw
		move.l	#s3BufB+S3MID,s3Show
		lea		s3XT,a0
		moveq	#5-1,d0
.xt:	move.w	#S3VX-S3BITC,(a0)+
		dbf		d0,.xt
		lea		s3Stars,a3
		move.w	#S3N,d7				; places left
		lea		slst0,a4
		moveq	#0,d6				; the layer (= the list)
		move.w	s3Seed,d3			; (a Weyl sequence: the depths' spread)
		bra.s	s3Bg
; ... and the next frames (warp.i, state 4): the other layers
s3Begin2::
		movem.l	d0-d7/a0-a6,-(a7)
		move.l	s3BgA,a3
		move.l	s3BgA+4,a4
		movem.w	s3BgW,d3/d6/d7
s3Bg:	moveq	#S3ADJ,d4			; (the frames to the field's first)
		sub.w	d6,d4
		move.l	a3,-(a7)
		bsr.s	s3Conv
		move.l	(a7)+,a1			; (their dots into the field's first
		bsr		s3Dots				; frame)
		move.l	a3,s3BgA
		move.l	a4,s3BgA+4
		movem.w	d3/d6/d7,s3BgW
		cmp.w	#4,d6
		beq.s	.full
		move.b	#4,warpState
		movem.l	(a7)+,d0-d7/a0-a6
		rts
		move.l	a3,a1
.full:	subq.w	#1,d7				; the other places: far off
		bmi.s	.done
		bsr		s3Spawn
		bra.s	.full
.done:	bsr		s3Dots
		move.l	s3ErP,d0			; the field's first frame is drawn (buffer
		sub.l	#s3Er0,d0			; A): shown from the next frame on, right
		lsr.w	#1,d0				; after the sprites' last (this one) - the
		move.w	d0,s3ErN			; copper changes over at the frame's edge
		bsr		s3Activate
		st		s3On
		st		s3Blend
		move.b	#3,warpState
		movem.l	(a7)+,d0-d7/a0-a6
		rts

; the sprite stars of a list into 3D stars. a3 = the next star, a4 = the
; list, d6 = its layer, d7 = places left, d3 = the Weyl sequence, d4 = the
; frames on (their way sideways added) -> a3/a4/d3/d6/d7 on
s3Conv:
		lea		s3CodeX+512,a0
		lea		s3CodeY+512,a1
		lea		s3ZTab-S3ZNEAR*8,a2
		move.w	d6,d0
		addq.w	#1,d0
		move.w	d0,s3BgE			; (the layer to stop at)
.list:	move.w	#stars_count-1,d5
		move.w	starV,d2			; a frame's way: starV >> (8 + layer) px
		muls	d4,d2
		moveq	#8,d0
		add.w	d6,d0
		asr.l	d0,d2
		move.w	d2,a5
.ent:	tst.w	d7
		beq.s	.out
		tst.l	4(a4)				; a star at all?
		beq.s	.next
		moveq	#0,d0				; x: HSTART << 1 | H0, on the game plane:
								; (the dot is the data's last bit, 15 on)
		move.b	1(a4),d0
		add.w	d0,d0
		moveq	#1,d1
		and.b	3(a4),d1
		or.w	d1,d0
		sub.w	#97-15-1,d0
		add.w	a5,d0
		cmp.w	#game_width,d0
		bhs.s	.next
		moveq	#0,d1				; y: VSTART (its bit 8 in the CTL byte)
		move.b	(a4),d1
		btst	#2,3(a4)
		beq.s	.y8
		bset	#8,d1
.y8:	sub.w	#$20,d1
		cmp.w	#game_height,d1
		bhs.s	.next
		sub.w	#S3VX,d0
		sub.w	#S3VY,d1
		add.w	#$9e37,d3			; depth: 256 << layer (quarter z), give
		move.w	d3,d2				; or take an eighth
		asr.w	#8,d2
		asr.w	#2,d2
		add.w	#256,d2
		lsl.w	d6,d2
		lsl.w	#3,d2				; the star (s3Make, s3ZTot 0)
		add.w	d0,d0
		move.w	(a0,d0.w),d0
		add.w	(a2,d2.w),d0		; + L(z0) * 4
		move.w	d0,(a3)+
		add.w	d1,d1
		move.w	(a1,d1.w),d1
		add.w	2(a2,d2.w),d1		; + L(z0) * 2
		move.w	d1,(a3)+
		move.w	d2,(a3)+
		move.w	d6,d0				; its way sideways: the front layer's
		add.w	d0,d0				; >> layer (s3XT)
		move.w	d0,(a3)+
		subq.w	#1,d7
.next:	addq.l	#8,a4
		dbf		d5,.ent
		addq.l	#4,a4				; (the list's end)
		addq.w	#1,d6
		cmp.w	s3BgE,d6
		blo.s	.list
		rts
.out:	move.w	s3BgE,d6			; (all places taken: the layer done)
		rts

;---------------------------------------------
; updateStars (warp.i warpStep) comes here once s3On: the field, a frame
s3Field::
		movem.l	d2-d7/a2-a6,-(a7)
		tst.b	s3Cop
		beq.s	.nm
		bsr		s3MidPatch			; (the planes below the logo)
.nm:	; the blend: a 0..256 (smoothstep) from sideways to ahead
		addq.w	#1,s3T
		move.w	#256,d5
		tst.b	s3Blend
		beq		.ahead
.bl:	move.w	s3T,d0
		mulu	#256,d0
		divu	#S3BLENDT,d0
		cmp.w	#256,d0
		bls.s	.u
		move.w	#256,d0
.u:		move.w	d0,d1
		mulu	d1,d1				; u^2 (16 bits)
		add.w	d0,d0
		neg.w	d0
		add.w	#768,d0				; 3 - 2u
		mulu	d0,d1
		swap	d1					; (u^2 (3-2u)) >> 16
		move.w	d1,d5
		; sideways: the front layer moves starV/16 px*16 a frame, times 1-a
		move.w	#256,d0
		sub.w	d5,d0
		muls	s3V0,d0
		asr.l	#8,d0
		asr.l	#4,d0
		add.w	s3XS,d0
		move.w	d0,s3XS
		lea		s3XT,a0				; ... a layer's: >> 4 + layer
		moveq	#4,d1
.xt:	move.w	d0,d2
		asr.w	d1,d2
		add.w	#S3VX-S3BITC,d2
		move.w	d2,(a0)+
		addq.w	#1,d1
		cmp.w	#8,d1
		blo.s	.xt
.ahead:	; ahead: warpVzNow (morph.i) times a, quarter z with a fraction
		move.w	d5,d0
		mulu	warpVzNow,d0
		lsr.l	#8,d0
		add.w	s3ZAcc,d0
		move.w	d0,d1
		lsr.w	#8,d1
		add.w	d1,s3ZTot
		and.w	#$ff,d0
		move.w	d0,s3ZAcc
		; the buffer drawn now: its dots of two frames ago off
		move.l	s3Draw,a0
		lea		s3Er0,a4
		lea		s3ErN,a1
		tst.b	s3Buf
		beq.s	.b0
		lea		s3Er1,a4
		addq.l	#2,a1
.b0:	move.l	a1,-(a7)
		move.w	(a1),d0
		move.l	a4,a1
		add.w	d0,d0				; (into the run below: 6 bytes a dot)
		move.w	d0,d1
		add.w	d0,d0
		add.w	d1,d0
		lea		.er9,a2
		sub.w	d0,a2
		jmp		(a2)
	rept	3*S3N
		move.w	(a1)+,d0
		clr.b	0(a0,d0.w)
	endr
.er9:
		; the stars
		lea		s3Stars,a3
		lea		s3ZTab,a2
		lea		s3ExpY+S3HY,a6
		move.w	s3ZTot,d6
		add.w	#S3ZNEAR,d6
		lsl.w	#3,d6
		tst.b	s3Blend
		bne		.blend
		lea		s3ExpX+S3HX,a5
		move.w	#S3SPMAX,d7			; (new ones this frame at most: d7's
		swap	d7					; high word)
		move.w	s3Live,d7
		subq.w	#1,d7
		lea		s3SpTab,a1			; (... and the next of them)
		add.w	s3SpI,a1
.s:		movem.w	(a3)+,d0-d3			; L(x z0)*4, L(y z0)*2, z*8, (shift)
		sub.w	d6,d2
		cmp.w	#S3SPAN8,d2
		bhi.s	.edge
		movem.w	(a2,d2.w),d2-d5		; L(z)*4, L(z)*2, its band's planes
		sub.w	d2,d0
		sub.w	d3,d1
		movem.w	(a5,d0.w),d2/d3		; byte, bit
		add.w	(a6,d1.w),d2		; + row
		bmi.s	.off				; (off the screen: it will not come back)
		add.w	d4,d2				; + the (first) plane
		bset	d3,(a0,d2.w)
		move.w	d2,(a4)+
		tst.w	d5					; (its band's colour in more planes)
		bne.s	.more
.n:		dbf		d7,.s
		sub.l	#s3SpTab,a1
		move.w	a1,s3SpI
		bra		.done
.more:	bmi.s	.m3
		add.w	d5,d2				; one more
		bset	d3,(a0,d2.w)
		move.w	d2,(a4)+
		bra.s	.n
.m3:	add.w	#S3PL,d2			; two more (all three)
		bset	d3,(a0,d2.w)
		move.w	d2,(a4)+
		add.w	#S3PL,d2
		bset	d3,(a0,d2.w)
		move.w	d2,(a4)+
		bra.s	.n
.edge:	tst.w	d2					; past us, or still to come (parked
		bpl.s	.n					; further off)
.off:	lea		-s3_len(a3),a3		; gone: more than S3NLIVE, the last one
		cmp.w	#S3NLIVE,s3Live	; takes its place, else a new one far off
		bhi.s	.kill
		sub.l	#$10000,d7
		bmi.s	.late
		cmp.l	#s3SpTab+S3SPN*s3_len,a1	; (s3Spawn, here)
		blo.s	.sp
		lea		s3SpTab,a1
.sp:	move.l	(a1)+,(a3)+
		move.w	(a1)+,d0
		add.w	d6,d0
		move.w	d0,(a3)+
		move.w	(a1)+,(a3)+
		bra.s	.n
.late:	addq.l	#s3_len,a3			; (next frame)
		bra.s	.n
.kill:	subq.w	#1,s3Live
		tst.w	d7
		bne.s	.k1
		subq.l	#s3_len,s3LastP	; (it was the last one)
		bra.s	.n
.k1:		move.l	a2,-(a7)
		move.l	s3LastP,a2
		move.l	(a2)+,(a3)
		move.l	(a2),4(a3)
		lea		-12(a2),a2
		move.l	a2,s3LastP
		move.l	(a7)+,a2
		subq.w	#1,d7				; (one less, and this one now)
		bra		.s
		; --- while it still goes sideways: the px, its way sideways added
.blend:	lea		s3ExpX+S3HX,a5
		lea		s3XT,a1
		move.w	s3Live,d7
		subq.w	#1,d7
		cmp.w	#S3ZSAFE,s3ZTot		; (at first all in one plane: quicker)
		blo		.cs
.bs:	movem.w	(a3)+,d0-d2/d4		; (d4: its way sideways, into s3XT)
		sub.w	d6,d2
		cmp.w	#S3SPAN8,d2
		bhi.s	.bedge
		sub.w	(a2,d2.w),d0		; L(z)*4
		move.w	(a1,d4.w),d4		; the middle, its way sideways with it
		sub.w	2(a5,d0.w),d4		; + px from the middle (-(-px - S3BITC))
		cmp.w	#game_width,d4
		bhs.s	.boff				; (gone: a new one far off)
		movem.w	2(a2,d2.w),d0/d3/d5	; L(z)*2, its band's planes
		sub.w	d0,d1
		move.w	(a6,d1.w),d1		; the row
		bmi.s	.boff
		add.w	d3,d1				; + the (first) plane
		move.w	d4,d0
		lsr.w	#3,d0
		add.w	d0,d1
		not.w	d4
		bset	d4,(a0,d1.w)
		move.w	d1,(a4)+
		tst.w	d5
		bne.s	.bmore
.bn:	dbf		d7,.bs
		bra.s	.bend
.bmore:	bmi.s	.bm3
		add.w	d5,d1
		bset	d4,(a0,d1.w)
		move.w	d1,(a4)+
		bra.s	.bn
.bm3:	add.w	#S3PL,d1
		bset	d4,(a0,d1.w)
		move.w	d1,(a4)+
		add.w	#S3PL,d1
		bset	d4,(a0,d1.w)
		move.w	d1,(a4)+
		bra.s	.bn
.bend:	bra		.bfold
		; --- ... the same, while every star is in one plane (S3ZSAFE)
.cs:	movem.w	(a3)+,d0-d2/d4		; (d4: its way sideways, into s3XT)
		sub.w	d6,d2
		cmp.w	#S3SPAN8,d2
		bhi.s	.cedge
		movem.w	(a2,d2.w),d2/d3/d5	; L(z)*4, L(z)*2, its plane
		sub.w	d2,d0
		sub.w	d3,d1
		move.w	(a1,d4.w),d2		; the middle, its way sideways with it
		sub.w	2(a5,d0.w),d2		; + px from the middle
		cmp.w	#game_width,d2
		bhs.s	.coff
		move.w	(a6,d1.w),d1		; the row
		bmi.s	.coff
		add.w	d5,d1				; + the plane
		move.w	d2,d0
		lsr.w	#3,d2
		add.w	d2,d1
		not.w	d0
		bset	d0,(a0,d1.w)
		move.w	d1,(a4)+
.cn:	dbf		d7,.cs
		bra.s	.bfold
.cedge:	tst.w	d2
		bpl.s	.cn
.coff:	lea		-s3_len(a3),a3		; gone: as in .boff
		cmp.w	#S3NLIVE,s3Live
		bls.s	.csp
		cmp.w	#S3FOLDT,s3T
		bhs.s	.csp
		subq.w	#1,s3Live
		tst.w	d7
		bne.s	.ck1
		subq.l	#s3_len,s3LastP
		bra.s	.cn
.ck1:	move.l	a2,-(a7)
		move.l	s3LastP,a2
		move.l	(a2)+,(a3)
		move.l	(a2),4(a3)
		lea		-12(a2),a2
		move.l	a2,s3LastP
		move.l	(a7)+,a2
		subq.w	#1,d7
		bra		.cs
.csp:	bsr		s3Spawn
		bra		.cn
.bfold:		; its last frames (it hardly goes sideways any more): their ways
		; sideways go into their places, S3FOLDN stars a frame
		move.w	s3T,d0
		sub.w	#S3FOLDT,d0
		blo.s	.done
		bsr		s3Fold
		cmp.w	#S3BLENDT,s3T
		blo.s	.done
		sf		s3Blend
		bra.s	.done
.bedge:	tst.w	d2
		bpl.s	.bn
.boff:	lea		-s3_len(a3),a3		; gone: as above (but not once the folds
		cmp.w	#S3NLIVE,s3Live	; have begun: a star moved would miss its
		bls.s	.bsp				; fold)
		cmp.w	#S3FOLDT,s3T
		bhs.s	.bsp
		subq.w	#1,s3Live
		tst.w	d7
		bne.s	.bk1
		subq.l	#s3_len,s3LastP
		bra.s	.bn
.bk1:	move.l	a2,-(a7)
		move.l	s3LastP,a2
		move.l	(a2)+,(a3)
		move.l	(a2),4(a3)
		lea		-12(a2),a2
		move.l	a2,s3LastP
		move.l	(a7)+,a2
		subq.w	#1,d7
		bra		.bs
.bsp:	bsr		s3Spawn
		bra		.bn
.done:	move.l	a4,d0				; the dots to clear next time
		move.l	s3Draw,a0
		lea		s3Er0,a1
		tst.b	s3Buf
		beq.s	.d0
		lea		s3Er1,a1
.d0:	sub.l	a1,d0
		lsr.w	#1,d0
		move.l	(a7)+,a1
		move.w	d0,(a1)
		tst.b	s3Cop				; the first frame: the copper over to it
		bne.s	.out
		bsr		s3Activate
.out:	movem.l	(a7)+,d2-d7/a2-a6
		rts

; a1 = the first star just made, a3 = right after the last (s3Begin:
; s3ZTot 0, nothing sideways yet): their dots into buffer A, the field's
; first frame (their bytes onto s3Er0 at s3ErP), as s3Field draws them.
; keeps all
s3Dots:
		movem.l	d0-d5/a0-a2/a4-a6,-(a7)
		lea		s3ZTab,a2
		lea		s3ExpX+S3HX,a5
		lea		s3ExpY+S3HY,a6
		lea		s3BufA+S3MID,a0
		move.l	s3ErP,a4
.l:		cmp.l	a3,a1
		bhs.s	.e
		movem.w	(a1)+,d0-d3			; L(x z0)*4, L(y z0)*2, z*8, (shift)
		sub.w	#S3ZNEAR*8,d2
		cmp.w	#S3SPAN8,d2
		bhi.s	.l
		movem.w	(a2,d2.w),d2-d5		; L(z)*4, L(z)*2, its band's planes
		sub.w	d2,d0
		sub.w	d3,d1
		movem.w	(a5,d0.w),d2/d3		; byte, bit
		add.w	(a6,d1.w),d2		; + row
		bmi.s	.l
		add.w	d4,d2				; + the (first) plane
		bset	d3,(a0,d2.w)
		move.w	d2,(a4)+
		tst.w	d5
		beq.s	.l
		bmi.s	.t
		add.w	d5,d2
		bset	d3,(a0,d2.w)
		move.w	d2,(a4)+
		bra.s	.l
.t:		add.w	#S3PL,d2
		bset	d3,(a0,d2.w)
		move.w	d2,(a4)+
		add.w	#S3PL,d2
		bset	d3,(a0,d2.w)
		move.w	d2,(a4)+
		bra.s	.l
.e:		move.l	a4,s3ErP
		movem.l	(a7)+,d0-d5/a0-a2/a4-a6
		rts
; the blend's end: a star's way sideways into its place (its log), from
; where it is now on the screen. d0 = the chunk (S3FOLDN stars), d6 = the
; near end (s3Field); a2/a5 as there
s3Fold:
		lsl.w	#3+3+1,d0			; (* S3FOLDN * s3_len)
		lea		s3Stars,a3
		add.w	d0,a3
		lea		s3XT,a1
		lea		s3CodeX+512,a0
		moveq	#S3FOLDN-1,d7
.f:		movem.w	(a3),d0-d3
		cmp.w	#S3K0,d3
		beq.s	.n					; (no way sideways)
		sub.w	d6,d2
		cmp.w	#S3SPAN8,d2
		bhi.s	.n
		move.w	d2,d4
		move.w	(a2,d2.w),d2
		sub.w	d2,d0
		move.w	(a1,d3.w),d3		; px now, with its way sideways (as in
		sub.w	2(a5,d0.w),d3		; s3Field's blend)
		move.w	d3,d0
		sub.w	#S3VX,d0
		cmp.w	#-256,d0
		bge.s	.f0
		move.w	#-256,d0
.f0:	cmp.w	#255,d0
		ble.s	.f1
		move.w	#255,d0
.f1:	add.w	d0,d0
		move.w	(a0,d0.w),d0		; L(x z) ...
		add.w	(a2,d4.w),d0		; ... as if made at this depth
		move.w	d0,(a3)
		move.w	#S3K0,6(a3)
.n:		addq.l	#s3_len,a3
		dbf		d7,.f
		rts

; clearScroller (the start of the frame): the buffer drawn last frame is
; shown now - into clistElite's top, the game's plane 4 with it
s3Flip::
		movem.l	d0-d1/a0,-(a7)
		move.l	s3Draw,d0
		move.l	s3Show,s3Draw
		move.l	d0,s3Show
		not.b	s3Buf
		tst.b	s3Back				; the first frame of clistElite: clist's
		beq.s	.nb					; logo part jumps back to it now (not
		sf		s3Back				; before: clist still ran last frame)
		move.l	d0,-(a7)
		lea		logoEndWait+4,a0
		move.l	#eliteMid,d0
		move.w	#$0084,(a0)+
		swap	d0
		move.w	d0,(a0)+
		move.w	#$0086,(a0)+
		swap	d0
		move.w	d0,(a0)+
		move.w	#$008a,(a0)+
		clr.w	(a0)+
		move.l	(a7)+,d0
.nb:
		sub.l	#S3MID,d0
		lea		elTop,a0
		bsr.s	s3Planes
		move.l	screenloc,d0		; the game's buffer shown: the one not
		cmp.l	#bufA,d0			; drawn
		beq.s	.b
		move.l	#bufA,d0
		bra.s	.g
.b:		move.l	#bufB,d0
.g:		move.w	d0,30(a0)
		swap	d0
		move.w	d0,26(a0)
		movem.l	(a7)+,d0-d1/a0
		rts
; d0 = plane 1's line, a0 = the copper's pointer moves: planes 1..3
s3Planes:
		moveq	#3-1,d1
.p:		move.w	d0,6(a0)
		swap	d0
		move.w	d0,2(a0)
		swap	d0
		add.l	#S3PL,d0
		addq.l	#8,a0
		dbf		d1,.p
		lea		-24(a0),a0
		rts

; the star planes again right below the logo (where it ends this frame)
s3MidPatch:
		movem.l	d0-d1/a0,-(a7)
		moveq	#0,d0
		move.b	logoEndWait,d0		; (the wait's line: the moves are in before
								; its first fetch)
		sub.w	#$20,d0
		mulu	#S3LI,d0
		add.l	s3Show,d0
		sub.l	#S3MID,d0
		lea		eliteMid,a0
		bsr.s	s3Planes
		movem.l	(a7)+,d0-d1/a0
		rts

; the first frame drawn: the copper over to clistElite from the next
; frame on (and clist's logo part jumps back there)
s3Activate:
		movem.l	d0-d1/a0,-(a7)
		lea		elSpr,a0			; no sprites
		move.l	#s3Null,d0
		moveq	#8-1,d1
.sp:	move.w	d0,6(a0)
		swap	d0
		move.w	d0,2(a0)
		swap	d0
		addq.l	#8,a0
		dbf		d1,.sp
	ifne	sprTest
		bsr		s3SprTest
	endc
		move.l	#logoStartWait,d0	; into clist for the logo ...
		move.w	d0,elJmpL
		swap	d0
		move.w	d0,elJmpH
		st		s3Back				; ... and back after it: s3Flip
		move.l	s3Draw,d0			; (shown from the next frame: as s3Flip
		sub.l	#S3MID,d0			; will have it)
		lea		elTop,a0
		bsr		s3Planes
		move.l	#clistElite,$dff080
		st		s3Cop
		movem.l	(a7)+,d0-d1/a0
		rts

	ifne	sprTest
; the sprite test (switches.i sprTest): all eight sprites as tall bars from
; the top (over the logo) down, 40 px apart - an even sprite's pattern
; leans one way, an odd one's the other, each pair its own colours, a
; white line every 16 rows. which come out clean shows in WinUAE
SPRT_H		= 236
s3SprTest:
		movem.l	d0-d7/a0-a2,-(a7)
		lea		s3SprT,a0
		lea		elSpr,a1
		moveq	#0,d7
.s:		move.l	a0,d0
		move.w	d0,6(a1)
		swap	d0
		move.w	d0,2(a1)
		addq.l	#8,a1
		move.w	d7,d0				; HSTART: x 16 + 40 i, + 96
		mulu	#40,d0
		add.w	#16+96,d0
		move.w	#$24,d1				; VSTART (row 4), VSTOP
		move.w	#$24+SPRT_H,d2
		move.w	d1,d3
		lsl.w	#8,d3
		move.w	d0,d4
		lsr.w	#1,d4
		move.b	d4,d3
		move.w	d3,(a0)+
		move.w	d2,d3
		lsl.w	#8,d3
		btst	#8,d2
		beq.s	.c1
		bset	#1,d3
.c1:	btst	#0,d0
		beq.s	.c2
		bset	#0,d3
.c2:	move.w	d3,(a0)+
		moveq	#0,d6				; the rows
.r:		moveq	#15,d0
		and.w	d6,d0
		bne.s	.r1
		move.l	#$ffffffff,(a0)+	; (a line: colour 3)
		bra.s	.r2
.r1:	move.l	#$ff00f0f0,(a0)+
		btst	#0,d7
		beq.s	.r2
		move.l	#$00ff0f0f,-4(a0)
.r2:	addq.w	#1,d6
		cmp.w	#SPRT_H,d6
		blo.s	.r
		clr.l	(a0)+
		addq.w	#1,d7
		cmp.w	#8,d7
		blo.s	.s
		lea		.col(pc),a0			; the colours 17..31
		lea		elSprCol+2,a1
		moveq	#15-1,d0
.c:		move.w	(a0)+,(a1)
		addq.l	#4,a1
		dbf		d0,.c
		movem.l	(a7)+,d0-d7/a0-a2
		rts
.col:	dc.w	$0f00,$00f0,$0fff,0,$0ff0,$00ff,$0fff,0
		dc.w	$0f80,$080f,$0fff,0,$0f0f,$08f8,$0fff
	endc

; -> d0 = a random long (xorshift). keeps the rest
s3Rand:
		move.l	d1,-(a7)
		move.l	s3Seed,d0
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
		move.l	d0,s3Seed
		move.l	(a7)+,d1
		rts

		include	"s3tabs.i"

		section "s3chip",bss_c
s3BufA:		ds.b	S3BUF
s3BufB:		ds.b	S3BUF
	ifne	sprTest
s3SprT:		ds.b	8*(4+SPRT_H*4+4)	; (s3SprTest) the eight bars
	endc

		section "s3bss",bss
s3ZTab:		ds.b	(S3ZMAX-S3ZNEAR+1)*8
s3ExpX:		ds.b	2*S3HX
s3ExpY:		ds.b	2*S3HY
s3CodeX:	ds.w	512
s3CodeY:	ds.w	512
s3Stars:	ds.b	S3N*s3_len
s3SpTab:	ds.b	S3SPN*s3_len
s3Er0:		ds.w	3*S3N	; (a dot in up to three planes)
s3Er1:		ds.w	3*S3N


