;======================================================================
; warp.i - the Elite transition, step 1: the parallax stars go over into
; a 3D starfield that comes at the viewer out of the depth. included at
; the end of asteroids.s (the stars live there).
;
; after the scroller is gone and the ship has had a look round (AFTER,
; warpWait frames - seq_after calls warpStart; F9 does it at once):
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
warpN		= 160		; stars in the field (each costs ~400 cycles a frame)
warpZNear	= 36		; quarter z: nearer than z 9 a star is gone
warpZFar	= 2048		; quarter z: z 512, the back layer - they come from here
warpZBright	= 384		; quarter z: nearer than z 96 bright ...
warpZMid	= 1536		; ... nearer than z 384 middle, else dim
warpCol1	= $0335		; dim
warpCol2	= $088a		; middle
warpCol3	= $0fff		; bright
warpCx		= 160		; the middle of the field: screen x 0..319 ...
warpCy		= 134		; ... and line from $20 ($a6)

warpLines	= $12c-$20	; lines $20..$12b
warpSlots	= warpLines/2	; entries a list
warpChan	= warpSlots*8+4	; a list, with its end
warpZRange	= warpZFar-warpZNear
warpX0		= 113		; sprite x (9 bits) of screen x 0

; a star
ws_p		= 0			; x times z, less the field's way sideways (warpPTot)
ws_q		= 2			; y times z (both: px * z/4)
ws_z		= 4			; quarter z plus the way ahead so far (warpZTot)
ws_line		= 6			; the line it is shown on (from $20), -1 none
ws_entry	= 8			; its list entry
ws_flags	= 12		; the entry's E8/L8 bits >> 1
ws_code		= 14		; its colour as written (movep: A<<8 | B)
ws_len		= 16

;---------------------------------------------
; once, from initScroller: a5 = the copper's sprite pointers
warpInit::
		move.l	a5,warpSpr
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

;---------------------------------------------
