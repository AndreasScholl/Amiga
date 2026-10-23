;---------------------------------------------
; seq_after (and F9): off it goes. keeps a0
warpStart::
		tst.b	warpState
		bne.s	.out
		move.b	#1,warpState
		clr.w	warpT
		move.w	#warpAcc,starAcc
		; the spare colours take copies: 19 the front layer's (17), 22 the
		; third layer's (23). the copper has them from the next frame on
		move.w	starColours+2,starColours+10
		move.w	starColours+22,starColours+18
		; the scroller has nothing left to show (the TV is off, the text all
		; gone): it need not run on, unseen, any more - its time is the
		; field's now
		tst.b	scrollGone
		beq.s	.out
		st		scrollerOff
.out:
		rts

;---------------------------------------------
; updateStars comes here once it has started
warpStep:
		addq.w	#1,warpT
		move.b	warpState,d0
		cmp.b	#3,d0
		beq		warpField
		cmp.b	#2,d0
		beq		warpThin
		bsr.s	warpFade
		bra		starsParallax

;--- 1: the colours ---------------------------
warpFade:
		move.w	warpT,d0
		cmp.w	#2,d0
		blo.s	.out
		bne.s	.fade
		; the copies are shown now: the front layer onto colour 3 of its
		; pair (19), the third onto colour 2 (22) - nothing to see
		move.l	#$00010001,d0
		lea		slst0+4,a0
		bsr.s	.all
		moveq	#$00000001,d0
		lea		slst2+4,a0
		bsr.s	.all
		; 17 and 23 are free now: straight to their end
		move.w	#warpCol1,starColours+2
		move.w	#warpCol3,starColours+22
		move.w	#warpFadeT,warpFadeC
.out:
		rts
.all:
		move.w	#stars_count-1,d7
.l:
		move.l	d0,(a0)
		addq.l	#8,a0
		dbf		d7,.l
		rts
.fade:
		subq.w	#1,warpFadeC
		bne.s	.out
		move.w	#warpFadeT,warpFadeC
		moveq	#0,d5				; one still on its way
		lea		starColours+6,a1	; 18: the second layer -> middle
		move.w	#warpCol2,d1
		bsr.s	.step
		lea		starColours+10,a1	; 19: the front -> bright
		move.w	#warpCol3,d1
		bsr.s	.step
		lea		starColours+14,a1	; 21: the back -> dim
		move.w	#warpCol1,d1
		bsr.s	.step
		lea		starColours+18,a1	; 22: the third -> middle
		move.w	#warpCol2,d1
		bsr.s	.step
		tst.w	d5
		bne.s	.out
		move.b	#2,warpState		; all there: the thinning
		clr.w	warpT
		clr.w	warpKept
		rts
.step:
		move.w	(a1),d0
		cmp.w	d1,d0
		beq.s	.same
		jsr		colorStepTo			; (scroller.s) uses d2-d4, -> d6
		move.w	d6,(a1)
		st		d5
.same:
		rts

;--- 2: the thinning --------------------------
; the first four frames choose who stays, a layer a frame (warpKeepers);
; every frame the dying ones step down the ramp when their time comes:
; bright, middle, dim, gone. once none is left: into depth
warpThin:
		move.w	warpT,d0
		cmp.w	#4,d0
		bhi.s	.steps
		subq.w	#1,d0
		bsr		warpKeepers
.steps:
		lea		slst0+4,a0
		lea		warpDie,a2
		moveq	#0,d5				; one still dying
		moveq	#4-1,d6
.layer:
		move.w	#stars_count-1,d7
.e:
		move.b	(a2)+,d0
		beq.s	.n
		subq.b	#1,d0
		bne.s	.wait
		movep.w	1(a0),d0			; the picture: plane A's and B's bit
		cmp.w	#$0101,d0
		bne.s	.s1
		moveq	#$0001,d0
		bra.s	.set
.s1:
		cmp.w	#$0001,d0
		bne.s	.s2
		move.w	#$0100,d0
		bra.s	.set
.s2:
		moveq	#0,d0
.set:
		movep.w	d0,1(a0)			; (movep leaves the flags as they were)
		beq.s	.gone
		moveq	#warpDieT,d0
.wait:
		move.b	d0,-1(a2)
		st		d5
		bra.s	.n
.gone:
		clr.b	-1(a2)
.n:
		addq.l	#8,a0
		dbf		d7,.e
		addq.l	#4,a0				; (the list's end)
		dbf		d6,.layer
		tst.b	d5
		bne		starsParallax		; on they go
		cmp.w	#4,warpT
		bls		starsParallax		; (not all layers chosen yet)
		bsr		starsParallax		; all gone: this frame's step still,
		bra		warpConvert			; then into depth

