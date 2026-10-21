;======================================================================
; morph.i - the Elite ending, steps 3 and 4. included at the end of
; asteroids.s, switched by switches.i elite3.
;
; step 3, the unfolding: the Defender ship, small and far off, unfolds
; into the Quadlite-Thrust fighter in 3D lines - no bigger than twice the
; Asteroids ship, so it only makes the viewer wonder. the model has 16
; points: each one starts on the flat Defender arrow (asteroids.s
; ship_coords turned to the right, times 7, z 0) and ends on the fighter.
; the parts unfold one after the other, each with its own start and a
; smoothstep: the arrow grows a little, the hull opens (and the ship
; rolls over and dips its nose, so the depth shows), the wing guns come
; out, the canopy rises, the engine plate ("the quad") comes on. a line
; that has just come out glows (drawn twice); towards the end the lines
; on faces turned away go (backface culling on the projected corners).
;
; step 4, the camera: the fighter turns its nose towards the viewer while
; the stars go into depth (warp.i, started here); then the camera flies
; at it and past it on its right: the ship (it only turns, it never moves)
; grows and goes off to the left as the stars rush by (warpVzNow up, a
; jolt), new stars come from further off while the ship is big
; (warpPark), and afterwards the stars slow down softly to their speed.
;
; the projection: a point of the model (1/16 units, turned) at depth Zs
; ahead of the eye: x = middle + x*F/(Zs - z). the middle is the ship
; (obj_xc/yc) until the flight, then it moves away from the stars'
; middle (morphVX/VY) as Zs gets less.
;
; obj_move comes here for the ship while morphOn is set: a0 the ship, a5
; yOffTab, a6 the draw table. the lines go into morphCache and the table
; gets a pointer to them; they are built only when something has changed
;======================================================================

		section "code",data,chip

morphLen	= 168		; frames from the flat arrow to the fighter
morphCull	= 134		; frames: from here on the back lines are hidden
morphGlow	= 6			; frames a part's lines glow either side of its end
morphRoll	= 46		; degrees the ship rolls over (its right wing up)
morphPitch	= 13		; degrees its nose dips (we see the engine plate)
morphHoldT	= 50		; frames the fighter waits (still) before it turns
morphTurnT	= 110		; frames it takes to turn towards the viewer
morphRoll2	= 18		; ... rolled this much then
morphPitch2	= 72		; ... and its nose this far round to us
morphFlyT	= 110		; frames of the fly-by (the camera at it and past it)
morphFlyD	= 14		; frames into it before the ship starts to move itself
morphRoll3	= -38		; ... into its flight position: banked the other way,
morphPitch3	= 76		; the nose still to us (it goes off left)
morphYaw3	= -36		; and up (to the logo)
morphSlide	= 40		; px (at its first size) the camera swings past it
morphZ0		= 1024*16	; the ship's depth (1/16 units) - far off
morphKMax	= 18		; ... and it 18 times as big at the end (by then it is
						; off the screen to the left)
morphF		= 288		; the lens: 0.28 px a unit at morphZ0 (the fighter
						; 72 units long: 20 px, twice the Asteroids ship)
