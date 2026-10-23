;======================================================================
; warp.i - the Elite transition, step 1: the parallax stars go over into
; a 3D starfield that comes at the viewer out of the depth. included at
; the end of asteroids.s (the stars live there).
;
; after the scroller is gone and the ship has had a look round (AFTER,
; warpWait frames - seq_after calls warpStart):
;   1  colours  the four layers' own colours go over to one brightness ramp
;               by depth, the same in both sprite pairs (warpCol1..3): the
;               front layer bright, the two middle ones middle, the back one
;               dim. first the two colour registers nobody uses (19 and 22)
;               take copies of the front and the third layer's colours, so
;               those can be put on them unseen and every pair has its
;               dim, middle and bright one
;   2  thinning of the stars in sight every other one fades out, a step of
;               the ramp every warpDieT frames, each from its own random
;               frame (warpDie): 480 are too many for four sprites once the
;               stars go up and down as well
;   3  depth    the rest become 3D stars right where they are: the depth
;               comes from the layer's speed (half as fast is twice as far:
;               z 64, 128, 256, 512), x and y are the screen place times the
;               depth. the sideways glide goes on and blends over warpBlendT
;               frames (smoothstep) into flying ahead: z gets less, the stars
;               come out of the middle along 1/z (warpRTab, made at init - no
;               division at run time), brighter as they come nearer; one
;               that leaves the screen comes back far off, somewhere new
;
; the stars are the same four sprites, each used again every two lines, on
; lists of their own now (wlst): a list has an entry for every other line
; of $20..$12b, so every line has two places, one in each colour pair. a
; star that comes onto another line takes a free place there; if both are
; taken it stays on its line a frame more (warpLags) - it never goes off.
; the lists are written while the beam shows them, so a star only changes
; lines when the beam is not on or next to either line (else it could be
; seen twice, or not at all, that frame); if it is, the star changes a
; frame later (warpDefers)
;======================================================================

		section "code",data,chip

warpWait	= 100		; AFTER frames (the ship looking round) before it starts
warpAcc		= 1			; starAcc from then on: the sideways glide dies slowly
warpFadeT	= 2			; frames a step of the colours (13 steps)
warpThinT	= 32		; the dying stars start within this many frames
warpDieT	= 2			; frames a brightness step of a dying star
warpBlendT	= 110		; frames from sideways to straight ahead
warpVz		= 1536		; the speed ahead at the end, 1/256 quarter z a frame
						; (1536: 1.5 z a frame)
warpN		= 144		; stars in the field (each costs ~450 cycles a frame)
warpZNear	= 36		; quarter z: nearer than z 9 a star is gone
warpZFar	= 2048		; quarter z: z 512, the back layer - they come from here
warpZBright	= 384		; quarter z: nearer than z 96 bright ...
warpZMid	= 1536		; ... nearer than z 384 middle, else dim
warpZBright2	= 1152		; once the field runs these reach further back, a few
warpZMid2	= 1792		; a frame: bright to z 288, middle to z 448 - so far
warpBrightStep	= 7		; more stars turn bright before they are past
warpMidStep	= 3
warpCol1	= $0125		; dim: the old back layer's blue
warpCol2	= $0371		; middle: the old second layer's green
warpCol3	= $0842		; bright: the old front layer's orange
	ifne	elite3
; (elite3) the four layers' colours at the end of the fade: those of the
; bitplane field's depth bands they go into (stars3d.i s3Band, scroller.s
; ELC1..7) - not a star changes its colour at the switch
	ifne	starPal2
warpColF	= $0842		; (switches.i starPal2) every layer keeps its own
warpColS	= $0371		; colour - the Defender's orange-brown, green,
warpColT	= $0631		; brown-red, blue: the bands they go into have them
warpColB	= $0125
	else
warpColF	= $0b72		; the front layer: orange
warpColS	= $0a32		; the second: red
warpColT	= $0a32		; the third: red (in the same band as the second)
warpColB	= $0125		; the back: dark blue (as it was)
	endc
	else
warpColF	= warpCol3
warpColS	= warpCol2
warpColT	= warpCol2
warpColB	= warpCol1
	endc
warpCx		= 160		; the middle of the field: screen x 0..319 ...
warpCy		= 134		; ... and line from $20 ($a6)

warpLines	= $12c-$20	; lines $20..$12b
warpSlots	= warpLines/2	; entries a list
warpChan	= warpSlots*8+4	; a list, with its end
warpZRange	= warpZFar-warpZNear
warpX0		= 113		; sprite x (9 bits) of screen x 0
warpRotStep	= 53		; (warpField: the next first star, prime to warpN)

