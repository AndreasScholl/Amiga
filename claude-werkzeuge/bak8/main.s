; todo:
;    letters centering
;    letter i offset smaller
;

		INCDIR      "include"
		INCLUDE     "hw.i"
		INCLUDE     "funcdef.i"
		INCLUDE     "exec/exec_lib.i"
		INCLUDE     "graphics/graphics_lib.i"
		INCLUDE     "hardware/cia.i"

		section "code",data,chip
init:
		bsr		randomize
		move.l	#st,$80
		trap	#0

		move.l	$4,a6
		move.l	#lib,a1
		clr.l	d0
		jsr		-552(a6)
		move.l	d0,a4
		move.l	38(a4),$dff080
		clr.w	$dff088
		moveq	#0,d0
		rts

lib:	dc.b	'graphics.library',0
		even

; a new seed at every start, while the system still runs: the date and time
; (dos.library DateStamp - to the 50th of a second, so even without a
; battery clock the moment the demo gets started counts), where the beam
; is, and both CIA clocks (frames and lines since the machine came on).
; everything random follows from it - the ship comes in from somewhere
; else, and the whole fight goes another way: an AI at work, not a
; recording
randomize:
		movem.l	d0-d2/a0-a1/a6,-(a7)
		move.l	$4.w,a6
		lea		dosName(pc),a1
		moveq	#0,d0
		jsr		-552(a6)			; OpenLibrary
		tst.l	d0
		beq.s	.noDos
		move.l	d0,a6
		move.l	#dateStamp,d1
		jsr		-192(a6)			; DateStamp
		move.l	a6,a1
		move.l	$4.w,a6
		jsr		-414(a6)			; CloseLibrary
