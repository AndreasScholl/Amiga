;======================================================================
; morph.i - the Elite ending: "Elite Attack". included at the end of
; asteroids.s, switched by switches.i elite3.
;
; the world changes from Asteroids (a tiny ship seen from above, very far
; off) to Elite (endless space, mighty sizes), and the scale is told by
; speeds: the stars, which are endlessly far, rush by faster and faster,
; while the fighter - huge, and flying the same way as we do - grows only
; slowly as we catch up with it.
;
;   UNFOLD  the Defender ship, small and far off, unfolds into the Quadlite
;           Thrust fighter in 3D lines (16 points, from the flat arrow;
;           part by part with a smoothstep, new lines glow; towards the
;           end the back lines go - backface culling)
;   HOLD    it settles; the stars start to go into depth (warp.i)
;   TURN    it turns into our way, its tail to us (the engine plate)
;   CHASE   we pick up speed - the stars faster and faster - and catch up
;           with it, slowly: on the way the pilot (Zeronine) gets ready
;           for the attack: banks to and fro, weaves, a roll. we overtake
;           it on its right: it goes past us on the left
;   LOOP    it is behind us, flying a loop (unseen)
;   ATTACK  and thunders past us on the right, away towards the logo - a
;           station of galactic size - and fires its torpedoes on the way;
;           they take a long while to get there (the hits: later)
;
; the ship is a body in the world: its middle (morphSX/SY/SZ, 1/16 units,
; ahead of the eye), turned by roll/pitch/yaw/tilt; a point on the screen
; is the stars' middle + (S + p) * lens / (SZ - z) - the same perspective
; as the stars'. no 2D tricks.
;
; obj_move comes here for the ship while morphOn is set: a0 the ship, a5
; yOffTab, a6 the draw table. the ship's lines go into morphCache and the
; table gets a pointer to them; they are built only when something has
; changed, and while it moves, over two frames (points, then lines)
;======================================================================

		section "code",data,chip

morphLen	= 168		; frames from the flat arrow to the fighter
morphCull	= 134		; frames: from here on the back lines are hidden
morphGlow	= 6			; frames a part's lines glow either side of its end
morphRoll	= 46		; degrees the ship rolls over (its right wing up)
morphPitch	= 13		; degrees its nose dips (we see the engine plate)
morphHoldT	= 50		; frames the fighter waits (still) before it turns
morphTurnT	= 110		; frames it takes to turn into our way
morphChaseT	= 400		; frames of the chase (we catch up and overtake)
morphZPass	= 40*16		; ... where it would be at its end (1/16 units):
						; by then it is past us (off the screen) already
morphBank	= 22		; degrees it banks to and fro meanwhile
morphChaseTilt = -20	; degrees its nose down (we are a little above it)
morphWeave	= 6*16		; 1/16 units it weaves sideways
morphRollAt	= 200		; frames into the chase: the roll ...
morphRollT	= 56		; ... takes this long
morphLoopT	= 150		; frames it is behind us (its loop)
morphAtkT	= 190		; frames of its attack run
morphAtkX	= 80*16		; it passes us this far to the right (1/16 units),
morphAtkY	= 48*16		; ... below (and so on the line to the logo)
morphAtkZ0	= -40*16	; ... coming from behind us,
morphAtkPassT = 70		; frames of its pass beside us ...
morphAtkZ1	= 250*16	; ... at the end of which it is this far ahead,
morphAtkGo	= 3300*16	; ... then the burn: this much further by the end
morphAtkTilt = 17		; degrees: its nose up, at the logo
morphAtkRoll = -60		; ... coming out of the loop banked
morphLogoY	= 46		; the logo (screen y): where it all goes
morphTorpN	= 3			; torpedoes
morphTorpAt	= 45		; frames into the run: the first one, ...
morphTorpGap = 10		; ... then one every this many frames
morphTorpV	= 52*16		; their speed ahead (1/16 units a frame)
morphTorpR	= 8*16		; their size (radius, 1/16 units)
morphTorpEnd = 8000*16	; ... gone this far off (on the logo, as a spark)
morphZ0		= 1024*16	; the ship's depth (1/16 units) - far off
morphF		= 288		; the lens: 0.28 px a unit at morphZ0 (the fighter
						; 72 units long: 20 px, twice the Asteroids ship)