; d0 = a layer: of its stars in sight every other one stays (warpN in all
; at most) and gets its 3D star now, all but x (that moves on till the
; end); the others keep their dying frame from warpInit; the ones out of
; sight are gone at once
warpKeepers:
		move.w	d0,d6
		move.w	d0,d1
		mulu	#stars_count*8+4,d1
		lea		slst0,a0
		add.l	d1,a0
		lea		warpDie,a2
		move.w	d0,d1
		mulu	#stars_count,d1
		add.w	d1,a2
		move.w	warpKept,d5
		move.w	d5,d1
		lsl.w	#4,d1				; (ws_len)
		lea		warpStars,a3
		add.w	d1,a3
		moveq	#4,d3				; its depth: z = 64 << layer, so
		add.w	d6,d3				; x*z/4 = x << (4+layer)
		moveq	#1,d2
		and.w	d6,d2
		add.w	#$30-$20,d2			; the line of the layer's first star
		moveq	#0,d4				; every other one
		move.w	#stars_count-1,d7
.e:
		moveq	#0,d0
		move.b	1(a0),d0
		add.w	d0,d0
		moveq	#1,d1
		and.b	3(a0),d1
		or.w	d1,d0
		sub.w	#warpX0,d0
		cmp.w	#320,d0
		blo.s	.seen
		clr.l	4(a0)				; out of sight: gone, unseen
		clr.b	(a2)
		bra.s	.n
.seen:
		not.w	d4
		beq.s	.n					; (this one dies)
		cmp.w	#warpN,d5
		bhs.s	.n					; (the field is full: this one too)
		addq.w	#1,d5
		clr.b	(a2)				; stays
		move.l	a0,ws_entry(a3)		; (its parallax entry, till the end)
		move.w	d2,ws_line(a3)
		move.w	d2,d1
		sub.w	#warpCy,d1
		asl.w	d3,d1
		move.w	d1,ws_q(a3)
		move.w	#256,d1
		lsl.w	d6,d1
		move.w	d1,ws_z(a3)
		move.b	d3,ws_shift(a3)
		lea		ws_len(a3),a3
.n:
		addq.l	#8,a0
		addq.l	#1,a2
		addq.w	#2,d2
		dbf		d7,.e
		move.w	d5,warpKept
		rts

;--- 3: into depth ----------------------------
; the stars that stay become the field's: x from where the parallax has
; them now, the place on the same line in the field's list of the same
; channel (the layer: the same pair, the same colour), and there they are.
; one that went out of sight, and the places left over, come from far off
warpConvert:
		move.b	#3,warpState
		clr.w	warpT
		clr.w	warpPTot
		clr.w	warpHAcc
		clr.w	warpZTot
		clr.w	warpZAcc
		clr.l	accelX				; (no dots now)
		movem.l	a2-a5,-(a7)
		lea		warpLineTab,a0
		lea		wlst,a4
		lea		warpStars,a3
		moveq	#0,d5				; (warpSpawn: the way sideways ...
		move.w	#warpZNear,d6		; ... and ahead so far)
		move.w	warpKept,d7
		bra.s	.more
.star:
		move.l	ws_entry(a3),a1
		moveq	#0,d0
		move.b	1(a1),d0
		add.w	d0,d0
		moveq	#1,d1
		and.b	3(a1),d1
		or.w	d1,d0
		sub.w	#warpX0,d0			; x on the screen
		cmp.w	#320,d0
		blo.s	.seen
		bsr		warpSpawn			; went out of sight
		bra.s	.next
.seen:
		move.b	ws_shift(a3),d3
		move.w	d0,d2
		sub.w	#warpCx,d2
		asl.w	d3,d2
		move.w	d2,ws_p(a3)
		movep.w	5(a1),d2			; its colour
		move.w	d2,ws_code(a3)
		move.w	ws_line(a3),d1
		add.w	d1,d1
		add.w	d1,d1
		move.b	3(a0,d1.w),ws_flags(a3)
		move.w	(a0,d1.w),d1		; its place: list 0/1 ...
		subq.b	#4,d3
		cmp.b	#2,d3
		blo.s	.pair
		add.w	#2*warpChan,d1		; ... or the other pair's, 2/3
.pair:
		lea		(a4,d1.w),a5
		move.l	a5,ws_entry(a3)
		add.w	#warpX0,d0
		lsr.w	#1,d0
		move.b	d0,1(a5)
		move.b	ws_flags(a3),d2		; (move keeps X)
		roxl.b	#1,d2
		move.b	d2,3(a5)
		move.l	4(a1),4(a5)
.next:
		lea		ws_len(a3),a3
.more:
		dbf		d7,.star
		move.w	#warpN-1,d7
		sub.w	warpKept,d7
		bra.s	.more2
