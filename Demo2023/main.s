; todo:
;    letters explosion
;		with lines
;		     copy line data of letter (at obj init?)
;			 line data can be manipulated by explosion rotuine
;
;    letters centering
;    letter i offset smaller
;    letters explode after time
; 	 copperbar shadow on bottom side
;    ship respawn
;    scroller without posteffect
;
; oder mit ablauf?
;    sterne im hintergrund -> weltraum :)
;    dann passieren verschiedene sachen vor dem sternenhintergrund
;    	asteroids game mit namen
;       scroller
;       logo erscheint
;       ...

		INCDIR      "include"
		INCLUDE     "hw.i"
		INCLUDE     "funcdef.i"
		INCLUDE     "exec/exec_lib.i"
		INCLUDE     "graphics/graphics_lib.i"
		INCLUDE     "hardware/cia.i"

		section "code",data,chip
init:
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

st:		
		move.w	#$2700,sr

		lea		$dff000,a6

        ; jsr     initGame
        jsr     initScroller

		move.w	$dff01c,d0			;get intena
		or.w	#$8000,d0
		move.w	d0,intenaStore
		move.w	#$7fff,$dff09a		;disable ints.
		move.w	#$7fff,$dff09c
		move.l	$6c.w,lev3			; save level 3
		move.l	#vblank,$6c.w		; set my level 3
		move.w	#$c020,$dff09a		; allow level 3
		move.w	#$2200,sr

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
        jsr     initGame
        ; jsr     initScroller
        ; move.l  #updateScroller,d0
        move.l  #updateGamePart,d0
        move.l  d0,updateFunction
        bra.s   .end
.noswitch

        move.l  updateFunction,a0
        jsr     (a0)
.end:
		movem.l	(a7)+,d0-d7/a0-a6
		move.w	#$0020,$dff09c
.nvbl:		
		rte
;-------
updateFunction:
        ; dc.l    updateGamePart
        dc.l    updateScroller
;-------
getRandomNumber::
		move.l 	seed,d0
		mulu 	#$a57b,d0
		addi.l 	#$bb40e62d,d0
 		rol.l	#6,d0
		move.l 	d0,seed
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