morphG0		= 131		; 8.8: the arrow at the start (the game's size)
morphVX		= 160		; the stars' middle (warp.i warpCx/warpCy): where
morphVY		= 134		; we fly to
morphVzMax	= 10		; the stars at the end of the chase: this many times
						; as fast as at the start
morphVzEnd	= 3			; ... and after the attack run
morphParkZ	= 200		; new stars this much further off for each step of speed
morphPark0	= 400		; ... and from the chase on this much anyway
morphFar	= 220*16	; (the chase) further off than this: a picture in three
						; frames (it is small), nearer: in two
morphNP		= 16		; points
morphNE		= 23		; edges
morphNF		= 9			; faces

MP_UNFOLD	= 0
MP_HOLD		= 1
MP_TURN		= 2
MP_CHASE	= 3
MP_LOOP		= 4
MP_ATTACK	= 5
MP_GONE		= 6

; the parts: start frame, frames to unfold
morphParts:	dc.w	0,46			; 0 the arrow grows
			dc.w	36,46			; 1 the hull opens, the ship rolls
			dc.w	76,46			; 2 the wing guns
			dc.w	99,46			; 3 the canopy
			dc.w	122,46			; 4 the engine plate

; a point: start (on the arrow), end (the fighter) - x forward, y towards
; the right wing (down on the screen), z up - and its part
MPT		macro
		dc.w	\1,\2,\3,(\4)-(\1),(\5)-(\2),(\6)-(\3),\7
		endm
morphPts:
		MPT		28,0,0,40,0,0,0				; 0 nose
		MPT		-14,0,0,-24,-12,9,1			; 1 back, top left
		MPT		-14,0,0,-24,12,9,1			; 2 back, top right
		MPT		-14,0,0,-24,-12,-6,1		; 3 back, bottom left
		MPT		-14,0,0,-24,12,-6,1			; 4 back, bottom right
		MPT		-35,-28,0,-32,-38,0,0		; 5 wing tip left
		MPT		-35,28,0,-32,38,0,0			; 6 wing tip right
		MPT		-14,0,0,-24,-7,5,4			; 7 engine plate
		MPT		-14,0,0,-24,7,5,4			; 8
		MPT		-14,0,0,-24,7,-2,4			; 9
		MPT		-14,0,0,-24,-7,-2,4			; 10
		MPT		8,0,0,16,0,6,3				; 11 canopy front
		MPT		-6,0,0,-6,-6,13,3			; 12 canopy back left
		MPT		-6,0,0,-6,6,13,3			; 13 canopy back right
		MPT		-35,-28,0,-6,-38,0,2		; 14 gun left
		MPT		-35,28,0,-6,38,0,2			; 15 gun right
mp_len	= 14

; an edge: two points (as offsets into morphXY), the two faces it is on
; (-1 none), its part, and whether it is one of the arrow's own lines
MED		macro
		dc.b	(\1)*4,(\2)*4,\3,\4,\5,\6
		endm
morphEdges:
		MED		0,1,0,1,1,0
		MED		0,2,0,2,1,0
		MED		0,3,3,4,1,0
		MED		0,4,3,5,1,0
		MED		0,5,1,4,0,1
		MED		0,6,2,5,0,1
		MED		1,2,0,6,1,0
		MED		3,4,3,6,1,0
		MED		1,3,6,7,1,0
		MED		2,4,6,8,1,0
		MED		1,5,1,7,1,1
		MED		3,5,4,7,1,0
		MED		2,6,2,8,1,1
		MED		4,6,5,8,1,0
		MED		7,8,6,-1,4,0
		MED		8,9,6,-1,4,0
		MED		9,10,6,-1,4,0
		MED		10,7,6,-1,4,0
		MED		11,12,0,-1,3,0
		MED		11,13,0,-1,3,0
		MED		12,13,0,-1,3,0
		MED		5,14,1,4,2,0
		MED		6,15,2,5,2,0
me_len	= 6
; the same edges: their faces as bits (all of them: on no face, always)
morphEM:
		dc.w	$0003,$0005,$0018,$0028,$0012,$0024,$0041,$0048
		dc.w	$00c0,$0140,$0082,$0090,$0104,$0120
		dc.w	$0040,$0040,$0040,$0040,$0001,$0001,$0001
		dc.w	$0012,$0024

; a face: three of its corners, counter-clockwise seen from outside
morphFaces:
		dc.b	0*4,2*4,1*4			; 0 top
		dc.b	0*4,1*4,5*4			; 1 top left
		dc.b	0*4,6*4,2*4			; 2 top right
		dc.b	0*4,3*4,4*4			; 3 bottom
		dc.b	0*4,5*4,3*4			; 4 bottom left
		dc.b	0*4,4*4,6*4			; 5 bottom right
		dc.b	1*4,2*4,4*4			; 6 back
		dc.b	1*4,3*4,5*4			; 7 back left
		dc.b	2*4,6*4,4*4			; 8 back right
		even

; smoothstep, 0..64 -> 0..256
morphSmooth:
MSI		set		0
		rept	65
		dc.w	(MSI*MSI*(192-2*MSI)*256)/(64*64*64)
MSI		set		MSI+1
		endr

morphOn::		dc.b	0		; seq_after: the ship is drawn from here
morphKept::		dc.b	0		; the unfolding is over
morphPhase::	dc.b	MP_UNFOLD
morphDirty:		dc.b	-1		; the picture has to be built again
morphFlyB:		dc.b	0		; (moving) which half of a picture
morphOut:		dc.b	0		; the ship has gone past, off the screen
morphHide:		dc.b	0		; the ship is not drawn (behind us, too far)
				even
morphT::		dc.w	0		; frames into the unfolding (< 0: the arrow)
morphPT:		dc.w	0		; frames in the phase
morphStep:		dc.w	0		; (the turn) which third of a picture
morphU:			ds.w	5		; each part's 0..256 this frame
morphFG:		dc.w	0		; the lens times the arrow's growth
morphRollD:		dc.w	0		; the ship's turn, degrees: roll (about its
morphPitchD:	dc.w	0		; length), pitch (about its wings), yaw (in
morphYawD:		dc.w	0		; the screen's plane), tilt (its nose up or
morphTiltD:		dc.w	0		; down, seen from us)
morphCR:		dc.w	0		; roll cos, sin
morphSR:		dc.w	0
morphCP:		dc.w	0		; pitch cos, sin
morphSP:		dc.w	0
morphSX:		dc.w	0		; the ship's middle, 1/16 units: across,
morphSY:		dc.w	0		; down,
morphSZ:		dc.l	morphZ0	; ahead
morphSX0:		dc.w	0		; ... where it was when it set off
morphSY0:		dc.w	0
morphSh:		dc.w	0		; far off: everything this much smaller (>>)
morphSXs:		dc.w	0		; ... the middle so
morphSYs:		dc.w	0
morphSZs:		dc.w	0
morphCX:		dc.w	0		; (the unfolding) its middle on the screen
morphCY:		dc.w	0
morphVz:		dc.w	256		; the stars' speed, 8.8 times warpVz
morphM:			ds.w	9		; (unfolded) the turn as a matrix, Q15
morphXY:		ds.w	2*morphNP	; the points on the screen
morphFV:		ds.b	morphNF		; faces seen
				even
morphFMask:		dc.w	0		; faces seen, a bit each
morphGlowE:		dc.w	0		; (morphLine) glow: the edge again, a line down
morphKey:		dc.l	-1		; xc:yc the cache was built for
morphCacheEnd:	dc.l	morphCache
morphCache:		ds.b	2*morphNE*line_entry

; a torpedo: age (0: none, -1: done), x (1/16 units), y, z (longs)
				rsreset
tp_age:			rs.w	1
tp_x:			rs.w	1
tp_y:			rs.l	1
tp_z:			rs.l	1
tp_len:			rs.b	0
morphTorps:		ds.b	morphTorpN*tp_len
morphTorpNext:	dc.w	0		; the next one to go