; a star
ws_p		= 0			; x times z, less the field's way sideways (warpPTot)
ws_q		= 2			; y times z (both: px * z/4)
ws_z		= 4			; quarter z plus the way ahead so far (warpZTot)
ws_line		= 6			; the line it is shown on (from $20), -1 none
ws_entry	= 8			; its list entry
ws_flags	= 12		; the entry's E8/L8 bits >> 1
ws_shift	= 13		; (till the field starts: 4 + its layer)
ws_code		= 14		; its colour as written (movep: A<<8 | B)
ws_len		= 16

;---------------------------------------------
; once, from initScroller: a5 = the copper's sprite pointers
warpInit::
		move.l	a5,warpSpr
	ifeq	dropWarpMem					; (switches.i: the tables of warp.i's own field -
										; never read under dropWarpSpr)
		; the lists: each entry's lines, for good. the picture and x later
		lea		wlst,a0
		moveq	#0,d6
.chan:
		moveq	#1,d0
		and.w	d6,d0
		add.w	#$20,d0
		move.w	#warpSlots-1,d7
.slot:
		bsr		warpCtlFlags
		move.b	d0,(a0)+
		clr.b	(a0)+
		move.w	d0,d1
		addq.w	#1,d1
		move.b	d1,(a0)+
		move.b	d2,(a0)+
		clr.l	(a0)+
		addq.w	#2,d0
		dbf		d7,.slot
		clr.l	(a0)+
		addq.w	#1,d6
		cmp.w	#4,d6
		bne.s	.chan
		; a line -> its place in list 0 or 1 (the other pair's is 2 lists on)
		lea		warpLineTab,a0
		moveq	#0,d1
.line:
		moveq	#1,d2
		and.w	d1,d2
		mulu	#warpChan,d2
		move.w	d1,d3
		lsr.w	#1,d3
		lsl.w	#3,d3
		add.w	d3,d2
		move.w	d2,(a0)+
		move.w	d1,d0
		add.w	#$20,d0
		bsr		warpCtlFlags
		lsr.w	#1,d2
		move.w	d2,(a0)+
		addq.w	#1,d1
		cmp.w	#warpLines,d1
		bne.s	.line
		; 1/z: 2^20 / quarter z (the 16 bits of x*z/4 times this, the high
		; word, is x again), and the colour by depth above it
		lea		warpRTab,a0
		move.w	#warpZNear,d0
.r:
		move.l	#$100000,d1
		divu	d0,d1
		move.w	#$0100,d2
		cmp.w	#warpZMid,d0
		bhs.s	.c
		moveq	#$0001,d2
		cmp.w	#warpZBright,d0
		bhs.s	.c
		move.w	#$0101,d2
.c:
		move.w	d2,(a0)+
		move.w	d1,(a0)+
		addq.w	#1,d0
		cmp.w	#warpZFar+1,d0
		bne.s	.r
		; the frame each star would start dying at, 1..warpThinT (its own
		; little random, so the game's stays as it was)
		lea		warpDie,a0
		move.w	#4*stars_count-1,d7
		move.w	#$1234,d0
.d:
		mulu	#25173,d0
		add.w	#13849,d0
		move.w	d0,d1
		lsr.w	#8,d1
		mulu	#warpThinT,d1
		lsr.w	#8,d1
		addq.w	#1,d1
		move.b	d1,(a0)+
		dbf		d7,.d
	endc
	ifne	elite3
		bsr		morphInit			; (morph.i)
	endc
		rts

; d0 = a sprite's (one line) start line -> d2 = its E8/L8 bits
warpCtlFlags:
		moveq	#0,d2
		cmp.w	#$ff,d0
		blo.s	.f
		moveq	#2,d2				; stops at $100
		cmp.w	#$100,d0
		blo.s	.f
		moveq	#6,d2				; starts there or below
.f:
		rts

	ifne	dropWarpSpr
	ifeq	elite3
	fail	"dropWarpSpr needs elite3"
	endc
	endc
;---------------------------------------------
;---------------------------------------------
; seq_after: off it goes. keeps a0
warpStart::
		tst.b	warpState
		bne.s	.out
		move.b	#1,warpState
		clr.w	warpT
		jsr		getRandomNumber		; (a start for warpRandom, new each run)
		move.l	d0,warpSeed
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
	ifne	elite3
		tst.b	s3On				; (stars3d.i: the field in bitplanes)
		bne		s3Field
	endc
		movem.l	a2-a5,-(a7)
		bsr.s	.go
		movem.l	(a7)+,a2-a5
		rts
.go:
		addq.w	#1,warpT
		move.b	warpState,d0
	ifeq	dropWarpSpr
		cmp.b	#3,d0
		beq		warpField
		cmp.b	#2,d0
		beq		warpThin
	endc
	ifne	elite3
		cmp.b	#4,d0			; (the field's second frame of making)
		bne.s	.g1
		jsr		s3Begin2
		bra		starsParallax
.g1:
	endc
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
		move.w	#warpColS,d1
		bsr.s	.step
		lea		starColours+10,a1	; 19: the front -> bright
		move.w	#warpColF,d1
		bsr.s	.step
		lea		starColours+14,a1	; 21: the back -> dim
		move.w	#warpColB,d1
		bsr.s	.step
		lea		starColours+18,a1	; 22: the third -> middle
		move.w	#warpColT,d1
		bsr.s	.step
		tst.w	d5
		bne.s	.out
	ifne	elite3
		jsr		s3Begin				; all there: every star into 3D, in
		move.b	#4,warpState		; bitplanes (stars3d.i), two frames
		rts
	endc
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
	ifeq	dropWarpSpr			; (switches.i: under elite3 the stars go to stars3d.i
								; before any of this - left out)

;--- 2: the thinning --------------------------
; the first four frames choose who stays, a layer a frame (warpKeepers);
; every frame the dying ones step down the ramp when their time comes:
; bright, middle, dim, gone. once none is left: into depth
warpThin:
		tst.b	warpThinDone		; the last one went last frame: this
		beq.s	.on					; frame's step, then into depth
		bsr		starsParallax
		bra		warpConvert
.on:
		move.w	warpT,d0
		cmp.w	#4,d0
		bhi.s	.early
		subq.w	#1,d0
		bsr		warpKeepers
		bra.s	.steps
.early:
		bsr		warpGoneEarly		; (the kept ones out of sight, an eighth)
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
		st		warpThinDone		; all gone (into depth next frame - not
		bsr		warpRest			; on top of this loop; nor the places left
		bra		starsParallax		; over: they are filled now)

; the stars chosen to stay that have gone out of sight while the others
; died (fast stars go a long way in that time): far off and new now, not
; all in warpConvert's frame. an eighth of them a frame (warpT picks which)
warpGoneEarly:
		moveq	#7,d0
		and.w	warpT,d0
		move.w	d0,d1
		lsl.w	#4,d1				; (ws_len)
		lea		warpStars,a3
		add.w	d1,a3
		move.w	warpKept,d7
		sub.w	d0,d7
		ble.s	.out
		addq.w	#7,d7
		lsr.w	#3,d7				; how many of the eighth
		moveq	#0,d5
		move.w	#warpZNear,d6
		bra.s	.more
.star:
		move.l	ws_entry(a3),d0
		beq.s	.next
		move.l	d0,a1
		moveq	#0,d0
		move.b	1(a1),d0
		add.w	d0,d0
		moveq	#1,d1
		and.b	3(a1),d1
		or.w	d1,d0
		sub.w	#warpX0,d0
		cmp.w	#320,d0
		blo.s	.next
		bsr		warpSpawn
		move.w	warpSeed,d0
		lsr.w	#5,d0
		and.w	#511,d0
		add.w	d0,ws_z(a3)
.next:
		lea		8*ws_len(a3),a3
.more:
		dbf		d7,.star
.out:
		rts

; the field's places no star of the parallax keeps: far off, a bit further
; each, coming in one after the other once the field gets going. done the
; frame before warpConvert - with the stars going fast more of them are
; left over, and both in one frame came to 122k
warpRest:
		lea		warpStars,a3
		move.w	warpKept,d7
		move.w	d7,d0
		lsl.w	#4,d0				; (ws_len)
		add.w	d0,a3
		neg.w	d7
		add.w	#warpN,d7
		moveq	#0,d5				; (warpSpawn: the way sideways and ahead
		move.w	#warpZNear,d6		; as warpConvert starts them)
		bra.s	.more
.spawn:
		bsr		warpSpawn
		move.w	warpSeed,d0			; (the last number's top bits)
		lsr.w	#5,d0
		and.w	#511,d0
		add.w	d0,ws_z(a3)
		lea		ws_len(a3),a3
.more:
		dbf		d7,.spawn
		rts

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
		moveq	#0,d0
		move.b	(a2),d0				; (its dying frame, 1..warpThinT: a random
		clr.b	(a2)				; number of its own for the depth below)
		move.l	a0,ws_entry(a3)		; (its parallax entry, till the end)
		move.w	d2,ws_line(a3)
		; its depth: the layer's (z = 64 << layer), give or take an eighth -
		; the stars of a layer all at one depth would come out of the middle
		; in step, a row like beads on a string. the back layer only nearer
		; (further is outside the field); the colour stays as it is
		move.w	#256,d1
		lsl.w	d6,d1
		sub.w	#warpThinT/2+1,d0
		lsl.w	#3,d0				; -128..120
		cmp.w	#3,d6
		bne.s	.jit
		tst.w	d0
		bmi.s	.jit
		neg.w	d0
.jit:
		muls	d1,d0
		asr.l	#8,d0
		asr.l	#2,d0
		add.w	d0,d1
		move.w	d1,ws_z(a3)
		move.w	d2,d0				; y times the depth (y*z/4 = y*Zb/16)
		sub.w	#warpCy,d0
		muls	d1,d0
		asr.l	#4,d0
		move.w	d0,ws_q(a3)
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
		lea		warpLineTab,a0
		lea		wlst,a4
		lea		warpStars,a3
		moveq	#0,d5				; (warpSpawn: the way sideways ...
		move.w	#warpZNear,d6		; ... and ahead so far)
		move.w	warpKept,d7
		bra.s	.more
.star:
		move.l	ws_entry(a3),d0
		beq.s	.next				; (new already: warpGoneEarly)
		move.l	d0,a1
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
		move.w	d0,d2				; x times its depth
		sub.w	#warpCx,d2
		muls	ws_z(a3),d2
		asr.l	#4,d2
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
		; (the places left over got their stars a frame before: warpRest)
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
		rts

;--- 3: the field, every frame ----------------
warpField:
		; the bright and the middle colour reach further back, step by step
		; (warpZBright2, warpZMid2): the table's colour words are moved on
		move.w	warpBrightZ,d0
		cmp.w	#warpZBright2,d0
		bhs.s	.bDone
		move.w	#$0101,d3
		moveq	#warpBrightStep-1,d1
		bsr.s	.reach
		move.w	d0,warpBrightZ
.bDone:
		move.w	warpMidZ,d0
		cmp.w	#warpZMid2,d0
		bhs.s	.mDone
		moveq	#$0001,d3
		moveq	#warpMidStep-1,d1
		bsr.s	.reach
		move.w	d0,warpMidZ
		bra.s	.mDone
.reach:
		lea		warpRTab-warpZNear*4,a1
.rStep:
		move.w	d0,d2
		add.w	d2,d2
		add.w	d2,d2
		move.w	d3,(a1,d2.w)
		addq.w	#1,d0
		dbf		d1,.rStep
		rts
.mDone:
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
		; ahead: warpVzNow (warpVz; morph.i speeds it up for the fly-by)
		; times a
		mulu	warpVzNow,d0
		lsr.l	#8,d0
		add.w	warpZAcc,d0
		move.w	d0,d1
		lsr.w	#8,d1
		add.w	d1,warpZTot
		and.w	#$ff,d0
		move.w	d0,warpZAcc

		; a different star first every frame: the loop takes as long every
		; frame, so a star always done at the same time would always find
		; the beam in the same place - and one near the top would be put off
		; for the beam again and again
		move.w	warpRot,d0
		add.w	#warpRotStep,d0
		cmp.w	#warpN,d0
		blo.s	.rot
		sub.w	#warpN,d0
.rot:
		move.w	d0,warpRot
		move.w	d0,warpLeft			; (the ones before it, after)
		lea		warpStars,a3
		move.w	d0,d1
		lsl.w	#4,d1				; (ws_len)
		add.w	d1,a3
		move.w	#warpN-1,d7
		sub.w	d0,d7
		lea		$dff000,a6
		lea		warpLineTab,a0
		lea		warpRTab,a2
		lea		wlst,a4
		move.w	warpPTot,d5
		move.w	warpZTot,d6
		add.w	#warpZNear,d6
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
		move.w	warpLeft,d7
		beq.s	.done
		clr.w	warpLeft
		subq.w	#1,d7
		lea		warpStars,a3
		bra		.star
.done:
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
		; both places taken: the nearest free line back toward where it is
		; (three tries - it lags a little, never far)
		move.w	#3,d3				; (the colour stays in the high word)
.back:
		cmp.w	d2,d1
		blt.s	.bUp
		subq.w	#1,d1
		bra.s	.bTry
.bUp:
		addq.w	#1,d1
.bTry:
		cmp.w	d2,d1
		beq.s	.stay
		bsr		warpClaim
		bne.s	.moved
		subq.w	#1,d3
		bne.s	.back
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
		bne.s	.born				; so no beam to mind. both places taken:
		addq.w	#1,d1				; the line below, or the one above
		cmp.w	#warpLines,d1
		bhs.s	.f2
		bsr		warpClaim
		bne.s	.born
.f2:
		subq.w	#2,d1
		bmi.s	.waits
		bsr		warpClaim
		beq.s	.waits
.born:
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

; -> d0 = a random long, its high word the good one. the warp's own: the
; game's getRandomNumber keeps only 16 bits and runs round after some 170
; numbers - new stars came again and again at the same few places and
; followed each other along the same ray, like beads on a string.
; x*69069+1 (mod 2^32), full period
warpRandom:							; (uses d1/d2)
		move.l	warpSeed,d0
		move.w	d0,d1
		mulu	#$0dcd,d1			; low * $0dcd
		move.l	d0,d2
		swap	d2
		mulu	#$0dcd,d2			; high * $0dcd, << 16
		swap	d2
		clr.w	d2
		add.l	d2,d1
		swap	d0					; + x << 16 (69069 = $10dcd)
		clr.w	d0
		add.l	d1,d0
		addq.l	#1,d0
		move.l	d0,warpSeed
		rts

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
		; x, y and a little depth each (so that two born in the same frame
		; do not move in step), from warpRandom
		bsr		warpRandom
		swap	d0
		and.w	#$7fff,d0
		move.w	d0,d1
		lsr.w	#2,d1
		add.w	d0,d1				; 0..40958
		sub.w	#20480,d1			; x -160..160 at z 512
		sub.w	d5,d1
		move.w	d1,ws_p(a3)
		bsr		warpRandom
		swap	d0
		move.w	d0,d1
		and.w	#$7fff,d1
		move.w	d1,d2
		lsr.w	#5,d2
		add.w	d2,d1				; 0..33790
		swap	d0
		sub.w	#16895,d1			; y -132..132
		move.w	d1,ws_q(a3)
		moveq	#63,d4				; (the low word's top bits: good enough)
		rol.w	#6,d0
		and.w	d0,d4
		add.w	d6,d4
		add.w	#warpZRange+1,d4
		add.w	warpPark,d4			; (morph.i: further off while the ship is big)
		move.w	d4,ws_z(a3)
		move.w	#-1,ws_line(a3)
		clr.l	ws_entry(a3)
		rts
	endc

;---------------------------------------------
warpState::		dc.b	0		; 0 off, 1 colours, 2 thinning, 3 the field, 4 its making (stars3d.i)
warpThinDone:	dc.b	0		; (2: all the dying ones gone)
				even
warpT::			dc.w	0		; frames in the state
warpFadeC:		dc.w	0
warpKept:		dc.w	0		; stars chosen to stay so far
warpRot:		dc.w	0		; the star the field starts with this frame
warpLeft:		dc.w	0
warpSpr:		dc.l	0		; the copper's sprite pointers
warpSeed:		dc.l	0		; warpRandom
warpBrightZ:	dc.w	warpZBright	; the bright colour's reach now (quarter z)
warpMidZ:		dc.w	warpZMid		; ... the middle one's
warpPTot::		dc.w	0		; the way sideways so far (x*z)
warpHAcc:		dc.w	0
warpZTot::		dc.w	0		; the way ahead so far (quarter z)
warpZAcc:		dc.w	0
warpLags::		dc.w	0		; (for the harness) moves both places full
warpDefers::	dc.w	0		; ... moves put off for the beam
warpWaits::		dc.w	0		; ... come in with no place yet
warpCount::		dc.w	warpN
warpVzNow::		dc.w	warpVz	; the speed ahead now
warpPark::		dc.w	0		; new stars this much further off (quarter z)

	ifeq	dropWarpMem					; (switches.i: never read under dropWarpSpr)
		section "warpchip",bss_c
wlst::			ds.b	4*warpChan

		section "warpbss",bss
warpStars::		ds.b	warpN*ws_len
warpRTab::		ds.l	warpZRange+1
warpLineTab::	ds.l	warpLines
warpDie:		ds.b	4*stars_count
	endc