.noDos:
		move.l	dateStamp,d0		; days
		rol.l	#7,d0
		add.l	dateStamp+4,d0		; minutes
		swap	d0
		rol.l	#3,d0
		add.l	dateStamp+8,d0		; ticks
		rol.l	#5,d0
		eor.l	d0,seed
		move.l	$dff004,d0			; the beam
		moveq	#0,d1
		move.b	$bfea01,d1			; CIA-A: frames (read high to low,
		lsl.l	#8,d1				; the low byte lets the latch go)
		move.b	$bfe901,d1
		lsl.l	#8,d1
		move.b	$bfe801,d1
		swap	d1
		eor.l	d1,d0
		moveq	#0,d1
		move.b	$bfda00,d1			; CIA-B: lines
		lsl.l	#8,d1
		move.b	$bfd900,d1
		lsl.l	#8,d1
		move.b	$bfd800,d1
		rol.l	#3,d1
		eor.l	d1,d0
		eor.l	d0,seed+0
		moveq	#7,d2				; stir
.stir:	bsr		getRandomNumber
		dbf		d2,.stir
		movem.l	(a7)+,d0-d2/a0-a1/a6
		rts

dosName:	dc.b	'dos.library',0
		cnop	0,4
dateStamp:	dc.l	0,0,0

st:		
		move.w	#$2700,sr

		lea		$dff000,a6

        bsr		initDemoPart

		move.w	$dff01c,d0			;get intena
		or.w	#$8000,d0
		move.w	d0,intenaStore
		move.w	#$7fff,$dff09a		;disable ints.
		move.w	#$7fff,$dff09c
		move.l	$6c.w,lev3			; save level 3
		move.l	#vblank,$6c.w		; set my level 3
		move.w	#$c020,$dff09a		; allow level 3
		move.w	#$2200,sr

		jsr		initMusic

		bsr		main

		move.w	#$7fff,$dff09a
		move.w	#$7fff,$dff09c
		move.l	lev3,$6c
		move.w	intenaStore,$dff09a
		rte

;--------------------------------------------------------------
lev3:		
		dc.l	0
intenaStore:		
		dc.w	0

;--------------------------------------------------------------
main:		
		cmp.b	#$ff,$dff006
		bne.s	main

        bra.s   main
		; btst	#6,$bfe001
		; bne.s	main
		; rts

;--------------------------------------------------------------
vblank:		
		btst	#5,$dff01f		; vbl int.?
		beq.s	.nvbl
;		move.w	#$0020,$dff096	; disable sprite dma

		movem.l	d0-d7/a0-a6,-(a7)

		btst	#6,$bfe001
		bne.s	.noswitch
		move.w	#1,activePart
		bsr		initDemoPart
        bra.s   .end
.noswitch

		; --- update demo part
		lea		demoParts,a0
		move.w	activePart,d0
		lsl.w	#3,d0
        move.l	4(a0,d0.w),a0
		jsr		(a0)
.end:
		movem.l	(a7)+,d0-d7/a0-a6
		; move.w	#$f0f,$dff180
		move.w	#$0020,$dff09c
.nvbl:		
		rte
;-------
initDemoPart:
		lea		demoParts,a0
		move.w	activePart,d0
		lsl.w	#3,d0
        move.l	(a0,d0.w),a0
		jsr		(a0)
		rts

nextDemoPart::
		add.w	#1,activePart
		bsr		initDemoPart
		rts
;-------
activePart::
		dc.w	1

demoParts::
        dc.l    initGame, 		updateGamePart
        dc.l    initScroller, 	updateScroller
        ; dc.l    initCopper,		updateCopper

;-------
; -> d0 = a random long (all of it usable, the low bits as well).
; xorshift32: the old mulu kept only 16 bits of the seed and ran round
; after some 170 numbers - the ship's spots, the new stars came again and
; again at the same few places. keeps every other register
getRandomNumber::
		move.l	d1,-(a7)
		move.l	seed,d0
		bne.s	.ok
		moveq	#1,d0				; (never 0: it would stay 0)
.ok:
		move.l	d0,d1				; x ^= x << 13
		lsl.l	#8,d1
		lsl.l	#5,d1
		eor.l	d1,d0
		move.l	d0,d1				; x ^= x >> 17
		clr.w	d1
		swap	d1
		lsr.l	#1,d1
		eor.l	d1,d0
		move.l	d0,d1				; x ^= x << 5
		lsl.l	#5,d1
		eor.l	d1,d0
		move.l	d0,seed
		move.l	(a7)+,d1
		rts

seed: 
		dc.l	$fc091337
;------
bbusy::
		move.w	#$8400,DMACON(a6)	; set blitter nasty
.wait:	btst	#6,2(a6)
		bne.s	.wait
		move.w	#$0400,DMACON(a6)	; clear blitter nasty
		rts
;------
getkey::							;<get rawkey routine>
		lea		$bfe000,a5
		btst	#3,$d01(a5)
		beq.w	.nkpress

		move.b	$c01(a5),d0
		not.b	d0
		ror.b	#1,d0
		move.b	d0,kcode
					;<keyboard joystick simulation>
		move.b	jkcode(pc),d7

		btst	#7,d0			;key release?
		bne.s	.release		

		cmp.b	#$3a,d0			;return ?
		bne.s	.nojks
		st	jkbutt
.nojks:
		cmp.b	#$39,d0			;$60 ?
		bne.s	.nok1
		bset	#2,d7
		bclr	#0,d7
.nok1:		
		cmp.b	#$4d,d0			;$4d ?
		bne.s	.nok2
		bset	#0,d7
		bclr	#2,d7
.nok2:		
		cmp.b	#$32,d0			;$4e ?
		bne.s	.nok3
		bset	#1,d7
		bclr	#3,d7
.nok3:		
		cmp.b	#$31,d0			;$4f ?
		bne.s	.nok4
		bset	#3,d7
		bclr	#1,d7
.nok4:		
		bra.s	.norelease

.release:				;<key released!>
		bclr	#7,d0
		cmp.b	#$3a,d0			;return
		bne.s	.nojkr
		sf		jkbutt
.nojkr:		
		cmp.b	#$39,d0			;$4c ?
		bne.s	.nokr1
		bclr	#2,d7
.nokr1:		
		cmp.b	#$4d,d0			;$4d ?
		bne.s	.nokr2
		bclr	#0,d7
.nokr2:		
		cmp.b	#$32,d0			;$4e ?
		bne.s	.nokr3
		bclr	#1,d7
.nokr3:		
		cmp.b	#$31,d0			;$4f ?
		bne.s	.nokr4
		bclr	#3,d7
.nokr4:		
.norelease:	
		move.b	d7,jkcode

		bset	#6,$e01(a5) 
		move.w	#$80,d1		
.shake:		
		dbf	d1,.shake	 
		bclr	#6,$e01(a5)
		move.b	kcode(pc),d0
.nkpress:	
		rts
;-----------------------------------------
kcode::		dc.b	0
jkcode::	dc.b	0
jkbutt::	dc.b	0
		even