morphG0		= 131		; 8.8: the arrow at the start (the game's size)
morphVX		= 160		; the stars' middle (warp.i warpCx/warpCy), where the
morphVY		= 134		; camera flies to
morphVzBoost = 2		; the jolt: the stars this many times faster on top
morphBoostUp = 12		; ... up by this a frame (of 256)
morphBoostDn = 5		; ... down by this a frame after the fly-by
morphParkZ	= 600		; new stars this much further off during the fly-by
morphParkT	= 50		; ... from this many frames before it
morphNP		= 16		; points
morphNE		= 23		; edges
morphNF		= 9			; faces

MP_UNFOLD	= 0
MP_HOLD		= 1
MP_TURN		= 2
MP_FLY		= 3
MP_GONE		= 4

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
morphT::		dc.w	0		; frames into the unfolding (< 0: the arrow)
morphPT:		dc.w	0		; frames in the phase (hold, turn, fly)
morphU:			ds.w	5		; each part's 0..256 this frame
morphFG:		dc.w	0		; the lens times the arrow's growth
morphRollD:		dc.w	0		; degrees now
morphPitchD:	dc.w	0
morphCR:		dc.w	0		; roll cos, sin
morphSR:		dc.w	0
morphCP:		dc.w	0		; pitch cos, sin
morphSP:		dc.w	0
morphZs:		dc.w	morphZ0	; the ship's depth now
morphCX:		dc.w	0		; its middle on the screen
morphCY:		dc.w	0
morphC0X:		dc.w	0		; ... where it was when the camera set off
morphC0Y:		dc.w	0
morphBoost:		dc.w	0		; 0..256 the jolt
morphStep:		dc.w	0		; (the turn) which third of a picture
morphFlyB:		dc.b	0		; (the fly-by) which half of a picture
morphFlyP:		dc.b	0		; ... its first pose is done
morphOut:		dc.b	0		; ... the ship is off the screen
				even
morphSlideX:	dc.w	0		; ... its place, so far to the left
				even
morphYawD:		dc.w	0		; degrees in the screen's plane (the fly-by)
morphM:			ds.w	9		; (unfolded) the turn as a matrix, Q15
morphXY:		ds.w	2*morphNP	; the points on the screen, round the middle
morphFV:		ds.b	morphNF		; faces seen
				even
morphFMask:		dc.w	0		; faces seen, a bit each
				even
morphGlowE:		dc.w	0		; (morphLine) glow: the edge again, a line down
morphKey:		dc.l	-1		; xc:yc the cache was built for
morphCacheEnd:	dc.l	morphCache
morphCache:		ds.b	2*morphNE*line_entry

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
		; the jolt: the stars' speed ahead
		move.w	morphBoost,d0
		mulu	#warpVz*morphVzBoost,d0
		lsr.l	#8,d0
		add.w	#warpVz,d0
		move.w	d0,warpVzNow
		rts
.tab:	dc.w	.unfold-.tab,.hold-.tab,.turn-.tab,.fly-.tab,.gone-.tab

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
		move.w	obj_xc(a0),morphC0X
		move.w	obj_yc(a0),morphC0Y
		rts

.turn:
		st		morphDirty
		move.w	morphPT,d0
		mulu	#64,d0
		divu	#morphTurnT,d0
		cmp.w	#64,d0
		bls.s	.t0
		moveq	#64,d0
.t0:	add.w	d0,d0
		lea		morphSmooth,a1
		move.w	(a1,d0.w),d1		; 0..256
		move.w	#morphRoll2-morphRoll,d0
		muls	d1,d0
		asr.l	#8,d0
		add.w	#morphRoll,d0
		move.w	d0,morphRollD
		move.w	#morphPitch2-morphPitch,d0
		muls	d1,d0
		asr.l	#8,d0
		add.w	#morphPitch,d0
		move.w	d0,morphPitchD
		cmp.w	#morphTurnT-morphParkT,morphPT	; new stars from further off
		blo.s	.t1						; already before the fly-by (it takes
		move.w	#morphParkZ,warpPark	; a while till there are fewer)
.t1:	cmp.w	#morphTurnT+6,morphPT	; (two pictures at the end pose)
		blo.s	.out
		move.b	#MP_FLY,morphPhase
		clr.w	morphPT
		move.w	#morphParkZ,warpPark	; (new stars from further off while the
		rts							; ship is big)

.fly:
		st		morphDirty
		add.w	#morphBoostUp,morphBoost
		cmp.w	#256,morphBoost
		bls.s	.f0
		move.w	#256,morphBoost
.f0:	; the depth: the ship's size on the screen (1/depth) grows from 1 to
		; morphKMax, faster and faster (u*u)
		move.w	morphPT,d0
		lsl.w	#8,d0
		ext.l	d0
		divu	#morphFlyT,d0		; u 0..256
		; the camera swings right past it: the ship's place slides to the
		; left more and more (and on, after the end, till it is gone)
		move.w	d0,d1				; (only late - it is big by then - and
		sub.w	#192,d1				; then all the more)
		bpl.s	.sl0
		moveq	#0,d1
.sl0:	mulu	d1,d1
		mulu	#morphSlide,d1
		lsr.l	#8,d1
		lsr.l	#4,d1
		move.w	d1,morphSlideX
		cmp.w	#256,d0
		bls.s	.fu
		move.w	#256,d0
.fu:	mulu	d0,d0
		lsr.l	#8,d0				; u*u
		mulu	#morphKMax-1,d0
		add.w	#256,d0				; 8.8, 1..morphKMax
		move.l	#morphZ0*256,d1
		divu	d0,d1
		move.w	d1,morphZs
		; and meanwhile it brings itself round into its flight position,
		; banking, the nose up to the logo - as if it had a plan
		move.w	morphPT,d0
		sub.w	#morphFlyD,d0
		bpl.s	.f1
		moveq	#0,d0
.f1:	mulu	#64,d0
		divu	#morphFlyT-morphFlyD,d0
		cmp.w	#64,d0
		bls.s	.f2
		moveq	#64,d0
.f2:	add.w	d0,d0
		lea		morphSmooth,a1
		move.w	(a1,d0.w),d1		; 0..256
		move.w	#morphRoll3-morphRoll2,d0
		muls	d1,d0
		asr.l	#8,d0
		add.w	#morphRoll2,d0
		move.w	d0,morphRollD
		move.w	#morphPitch3-morphPitch2,d0
		muls	d1,d0
		asr.l	#8,d0
		add.w	#morphPitch2,d0
		move.w	d0,morphPitchD
		move.w	#morphYaw3,d0
		muls	d1,d0
		asr.l	#8,d0
		move.w	d0,morphYawD
		tst.b	morphOut			; gone once it is all off the screen (or
		bne.s	.fe					; a while after the end, anyway)
		cmp.w	#morphFlyT+40,morphPT
		blo.s	.out
.fe:	move.b	#MP_GONE,morphPhase
		clr.w	warpPark
		rts

.gone:
		move.w	morphBoost,d0		; the stars slow down softly
		sub.w	#morphBoostDn,d0
		bpl.s	.g0
		moveq	#0,d0
.g0:	move.w	d0,morphBoost
		rts

;---------------------------------------------
morphDraw:
		cmp.b	#MP_GONE,morphPhase
		beq		.none
		tst.b	morphDirty
		bne.s	.build
		move.l	obj_xc(a0),d0		; the same picture: and the ship on the
		cmp.l	morphKey,d0			; same pixel?
		beq		.emit
.build:
		move.l	obj_xc(a0),morphKey
		cmp.b	#MP_FLY,morphPhase
		bne.s	.noFly
		; the fly-by (the stars rush, the ship is big): a picture takes two
		; frames - the points and faces, then the lines
		not.b	morphFlyB
		bne.s	.fl1
		tst.b	morphFlyP			; (the first frame of it: no pose yet)
		bne.s	.fl0
		st		morphFlyP
		bsr		morphPose
.fl0:	moveq	#0,d6
		moveq	#morphNP-1,d7
		bsr		morphPoints
		lea		morphXY,a1			; all of it off the screen (to the left
		moveq	#morphNP-1,d0		; or below)?
.ox:	tst.w	(a1)
		bmi.s	.ox1
		cmp.w	#game_height,2(a1)
		blt		.emit
.ox1:	addq.l	#4,a1
		dbf		d0,.ox
		st		morphOut
		bra		.emit
.fl1:	sf		morphDirty			; the faces, the pose for the next picture
		bsr		morphFaceVis		; (a frame early: the same as then, near
		bsr		morphPose			; enough), the lines
		bra		.lines
.noFly:
		cmp.b	#MP_TURN,morphPhase
		bne.s	.whole
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
		tst.b	morphKept
		bne.s	.seen
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

; this frame's turn, growth, depth and middle
morphPose:
		tst.b	morphKept
		bne.s	.done
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
		bra.s	.trig
.done:
		move.w	#morphF,morphFG
		cmp.b	#MP_FLY,morphPhase
		beq.s	.fly
		move.w	obj_xc(a0),morphCX	; (hold: wherever it is; turn: it is
		move.w	obj_yc(a0),morphCY	; still)
		cmp.b	#MP_TURN,morphPhase
		bne.s	.trig
		move.w	morphC0X,morphCX
		move.w	morphC0Y,morphCY
		bra.s	.trig
.fly:	; the middle moves away from the stars' middle as the camera comes
		move.w	morphC0X,d0
		sub.w	#morphVX,d0
		sub.w	morphSlideX,d0
		muls	#morphZ0/16,d0
		lsl.l	#4,d0
		divs	morphZs,d0
		add.w	#morphVX,d0
		move.w	d0,morphCX
		move.w	morphC0Y,d0
		sub.w	#morphVY,d0
		muls	#morphZ0/16,d0
		lsl.l	#4,d0
		divs	morphZs,d0
		add.w	#morphVY,d0
		move.w	d0,morphCY
.trig:
		lea		sctab,a3
		move.w	morphRollD,d0
		bpl.s	.r0
		add.w	#360,d0
.r0:	lsl.w	#2,d0
		movem.w	(a3,d0.w),d2/d3		; sin, cos
		move.w	d3,morphCR
		move.w	d2,morphSR
		move.w	morphPitchD,d0
		bpl.s	.p2
		add.w	#360,d0
.p2:	lsl.w	#2,d0
		movem.w	(a3,d0.w),d2/d3
		move.w	d3,morphCP
		move.w	d2,morphSP
		tst.b	morphKept
		beq.s	.out
		; unfolded: roll, pitch and the yaw (the turn in the screen's plane,
		; the fly-by) as one matrix, Q15 - nine muls a point
		move.w	morphYawD,d0
		bpl.s	.y0
		add.w	#360,d0
.y0:	lsl.w	#2,d0
		movem.w	(a3,d0.w),d6/d7		; syw, cyw
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
.out:	rts

; the points d6.. (d7+1 of them): unfolded as far as their part is,
; turned, onto the screen. the turned ones are kept (morphRot): in the
; fly-by the ship does not turn any more, there only the projection is new
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
		beq.s	.pt
		; unfolded: the end points through the matrix (morphPose)
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
		swap	d4					; x on the screen (round the middle)
		move.w	(a3)+,d3
		muls	d0,d3
		move.w	(a3)+,d5
		muls	d1,d5
		add.l	d5,d3
		move.w	(a3)+,d5
		muls	d2,d5
		add.l	d5,d3
		add.l	d3,d3
		swap	d3					; y
		move.w	(a3)+,d5
		muls	d0,d5
		move.w	(a3)+,d6
		muls	d1,d6
		add.l	d6,d5
		move.w	(a3)+,d6
		muls	d2,d6
		add.l	d6,d5
		add.l	d5,d5
		swap	d5
		move.w	d5,d2				; z (+: towards the eye)
		bsr.s	.project
		lea		mp_len(a1),a1
		dbf		d7,.km
		rts
.pt:	movem.w	(a1),d0-d2			; start
		movem.w	6(a1),d3-d5			; the way to the end
		tst.b	morphKept
		beq.s	.unf
		add.w	d3,d0				; done: the end
		add.w	d4,d1
		add.w	d5,d2
		lsl.w	#4,d0
		lsl.w	#4,d1
		lsl.w	#4,d2
		bra.s	.turn
.unf:	move.w	12(a1),d6			; its part's smoothstep
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
.turn:	; roll about x: y' = y cr - z sr, z' = y sr + z cr
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
		bsr.s	.project
		lea		mp_len(a1),a1
		dbf		d7,.pt
		rts
; onto the screen: x'' d4, y' d3, z'' d2 -> * lens / (depth - z'')
.project:
		move.w	morphZs,d1
		sub.w	d2,d1
		cmp.w	#64,d1				; (never at or behind the eye)
		bge.s	.pz
		moveq	#64,d1
.pz:	tst.b	morphKept			; unfolded: the lens is morphF - from the
		beq.s	.pdiv				; table (morphInit), an eighth of a unit
		lsr.w	#3,d1				; apart
		add.w	d1,d1
		lea		morphRcp,a3
		move.w	(a3,d1.w),d0
		bra.s	.pmul
.pdiv:	moveq	#0,d0				; lens/(depth - z'') once, as 4.12
		move.w	morphFG,d0
		lsl.l	#8,d0
		lsl.l	#4,d0
		divu	d1,d0
.pmul:	muls	d0,d4
		asr.l	#8,d4
		asr.l	#4,d4
		muls	d0,d3
		asr.l	#8,d3
		asr.l	#4,d3
		add.w	morphCX,d4			; (on the screen: round the middle)
		add.w	morphCY,d3
		move.w	d4,(a2)+
		move.w	d3,(a2)+
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

; a4 = an edge: its line into the table at a6 (the cache), round the middle
; (and once more a line lower while it glows). keeps a4
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