.spawn:
		bsr		warpSpawn			; the places left: far off, a bit further
		jsr		getRandomNumber		; each, coming in one after the other
		and.w	#511,d0				; once the field gets going
		add.w	d0,ws_z(a3)
		lea		ws_len(a3),a3
.more2:
		dbf		d7,.spawn
		; and the sprites take the field's lists from the next frame on
		move.l	warpSpr,a5
		move.l	#wlst,d0
		moveq	#4-1,d7
.ptr:
		move.w	d0,6(a5)
		swap	d0
		move.w	d0,2(a5)
		swap	d0
		add.l	#warpChan,d0
		addq.l	#8,a5
		dbf		d7,.ptr
		movem.l	(a7)+,a2-a5
		rts

;--- 3: the field, every frame ----------------
warpField:
		movem.l	a2-a5,-(a7)
		; the sideways glide eases on, as in updateStars
		move.w	starV,d1
		move.w	starTarget,d0
		sub.w	d1,d0
		move.w	starAcc,d2
		cmp.w	d2,d0
		ble.s	.e0
		move.w	d2,d0
.e0:
		neg.w	d2
		cmp.w	d2,d0
		bge.s	.e1
		move.w	d2,d0
.e1:
		add.w	d0,d1
		move.w	d1,starV
		; a = 0..256, sideways -> ahead: smoothstep, u*u*(3-2u)
		move.w	warpT,d0
		cmp.w	#warpBlendT,d0
		blo.s	.ramp
		move.w	#256,d0
		bra.s	.blend
.ramp:
		mulu	#65536/warpBlendT,d0
		lsr.l	#8,d0				; u 0..255
		move.w	d0,d1
		mulu	d1,d1
		lsr.l	#8,d1				; u*u
		add.w	d0,d0
		neg.w	d0
		add.w	#3*256,d0			; 3-2u
		mulu	d1,d0
		lsr.l	#8,d0
.blend:
		; sideways: x*z moves by starV/16 a frame (as the parallax's front
		; layer at z 64 moves starV/256 px), times 1-a
		move.w	#256,d1
		sub.w	d0,d1
		muls	starV,d1
		asr.l	#8,d1
		add.w	warpHAcc,d1
		move.w	d1,d2
		asr.w	#4,d2
		add.w	d2,warpPTot
		lsl.w	#4,d2
		sub.w	d2,d1
		move.w	d1,warpHAcc
		; ahead: warpVz times a
		mulu	#warpVz,d0
		lsr.l	#8,d0
		add.w	warpZAcc,d0
		move.w	d0,d1
		lsr.w	#8,d1
		add.w	d1,warpZTot
		and.w	#$ff,d0
		move.w	d0,warpZAcc

		lea		$dff000,a6
		lea		warpLineTab,a0
		lea		warpRTab,a2
		lea		warpStars,a3
		lea		wlst,a4
		move.w	warpPTot,d5
		move.w	warpZTot,d6
		add.w	#warpZNear,d6
		move.w	#warpN-1,d7
; registers in the loop: a0 lines, a2 1/z, a3 the star, a4 the lists, a6
; custom; d5 the way sideways, d6 the way ahead + warpZNear, d7 count
.star:
		movem.w	(a3),d0-d2			; x*z, y*z, z
		sub.w	d6,d2
		cmp.w	#warpZRange,d2
		bhi.s	.outZ
		add.w	d5,d0
		add.w	d2,d2
		add.w	d2,d2
		move.l	(a2,d2.w),d3		; colour : 1/z
		muls	d3,d0
		swap	d0
		add.w	#warpCx,d0
		cmp.w	#320,d0
		bhs.s	.goneJ
		muls	d3,d1
		swap	d1
		add.w	#warpCy,d1
		cmp.w	#warpLines,d1
		bhs.s	.goneJ
		cmp.w	ws_line(a3),d1
		bne.s	.newLineJ
		move.l	ws_entry(a3),a1
.put:
		; a1 = its entry: x (HSTART, and H0 with the E8/L8 bits)
		add.w	#warpX0,d0
		lsr.w	#1,d0
		move.b	d0,1(a1)
		move.b	ws_flags(a3),d4		; (move keeps X)
		roxl.b	#1,d4
		move.b	d4,3(a1)
		swap	d3
		cmp.w	ws_code(a3),d3
		bne.s	.colour
.next:
		lea		ws_len(a3),a3
		dbf		d7,.star
		movem.l	(a7)+,a2-a5
		rts
.colour:
		move.w	d3,ws_code(a3)
		movep.w	d3,5(a1)
		bra.s	.next
.outZ:
		tst.w	d2					; still to come (far off)?
		bpl.s	.next
.goneJ:
		bra		.gone
.newLineJ:
		bra		.newLine