;---------------------------------------------
; d0 = degrees (any) -> d0 = sin, d1 = cos (Q15). uses a1
morphSinCos:
		tst.w	d0
		bpl.s	.p
.n:		add.w	#360,d0
		bmi.s	.n
.p:		cmp.w	#360,d0
		blo.s	.ok
		sub.w	#360,d0
		bra.s	.p
.ok:	lsl.w	#2,d0
		lea		sctab,a1
		move.w	2(a1,d0.w),d1
		move.w	(a1,d0.w),d0
		rts

; d0 = a wave (0..4), d1 = its step (1/16 degrees a frame), d2 = amplitude
; -> d0 = amplitude * sin(its phase), the phase one step on. uses a1
morphWave:
		add.w	d0,d0
		lea		morphPh,a1
		add.w	d0,a1
		move.w	(a1),d0
		add.w	d1,d0
		cmp.w	#360*16,d0
		blo.s	.w0
		sub.w	#360*16,d0
.w0:	move.w	d0,(a1)
		lsr.w	#4,d0
		lsl.w	#2,d0
		lea		sctab,a1
		move.w	(a1,d0.w),d0
		muls	d2,d0
		add.l	d0,d0
		swap	d0
		rts
morphPh:	ds.w	5			; the waves' phases

; d0 = frames, d1 = frames in all -> d0 = 0..256 (clamped), d1 the
; smoothstep of it
morphUnit:
		cmp.w	d1,d0
		blo.s	.u0
		move.w	d1,d0
.u0:	tst.w	d0
		bpl.s	.u1
		moveq	#0,d0
.u1:	ext.l	d0
		lsl.l	#6,d0
		divu	d1,d0				; 0..64
		move.w	d0,d1
		add.w	d1,d1
		lea		morphSmooth(pc),a1
		move.w	(a1,d1.w),d1
		lsl.w	#2,d0				; 0..256
		rts

;---------------------------------------------
; once a frame from seq_morph (asteroids.s), before the ship moves and is
; drawn: the timeline. a0 the ship, kept. d0 = 0: the ship may not start to
; turn yet (it is not still)
morphTick::
		move.w	d0,-(a7)
		addq.w	#1,morphT
		addq.w	#1,morphPT
		moveq	#0,d1
		move.b	morphPhase,d1
		add.w	d1,d1
		move.w	.tab(pc,d1.w),d1
		jsr		.tab(pc,d1.w)
		addq.l	#2,a7
		bsr		morphTorpMove
		; the stars' speed, and fewer of them while they rush
		move.w	morphVz,d0
		mulu	#warpVz,d0
		lsr.l	#8,d0
		move.w	d0,warpVzNow
		; new stars from further off the faster they come (the same wait for
		; each: the faster, the fewer of them in sight - a rush of stars
		; costs; the parked ones next to nothing)
		move.w	morphVz,d0
		sub.w	#256,d0
		mulu	#morphParkZ,d0
		lsr.l	#8,d0
		cmp.b	#MP_CHASE,morphPhase	; (from the chase on a few always:
		blo.s	.pk						; the ship costs its share)
		add.w	#morphPark0,d0
.pk:	move.w	d0,warpPark
		rts
.tab:	dc.w	.unfold-.tab,.hold-.tab,.turn-.tab,.chase-.tab,.loop-.tab
		dc.w	.attack-.tab,.gone-.tab

.unfold:
		st		morphDirty
		cmp.w	#morphLen+morphGlow,morphT
		blt.s	.out
		st		morphKept
		move.b	#MP_HOLD,morphPhase
		clr.w	morphPT
.out:	rts

.hold:
		tst.w	4(a7)				; (d0: still?)
		bne.s	.h0
		clr.w	morphPT				; not yet
		rts