.newLine:
		move.w	ws_line(a3),d2
		bmi.s	.fresh
		; the beam: not on or next to either line
		move.l	4(a6),d4
		lsr.l	#8,d4
		and.w	#$1ff,d4
		sub.w	#$20-2,d4			; its line in the field, + 2
		cmp.w	d2,d1
		blt.s	.up
		cmp.w	d2,d4				; down: before the old line - 2?
		blt.s	.go
		subq.w	#3,d4				; past the new one + 1?
		cmp.w	d1,d4
		bgt.s	.go
		bra.s	.defer
.up:
		cmp.w	d1,d4
		blt.s	.go
		subq.w	#3,d4
		cmp.w	d2,d4
		bgt.s	.go
.defer:
		addq.w	#1,warpDefers
		bra.s	.stay
.go:
		bsr		warpClaim
		bne.s	.moved
		addq.w	#1,warpLags
		; both places taken: one line nearer where it is, if that is not
		; where it is anyway
		cmp.w	d2,d1
		bgt.s	.ldn
		addq.w	#1,d1
		bra.s	.l2
.ldn:
		subq.w	#1,d1
.l2:
		cmp.w	d2,d1
		beq.s	.stay
		bsr		warpClaim
		bne.s	.moved
.stay:
		move.l	ws_entry(a3),a1
		bra		.put
.moved:
		move.l	ws_entry(a3),a5
		clr.l	4(a5)				; off the old line
		move.l	a1,ws_entry(a3)
		move.w	d1,ws_line(a3)
		move.w	#-1,ws_code(a3)		; (the new place's picture in, too)
		bra		.put
.fresh:
		bsr		warpClaim			; just come in: nothing to be seen yet,
		beq.s	.waits				; so no beam to mind
		move.l	a1,ws_entry(a3)
		move.w	d1,ws_line(a3)
		move.w	#-1,ws_code(a3)
		bra		.put
.waits:
		addq.w	#1,warpWaits
		bra		.next
.gone:
		; off the screen or past us: off its line, and far off again
		move.l	ws_entry(a3),d4
		beq.s	.free
		move.l	d4,a1
		clr.l	4(a1)
.free:
		bsr.s	warpSpawn
		bra		.next

; d1 = a line of the field -> a1 = a free place on it, NE (Z: both taken);
; ws_flags(a3) for it. uses d4/a5
warpClaim:
		move.w	d1,d4
		add.w	d4,d4
		add.w	d4,d4
		lea		(a0,d4.w),a5
		move.w	(a5),d4
		lea		(a4,d4.w),a1
		tst.l	4(a1)
		beq.s	.got
		lea		2*warpChan(a1),a1	; the other pair's
		tst.l	4(a1)
		beq.s	.got
		moveq	#0,d4
		rts
.got:
		move.b	3(a5),ws_flags(a3)
		moveq	#1,d4
		rts

; a3 = a star -> somewhere new, at z 512, coming in with the next step
; ahead. d5/d6 the way sideways/ahead as in warpField. uses d0/d1/d4
warpSpawn:
		jsr		getRandomNumber
		move.w	d0,d1
		and.w	#$7fff,d1
		move.w	d1,d4
		lsr.w	#2,d4
		add.w	d4,d1				; 0..40958
		sub.w	#20480,d1			; x -160..160 at z 512
		sub.w	d5,d1
		move.w	d1,ws_p(a3)
		swap	d0
		and.w	#$7fff,d0
		move.w	d0,d1
		lsr.w	#5,d1
		add.w	d0,d1				; 0..33790
		sub.w	#16895,d1			; y -132..132
		move.w	d1,ws_q(a3)
		move.w	d6,d1
		add.w	#warpZRange+1,d1
		move.w	d1,ws_z(a3)
		move.w	#-1,ws_line(a3)
		clr.l	ws_entry(a3)
		rts

;---------------------------------------------
warpState::		dc.b	0		; 0 off, 1 colours, 2 thinning, 3 the field
				even
warpT::			dc.w	0		; frames in the state
warpFadeC:		dc.w	0
warpKept:		dc.w	0		; stars chosen to stay so far
warpSpr:		dc.l	0		; the copper's sprite pointers
warpPTot::		dc.w	0		; the way sideways so far (x*z)
warpHAcc:		dc.w	0
warpZTot::		dc.w	0		; the way ahead so far (quarter z)
warpZAcc:		dc.w	0
warpLags::		dc.w	0		; (for the harness) moves both places full
warpDefers::	dc.w	0		; ... moves put off for the beam
warpWaits::		dc.w	0		; ... come in with no place yet
warpCount::		dc.w	warpN

		section "warpchip",bss_c
wlst::			ds.b	4*warpChan

		section "warpbss",bss
warpStars::		ds.b	warpN*ws_len
warpRTab::		ds.l	warpZRange+1
warpLineTab::	ds.l	warpLines
warpDie:		ds.b	4*stars_count