.h0:	tst.b	warpState			; still: the stars start to go into
		bne.s	.h1					; depth (their colours, then fewer of
		jsr		warpStart			; them - the ship meanwhile drawn once,
.h1:	cmp.w	#morphHoldT,morphPT	; only shown)
		blo.s	.out
		cmp.b	#3,warpState		; and turns once they fly
		bne.s	.out
		move.b	#MP_TURN,morphPhase
		clr.w	morphPT
		clr.w	morphStep
		move.w	morphSX,morphSX0	; (morphPose has it from the ship)
		move.w	morphSY,morphSY0
		rts

.turn:	; into our way: its tail to us (pitch -90, yaw -90 is the ship seen
		; from behind, upright)
		st		morphDirty
		move.w	morphPT,d0
		move.w	#morphTurnT,d1
		bsr		morphUnit			; d1 0..256
		move.w	#-morphRoll,d0
		muls	d1,d0
		asr.l	#8,d0
		add.w	#morphRoll,d0
		move.w	d0,morphRollD
		move.w	#-90-morphPitch,d0
		muls	d1,d0
		asr.l	#8,d0
		add.w	#morphPitch,d0
		move.w	d0,morphPitchD
		move.w	#-90,d0
		muls	d1,d0
		asr.l	#8,d0
		move.w	d0,morphYawD
		cmp.w	#morphTurnT+6,morphPT	; (two pictures at the end pose)
		blo.s	.out
		move.b	#MP_CHASE,morphPhase
		clr.w	morphPT
		rts

.chase:
		st		morphDirty
		; the way: from far off to past us, faster at first, slower near
		; (ease out): it grows slowly - big, and nearly as fast as we are
		move.w	morphPT,d0
		move.w	#morphChaseT,d1
		bsr		morphUnit			; d0 u 0..256
		move.w	d0,d2				; (u, for the stars)
		move.w	#256,d1
		sub.w	d0,d1
		mulu	d1,d1
		lsr.l	#8,d1				; (1-u)^2
		move.l	#morphZ0-morphZPass,d0
		lsr.l	#4,d0
		mulu	d1,d0
		lsr.l	#4,d0
		add.l	#morphZPass,d0		; ZPass + (Z0 - ZPass) (1-u)^2
		move.l	d0,morphSZ
		; we pick up speed: the stars faster and faster (u*u)
		mulu	d2,d2
		lsr.l	#8,d2
		mulu	#morphVzMax-1,d2
		add.w	#256,d2
		move.w	d2,morphVz
		; the pilot gets ready: banks to and fro, weaves, the nose a little
		; this way and that - and once a full roll
		moveq	#0,d0
		moveq	#22,d1
		moveq	#morphBank,d2
		bsr		morphWave
		move.w	d0,d3
		move.w	morphPT,d0
		sub.w	#morphRollAt,d0
		move.w	#morphRollT,d1
		bsr		morphUnit			; d1 0..256 (0 before, 256 after)
		mulu	#360,d1
		lsr.l	#8,d1
		cmp.w	#360,d1
		blo.s	.c0
		moveq	#0,d1				; (round: as before)
.c0:	add.w	d1,d3
		move.w	d3,morphRollD
		moveq	#1,d0
		moveq	#34,d1
		moveq	#4,d2
		bsr		morphWave
		sub.w	#90,d0
		move.w	d0,morphPitchD
		moveq	#2,d0
		moveq	#13,d1
		moveq	#5,d2
		bsr		morphWave
		sub.w	#90,d0
		move.w	d0,morphYawD
		moveq	#3,d0
		moveq	#27,d1
		moveq	#3,d2
		bsr		morphWave
		add.w	#morphChaseTilt,d0	; (we see it a little from above)
		move.w	d0,morphTiltD
		moveq	#4,d0
		moveq	#14,d1
		move.w	#morphWeave,d2
		bsr		morphWave
		add.w	morphSX0,d0
		move.w	d0,morphSX
		move.w	morphSY0,morphSY
		; past us (all of it off the screen): it is behind us now
		tst.b	morphOut
		bne.s	.toLoop
		cmp.w	#morphChaseT,morphPT
		blo		.out
.toLoop:
		move.b	#MP_LOOP,morphPhase
		clr.w	morphPT
		st		morphHide
		rts

.loop:
		cmp.w	#morphLoopT,morphPT
		blo		.out
		move.b	#MP_ATTACK,morphPhase
		clr.w	morphPT
		sf		morphOut
		st		morphDirty
		move.w	#morphAtkX,morphSX
		rts

.attack:
		st		morphDirty
		; from behind us past us on the right - a little faster than we are,
		; so it is big beside us for a while - then the afterburner: away
		; towards the logo, faster and faster
		move.w	morphPT,d0
		move.w	#morphAtkT,d1
		bsr		morphUnit
		move.w	d1,d3				; (its smoothstep: rolling out)
		move.w	morphPT,d0
		cmp.w	#morphAtkPassT,d0
		bhs.s	.ab
		mulu	#(morphAtkZ1-morphAtkZ0)/morphAtkPassT,d0	; the pass
		add.l	#morphAtkZ0,d0
		bra.s	.az
.ab:	sub.w	#morphAtkPassT,d0	; the burn: z1 + go * t^2
		move.w	#morphAtkT-morphAtkPassT,d1
		bsr		morphUnit			; d0 0..256
		mulu	d0,d0
		lsr.l	#8,d0
		move.l	#morphAtkGo/16,d1
		mulu	d1,d0
		lsr.l	#4,d0
		add.l	#morphAtkZ1,d0
.az:	move.l	d0,morphSZ
		; up along the line that ends on the logo: y = y0 + dz * k
		sub.l	#morphAtkZ0,d0
		lsr.l	#4,d0				; (units)
		muls	#(morphLogoY-morphVY)*16*16/morphF,d0
		asr.l	#4,d0
		add.w	#morphAtkY,d0
		move.w	d0,morphSY
		; seen from behind, its nose up at the logo, rolling out of the loop
		move.w	#-morphAtkRoll,d0
		muls	d3,d0
		asr.l	#8,d0
		add.w	#morphAtkRoll,d0
		move.w	d0,morphRollD
		move.w	#-90,morphPitchD
		move.w	#-90,morphYawD
		move.w	#morphAtkTilt,morphTiltD
		; drawn only while it is ahead of us (and not too far off)
		sf		morphHide
		cmp.l	#1500,morphSZ
		bge.s	.a0
		st		morphHide
.a0:	; the torpedoes
		move.w	morphTorpNext,d0
		cmp.w	#morphTorpN,d0
		bhs.s	.a1
		mulu	#morphTorpGap,d0
		add.w	#morphTorpAt,d0
		cmp.w	morphPT,d0
		bne.s	.a1
		bsr		morphTorpFire
.a1:	cmp.w	#morphAtkT,morphPT
		blo		.out
		move.b	#MP_GONE,morphPhase
		clr.w	morphPT
		st		morphHide
		rts

.gone:	; the stars slow down softly
		move.w	morphVz,d0
		cmp.w	#morphVzEnd*256,d0
		bls		.out
		subq.w	#8,d0
		move.w	d0,morphVz
		rts

;---------------------------------------------
; a torpedo off: from the ship's nose (a little ahead of its middle),
; along the line to the logo, faster than the ship
morphTorpFire:
		move.w	morphTorpNext,d0
		addq.w	#1,morphTorpNext
		mulu	#tp_len,d0
		lea		morphTorps,a1
		add.w	d0,a1
		move.w	#1,tp_age(a1)
		move.w	morphSX,tp_x(a1)
		move.w	morphSY,d0
		ext.l	d0
		sub.l	#6*16,d0
		move.l	d0,tp_y(a1)
		move.l	morphSZ,d0
		add.l	#38*16,d0
		move.l	d0,tp_z(a1)
		rts

; the torpedoes on: ahead, and up along the line to the logo
morphTorpMove:
		lea		morphTorps,a1
		moveq	#morphTorpN-1,d7
.t:		move.w	tp_age(a1),d0
		ble.s	.n
		addq.w	#1,tp_age(a1)
		add.l	#morphTorpV,tp_z(a1)
		add.l	#(morphLogoY-morphVY)*morphTorpV/morphF,tp_y(a1)
		cmp.l	#morphTorpEnd,tp_z(a1)
		blt.s	.n
		move.w	#-1,tp_age(a1)		; there (the hits: later)
.n:		lea		tp_len(a1),a1
		dbf		d7,.t
		rts

; the torpedoes into the draw table: a plasma ball - a diamond that
; twinkles, its size by its distance - then a spark, then a dot; and a
; muzzle flash at the nose for their first frames. a5/a6 as set_line
morphTorpDraw:
		lea		morphTorps,a4
		moveq	#morphTorpN-1,d7
.t:		move.w	tp_age(a4),d0
		ble		.n
		movem.l	d7/a4,-(a7)
		; onto the screen: x = mid + x*lens/z (long z: both halved till it
		; fits a word)
		move.l	tp_z(a4),d5
		move.w	tp_x(a4),d3
		ext.l	d3
		move.l	tp_y(a4),d4
.sh:	cmp.l	#32000,d5
		blt.s	.s0
		asr.l	#1,d5
		asr.l	#1,d3
		asr.l	#1,d4
		bra.s	.sh
.s0:	muls	#morphF,d3
		divs	d5,d3
		add.w	#morphVX,d3			; x
		muls	#morphF,d4
		divs	d5,d4
		add.w	#morphVY,d4			; y
		move.l	tp_z(a4),d5			; the radius
		moveq	#0,d6
.r:		cmp.l	#32000,d5
		blt.s	.r0
		asr.l	#1,d5
		addq.w	#1,d6
		bra.s	.r
.r0:	move.l	#morphTorpR*morphF,d0
		lsr.l	d6,d0
		divu	d5,d0				; px
		move.w	tp_age(a4),d1
		btst	#0,d1				; the twinkle
		beq.s	.tw
		addq.w	#1,d0
.tw:	cmp.w	#2,d0
		blo.s	.dot
		; a diamond of radius d0 round d3/d4
		movem.w	d0/d3/d4,-(a7)
		move.w	d3,d1
		sub.w	d0,d1				; (left)
		move.w	d4,d2
		bsr		.line4
		movem.w	(a7)+,d0/d3/d4
		cmp.w	#5,d0				; big: a smaller one inside, every
		blo.s	.nf					; other frame (the plasma swirls)
		move.w	tp_age(a4),d1
		btst	#1,d1
		bne.s	.nf
		lsr.w	#1,d0
		movem.w	d0/d3/d4,-(a7)
		bsr		.line4
		movem.w	(a7)+,d0/d3/d4
		bra.s	.nf
.dot:	movem.w	d3/d4,-(a7)
		move.w	d3,d0
		move.w	d4,d1
		jsr		set_point
		movem.w	(a7)+,d3/d4
.nf:	; the muzzle flash: rays at its start, shorter each frame
		move.w	tp_age(a4),d0
		cmp.w	#5,d0
		bhs.s	.nx
		moveq	#5,d1
		sub.w	d0,d1
		mulu	#3,d1				; 12, 9, 6, 3
		move.w	d1,d0
		bsr		.rays
.nx:	movem.l	(a7)+,d7/a4
.n:		lea		tp_len(a4),a4
		dbf		d7,.t
		rts
; four lines: the diamond of radius d0 round d3/d4
.line4:
		move.w	d0,d5
		move.w	d3,d0				; left -> top
		sub.w	d5,d0
		move.w	d4,d1
		move.w	d3,d2
		move.w	d4,d3
		sub.w	d5,d3
		movem.w	d0-d5,-(a7)
		jsr		set_line
		movem.w	(a7)+,d0-d5
		move.w	d2,d0				; top -> right
		move.w	d3,d1
		add.w	d5,d2
		add.w	d5,d3
		movem.w	d0-d5,-(a7)
		jsr		set_line
		movem.w	(a7)+,d0-d5
		move.w	d2,d0				; right -> bottom
		move.w	d3,d1
		sub.w	d5,d2
		add.w	d5,d3
		movem.w	d0-d5,-(a7)
		jsr		set_line
		movem.w	(a7)+,d0-d5
		move.w	d2,d0				; bottom -> left
		move.w	d3,d1
		sub.w	d5,d2
		sub.w	d5,d3
		jmp		set_line
; four rays of length d0 round d3/d4: a cross, and a diagonal one
.rays:
		move.w	d0,d5
		move.w	d3,d0
		sub.w	d5,d0
		move.w	d4,d1
		move.w	d3,d2
		add.w	d5,d2
		movem.w	d3-d5,-(a7)
		move.w	d1,d3
		jsr		set_line			; across
		movem.w	(a7)+,d3-d5
		move.w	d3,d0
		move.w	d4,d1
		sub.w	d5,d1
		move.w	d3,d2
		movem.w	d3-d5,-(a7)
		move.w	d4,d3
		add.w	d5,d3
		jsr		set_line			; up and down
		movem.w	(a7)+,d3-d5
		lsr.w	#1,d5
		move.w	d3,d0
		sub.w	d5,d0
		move.w	d4,d1
		sub.w	d5,d1
		move.w	d3,d2
		add.w	d5,d2
		movem.w	d3-d5,-(a7)
		move.w	d4,d3
		add.w	d5,d3
		jsr		set_line			; one diagonal
		movem.w	(a7)+,d3-d5
		move.w	d3,d0
		add.w	d5,d0
		move.w	d4,d1
		sub.w	d5,d1
		move.w	d3,d2
		sub.w	d5,d2
		move.w	d4,d3
		add.w	d5,d3
		jmp		set_line			; the other

;---------------------------------------------
morphDraw:
		bsr		morphTorpDraw
		tst.b	morphHide
		bne		.none
		tst.b	morphDirty
		bne.s	.build
		move.l	obj_xc(a0),d0		; the same picture: and the ship on the
		cmp.l	morphKey,d0			; same pixel?
		beq		.emit
.build:
		move.l	obj_xc(a0),morphKey
		cmp.b	#MP_CHASE,morphPhase
		bhs.s	.moving
		cmp.b	#MP_TURN,morphPhase
		beq.s	.turn
		bra		.whole
.moving:
		; on the move (the chase, the attack run): a picture takes two
		; frames - the points, then the faces and the lines; while it is
		; still small and far off in the chase, three (as in the turn)
		cmp.b	#MP_CHASE,morphPhase
		bne.s	.two
		cmp.l	#morphFar,morphSZ
		bgt		.turn
.two:	not.b	morphFlyB
		bne.s	.fl1
		bsr		morphPose
		moveq	#0,d6
		moveq	#morphNP-1,d7
		bsr		morphPoints
		cmp.b	#MP_CHASE,morphPhase
		bne		.emit
		lea		morphXY,a1			; (the chase) all of it off the screen,
		moveq	#morphNP-1,d0		; to the left or below?
.ox:	tst.w	(a1)
		bmi.s	.ox1
		cmp.w	#game_height,2(a1)
		blt		.emit
.ox1:	addq.l	#4,a1
		dbf		d0,.ox
		st		morphOut
		bra		.emit
.fl1:	sf		morphDirty
		bsr		morphFaceVis
		bra		.lines
.turn:
		; the turn (the ship small, far off, turning slowly): a picture
		; takes three frames - half the points, the other half and the
		; faces, the lines. the one before is shown meanwhile
		move.w	morphStep,d0
		addq.w	#1,morphStep
		cmp.w	#3,morphStep
		blo.s	.st
		clr.w	morphStep
.st:	tst.w	d0
		bne.s	.st1
		bsr		morphPose
		moveq	#0,d6
		moveq	#8-1,d7
		bsr		morphPoints
		bra		.emit
.st1:	subq.w	#1,d0
		bne.s	.st2
		moveq	#8,d6
		moveq	#8-1,d7
		bsr		morphPoints
		bsr		morphFaceVis
		bra		.emit
.st2:	sf		morphDirty
		bra.s	.lines
.whole:
		sf		morphDirty
		bsr		morphPose
		moveq	#0,d6
		moveq	#morphNP-1,d7
		bsr		morphPoints
		; which faces we see
		cmp.w	#morphCull,morphT
		blt.s	.allFaces
		bsr		morphFaceVis
		bra.s	.lines
.allFaces:
		lea		morphFV,a1
		moveq	#morphNF-1,d0
.af:	st		(a1)+
		dbf		d0,.af
.lines:
		move.l	a6,-(a7)
		lea		morphCache,a6
		lea		morphEdges,a4
		moveq	#morphNE-1,d7
		tst.b	morphKept
		beq.s	.edge
		; unfolded: an edge is drawn if one of its faces is seen (morphEM
		; against morphFaceVis's bits), no glow
		move.w	morphFMask,d5
		lea		morphEM,a3
		lea		morphXY,a1
.k:		move.w	(a3)+,d0
		and.w	d5,d0
		beq.s	.kn
		moveq	#0,d0
		move.b	(a4),d0
		moveq	#0,d2
		move.b	1(a4),d2
		movem.w	(a1,d0.w),d0/d1
		movem.w	(a1,d2.w),d2/d3
		movem.w	d5/d7,-(a7)
		jsr		set_line			; (keeps a1-a4)
		movem.w	(a7)+,d5/d7
.kn:	addq.l	#me_len,a4
		dbf		d7,.k
		bra.s	.lend
.edge:	move.w	d7,-(a7)
		clr.w	morphGlowE
		moveq	#0,d0
		move.b	4(a4),d0			; its part
		lsl.w	#2,d0
		lea		morphParts,a1
		move.w	morphT,d1
		sub.w	(a1,d0.w),d1		; frames since its part started
		bgt.s	.out
		tst.b	5(a4)				; not out yet: only the arrow's own lines
		beq.s	.skip
.out:	sub.w	2(a1,d0.w),d1		; glow: near the end of its part
		bpl.s	.g0
		neg.w	d1
.g0:	cmp.w	#morphGlow,d1
		bhi.s	.seen
		move.w	#1,morphGlowE
.seen:	bsr		morphSeen
		beq.s	.skip
		bsr		morphLine
.skip:	lea		me_len(a4),a4
		move.w	(a7)+,d7
		dbf		d7,.edge
.lend:	move.l	a6,morphCacheEnd
		move.l	(a7)+,a6
.emit:
		move.l	morphCacheEnd,d0
		cmp.l	#morphCache,d0
		beq.s	.none
		move.w	#-2,(a6)+
		move.l	#morphCache,(a6)+
		move.l	d0,(a6)+
.none:	rts

; this frame's turn, growth and place
morphPose:
		tst.b	morphKept
		bne		.done
		; the unfolding: the parts' smoothsteps
		move.w	morphT,d6
		bpl.s	.t0
		moveq	#0,d6
.t0:	lea		morphParts,a1
		lea		morphU,a2
		lea		morphSmooth,a3
		moveq	#5-1,d7
.part:	moveq	#0,d0
		move.w	d6,d0
		sub.w	(a1)+,d0
		bpl.s	.p0
		moveq	#0,d0
.p0:	move.w	(a1)+,d1
		cmp.w	d1,d0
		blo.s	.p1
		move.w	d1,d0
.p1:	lsl.w	#6,d0				; 0..64
		divu	d1,d0
		add.w	d0,d0
		move.w	(a3,d0.w),(a2)+
		dbf		d7,.part
		; the arrow grows a little (from the game's size)
		move.w	morphU,d0
		mulu	#256-morphG0,d0
		lsr.l	#8,d0
		add.w	#morphG0,d0
		mulu	#morphF,d0
		lsr.l	#8,d0
		move.w	d0,morphFG
		; roll and pitch come in with the hull
		move.w	morphU+2,d1
		move.w	d1,d0
		mulu	#morphRoll,d0
		lsr.l	#8,d0
		move.w	d0,morphRollD
		mulu	#morphPitch,d1
		lsr.l	#8,d1
		move.w	d1,morphPitchD
		move.w	obj_xc(a0),morphCX
		move.w	obj_yc(a0),morphCY
		move.w	morphRollD,d0
		bsr		morphSinCos
		move.w	d1,morphCR
		move.w	d0,morphSR
		move.w	morphPitchD,d0
		bsr		morphSinCos
		move.w	d1,morphCP
		move.w	d0,morphSP
		rts
.done:
		; unfolded: a body in the world. until it sets off its place comes
		; from the ship (obj_xc/yc, at morphZ0)
		cmp.b	#MP_TURN,morphPhase
		bhs.s	.place
		move.w	obj_xc(a0),d0
		sub.w	#morphVX,d0
		muls	#morphZ0,d0
		divs	#morphF,d0
		move.w	d0,morphSX
		move.w	obj_yc(a0),d0
		sub.w	#morphVY,d0
		muls	#morphZ0,d0
		divs	#morphF,d0
		move.w	d0,morphSY
.place:	; far off: all of it smaller by a shift, so the depth fits the table
		move.l	morphSZ,d2
		move.w	morphSX,d0
		move.w	morphSY,d1
		moveq	#0,d3
.sh:	cmp.l	#16000,d2
		ble.s	.sh0
		asr.l	#1,d2
		asr.w	#1,d0
		asr.w	#1,d1
		addq.w	#1,d3
		bra.s	.sh
.sh0:	move.w	d2,morphSZs
		move.w	d0,morphSXs
		move.w	d1,morphSYs
		move.w	d3,morphSh
		; the turn as one matrix, Q15: roll, pitch, yaw, then the tilt
		move.w	morphRollD,d0
		bsr		morphSinCos
		move.w	d1,morphCR
		move.w	d0,morphSR
		move.w	morphPitchD,d0
		bsr		morphSinCos
		move.w	d1,morphCP
		move.w	d0,morphSP
		move.w	morphYawD,d0
		bsr		morphSinCos
		move.w	d0,d6				; syw
		move.w	d1,d7				; cyw
		lea		morphM,a2
		move.w	morphSP,d4
		move.w	morphSR,d0
		muls	d4,d0
		add.l	d0,d0
		swap	d0					; t1 = sr sp
		move.w	morphCR,d1
		muls	d4,d1
		add.l	d1,d1
		swap	d1					; t2 = cr sp
		move.w	morphCP,d5
		; m00 = cp cyw
		move.w	d5,d2
		muls	d7,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; m01 = -t1 cyw - cr syw
		move.w	d0,d2
		muls	d7,d2
		move.w	morphCR,d3
		muls	d6,d3
		add.l	d3,d2
		neg.l	d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; m02 = -t2 cyw + sr syw
		move.w	d1,d2
		muls	d7,d2
		move.w	morphSR,d3
		muls	d6,d3
		sub.l	d2,d3
		add.l	d3,d3
		swap	d3
		move.w	d3,(a2)+
		; m10 = cp syw
		move.w	d5,d2
		muls	d6,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; m11 = -t1 syw + cr cyw
		move.w	morphCR,d2
		muls	d7,d2
		move.w	d0,d3
		muls	d6,d3
		sub.l	d3,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; m12 = -t2 syw - sr cyw
		move.w	d1,d2
		muls	d6,d2
		move.w	morphSR,d3
		muls	d7,d3
		add.l	d3,d2
		neg.l	d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; m20 = sp, m21 = sr cp, m22 = cr cp
		move.w	d4,(a2)+
		move.w	morphSR,d2
		muls	d5,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		move.w	morphCR,d2
		muls	d5,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; the tilt (about the screen's x, + its nose up while it flies
		; away): y' = c y + s z, z' = -s y + c z, column by column
		move.w	morphTiltD,d0
		beq.s	.out
		bsr		morphSinCos			; d0 s, d1 c
		lea		morphM+6,a2			; row y
		moveq	#3-1,d7
.tc:	move.w	(a2),d2				; y
		move.w	6(a2),d3			; z
		move.w	d2,d4
		muls	d1,d4
		move.w	d3,d5
		muls	d0,d5
		add.l	d5,d4
		add.l	d4,d4
		swap	d4
		move.w	d4,(a2)
		muls	d1,d3
		muls	d0,d2
		sub.l	d2,d3
		add.l	d3,d3
		swap	d3
		move.w	d3,6(a2)
		addq.l	#2,a2
		dbf		d7,.tc
.out:	rts

; the points d6.. (d7+1 of them): unfolded as far as their part is,
; turned, onto the screen
morphPoints:
		move.w	d6,d0
		mulu	#mp_len,d0
		lea		morphPts,a1
		add.w	d0,a1
		move.w	d6,d0
		lsl.w	#2,d0
		lea		morphXY,a2
		add.w	d0,a2
		tst.b	morphKept
		beq		.pt
		; unfolded: the end points through the matrix (morphPose), and
		; onto the screen from where the ship is in the world
.km:	movem.w	(a1),d0-d2
		add.w	6(a1),d0
		add.w	8(a1),d1
		add.w	10(a1),d2
		lsl.w	#4,d0
		lsl.w	#4,d1
		lsl.w	#4,d2
		lea		morphM,a3
		move.w	(a3)+,d4
		muls	d0,d4
		move.w	(a3)+,d5
		muls	d1,d5
		add.l	d5,d4
		move.w	(a3)+,d5
		muls	d2,d5
		add.l	d5,d4
		add.l	d4,d4
		swap	d4					; x (across)
		move.w	(a3)+,d3
		muls	d0,d3
		move.w	(a3)+,d5
		muls	d1,d5
		add.l	d5,d3
		move.w	(a3)+,d5
		muls	d2,d5
		add.l	d5,d3
		add.l	d3,d3
		swap	d3					; y (down)
		move.w	(a3)+,d5
		muls	d0,d5
		move.w	(a3)+,d6
		muls	d1,d6
		add.l	d6,d5
		move.w	(a3)+,d6
		muls	d2,d6
		add.l	d6,d5
		add.l	d5,d5
		swap	d5					; z (+: towards the eye)
		move.w	morphSh,d1
		asr.w	d1,d4
		asr.w	d1,d3
		asr.w	d1,d5
		move.w	morphSZs,d1
		sub.w	d5,d1
		cmp.w	#64,d1				; (never at or behind the eye)
		bge.s	.kz
		moveq	#64,d1
.kz:	lsr.w	#3,d1				; the lens over the depth: the table
		add.w	d1,d1				; (morphInit)
		lea		morphRcp,a3
		move.w	(a3,d1.w),d0
		add.w	morphSXs,d4
		muls	d0,d4
		asr.l	#8,d4
		asr.l	#4,d4
		add.w	#morphVX,d4
		add.w	morphSYs,d3
		muls	d0,d3
		asr.l	#8,d3
		asr.l	#4,d3
		add.w	#morphVY,d3
		move.w	d4,(a2)+
		move.w	d3,(a2)+
		lea		mp_len(a1),a1
		dbf		d7,.km
		rts
.pt:	movem.w	(a1),d0-d2			; start
		movem.w	6(a1),d3-d5			; the way to the end
		move.w	12(a1),d6			; its part's smoothstep
		add.w	d6,d6
		lea		morphU,a3
		move.w	(a3,d6.w),d6
		lsl.w	#4,d0				; 1/16 units: x*16 + d*u/16
		lsl.w	#4,d1
		lsl.w	#4,d2
		muls	d6,d3
		asr.l	#4,d3
		add.w	d3,d0
		muls	d6,d4
		asr.l	#4,d4
		add.w	d4,d1
		muls	d6,d5
		asr.l	#4,d5
		add.w	d5,d2
		; roll about x: y' = y cr - z sr, z' = y sr + z cr
		move.w	d1,d3
		muls	morphCR,d3
		move.w	d2,d4
		muls	morphSR,d4
		sub.l	d4,d3
		add.l	d3,d3
		swap	d3					; y'
		muls	morphSR,d1
		muls	morphCR,d2
		add.l	d1,d2
		add.l	d2,d2
		swap	d2					; z'
		; pitch about y: x'' = x cp - z' sp, z'' = x sp + z' cp
		move.w	d0,d4
		muls	morphCP,d4
		move.w	d2,d5
		muls	morphSP,d5
		sub.l	d5,d4
		add.l	d4,d4
		swap	d4					; x''
		muls	morphSP,d0
		muls	morphCP,d2
		add.l	d0,d2
		add.l	d2,d2
		swap	d2					; z'' (+: towards the eye)
		; onto the screen round the ship: * lens*growth / (depth - z'')
		move.w	#morphZ0,d1
		sub.w	d2,d1
		moveq	#0,d0				; (4.12)
		move.w	morphFG,d0
		lsl.l	#8,d0
		lsl.l	#4,d0
		divu	d1,d0
		muls	d0,d4
		asr.l	#8,d4
		asr.l	#4,d4
		muls	d0,d3
		asr.l	#8,d3
		asr.l	#4,d3
		add.w	morphCX,d4
		add.w	morphCY,d3
		move.w	d4,(a2)+
		move.w	d3,(a2)+
		lea		mp_len(a1),a1
		dbf		d7,.pt
		rts

; the faces seen, from the projected corners (screen y down: a face whose
; corners run counter-clockwise from outside comes out negative)
morphFaceVis:
		lea		morphFaces,a1
		lea		morphXY,a2
		lea		morphFV,a3
		moveq	#0,d6
		moveq	#morphNF-1,d7
.f:		moveq	#0,d0
		move.b	(a1)+,d0
		movem.w	(a2,d0.w),d0/d1		; a
		moveq	#0,d2
		move.b	(a1)+,d2
		movem.w	(a2,d2.w),d2/d3		; b
		moveq	#0,d4
		move.b	(a1)+,d4
		movem.w	(a2,d4.w),d4/d5		; c
		sub.w	d0,d2				; b-a
		sub.w	d1,d3
		sub.w	d0,d4				; c-a
		sub.w	d1,d5
		muls	d2,d5				; (bx-ax)(cy-ay)
		muls	d3,d4				; (by-ay)(cx-ax)
		sub.l	d4,d5
		smi		(a3)+
		bpl.s	.nv
		moveq	#8,d0				; (and a bit for each face seen: the
		sub.w	d7,d0				; unfolded ship's quick line loop)
		bset	d0,d6
.nv:	dbf		d7,.f
		move.w	d6,morphFMask
		rts

; a4 = an edge -> NE if one of its faces is seen (or it is on none)
morphSeen:
		move.b	2(a4),d2
		bmi.s	.yes
		ext.w	d2
		lea		morphFV,a1
		tst.b	(a1,d2.w)
		bne.s	.yes
		move.b	3(a4),d2
		bmi.s	.no
		ext.w	d2
		tst.b	(a1,d2.w)
		rts
.yes:	moveq	#1,d2
		rts
.no:	moveq	#0,d2
		rts

; a4 = an edge: its line into the table at a6 (the cache) (and once more a
; line lower while it glows). keeps a4
morphLine:
		lea		morphXY,a1
		moveq	#0,d0
		move.b	(a4),d0
		moveq	#0,d2
		move.b	1(a4),d2
		movem.w	(a1,d0.w),d0/d1
		movem.w	(a1,d2.w),d2/d3
		movem.w	d0-d3,-(a7)
		jsr		set_line
		movem.w	(a7)+,d0-d3
		tst.w	morphGlowE
		beq.s	.out
		addq.w	#1,d1
		addq.w	#1,d3
		jsr		set_line
.out:	rts

;---------------------------------------------
; once, at the start (warp.i warpInit): the lens over the depth, an eighth
; of a unit apart (4.12) - no division a point once the ship is unfolded
morphInit:
		lea		morphRcp,a0
		moveq	#0,d1
.r:		move.w	d1,d2
		lsl.w	#3,d2
		cmp.w	#64,d2
		bhs.s	.r0
		moveq	#64,d2
.r0:	move.l	#morphF<<12,d0
		divu	d2,d0
		move.w	d0,(a0)+
		addq.w	#1,d1
		cmp.w	#morphRcpN,d1
		bne.s	.r
		rts

morphRcpN	= 2200		; up to a depth of 17600 (1/16 units)

		section "morphbss",bss
morphRcp:	ds.w	morphRcpN
