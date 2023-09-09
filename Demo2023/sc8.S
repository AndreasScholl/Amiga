
		INCDIR      "include"
		INCLUDE     "hw.i"
		INCLUDE     "funcdef.i"
		INCLUDE     "exec/exec_lib.i"
		INCLUDE     "graphics/graphics_lib.i"
		INCLUDE     "hardware/cia.i"

logoY			= $40

src_adr			= $6e000		; scroll buffer source adress
src_line 		= $32			; source line width

;screen			= $70000		; single color bitplane start
screenHeight	= 128
li				= $2e			; screen line size in bytes

; ho				= li*23		; dst height start offset
sc_offset		= 82			; scroller y offset
ho				= li*sc_offset	; dst height start offset
yTop			= sc_offset-23	; scroller top y pos (for copy and pixel effect)
sc_top			= yTop*li		;

ss		 		= $6e014		; source start of scoller turn
ds		 		= $14			; destination start	of scroller turn

game_width		= 352
game_height		= 160

;numPoints		= 128
numPoints		= 64

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

		move.l	#logo,d0
		move.l	#(320/8)*64,d1
		move.w	d0,logobp0l
		swap	d0
		move.w	d0,logobp0h
		swap	d0
		add.l	d1,d0
		move.w	d0,logobp1l
		swap	d0
		move.w	d0,logobp1h
		swap	d0
		add.l	d1,d0
		move.w	d0,logobp2l
		swap	d0
		move.w	d0,logobp2h
		swap	d0
		add.l	d1,d0
		move.w	d0,logobp3l
		swap	d0
		move.w	d0,logobp3h

		bsr		buildLogoColors

		bsr		setupStarfield	; starfield
		bsr		setupScroller
		bsr		initPoints
		bsr		initGame

;		move.w	#$0020,$dff096

		move.w	$dff01c,d0			;get intena
		or.w	#$8000,d0
		move.w	d0,intenaStore
		move.w	#$7fff,$dff09a		;disable ints.
		move.w	#$7fff,$dff09c
		move.l	$6c.w,lev3		;save level 3
		move.l	#vblank,$6c.w		;set my level 3
		move.w	#$c020,$dff09a		;allow level 3
		move.w	#$2200,sr

 		move.l	#clist,$dff080
		clr.w	$dff088

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

		btst	#6,$bfe001
		bne.s	main
		rts
;--------------------------------------------------------------
vblank:		
		btst	#5,$dff01f		; vbl int.?
		beq.s	.nvbl
;		move.w	#$0020,$dff096	; disable sprite dma

		movem.l	d0-d7/a0-a6,-(a7)

		cmp.b	#$50,kcode
		bne.s	.ncol
		move.w	#$444,$dff180
.ncol:		
		bsr		getkey

		bsr		clear			;clear screen
		bsr		updateStars
 		bsr		updateGame

; 		tst.l	enemy_con		; all enemies gone?
; 		bne.s	.hmm
; 		bsr		initGame		; reset game
; .hmm:
		lea		$dff000,a6
		bsr		scroll
		; move.w	#$424,$180(a6)
		bsr		postEffect

		; move.w	#$266,$180(a6)
		lea		$dff000,a6
		bsr		addPoints
		bsr		drawPoints
		; move.w	#$882,$180(a6)
		; bsr		updateLogoColors		; super slow :(
		bsr		updateLogoPos

		movem.l	(a7)+,d0-d7/a0-a6
		move.w	#$0020,$dff09c
.nvbl:		
		rte

;-------
initPoints:
		lea		points,a5
		moveq	#0,d1
		move.l	#numPoints-1,d7		
.loop:	
		move.w	d1,point_life(a5)	

		lea		point_len(a5),a5
		dbf		d7,.loop
		rts

;-------
drawPoints:
		move.l	screenloc,a0
		lea		points,a5
		move.l	#numPoints-1,d7	
		moveq	#0,d0
		moveq	#0,d1
.loop:
		move.w	point_life(a5),d0
		beq		.next
		subq	#1,d0
		move.w	d0,point_life(a5)

		move.w	point_xvelo(a5),d2
		move.w	point_xfloat(a5),d0	; x fixed
		add.w	d2,d0				; + x velocity
		move.w	d0,point_xfloat(a5)	; store x
		lsr.w	#7,d0				; convert to integer

		add.w	#$07,d2				; accelerate
		move.w	d2,point_xvelo(a5)

		move.w	point_yvelo(a5),d2
		move.w	point_yfloat(a5),d1	; y fixed
		add.w	d2,d1				; + y velocity
		move.w	d1,point_yfloat(a5)	; store y
		lsr.w	#7,d1				; convert to integer

		; add.w	#$2,d2				; accelerate
;		addq	#1,d2				; accelerate
		move.w	d2,point_yvelo(a5)

		bsr		setPointScroller

.next:
		lea		point_len(a5),a5
		dbf		d7,.loop
		rts

;-------
addPoints:
		move.l	screenloc,a1
		add.l	#sc_top+8,a1
		moveq	#yTop,d7
		moveq	#6-1,d6
.addloop:		
		move.b	(a1),d0
		btst	#7,d0
		beq		.nopixel
		bsr		addPoint
.nopixel
		lea		li(a1),a1	; next line

		addq	#1,d7

		; cmp.w	#7,d7		
		; bne		.addloop
		dbf		d6,.addloop

		rts
;-------
addPoint:				; add single point at y offset d7

		lea		freePoint(pc),a0
		move.w	(a0),d0
		move.w	d0,d1
		mulu	#point_len,d1
		addq.w	#1,d0
		cmp.w	#numPoints,d0
		bne		.notend
		clr.w	d0
.notend:
		move.w	d0,(a0)
		lea		points,a5
		add.w	d1,a5
		move.w	#60,point_life(a5)

		move.w	#(8*8)+1,d0
		lsl.w	#7,d0
		move.w	d0,point_xfloat(a5)

		move.w	d7,d0			; y offset
		lsl.w	#7,d0
		move.w	d0,point_yfloat(a5)

		moveq	#0,d0			; x speed
		bsr		getRandomNumber
		and.w	#$7f,d0
		add.w	#$60,d0
;		move.w	#$80,d0
		neg.w	d0
		move.w	d0,point_xvelo(a5)

		move.w	#0,d0			; test y speed
		bsr		getRandomNumber
;		and.w	#$03,d0

		and.w	#$1f,d0
		sub.w	#$20,d0

;		sub.w	#16,d0
;		sub.w	d1,d0
		move.w	d0,point_yvelo(a5)

; 		add.w	#1,postest
; 		cmp.w	#7,postest
; 		bne		.nopostestend
; 		move.w	#0,postest
; .nopostestend:

		moveq	#0,d0
		rts

freePoint:					; index of next free point
		dc.w	0			

postest:	
		dc.w	0
;-------
postEffect:
; 		bsr		bbusy
; 		move.l	#screen,$54(a6)
; 		move.l	#-1,$44(a6)
; 		move.l	#0,$64(a6)
; 		move.l	#$01000000,$40(a6)
; 		move.w	#(screenHeight<<6)+(li/2),$58(a6)
; ;---
; 		bsr		bbusy

; 		lea		table,a2
; 		moveq	#((tabend-table)/10)-1,d7
; copyloop:
; 		move.l	(a2)+,a0
; 		move.w	(a2)+,d1
; 		move.l	(a2)+,a1
; 		bsr		copyColumn
; 		dbf		d7,copyloop

; backwards pixels and rest

		lea		table2,a2
		moveq	#((tabend2-table2)/12)-1,d7
		move.l	screenloc,d6
copyloop2:
		move.l	(a2)+,a0
		move.w	(a2)+,d1
		move.l	(a2)+,a1
		add.l	d6,a1
		move.w	(a2)+,d2
		bsr		copyColumnShift
		dbf		d7,copyloop2

;		rts
; copy rest of scroller (for now with processor)

; leftblock_words = 10
; 		lea		src_adr,a0
; 		lea 	$70000,a1
leftblock_words = 6
 		lea		src_adr+8,a0
 		;  lea 	$70000+8,a1							; dst
		move.l	screenloc,a1
		add.l 	#sc_top+8,a1						; dest
		move.l	#src_line-(leftblock_words*2),d4	; src modulo
		move.l	#li-(leftblock_words*2),d5			; dst modulo
		moveq	#7-1,d6			; height
lineloop:
		moveq	#leftblock_words-1,d7
rowloop:	
		move.w	(a0)+,(a1)+
;		move.w	#-1,(a1)+
		dbf		d7,rowloop
		add.l	d4,a0
		add.l	d5,a1
		dbf		d6,lineloop

		; rts	; test only left block

; right block
rightblock_words = 12
		lea		ss+6,a0				; source
;		lea 	$70016+ho,a1		; dest
		move.l	screenloc,a1
		add.l 	#ds+ho-(li*1)+2+1,a1	; dest
		move.l	#src_line-(rightblock_words*2),d4	; src modulo
		move.l	#li-(rightblock_words*2),d5			; dst modulo
		moveq	#7-1,d6			; height
lineloop2:
		moveq	#(rightblock_words*2)-1,d7
rowloop2:	
		move.b	(a0)+,(a1)+
;		ror.l	#8,d0
;		move.w	d0,(a1)+
;		move.w	#-1,(a1)+
		dbf		d7,rowloop2
		add.l	d4,a0
		add.l	d5,a1
		dbf		d6,lineloop2

		rts
;-------
copyColumn:
		move.w	(a0),d0
		and.w	d1,d0
		or.w	d0,(a1)		

		move.w	src_line*1(a0),d0
		and.w	d1,d0
		or.w	d0,li*1(a1)		

		move.w	src_line*2(a0),d0
		and.w	d1,d0
		or.w	d0,li*2(a1)		

		move.w	src_line*3(a0),d0
		and.w	d1,d0
		or.w	d0,li*3(a1)		

		move.w	src_line*4(a0),d0
		and.w	d1,d0
		or.w	d0,li*4(a1)		

		move.w	src_line*5(a0),d0
		and.w	d1,d0
		or.w	d0,li*5(a1)		

		rts

;-------
copyColumnShift:
		; tweak destination test -> doesnt work, would have to change the data in the table to not have a direct dest pointer
		; move.l	a1,d0
		; sub.l	#ds+ho,d0
		; lsr.l	#1,d0
		; bclr	#0,d0
		; add.l	#ds+ho,d0
		; move.l	d0,a1

		move.w	(a0),d0
		and.w	d1,d0
		ror.w	d2,d0
		or.w	d0,(a1)		

		move.w	src_line*1(a0),d0
		and.w	d1,d0
		ror.w	d2,d0
		or.w	d0,li*1(a1)		

		move.w	src_line*2(a0),d0
		and.w	d1,d0
		ror.w	d2,d0
		or.w	d0,li*2(a1)		

		move.w	src_line*3(a0),d0
		and.w	d1,d0
		ror.w	d2,d0
		or.w	d0,li*3(a1)		

		move.w	src_line*4(a0),d0
		and.w	d1,d0
		ror.w	d2,d0
		or.w	d0,li*4(a1)		

		move.w	src_line*5(a0),d0
		and.w	d1,d0
		ror.w	d2,d0
		or.w	d0,li*5(a1)		

		rts
;-----
getRandomNumber: 
		move.l 	seed,d0
		mulu 	#$a57b,d0
		addi.l 	#$bb40e62d,d0
 		rol.l	#6,d0
		move.l 	d0,seed
		rts

seed: 
		dc.l	$fc091337

table:		
		dc.l ss
		dc.w $000f
		dc.l ds+ho

		dc.l ss
		dc.w $0070
		dc.l ds+ho-(li*1)

		dc.l ss
		dc.w $0180
		dc.l ds+ho-(li*2)

		dc.l ss
		dc.w $0280
		dc.l ds+ho-(li*3)

		dc.l ss
		dc.w $0400
		dc.l ds+ho-(li*4)

		dc.l ss
		dc.w $0800
		dc.l ds+ho-(li*5)

		dc.l ss
		dc.w $0800
		dc.l ds+ho-(li*6)

		dc.l ss
		dc.w $0800
		dc.l ds+ho-(li*7)
tabend:		
;-------
; second table -> also able to shift dest pixels
; 		dc.l source address
;		dc.w bitmask
; 		dc.l dest address
; 		dc.w shift right amount
table2:
		; 6 pixels (forward direction)
		dc.l ss+4		;
		dc.w $003f
		dc.l ds+ho-(li*2)+2
		dc.w 8			;

		; 4 pixels (forward direction)
		dc.l ss+4		; 4/4
		dc.w $00c0
		dc.l ds+ho-(li*3)+2
		dc.w 8			;

		dc.l ss+4		; 2/4
		dc.w $0300
		dc.l ds+ho-(li*3)
		dc.w 8			;

		; 3 pixels (forward direction)
		dc.l ss+4		;
		dc.w $1c00
		dc.l ds+ho-(li*4)
		dc.w 8			;

		; 2 pixels (forward direction)
		dc.l ss+4		;
		dc.w $6000
		dc.l ds+ho-(li*5)
		dc.w 8			;

		; 1 pixel (forward direction)
		dc.l ss+4		;
		dc.w $8000
		dc.l ds+ho-(li*6)
		dc.w 8			;

		; 1 pixel (turn bottom pixel)
		dc.l ss+2		;
		dc.w $0001
		dc.l ds+ho-(li*7)
		dc.w 8			;

		; 1 pixel (turn mid pixel)
		dc.l ss+2		;
		dc.w $0002
		dc.l ds+ho-(li*8)
		dc.w 9			;

		; 1 pixel (turn top pixel)
		dc.l ss+2		;
		dc.w $0004
		dc.l ds+ho-(li*9)
		dc.w 10			;

		; 1 pixel
		dc.l ss+2		;
		dc.w $0008
		dc.l ds+ho-(li*10)
		dc.w 12			;

		; 2 pixels (backwards)
		dc.l ss+2		; 2/2
		dc.w $0010
		dc.l ds+ho-(li*11)
		dc.w 14			;

		dc.l ss+2		; 1/2
		dc.w $0020
		dc.l ds+ho-(li*11)
		dc.w 0

		; 3 pixels (backwards)
		dc.l ss+2		; 3/3
		dc.w $0040
		dc.l ds+ho-(li*12)
		dc.w 2			;

		dc.l ss+2		; 2/3
		dc.w $0080
		dc.l ds+ho-(li*12)
		dc.w 4			;

		dc.l ss+2		; 1/3
		dc.w $0100
		dc.l ds+ho-(li*12)
		dc.w 6

		; 2 pixels (backwards)
		dc.l ss+2		; 2/2
		dc.w $0200
		dc.l ds+ho-(li*13)
		dc.w 8			;

		dc.l ss+2		; 1/2
		dc.w $0400
		dc.l ds+ho-(li*13)
		dc.w 10			; <- 5

		dc.l ss+2		; 1 wide
		dc.w $0800
		dc.l ds+ho-(li*14)+2
		dc.w 12			; <- 4

		dc.l ss+2		; 1 wide
		dc.w $1000
		dc.l ds+ho-(li*15)+2
		dc.w 14			; <- 2

		dc.l ss+2		; 1 wide
		dc.w $2000
		dc.l ds+ho-(li*16)+2
		dc.w 15			; <- 1

		dc.l ss+2		; 1 wide
		dc.w $4000
		dc.l ds+ho-(li*17)+2
		dc.w 0

		dc.l ss+2		; 1 wide
		dc.w $8000
		dc.l ds+ho-(li*18)+2
		dc.w 0

		dc.l ss			; 2 wide
		dc.w $0003
		dc.l ds+ho-(li*19)
		dc.w 0

		dc.l ss			; 3 wide
		dc.w $001c
		dc.l ds+ho-(li*20)
		dc.w 0

		dc.l ss			; 4 wide
		dc.w $01e0
		dc.l ds+ho-(li*21)
		dc.w 0

		dc.l ss			; 5 wide
		dc.w $fe00
		dc.l ds+ho-(li*22)
		dc.w 0
tabend2:

;------------------------
setupScroller:
		bsr		mctab

		lea		$6e000-li,a0		; one more line for empty line -> sprite display
		move.l	#(li*8)/4,d7
.clear:
		clr.l	(a0)+
		dbf		d7,.clear

		rts
mctab:		
		lea		rchartab,a0
		lea		chartab,a1
		moveq	#0,d0
		moveq	#0,d1
makerctab:	
		move.b	(a1),d1
		move.b	d0,(a0,d1.w)
		addq.w	#1,d0
		tst.b	(a1)+
		bpl.s	makerctab
		rts
;------
bbusy:		
		move.w	#$8400,DMACON(a6)	; set blitter nasty
.wait:	btst	#6,2(a6)
		bne.s	.wait
		move.w	#$0400,DMACON(a6)	; clear blitter nasty
		rts
;------
scount:		
		dc.w	$11
tcount:		
		dc.w	$00
scwait:		
		dc.w	$00

scroll:		
;		lea	sreg+3,a0	; scroll register in copperlist
;		subq.b	#1,(a0)		; - scroll speed
;		bne.s	noscro
;		move.b	#$10,(a0)	; back to 16	
;noscro:		
		bsr		bbusy

		; scroll by 1 (pixels) with blitter
		move.w	#$8400,DMACON(a6)		
		move.l	#src_adr,$54(a6)
		move.l	#src_adr+2,$50(a6)
		move.l	#$f9f00000,BLTCON0(a6)
		move.l	#$00000000,BLTAMOD(a6)
		move.w	#(7*64)+(src_line/2),BLTSIZE(a6)	; size
		move.w	#$0400,DMACON(a6)

		lea		scount,a4
		subq.w	#1,(a4)
		beq.s	newchars	
		rts
newchars:
		move.w	#$10,(a4)

		moveq	#0,d7		; even letter
		bsr		putchar
		moveq	#1,d7		; uneven letter
		bsr		putchar
		rts
;-------	
putchar:	
		moveq	#0,d0
		lea		tcount,a4
		lea		text,a0
		add.w	(a4),a0
		addq.w	#1,(a4)
		moveq	#43,d1
		move.b	(a0),d0
		bne.s	notextfin
		clr.w	(a4)		
		bra.s	textfin2
notextfin:
		lea		rchartab,a1
		move.b	(a1,d0.w),d1
textfin2:	
		lea		char(pc),a2
		add.w	d1,a2
		lea		src_adr+src_line-2,a1	; offset to end of line (putchar destination)
		add.w	d7,a1

		bsr		bbusy

		move.b	(a2),(a1)
		move.b	050(a2),1*src_line(a1)
		move.b	100(a2),2*src_line(a1)
		move.b	150(a2),3*src_line(a1)
		move.b	200(a2),4*src_line(a1)
		move.b	250(a2),5*src_line(a1)
		rts	

		rsreset
point_life:	rs.w	1			;life time
point_xfloat:	rs.w	1		;x-coordinate (floating)
point_yfloat:	rs.w	1		;y-coordinate (floating)
point_xvelo:	rs.w	1		;x velocity
point_yvelo:	rs.w	1		;y velocity
point_len:	rs.w	0

points:		ds.b	point_len*numPoints

setPointScroller:
		cmp.w	#game_width-1,d0	; range check
		bhi.s	.npoint
		cmp.w	#game_height-1,d1
		bhi.s	.npoint

		mulu	#li,d1		; y * linesize	-> todo: use table to optimize
		move.w	d0,d2
		eor.w	#$07,d2
		lsr.w	#3,d0
		add.l	d0,d1
		move.l	a0,a1
		add.l	d1,a1
		bset	d2,(a1)
.npoint:
		rts

text:
;		dc.b	"                                                               "
		dc.b    "quadlite and thrust present the next iteration of the scroller --- "
		dc.b	"zeronine says hi to --- major rom --- mark ii ---- equalizer --- exciter --- "
		dc.b	"dandee -- lord performer --- exolon --- phil --- doctor soft --- kongoman and all the others ........ ",0
		even

chartab:
		dc.b	"abcdefghijklmnopqrstuvwxyz0123456789.,!()/$ ?-+='",-1
ctend:
		even

char:
		dc.l $78f87cf8,$fcfc7ccc,$fc3cccc0,$c6cc78f8,$78f87cfc,$ccccc6cc
		dc.l $ccfc7830,$f8f8c0fc,$7cfc7878,$00006030,$600c0000,$78000000
		dc.l $0c00cccc,$c0ccc0c0,$c0cc3018,$d8c0feec,$cccccccc,$c030cccc
		dc.l $c678cc18,$ccf00c0c,$d8c0c00c,$cccc0000,$60603018,$6000cc00
		dc.l $10780c00,$fcf8c0cc,$f8f8dcfc,$3018f0c0,$d6fccccc,$cccc7830
		dc.l $cc78d630,$7830cc30,$7838fcf8,$f818787c,$00006060,$30300000
		dc.l $18383800,$1800cccc,$c0ccc0c0,$cccc30d8,$d8c0c6dc,$ccf8d8f8
		dc.l $0c30cc78,$fe783060,$cc30c00c,$180ccc30,$cc0c6060,$00603060
		dc.l $00000000,$10780000,$ccf87cf8,$fcc07ccc,$fc70ccfc,$c6cc78c0
		dc.l $7cccf830,$7830c6cc,$30fc78fc,$fcf818f8,$786078f8,$60606030
		dc.l $60c06000,$30000000,$00000000,$00000000,$00000000,$00000000
		dc.l $00000000,$00000000,$00000000,$00000000,$00000000,$000000c0
		dc.l $00000000,$00000000,$00000000,$00000000,$00000000,$00000000

; colortest:
; 		lea		clistcolors+6,a0

; 		moveq	#0,d0
; 		moveq	#6,d6
; 		move.w	coloradd,d5
; .lines
; 		moveq	#45-1,d7
; .line
; 		move.w	d7,d0
; 		lsl.w	#4,d0
; 		add.w	d6,d0
; 		add.w	d5,d0
; 		move.w	d0,(a0)
; 		lea		4(a0),a0
; 		dbf		d7,.line
; 		lea		4(a0),a0
; 		dbf		d6,.lines

; 		add.w	#1,coloradd
; 		rts

; coloradd:
; 		dc.w	0

;		input:   d0: color
;				 d7: fade level (0-256)
;				 d6: output color
colorFade:
			; move.w	d0,d6
			move.w	d0,d1
			lsr.w	#8,d1		; r (nibble)
			mulu.w	d7,d1		; * fade level
			lsr.w	#8,d1		; / 256
			lsl.w	#8,d1		; shift r into right spot
			move.w	d1,d6			

			move.w	d0,d1
			lsr.w	#4,d1		; g (nibble)
			and.w	#$0f,d1
			mulu.w	d7,d1		; * fade level
			lsr.w	#8,d1		; / 256
			lsl.w	#4,d1		; shift g into right spot
			or.w	d1,d6

			move.w	d0,d1
			and.w	#$0f,d1		; b (nibble)
			mulu.w	d7,d1		; * fade level
			lsr.w	#8,d1		; / 256
			or.w	d1,d6
			rts

fadeIncrease = 4

buildLogoColors:
			lea		logoColors,a1
			lea		colorAdd,a2
			lea		fadeLevel,a3

			; move.w	#$6101,d4						; wait start
			move.w	#((logoY+1)<<8)+1,d4
;			move.w	#256-(44*fadeIncrease),d7		; fade level

			move.w	#44-1,d5
			bra		.skipWait				; first entry has no wait
.loop:
			move.w	d4,(a1)+				; copper wait
			move.w	#$fffe,(a1)+			;
			add.w	#$0100,d4
.skipWait:			
			move.w	(a2)+,d2				; color add test
			move.w	(a3)+,d7				; fade level
;			move.w	#256,d7

			lea		logoColorsOrig,a0
			move.w	#14-1,d3
.colorLoop:
			move.w	(a0)+,(a1)+				; color reg
			move.w	(a0)+,d0
			or.w	d2,d0

			bsr		colorFade
;			or.w	d2,d6
;			move.w	d0,d6

			move.w	d6,(a1)+				; color reg
			dbf		d3,.colorLoop

			dbf		d5,.loop
			rts

updateLogoColors:
			lea		logoColors+2,a1
			lea		colorAdd,a2
			lea		fadeLevel,a3

			move.w	#44-1,d5
			bra		.noWait				; first entry has no wait
.loop:
			lea		4(a1),a1				; skip wait
.noWait:			
			clr.w	d2
			move.w	(a2)+,d2				; color add
			add.w	colorAddVar,d2

			move.w	(a3)+,d7				; fade level
			add.w	colorFadeVar,d7
			cmp.w	#256,d7
			ble		.noHighFade
			move.w	#256,d7
.noHighFade

			lea		logoColorsOrig+2,a0
			move.w	#14-1,d3
.colorLoop:
			move.w	(a0),d0
			lea		4(a0),a0				; next source color value
			or.w	d2,d0
			bsr		colorFade
			move.w	d6,(a1)					; color value
			lea		4(a1),a1
			dbf		d3,.colorLoop

			dbf		d5,.loop

			add.w	#$001,colorAddVar

			move.w	colorFadeDir,d0
			add.w	d0,colorFadeVar

			add.w	#1,colorFadeDirCount
			cmp.w	#32,colorFadeDirCount
			bne		.noColFadeToggle
			move.w	#0,colorFadeDirCount
			neg.w	colorFadeDir
.noColFadeToggle
			rts

colorFadeDir:
			dc.w	4

colorFadeDirCount:
			dc.w	1

colorFadeVar:
			dc.w	0

colorAddVar:
			dc.w	0

colorAdd:
			dc.w	$0		; 0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$1
			dc.w	$1		; 10
			dc.w	$1
			dc.w	$2
			dc.w	$2
			dc.w	$2
			dc.w	$3
			dc.w	$3
			dc.w	$3
			dc.w	$3
			dc.w	$4
			dc.w	$4	; 20
			dc.w	$4
			dc.w	$5
			dc.w	$5
			dc.w	$5
			dc.w	$6
			dc.w	$6
			dc.w	$6
			dc.w	$7
			dc.w	$107
			dc.w	$107	; 30
			dc.w	$108
			dc.w	$108
			dc.w	$208
			dc.w	$209
			dc.w	$209
			dc.w	$209
			dc.w	$30a
			dc.w	$30a
			dc.w	$30a
			dc.w	$30a	; 40
			dc.w	$40b
			dc.w	$40b
			dc.w	$40b
			dc.w	$40c

fadeLevel:
			dc.w	11*1		; 0
			dc.w	11*2
			dc.w	11*3
			dc.w	11*4
			dc.w	11*5
			dc.w	11*6
			dc.w	11*7
			dc.w	11*8
			dc.w	11*9
			dc.w	11*10
			dc.w	11*11		; 10
			dc.w	11*12
			dc.w	11*13
			dc.w	11*14
			dc.w	11*15
			dc.w	11*16
			dc.w	11*17
			dc.w	11*18
			dc.w	11*19
			dc.w	11*20
			dc.w	11*21		; 20
			dc.w	11*21
			dc.w	11*21
			dc.w	11*21
			dc.w	11*20
			dc.w	11*19
			dc.w	11*18
			dc.w	11*17
			dc.w	11*16
			dc.w	11*15
			dc.w	11*14		; 30
			dc.w	11*13
			dc.w	11*12
			dc.w	11*11
			dc.w	11*10
			dc.w	11*9
			dc.w	11*8
			dc.w	11*7
			dc.w	11*6
			dc.w	11*5
			dc.w	11*4		; 40
			dc.w	11*3
			dc.w	11*2
			dc.w	11*1
			dc.w	11*0

updateLogoPos:
			move.w	logoMoveDir,d0
			add.w	d0,logoMoveSpeed

			move.w	logoMoveSpeed,d0
			add.w	d0,logoPos

			add.w	#1,logoMoveDirCount
			cmp.w	#48,logoMoveDirCount
			bne		.noToggle
			move.w	#0,logoMoveDirCount
			neg.w	logoMoveDir
.noToggle
			move.w	logoPos,d0
			addq	#8,d0
			lsr.w	#4,d0
			add.w	#logoY-16,d0
			move.b	d0,logoStartWait
			add.w	#44,d0
			move.b	d0,logoEndWait
			rts

logoMoveDir:
			dc.w	1
logoMoveDirCount:
			dc.w	24
logoMoveSpeed:
			dc.w	0
logoPos:
			dc.w	0

logo:
			INCBIN	"thrust-quadlite_green_lo4.bin"

; palette for: thrust-quadlite_green
logoColorsOrig:
		dc.w	$0182,$0120
		dc.w	$0184,$0251
		dc.w	$0186,$0381
		dc.w	$0188,$04b2
		dc.w	$018a,$05c3
		dc.w	$018c,$06d5
		dc.w	$018e,$08d6
		dc.w	$0190,$09e8
		dc.w	$0192,$0ae9
		dc.w	$0194,$0bea
		dc.w	$0196,$0cfb
		dc.w	$0198,$0dfd
		dc.w	$019a,$0efe
		dc.w	$019c,$0fff
		; dc.w	$019e,$0fff

clist:		
		dc.w	BPLCON0,$0200		; bitplanes off

		dc.w	$0108,$0000		; even bitplanes modulo
		dc.w	$010a,$0000		; odd bitplanes modulo

		dc.w	DDFSTRT,$0038
		dc.w	DDFSTOP,$00d0

		; dc.w	$0104,%100100	; set playfield prios
		dc.w	$0104,%000000	; set playfield prios	(sprites behind playfields)

spoint:		; sprite pointers
		dc.w	$120,0,$122,0,$124,0,$126,0
		dc.w	$128,0,$12a,0,$12c,0,$12e,0
		dc.w	$130,0,$132,0,$134,0,$136,0
		dc.w	$138,0,$13a,0,$13c,0,$13e,0

		dc.w	$01a2,$0842		; 1
		dc.w	$01a4,$0371		; 2
		dc.w	$01a6,$0fff
		dc.w	$01aa,$0125		; 4
		dc.w	$01ac,$0fff
		dc.w	$01ae,$0631		; 3

		dc.w	$00e4
logobp1h:	
		dc.w	0	
		dc.w	$00e6
logobp1l:	
		dc.w	0	
		dc.w	$00e8
logobp2h:	
		dc.w	0	
		dc.w	$00ea
logobp2l:	
		dc.w	0	
		dc.w	$00ec
logobp3h:	
		dc.w	0	
		dc.w	$00ee
logobp3l:	
		dc.w	0	

		dc.w	$2001,$fffe			; stars start
		dc.w	$0182,$0000	   ; black plane
		dc.w	BPLCON0,$1200		; one plane
		dc.w	$00e0,$0006
		dc.w	$00e2,$e000-li
		dc.w	$0108,$ffd8			; even bitplanes modulo

logoStartWait:
 		dc.w	$6001,$fffe
		dc.w	BPLCON0,$4200		; 4 bitplanes
		dc.w	$0108,$0000			; even bitplanes modulo

		dc.w	$00e0
logobp0h:	
		dc.w	0	
		dc.w	$00e2
logobp0l:	
		dc.w	0	

logoColors:
		blk.w	((2+(14*2))*44)-2,0

logoEndWait:
 		dc.w	$8c01,$fffe			; logo end wait
		dc.w	BPLCON0,$0200		; bitplanes off

		dc.w	$0182,$0000	   ; black plane
		dc.w	BPLCON0,$1200		; one plane
		dc.w	$00e0,$0006
		dc.w	$00e2,$e000-li
		dc.w	$0108,$ffd8			; even bitplanes modulo

		dc.w	$8401,$fffe		; start of "game" area
		dc.w	BPLCON0,$1200		; 1 bitplanes on
		dc.w	$00e0,$0007		; bitplane 0 
bp0:	dc.w	$00e2,$0000		;

		dc.w	$0108,$0000		; even bitplanes modulo
		dc.w	$010a,$0000		; odd bitplanes modulo

		dc.w	$0092,$0028
		dc.w	$0094,$00d8

		dc.w	$0182,$0777
		dc.w	$c101,$fffe
		dc.w	$0182,$0888
		dc.w	$c201,$fffe
		dc.w	$0182,$0999
		dc.w	$c301,$fffe
		dc.w	$0182,$0aaa

		dc.w	$c401,$fffe
		dc.w	$0182,$0bbb
		dc.w	$0100,$2600				; 2 bitplanes on	(dual playfield mode)
		dc.w	$00e4,$0007				; bitplane 01
		dc.w	$00e6,(li*75)-2		 ; + lines offset to adjust shadow pos
		dc.w	$0192,$0000		; shadow color

		dc.w	$c501,$fffe
		dc.w	$0182,$0ccc
		dc.w	$010a,$ffd2		; negative odd bitplanes modulo -> repeat last line
		dc.w	$0102,$0050		; scroll
		dc.w	$c601,$fffe
		dc.w	$0182,$0ddd
		dc.w	$010a,$0000		; odd bitplanes modulo
		dc.w	$0102,$0040		; scroll
		dc.w	$c701,$fffe
		dc.w	$0182,$0ccc
		dc.w	$010a,$ffd2		; negative odd bitplanes modulo -> repeat last line
		dc.w	$0102,$0030		; scroll
		dc.w	$c801,$fffe
		dc.w	$0182,$0aaa
		dc.w	$010a,$0000		; odd bitplanes modulo
		dc.w	$0102,$0020		; scroll
		dc.w	$c901,$fffe
		dc.w	$0182,$0989
		dc.w	$010a,$ffd2		; negative odd bitplanes modulo -> repeat last line
		dc.w	$0102,$0010		; scroll
		dc.w	$ca01,$fffe
		dc.w	$0182,$0868
		dc.w	$010a,$0002		; odd bitplanes modulo
		dc.w	$0102,$0000		; scroll
		dc.w	$cb01,$fffe
		dc.w	$0182,$0868
		dc.w	$010a,$ffd2		; negative odd bitplanes modulo -> repeat last line
		dc.w	$0102,$00f0		; scroll
		dc.w	$ce01,$fffe
		dc.w	$0182,$0858
		dc.w	$010a,$0000		; odd bitplanes modulo
		dc.w	$0102,$00e0		; scroll
		dc.w	$cf01,$fffe
		dc.w	$0180,$0112	; flat scrollarea anti alias line ;)
		dc.w	$0182,$0858
		dc.w	$010a,$ffd2		; negative odd bitplanes modulo -> repeat last line
		dc.w	$0102,$00c0		; scroll
		dc.w	$0192,$0112		; shadow color
		dc.w	$d001,$fffe
		dc.w	$0180,$0234	; flat scrollarea start
		dc.w	$0182,$0868
		dc.w	$010a,$0000		; odd bitplanes modulo
		dc.w	$0102,$00b0		; scroll
		dc.w	$d101,$fffe
		dc.w	$0182,$0767
		dc.w	$010a,$ffd2		; negative odd bitplanes modulo -> repeat last line
		dc.w	$0102,$00a0		; scroll
		dc.w	$d201,$fffe
		dc.w	$0182,$0656
		dc.w	$010a,$0000		; odd bitplanes modulo
		dc.w	$0102,$0090		; scroll
		dc.w	$d301,$fffe
		dc.w	$0182,$0666
		dc.w	$010a,$ffd2		; negative odd bitplanes modulo -> repeat last line
		dc.w	$0102,$0080		; scroll
		dc.w	$d401,$fffe
		dc.w	$0182,$0777
		dc.w	$010a,$0000		; odd bitplanes modulo
		dc.w	$0102,$0070		; scroll
		dc.w	$d501,$fffe
		dc.w	$0182,$0888
		dc.w	$010a,$ffd2		; negative odd bitplanes modulo -> repeat last line
		dc.w	$0102,$0060		; scroll
		dc.w	$d601,$fffe
		dc.w	$0182,$0988
		dc.w	$010a,$0000		; odd bitplanes modulo
		dc.w	$0102,$0050		; scroll
		dc.w	$d701,$fffe
		dc.w	$0182,$0a99
		dc.w	$010a,$ffd2		; negative odd bitplanes modulo -> repeat last line
		dc.w	$0102,$0040		; scroll
		dc.w	$d801,$fffe
		dc.w	$0182,$0baa
		dc.w	$010a,$0000		; odd bitplanes modulo
		dc.w	$0102,$0030		; scroll
		dc.w	$d901,$fffe
		dc.w	$0182,$0dcc
		dc.w	$010a,$ffd2		; negative odd bitplanes modulo -> repeat last line
		dc.w	$0102,$0020		; scroll
		dc.w	$da01,$fffe
		dc.w	$0182,$0ddd
		dc.w	$010a,$0000		; odd bitplanes modulo
		dc.w	$0102,$0010		; scroll
		dc.w	$db01,$fffe
		dc.w	$0182,$0eee
		dc.w	$0102,$0000		; scroll

		; dc.w	$dc01,$fffe
		; dc.w	$0100,$0200		; bitplanes off

		; dc.w	$0180,$0234	; flat scrollarea color
		dc.w	$de01,$fffe
		dc.w	$0180,$0567	; wall downwards start
		dc.w	$df01,$fffe
		dc.w	$0180,$0356	; wall 

		dc.w	$e001,$fffe
		dc.w	$0180,$0355	; wall 
		dc.w	$e101,$fffe
		dc.w	$0180,$0345	; wall 
		dc.w	$e201,$fffe
		dc.w	$0180,$0245	; wall 
		dc.w	$e301,$fffe
		dc.w	$0180,$0244	; wall 
		dc.w	$e401,$fffe
		dc.w	$0180,$0234	; wall 
		dc.w	$e501,$fffe
		dc.w	$0180,$0134	; wall 
		dc.w	$e601,$fffe
		dc.w	$0180,$0133	; wall 
		dc.w	$e701,$fffe
		dc.w	$0180,$0123	; wall 
		dc.w	$e801,$fffe
		dc.w	$0180,$0023	; wall 
		dc.w	$e901,$fffe
		dc.w	$0180,$0022	; wall 
		dc.w	$ea01,$fffe
		dc.w	$0180,$0012	; wall 
		dc.w	$eb01,$fffe
		dc.w	$0180,$0012	; wall 
		dc.w	$ec01,$fffe
		dc.w	$0180,$0011	; wall 
		dc.w	$ed01,$fffe
		dc.w	$0180,$0001	; wall 
		dc.w	$ee01,$fffe
		dc.w	$0180,$0001	; wall 
		dc.w	$ef01,$fffe
		dc.w	$0180,$0000	; wall 

		dc.w	$f001,$fffe
		dc.w	$0180,$0000	; wall end


		dc.w	$ffdf,$fffe		; wait for end of line 255
		dc.w	$0001,$fffe
; sreg:		
; 		dc.w	$0102,$0010
; 		dc.w	BPL1PTH,src_adr>>16
; 		dc.w	BPL1PTL,src_adr&$ffff

; 		dc.w	DDFSTRT,$0028
; 		dc.w	DDFSTOP,$00d8
; 		dc.w	BPL1MOD,src_line-$2e	; bitplane modulo (visible bytes per line = $2e)

; 		dc.w	$0182,$0fea
; 		dc.w	$0101,$fffe
; 		dc.w	$0182,$0ecf
; 		dc.w	$0100,$1200
; 		dc.w	$0201,$fffe
; 		dc.w	$0182,$0dae
; 		dc.w	$0301,$fffe
; 		dc.w	$0182,$0c8d
; 		dc.w	$0401,$fffe
; 		dc.w	$0182,$0b6c
; 		dc.w	$0501,$fffe
; 		dc.w	$0182,$0a4b
; 		dc.w	$0701,$fffe
; 		dc.w	$0092,$0050
; 		dc.w	$0094,$00c0
; 		dc.w	$0108,$0022
; 		dc.w	$010a,$0022
; 		dc.w	$0102,$0000
; 		dc.w	$0100,$0200
		dc.w	$ffff,$fffe

rchartab:	
		blk.w	256,0

;--------------------------------------------------------------
updateGame:		
		; enemys / asteroids
		lea		linetab(pc),a6		
		bsr		updateEnemies
		clr.w	(a6)			; and of draw table
		bsr		objects_draw

		; player and shots
		lea		linetab(pc),a6
		tst.b	ship_next
		bne.s	.nsdraw
		move.l	a6,-(a7)
		bsr		shipcoll		; collision
		move.l	(a7)+,a6
		bsr		ship_set
.nsdraw:	
		bsr		ship_explode
		bsr		shots_set
		clr.w	(a6)			; and of draw table
		bsr		objects_draw

		cmp.b	#$45,kcode		; escape key?
		bne.s	.nrestart
		clr.b	kcode
		tst.b	ship_next		; ship destroyed?
		beq.s	.nrestart
		sf		ship_next
		bsr		initGame
.nrestart:
		; letter counter and initialization
		lea		letters_init,a0
		tst.w	(a0)
		beq		.noLetterInit
		sub.w	#1,(a0)
		bne		.noLetterInit
		move.w	#20*50,(a0)		; delay for next letters
		bsr		asteroids_init
.noLetterInit:

		rts
**********************************************************************
*vector object_class                                                 *
*
				rsreset
obj_xc:			rs.w	1		;x-coordinate
obj_yc:			rs.w	1		;y-coordinate
obj_xfloat:		rs.w	1		;x-coordinate (floating)
obj_yfloat:		rs.w	1		;y-coordinate (floating)
obj_angle:		rs.w	1		;angle
obj_scale:		rs.w	1		;scale
obj_coords:		rs.l	1		;pointer on coord-table
obj_xvelo:		rs.w	1		;x velocity
obj_yvelo:		rs.w	1		;y velocity
obj_name:		rs.w	1		;name (identification)
obj_collsize:	rs.w	1
obj_appear:		rs.w	1
obj_len:		rs.w	0		; end
;---------------------------------------------
obj_init:				;<initialize object>
		move.w	d0,obj_xc(a0)
		move.w	d1,obj_yc(a0)
		lsl.w	#7,d0
		move.w	d0,obj_xfloat(a0)
		lsl.w	#7,d1
		move.w	d1,obj_yfloat(a0)

		move.w	d2,obj_angle(a0)
		move.w	d3,obj_xvelo(a0)
		move.w	d4,obj_yvelo(a0)
		move.w	d5,obj_name(a0)
		lsl.w	#2,d5
		lea		coord_tabs(pc),a1
		move.l	(a1,d5.w),obj_coords(a0)
		move.w	#64,obj_scale(a0)
		rts
;---------------------------------------------
obj_slowdown:
		tst.w	obj_xvelo(a0)
		beq.s	.xng
		bpl.s	.xvp2
		addq.w	#1,obj_xvelo(a0)
		bra.s	.xng
.xvp2:		
		subq.w	#1,obj_xvelo(a0)
.xng:
		tst.w	obj_yvelo(a0)
		beq.s	.yng
		bpl.s	.yvp2
		addq.w	#1,obj_yvelo(a0)
		bra.s	.yng
.yvp2:		
		subq.w	#1,obj_yvelo(a0)
.yng:		
		rts
;---------------------------------------------
obj_addangle:				;<increase angle>
		add.w	d1,obj_angle(a0)
		cmp.w	#360,obj_angle(a0)
		blt.s	.angleok
		sub.w	#360,obj_angle(a0)
.angleok:	
		rts
;---------------------------------------------
obj_subangle:				;<decrease angle>
		sub.w	d1,obj_angle(a0)
		bpl.s	.angleok
		add.w	#360,obj_angle(a0)
.angleok:	
		rts
;---------------------------------------------
obj_thrust:				;<accelerate object, value in d2>
		move.w	obj_angle(a0),d1
		sub.w	#90,d1
		bpl.s	.angleok
		add.w	#360,d1
.angleok:
		lsl.w	#2,d1
		lea		sctab(pc),a3

		move.w	d2,d4			;save thrust value
		muls	2(a3,d1.w),d2		;dx=cos(angle)*value
		lsl.l	#1,d2
		swap	d2
		add.w	d2,obj_xvelo(a0)
		move.w	d4,d2			;restore thrust value

		muls	(a3,d1.w),d2		;dy=sin(angle)*value
		lsl.l	#1,d2
		swap	d2
		add.w	d2,obj_yvelo(a0)

		cmp.w	#4*128,obj_xvelo(a0)	;x velocity too high?
		blt.s	.nhxv
		move.w	#4*128,obj_xvelo(a0)
.nhxv:		
		cmp.w	#-4*128,obj_xvelo(a0)	;x velocity too low?
		bgt.s	.nlxv
		move.w	#-4*128,obj_xvelo(a0)
.nlxv:
		cmp.w	#4*128,obj_yvelo(a0)	;y velocity too high?
		blt.s	.nhyv
		move.w	#4*128,obj_yvelo(a0)
.nhyv:		
		cmp.w	#-4*128,obj_yvelo(a0)	;y velocity too low?
		bgt.s	.nlyv
		move.w	#-4*128,obj_yvelo(a0)
.nlyv:
		rts
;---------------------------------------------
obj_move:				;<calculate new object coords>
		
		move.w	obj_xfloat(a0),d0		; x floating
		add.w	obj_xvelo(a0),d0		; + x velocity

		cmp.w	#(game_width+16)*128,d0	; x coord too high?
		bls.s	.nhx
		cmp.w	#(game_width+16+16)*128,d0
		bhi.s	.nhx
		sub.w	#(game_width+16+16)*128,d0
.nhx:		
		cmp.w	#-16*128,d0				; x coord too low?
		bhi.s	.nlx
		cmp.w	#(game_width+16+16)*128,d0
		bls.s	.nlx
		add.w	#(game_width+16+16)*128,d0
.nlx:
		move.w	d0,obj_xfloat(a0)		; store x floating
		lsr.w	#7,d0					; convert to integer
		move.w	d0,obj_xc(a0)			; x integer

		move.w	obj_yfloat(a0),d0		; y floating
		add.w	obj_yvelo(a0),d0		; + y velocity

		cmp.w	#(game_height+16)*128,d0	;y coord too high?
		bls.s	.nhy
		cmp.w	#(game_height+16+16)*128,d0
		bhi.s	.nhy
		sub.w	#(game_height+16+16)*128,d0
.nhy:		
		cmp.w	#-16*128,d0				; y coord too low?
		bhi.s	.nly
		cmp.w	#(game_height+16+16)*128,d0
		bls.s	.nly
		add.w	#(game_height+16+16)*128,d0
.nly:
		move.w	d0,obj_yfloat(a0)		; store y floating
		lsr.w	#7,d0					; convert to integer
		move.w	d0,obj_yc(a0)			; y integer
		
		move.l	obj_coords(a0),a1		; pointer to coord tab
		move.l	a1,d0
		bne.s	.lineobj				; point or lines
		move.w	obj_xc(a0),d0
		move.w	obj_yc(a0),d1
		bsr		set_point
		rts
.lineobj:	
		move.w	obj_angle(a0),d0
		cmp.w	#$8000,d0			;rotate?
		beq		.norotobj
		lsl.w	#2,d0
		lea		sctab(pc),a3
		movem.w	(a3,d0.w),d4/d5		;sin,cos

		move.w	(a1)+,d7
		subq.w	#1,d7
.lines:		
		movem.w	(a1)+,d0-d3
		muls.w	obj_scale(a0),d0
		muls.w	obj_scale(a0),d1
		muls.w	obj_scale(a0),d2
		muls.w	obj_scale(a0),d3
		asr.w	#6,d0
		asr.w	#6,d1
		asr.w	#6,d2
		asr.w	#6,d3
		move.w	d7,-(a7)
		bsr		rotate
		add.w	obj_xc(a0),d0
		add.w	obj_xc(a0),d2
		add.w	obj_yc(a0),d1
		add.w	obj_yc(a0),d3
		bsr		set_line
		move.w	(a7)+,d7
		dbf		d7,.lines
		rts
.norotobj:
		move.w	(a1)+,d7
		subq.w	#1,d7
.norotlines:	
		movem.w	(a1)+,d0-d3
		; muls.w	#3,d0			; test -> shrink
		; muls.w	#3,d1
		; muls.w	#3,d2
		; muls.w	#3,d3
		; asr.w	#2,d0			
		; asr.w	#2,d1
		; asr.w	#2,d2
		; asr.w	#2,d3
		add.w	obj_xc(a0),d0
		add.w	obj_xc(a0),d2
		add.w	obj_yc(a0),d1
		add.w	obj_yc(a0),d3
		move.w	d7,-(a7)
		bsr		set_line
		move.w	(a7)+,d7
		dbf		d7,.norotlines
		rts

; object names (ids)
ship	=	0		; own spaceship
shot	=	1		; own shot
big		=	2		; big asteroid
medium	=	3		; medium asteroid
small	=	4		; small asteroid
zn_z	=	5

;---------------------------------------------
coord_tabs:
		dc.l	ship_coords
		dc.l	0
		dc.l	astb_coords
		dc.l	astm_coords
		dc.l	asts_coords
		dc.l	a_coords
		dc.l	b_coords
		dc.l	c_coords
		dc.l	d_coords
		dc.l	e_coords
		dc.l	f_coords
		dc.l	g_coords
		dc.l	h_coords
		dc.l	i_coords
		dc.l	j_coords
		dc.l	k_coords
		dc.l	l_coords
		dc.l	m_coords
		dc.l	n_coords
		dc.l	o_coords
		dc.l	p_coords
		dc.l	q_coords
		dc.l	r_coords
		dc.l	s_coords
		dc.l	t_coords
		dc.l	u_coords
		dc.l	v_coords
		dc.l	w_coords
		dc.l	x_coords
		dc.l	y_coords
		dc.l	z_coords
		dc.l	0
;---------------------------------------------
shot_con:		dc.w	0
shot_times:		ds.w	16
shot_structs:	ds.b	obj_len*16
enemy_con:		dc.l	0
enemy_structs:	ds.b	obj_len*32
ship_struct:	ds.b	obj_len
ship_estruct:	ds.b	obj_len*$15
ship_next:		dc.b	0
ship_exploding:	dc.b	0
				even
letters_init:	dc.w	10		; delay in frames

;---------------------------------------------
ship_coords:	dc.w	4
		dc.w	0,-4,-4,5
		dc.w	0,-4, 4,5
		dc.w	4,5,0,2
		dc.w	-4,5,0,2
;---------------------------------------------
astb_coords:	dc.w	9
		dc.w	0,-16,-10,-10
		dc.w	-10,-10,-4,-4
		dc.w	-4,-4,-14,-6
		dc.w	-14,-6,-16,0
		dc.w	-16,0,-10,12
		dc.w	-10,12,6,16
		dc.w	6,16,16,4
		dc.w	16,4,14,-8
		dc.w	14,-8,0,-16

;---------------------------------------------
astm_coords:	dc.w	6
		dc.w	0,-10,-10,-4
		dc.w	-10,-4,-8,8
		dc.w	-8,8,4,10
		dc.w	4,10,10,2
		dc.w	10,2,8,-6
		dc.w	8,-6,0,-10
;---------------------------------------------
asts_coords:	dc.w	5
		dc.w	2,-6,-4,-4
		dc.w	-4,-4,-4,2
		dc.w	-4,2,2,4
		dc.w	2,4,6,-2
		dc.w	6,-2,2,-6
;---------------------------------------------
zn_z_coords:	
		dc.w	8				; anzahl linien
		dc.w	-20,-16,9,-12	; linie 1: x1,y1, x2,y2
		dc.w	9,-12,6,4		; linie 2: x1,y1, x2,y2
		dc.w	6,4,14,4		; usw.
		dc.w	14,4,14,13
		dc.w	14,13,-13,8
		dc.w	-13,8,0,-7
		dc.w	0,-7,-17,-6
		dc.w	-17,-6,-20,-16

a_coords:
		dc.w 	6
		dc.w 	-9,-11,7,-16
		dc.w 	7,-16,17,15
		dc.w 	17,15,1,8
		dc.w	1,8,-16,17
		dc.w 	-16,17,-9,-11
		dc.w 	-4,-3,5,2

b_coords:
		dc.w 8
		dc.w -10,-16,14,-12
		dc.w 14,-12,7,-3
		dc.w 7,-3,17,7
		dc.w 17,7,7,17
		dc.w 7,17,-16,12
		dc.w -16,12,-10,-16
		dc.w -5,-3,-2,-8
		dc.w -6,8,2,4

c_coords:
		dc.w 7
		dc.w -7,-16,17,-9
		dc.w 17,-9,4,-5
		dc.w 4,-5,-3,5
		dc.w -3,5,17,12
		dc.w 17,12,-8,17
		dc.w -8,17,-16,6
		dc.w -16,6,-7,-16

d_coords:
		dc.w 6
		dc.w -16,-7,-6,-16
		dc.w -6,-16,17,2
		dc.w 17,2,9,18
		dc.w 9,18,-11,17
		dc.w -11,17,-16,-7
		dc.w -4,-4,2,8		

e_coords:
		dc.w 8
		dc.w -6,-16,17,-10
		dc.w 17,-10,2,-6
		dc.w 2,-6,14,1
		dc.w 14,1,2,4
		dc.w 2,4,17,9
		dc.w 17,9,-5,17
		dc.w -5,17,-17,6
		dc.w -17,6,-6,-16

f_coords:
		dc.w 7
		dc.w -16,-11,16,-16
		dc.w 16,-16,-1,-3
		dc.w -1,-3,11,1
		dc.w 11,1,1,8
		dc.w 1,8,2,14
		dc.w 2,14,-9,17
		dc.w -9,17,-16,-11

g_coords:
		dc.w 9
		dc.w -5,-16,16,-14
		dc.w 16,-14,2,-9
		dc.w 2,-9,-2,2
		dc.w -2,2,10,5
		dc.w 10,5,4,-3
		dc.w 4,-3,17,-4
		dc.w 17,-4,17,17
		dc.w 17,17,-16,10
		dc.w -16,10,-5,-16

h_coords:
		dc.w 8
		dc.w -10,-16,-3,-5
		dc.w -3,-5,5,-6
		dc.w 5,-6,17,-16
		dc.w 17,-16,11,17
		dc.w 11,17,5,7
		dc.w 5,7,-4,6
		dc.w -4,6,-16,17
		dc.w -16,17,-10,-16	

i_coords:
		dc.w 3
		dc.w -7,-16,10,-13
		dc.w 10,-13,3,17
		dc.w 3,17,-7,-16	

j_coords:
		dc.w 6
		dc.w 2,10,3,-16
		dc.w 3,-16,15,-12
		dc.w 15,-12,12,13
		dc.w 12,13,-9,17
		dc.w -9,17,-12,-1
		dc.w -12,-1,2,10

k_coords:
		dc.w 9
		dc.w -12,-16,-4,-4
		dc.w -4,-4,16,-15
		dc.w 16,-15,5,1
		dc.w 5,1,17,11
		dc.w 17,11,6,17
		dc.w 6,17,-4,9
		dc.w -4,9,-9,17
		dc.w -9,17,-16,15
		dc.w -16,15,-12,-16

l_coords:
		dc.w 5
		dc.w -16,-11,-1,-16
		dc.w -1,-16,3,7
		dc.w 3,7,18,5
		dc.w 17,5,-5,17
		dc.w -5,17,-16,-11

m_coords:
		dc.w 9
		dc.w -13,-11,-1,-16
		dc.w -1,-16,5,-5
		dc.w 5,-5,13,-16
		dc.w 13,-16,17,15
		dc.w 17,15,9,7
		dc.w 9,7,2,15
		dc.w 2,15,-7,4
		dc.w -7,4,-16,17
		dc.w -16,17,-13,-11

n_coords:
		dc.w 7
		dc.w -16,-13,6,-5
		dc.w 6,-5,8,-16
		dc.w 8,-16,17,10
		dc.w 17,10,10,16
		dc.w 10,16,-6,6
		dc.w -6,6,-11,17
		dc.w -11,17,-16,-13

o_coords:
		dc.w 6
		dc.w -16,-9,9,-16
		dc.w 9,-16,17,7
		dc.w 17,7,8,17
		dc.w 8,17,-14,5
		dc.w -14,5,-16,-9
		dc.w -2,-5,3,4

p_coords:
		dc.w 7
		dc.w -16,-11,5,-16
		dc.w 5,-16,17,-6
		dc.w 17,-6,11,10
		dc.w 11,10,-3,7
		dc.w -3,7,-11,17
		dc.w -11,17,-16,-11
		dc.w -2,-1,3,-7

q_coords:
		dc.w 9
		dc.w -16,-2,-5,-16
		dc.w -5,-16,5,-16
		dc.w 5,-16,17,2
		dc.w 17,2,11,7
		dc.w 11,7,15,17
		dc.w 15,17,5,11
		dc.w 5,11,-8,17
		dc.w -8,17,-16,-2
		dc.w -4,2,4,-4

r_coords:
		dc.w 8
		dc.w -16,-10,3,-16
		dc.w 3,-16,17,-2
		dc.w 17,-2,9,7
		dc.w 9,7,14,17
		dc.w 14,17,-4,11
		dc.w -4,11,-11,17
		dc.w -11,17,-16,-10
		dc.w -4,-7,1,3

s_coords:
		dc.w 8
		dc.w -13,-10,14,-16
		dc.w 14,-16,-3,-6
		dc.w -3,-6,13,-4
		dc.w 13,-4,17,12
		dc.w 17,12,-12,17
		dc.w -12,17,2,9
		dc.w 2,9,-16,3
		dc.w -16,3,-13,-10

t_coords:
		dc.w 6
		dc.w -16,-13,17,-15
		dc.w 17,-15,6,-6
		dc.w 6,-6,8,17
		dc.w 8,17,-6,-3
		dc.w -6,-3,-13,2
		dc.w -13,2,-16,-13

u_coords:
		dc.w 6
		dc.w -10,-16,-5,-3
		dc.w -5,-3,4,2
		dc.w 4,2,12,-16
		dc.w 12,-16,17,17
		dc.w 17,17,-16,8
		dc.w -16,8,-10,-16

v_coords:
		dc.w 5
		dc.w -16,-4,-4,-15
		dc.w -4,-15,6,-3
		dc.w 6,-3,15,-16
		dc.w 15,-16,7,17
		dc.w 7,17,-16,-4

w_coords:
		dc.w 9
		dc.w -16,-10,-8,-2
		dc.w -8,-2,-2,-11
		dc.w -2,-11,6,2
		dc.w 6,2,12,-16
		dc.w 12,-16,17,9
		dc.w 17,9,7,17
		dc.w 7,17,1,8
		dc.w 1,8,-11,17
		dc.w -11,17,-16,-10

x_coords:
		dc.w 8
		dc.w -16,-16,1,-7
		dc.w 1,-7,8,-1
		dc.w 8,-1,16,17
		dc.w 16,17,2,8
		dc.w 2,8,-16,16
		dc.w -16,16,-6,3
		dc.w -6,3,-16,-16

y_coords:
		dc.w 7
		dc.w -16,-6,-7,-16
		dc.w -7,-16,3,-5
		dc.w 3,-5,16,-16
		dc.w 16,-16,6,17
		dc.w 6,17,-7,13
		dc.w -7,13,-3,5
		dc.w -3,5,-16,-6

z_coords:
		dc.w 7
		dc.w -16,-8,12,-16
		dc.w 12,-16,8,7
		dc.w 8,7,17,10
		dc.w 17,10,-12,17
		dc.w -12,17,-3,-3
		dc.w -3,-3,-12,3
		dc.w -12,3,-16,-8

;---------------------------------------------
updateEnemies:
		move.l	enemy_con(pc),d0
		lea		enemy_structs(pc),a0
		moveq	#31,d7
.setenemys:	
		btst	d7,d0
		beq.s	.nenemy
		movem.l	d0/d7,-(a7)
		bsr		obj_move
		movem.l	(a7)+,d0/d7

		move.w	obj_appear(a0),d1
		tst.w	d1
		beq		.noAppear
		subq	#1,d1
		move.w	d1,obj_appear(a0)
		moveq	#4,d1
		bsr		obj_addangle
		move.w	obj_scale(a0),d1
		cmp.w	#64,d1
		beq		.noAppear
		addq	#1,d1
		move.w	d1,obj_scale(a0)
		bra		.appearing
.noAppear:
		move.w	#$8000,obj_angle
.appearing:

.nenemy:	
		lea		obj_len(a0),a0
		dbf		d7,.setenemys
		rts
;---------------------------------------------
shot_init:				;<initialize a shot>
		move.l	a0,-(a7)
		move.w	shot_con(pc),d6
		lea	shot_structs(pc),a0
		lea	shot_times(pc),a1
		moveq	#15,d7
.findshot:	btst	d7,d6
		beq.s	.freeshot
		lea	obj_len(a0),a0
		addq.w	#2,a1
		dbf	d7,.findshot
		bra.s	.nofreeshot
.freeshot:
		move.w	#80,(a1)		;shot duration
		moveq	#shot,d5
		bsr	obj_init
		bset	d7,d6
		move.w	d6,shot_con

.nofreeshot:	move.l	(a7)+,a0
		rts

; initialize a enemy (asteroid/ufo)
;
enemy_init:				
;		move.l	a0,-(a7)
		move.l	enemy_con(pc),d6
		lea		enemy_structs(pc),a0
		moveq	#31,d7
.findfree:	
		btst	d7,d6
		beq.s	.free
		lea		obj_len(a0),a0
		dbf		d7,.findfree
		bra.s	.nofree
.free:
		move.w	#$8000,d2
		bsr		obj_init
		bset	d7,d6
		move.l	d6,enemy_con
.nofree:	
;		move.l	(a7)+,a0
		rts
;---------------------------------------------
shots_set:	
		move.w	shot_con(pc),d0
		lea		shot_structs(pc),a0
		lea		shot_times(pc),a1
		moveq	#16-1,d7
.setshots:	
		btst	d7,d0
		beq.s	.nshot
		subq.w	#1,(a1)			;shot duration
		bne.s	.flying
		bclr	d7,d0			;switch shot off
		bra.s	.nshot
.flying:
		movem.w	d0/d7,-(a7)
		move.l	a1,-(a7)
		bsr		obj_move
		bsr		shot_collision
		move.l	(a7)+,a1
		movem.w	(a7)+,d0/d7
		
		tst.w	d1				; collision?
		beq.s	.nocoll
		bclr	d7,d0			; switch shot off
.nocoll:
.nshot:		
		lea		obj_len(a0),a0
		addq.w	#2,a1
		dbf		d7,.setshots
		
		move.w	d0,shot_con
		rts
;---------------------------------------------
shot_collision:
		move.w	obj_xc(a0),d0
		move.w	obj_yc(a0),d1

		lea		enemy_structs(pc),a3
		move.l	enemy_con(pc),d7
		moveq	#32-1,d6
.shotcoll:	
		move.l	d7,a5
		btst	d6,d7
		beq.w	.nocoll

		move.w	obj_xc(a3),d2
		move.w	obj_yc(a3),d3
		move.w	d2,d4
		move.w	d3,d5

		move.w	obj_collsize(a3),d7

		sub.w	d7,d2
		cmp.w	d0,d2
		bgt.s	.nocoll	
		add.w	d7,d4
		cmp.w	d0,d4
		blt.s	.nocoll
		sub.w	d7,d3
		cmp.w	d1,d3
		bgt.s	.nocoll
		add.w	d7,d5
		cmp.w	d1,d5
		blt.s	.nocoll

		cmp.w	#small,obj_name(a3)
		bne.s	.nlast
		move.l	a5,d7
		bclr	d6,d7
		move.l	d7,enemy_con
		rts
.nlast:
		; split object into two (reusing self)
		move.w	#small,obj_name(a3)
		lea		coord_tabs(pc),a4
		move.l	small*4(a4),obj_coords(a3)
		add.w	#32,obj_xvelo(a3)
		add.w	#32,obj_yvelo(a3)
		neg.w	obj_yvelo(a3)
		move.w	#8,obj_collsize(a3)

		; second
		move.w	obj_xc(a3),d0
		move.w	obj_yc(a3),d1
		move.w	obj_xvelo(a3),d3
		neg.w	d3
		move.w	obj_yvelo(a3),d4
		neg.w	d4
		move.w	obj_name(a3),d5		; same name (id)
		moveq	#0,d2
		bsr		enemy_init
		move.w	#8,obj_collsize(a0)
		rts
.nocoll:	
		move.l	a5,d7
		lea	obj_len(a3),a3
		dbf	d6,.shotcoll
.colldone:	
		moveq	#0,d1
		rts
;---------------------------------------------
ship_explode:
		tst.b	ship_next
		beq.w	.noinit
		tst.b	ship_exploding
		bne.s	.noinit

		lea		ship_struct(pc),a0
		move.w	obj_xc(a0),d5
		move.w	obj_yc(a0),d6
		move.w	obj_xvelo(a0),d3
		move.w	obj_yvelo(a0),d4
		moveq	#0,d3
		moveq	#0,d4
		move.w	obj_angle(a0),a4

		lea		ship_estruct(pc),a0
		lea		ship_ptab(pc),a1
		lea		sctab(pc),a3

		move.w	(a1)+,d7
		subq.w	#1,d7
		move.w	#270,d2			;angle
.initpoints:	
		move.w	(a1)+,d0
		move.w	(a1)+,d1
		movem.l	d4-d7,-(a7)
		move.w	a4,d6
		lsl.w	#2,d6
		movem.w	(a3,d6.w),d4/d5
		bsr		point_rotate
		movem.l	(a7)+,d4-d7

		add.w	d5,d0
		add.w	d6,d1

		movem.l	d0-a3,-(a7)

		moveq	#shot,d5
		bsr		obj_init
		moveq	#50,d2
		bsr		obj_thrust
		movem.l	(a7)+,d0-a3

		add.w	#23,d2
		cmp.w	#360,d2
		blt.s	.hang
		sub.w	#360,d2
.hang:
		lea		obj_len(a0),a0
		dbf		d7,.initpoints

		st		ship_exploding
.noinit:
		tst.b	ship_exploding
		beq.s	.noexplosion

		lea		ship_estruct(pc),a0		
		move.w	ship_ptab(pc),d7
		subq.w	#1,d7
.setpoints:	
		tst.w	obj_xvelo(a0)
		bne.s	.set
		tst.w	obj_yvelo(a0)
		beq.s	.next
.set:
		bsr		obj_move
		bsr		obj_slowdown
.next:		
		lea		obj_len(a0),a0
		dbf		d7,.setpoints
.noexplosion:	
		rts
;---------------------------------------------
ship_set:				;<set ship, keyboard control>
		lea		ship_struct(pc),a0

		move.b	jkcode(pc),d0
		btst	#3,d0
		beq.s	.ntleft
		moveq	#4,d1
		bsr		obj_subangle
.ntleft:
		btst	#1,d0
		beq.s	.ntright
		moveq	#4,d1
		bsr		obj_addangle
.ntright:
		btst	#2,d0
		beq.s	.nthrust
		moveq	#8,d2
		bsr		obj_thrust
.nthrust:
		tst.b	jkbutt
		beq.s	.nfire

		move.w	obj_xc(a0),d0			;x
		move.w	obj_yc(a0),d1			;y

		move.w	obj_angle(a0),d2
		sub.w	#90,d2
		bpl.s	.angleok
		add.w	#360,d2
.angleok:
		lsl.w	#2,d2
		lea		sctab(pc),a3

		move.w	#256,d3				; thrust value
		muls	2(a3,d2.w),d3		; xvelo=cos(angle)*value
		lsl.l	#1,d3
		swap	d3

		move.w	#256,d4
		muls	(a3,d2.w),d4		; yvelo=sin(angle)*value
		lsl.l	#1,d4
		swap	d4

		add.w	obj_xvelo(a0),d3
		add.w	obj_yvelo(a0),d4

		bsr	shot_init
		sf	jkbutt
.nfire:
.nokeys:
		bsr	obj_move
;		bsr	obj_slowdown
		rts
;---------------------------------------------
initGame:				;<initialize game>
		bsr		scaleLetters

		bsr		shots_init
		bsr		ship_init
		clr.l	enemy_con
		sf		ship_exploding
;		bsr		asteroids_init
		rts

scaleLetters:
		lea		coord_tabs+(5*4),a5	; letter start
		moveq	#26-1,d7
.loop:
		move.l	(a5)+,a0
		move.w	(a0)+,d6
		subq.w	#1,d6
.line:
		moveq	#4-1,d5
.value:
		move.w	(a0),d0
		bsr		scaleOffset
		move.w	d0,(a0)+
		dbf		d5,.value
		dbf		d6,.line

		dbf		d7,.loop
		rts

scaleOffset:
		muls.w	#3,d0
		asr.w	#2,d0
		rts

;---------------------------------------------
ast_count = 8

; ast_x_start		= 80			; for big
; ast_x_offset 	= 32

ast_x_start		= 100			; for medium
ast_x_offset 	= 24

; ast_x_start		= 70+((8*16)/2)			; for small
; ast_x_offset 	= 16

asteroids_init:
		rts

		move.w	#ast_x_start,d0		;x
		move.w	#28,d1				;y
		move.w	#0,d2				;angle
		move.w	#0,d3				;x velo
		move.w	#0,d4				;y velo
		moveq	#zn_z,d5			;name
		lea		coord_tabs+(5*4)+(8*4)+(8*4)+(2*4),a5	; letter start
		moveq	#ast_count-1,d7		
.loop:
		move.l	d0,d6
		bsr		getRandomNumber
		and.l	#$1f,d0
		sub.l	#$10,d0
		moveq	#0,d0		; test
		move.l	d0,d3
		bsr		getRandomNumber
		and.l	#$1f,d0
		sub.l	#$10,d0
		moveq	#0,d0		; test
		move.l	d0,d4
		move.l	d6,d0

		movem.l	d0-d7/a0-a6,-(a7)
		bsr		enemy_init
		move.w	#12,obj_collsize(a0)
		move.l	(a5),obj_coords(a0)

		; move.w	d7,d6
		; lsl.w	#2,d6
		; move.w	d6,obj_angle(a0)
		move.w	#360/4,d5
		; sub.w	d6,d5
		move.w	d5,obj_appear(a0)
		move.w	#0,obj_angle(a0)
		move.w	#4,obj_scale(a0)
		movem.l	(a7)+,d0-d7/a0-a6
		
		add.w	#ast_x_offset,d0
		lea		4(a5),a5

		dbf		d7,.loop

		; move.w	#64,d0			;x
		; move.w	#28,d1			;y
		; move.w	#0,d2			;angle
		; move.w	#-4,d3			;x velo
		; move.w	#-2,d4			;y velo
		; moveq	#zn_z,d5		;name
		; bsr		enemy_init

		; move.w	#280,d0			;x
		; move.w	#128,d1			;y
		; move.w	#-25,d3			;x velo
		; move.w	#10,d4			;y velo
		; moveq	#big,d5			;name
		; bsr		enemy_init

		; move.w	#145,d0			;x
		; move.w	#13,d1			;y
		; move.w	#-12,d3			;x velo
		; move.w	#14,d4			;y velo
		; moveq	#big,d5			;name
		; bsr		enemy_init

		; move.w	#14,d0			;x
		; move.w	#942,d1			;y
		; move.w	#32,d3			;x velo
		; move.w	#5,d4			;y velo
		; moveq	#big,d5			;name
		; bsr		enemy_init
		rts
;---------------------------------------------
shots_init:				;<initialize shot status>
		clr.w	shot_con
		rts
;---------------------------------------------
ship_pcoords:				;<get point coords>
		lea		ship_struct(pc),a0
		move.w	#16,d0			;x
		move.w	#16,d1			;y
		move.w	#0,d2			;angle
		move.w	#0,d3			;x velo
		move.w	#0,d4			;y velo
		moveq	#ship,d5
		bsr		obj_init

		lea		linetab(pc),a6
		bsr		obj_move
		clr.w	(a6)
		bsr		objects_draw

		lea		ship_ptab,a1
		bsr		get_pcoords
		rts
;---------------------------------------------
get_pcoords:
		move.l	a1,a2
		clr.w	(a1)+

		moveq	#0,d1			;ycoord
.vert:		
		moveq	#0,d0			;xcoord
.horiz:		
		bsr		check_point
		beq.s	.nopoint
		move.w	d0,d2
		move.w	d1,d3
		sub.w	#16,d2
		sub.w	#16,d3
		move.w	d2,(a1)+		;store x
		move.w	d3,(a1)+		;store y
		addq.w	#1,(a2)
.nopoint:	
		addq.w	#1,d0
		cmp.w	#32,d0
		bne.s	.horiz
		addq.w	#1,d1
		cmp.w	#32,d1
		bne.s	.vert
		rts
;---------------------------------------------
check_point:				;<check if point is set in bitmap>
					;<at coordinates d0/d1>
		movem.l	d0-d2/a2,-(a7)

		move.l	screenloc(pc),a2
		mulu	#li,d1
		move.w	d0,d2
		eor.w	#$0f,d2
		lsr.w	#3,d0
		add.w	d0,d1
		btst	d2,(a2,d1.w)
		beq.s	.nopoint
		movem.l	(a7)+,d0-d2/a2
		moveq	#-1,d7
		rts
.nopoint:	movem.l	(a7)+,d0-d2/a2
		moveq	#0,d7
		rts
;---------------------------------------------
ship_ptab:	ds.l	100
;---------------------------------------------
ship_init:				;<initialize ship pos,angle>
		
		bsr	ship_pcoords

		lea	ship_struct(pc),a0
		move.w	#160,d0			;x
		move.w	#128,d1			;y
		move.w	#0,d2			;angle
		move.w	#0,d3			;x velo
		move.w	#0,d4			;y velo
		moveq	#ship,d5
		bsr	obj_init
		rts
;---------------------------------------------
clear:					;<switch screens and clear>
		lea		$dff000,a6
		not.b	screenToggle
		bne.s	.s0
		move.w	#0,bp0+2
		move.l	#$78000,screenloc
		bra.s	.s1
.s0:		
		move.w	#$8000,bp0+2
		move.l	#$70000,screenloc
.s1:
		bsr		bbusy
		move.l	screenloc,$54(a6)
		move.l	#-1,$44(a6)
		move.l	#0,$64(a6)
		move.l	#$01000000,$40(a6)
		move.w	#(game_height<<6)+(li/2),$58(a6)
		rts
;---------------------------------------------
screenToggle:		
		dc.w	0
screenloc:			
		dc.l	$70000
;---------------------------------------------
set_line:
		movem.w	d4-d5,-(a7)
onceag:		
		moveq	#0,d6
		tst.w	d1			;y1 < 0 ?
		bmi.s	.y11
		tst.w	d3			;y2 < 0 ?
		bmi.s	.y12
		move.w	#game_height-1,d6
		cmp.w	d6,d1		;y1 > 255 ?
		bgt.s	.y21
		cmp.w	d6,d3		;y2 > 255 ?
		bgt.s	.y22

		moveq	#0,d6
		tst.w	d0			;x1 < 0 ?
		bmi.s	.x11
		tst.w	d2			;x2 < 0 ?
		bmi.s	.x12
		move.w	#game_width-1,d6
		cmp.w	d6,d0		;x1 > 319 ?
		bgt.s	.x21
		cmp.w	d6,d2		;x2 > 319 ?
		bgt.s	.x22
		bra.s	drawline	
.y11:
		tst.w	d3			;y2 auch < 0 ?
		bmi.s	clpend		;dann gar nix
		bsr.s	clipy
		move.w	d4,d0		;neues x1
		moveq	#0,d1		;y1 = 0
		bra.s	onceag
.y12:		
		bsr.s	clipy
		move.w	d4,d2		;neues x2
		moveq	#0,d3		;y2 = 0
		bra.s	onceag
.y21:
		cmp.w	d6,d3
		bgt.s	clpend
		bsr.s	clipy
		move.w	d4,d0
		move.w	d6,d1
		bra.s	onceag
.y22:		
		bsr.s	clipy
		move.w	d4,d2
		move.w	d6,d3
		bra.s	onceag
.x11:		
		tst.w	d2
		bmi.s	clpend
		bsr.s	clipx
		move.w	d4,d1
		moveq	#0,d0
		bra.s	onceag
.x12:
		bsr.s	clipx
		move.w	d4,d3
		moveq	#0,d2
		bra.s	onceag
.x21:		
		cmp.w	d6,d2
		bgt.s	clpend
		bsr.s	clipx
		move.w	d4,d1
		move.w	d6,d0
		bra.s	onceag
.x22:
		bsr.s	clipx
		move.w	d4,d3
		move.w	d6,d2
		bra.s	onceag
clpend:						;linie unsichtbar
		movem.w	(a7)+,d4-d5
		rts
;-------------------------------------
clipy:
		move.w	d0,d4
		sub.w	d2,d4
		move.w	d3,d5
		move.w	d3,d7
		sub.w	d6,d7
		muls	d7,d4
		sub.w	d1,d5
		divs	d5,d4
		add.w	d2,d4
		rts
;-------------------------------------
clipx:		
		move.w	d1,d4
		sub.w	d3,d4
		move.w	d2,d5
		move.w	d2,d7
		sub.w	d6,d7
		muls	d7,d4
		sub.w	d0,d5
		divs	d5,d4
		add.w	d3,d4
		rts
;-------------------------------------
drawline:	
		move.l	a4,-(a7)

		moveq	#$f,d4
		and.w	d2,d4
		ror.w	#4,d4

		or.w	#%0000101111001010,d4
		sub.w	d3,d1			;=>dy
		sub.w	d2,d0			;=>dx
		blt.s	.l1
		tst.w	d1
		ble.s	.l2
		cmp.w	d0,d1
		bge.s	.l3
		moveq	#17,d7
		bra.s	.l4
.l3:		
		moveq	#1,d7
		exg	d1,d0
		bra.s	.l4
.l2:		
		neg.w	d1
		cmp.w	d0,d1
		bge.s	.l5
		moveq	#$19,d7
		bra.s	.l4
.l5:		
		moveq	#$5,d7
		exg	d1,d0
		bra.s	.l4
.l1:		
		neg.w	d0
		tst.w	d1
		blt.s	.l6
		cmp.w	d0,d1
		bge.s	.l7
		moveq	#$15,d7
		bra.s	.l4
.l7:		
		moveq	#$9,d7
		exg	d1,d0
		bra.s	.l4
.l6:		
		neg.w	d1
		cmp.w	d0,d1
		bge.s	.l8
		moveq	#$1d,d7
		bra.s	.l4
.l8:		
		moveq	#$0d,d7
		exg		d1,d0
						;BltStart nach d6
.l4:		
		move.l	screenloc(pc),a4
		mulu	#li,d3
		and.w	#$fff0,d2
		lsr.w	#3,d2
		add.w	d3,a4
		add.w	d2,a4
						;Bltsize nach d5
		move.w	d0,d5
		addq	#1,d5
 		lsl.w	#6,d5
		addq	#2,d5
						;2*y-x nach a3 und 4*y nach d1
		add.w	d1,d1
		move.w	d1,d3
		sub.w	d0,d3
		bpl.s	notneg
		bset	#6,d7
notneg:
		add.w	d1,d1
						;4*y-4*x nach a5
		move.w	d1,d6
		lsl.w	#2,d0
		sub.w	d0,d6

		move.l	a4,(a6)+
		move.w	d3,(a6)+
		move.w	d4,(a6)+
		move.w	d7,(a6)+
		move.w	d1,(a6)+
		move.w	d6,(a6)+
		move.w	d5,(a6)+

		move.l	(a7)+,a4
		movem.w	(a7)+,d4-d5
		rts
;-------------------------------------------------------
set_point:
		cmp.w	#game_width-1,d0
		bhi.s	.npoint
		cmp.w	#game_height-1,d1
		bhi.s	.npoint

		move.w	#-1,(a6)		;set flag for point (not line)
		mulu	#li,d1
		move.w	d0,d2
		eor.w	#$07,d2
		lsr.w	#3,d0
		add.l	d0,d1
		add.l	screenloc(pc),d1
		move.l	d1,2(a6)
		move.w	d2,6(a6)
		lea		16(a6),a6
.npoint:	
		rts
;-------------------------------------------------------
point_rotate:
		move.w	d0,d6			;x
		muls	d5,d0			;*cos
		move.w	d1,d7			;y
		muls	d4,d7			;*sin
		sub.l	d7,d0			;x*cos - y*sin
		lsl.l	#1,d0
		swap	d0			;new x

		muls	d4,d6			;x*sin
		move.w	d1,d7			;y
		muls	d5,d7			;*cos
		add.l	d7,d6			;x*sin - y*cos
		lsl.l	#1,d6
		swap	d6			;new y
		move.w	d6,d1
		btst	#31,d6
		beq.s	.nn
		addq.w	#1,d1
.nn:
		btst	#31,d0
		beq.s	.nn2
		addq.w	#1,d0
.nn2:
		rts
;-------------------------------------------------------
rotate:					;<rotation>
		move.w	d0,d6			;x
		muls	d5,d0			;*cos
		move.w	d1,d7			;y
		muls	d4,d7			;*sin
		sub.l	d7,d0			;x*cos - y*sin
		lsl.l	#1,d0
		swap	d0				;new x

		muls	d4,d6			;x*sin
		move.w	d1,d7			;y
		muls	d5,d7			;*cos
		add.l	d7,d6			;x*sin - y*cos
		lsl.l	#1,d6
		swap	d6				;new y
		move.w	d6,d1

		move.w	d2,d6			;x
		muls	d5,d2			;*cos
		move.w	d3,d7			;y
		muls	d4,d7			;*sin
		sub.l	d7,d2			;x*cos - y*sin
		lsl.l	#1,d2
		swap	d2				;new x

		muls	d4,d6			;*sin
		move	d3,d7			;y
		muls	d5,d7			;*cos
		add.l	d7,d6			;x*sin - y*cos
		lsl.l	#1,d6
		swap	d6				;new y
		move.w	d6,d3
		rts
;-------------------------------------------------------
shipcoll:
		lea		$dff000,a6
		bsr		bbusy
		move.l	screenloc(pc),a0
		lea		ship_struct(pc),a1
		movem.w	obj_xc(a1),d0/d1
		subq.w	#2,d0
		cmp.w	#game_width-1,d0
		bhi.s	.nc
		subq.w	#2,d1
		cmp.w	#game_height-1,d1
		bhi.s	.nc
		moveq	#$0f,d3
		and.w	d0,d3
		lsr.w	#3,d0
		mulu	#li,d1
		add.w	d0,d1
		add.w	d1,a0

		move.l	a0,$4c(a6)
;		move.l	a0,$54(a6)
		move.l	#$04c00000,$40(a6)		;$5fc for or!
		move.l	#$f0000000,d4			; src mask
		lsr.l	d3,d4
		move.l	d4,$44(a6)
		move.w	#li-4,$62(a6)			; modulo
; 		move.w	#$0024,$62(a6)
;		move.w	#$0024,$66(a6)
		move.w	#-1,$74(a6)
		move.w	#5*64+2,$58(a6)

		bsr		bbusy

		btst	#5,$02(a6)
		bne.w	.nc
		tst.b	ship_next
		bne.s	.nc
		st		ship_next
.nc:
		rts
;-------------------------------------------------------
objects_draw:
		lea		linetab(pc),a0

		lea		$dff000,a6
		bsr		bbusy
		move.w	#li,$60(a6)
		move.w	#li,$66(a6)
		; move.w	#$28,$60(a6)
		; move.w	#$28,$66(a6)
		move.l  #$ffff0000,$44(a6)
		move.w	#$8000,$74(a6)
		move.w	#-1,$72(a6)
.objects:	
		tst.w	(a0)
		beq.s	.end
		bpl.s	.line			;point or line?
					;<draw point>
		move.l	2(a0),a4
		move.w	6(a0),d3
		bset	d3,(a4)
		lea		16(a0),a0
		bra.s	.objects
.line:
					;<draw line>
		move.l	(a0)+,a4
		move.w	(a0)+,d3
		move.w	(a0)+,d4
		move.w	(a0)+,d7
		move.w	(a0)+,d1
		move.w	(a0)+,a5
		move.w	(a0)+,d5

		bsr		bbusy
		move.l	a4,$48(a6)
		move.l	a4,$54(a6)
		move.w	d3,$52(a6)
		movem.w	d4/d7,$40(a6)
		movem.w	d1/a5,$62(a6)
		move.w	d5,$58(a6)		;zeinchen der linie
		bra.s	.objects
.end:		
		rts
;----------------------------------------
getkey:					;<get rawkey routine>
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
kcode:		dc.b	0
jkcode:		dc.b	0
jkbutt:		dc.b	0
		even
;-------------------------------------------------------
; sin cos table
sctab:
 dc.l $00007fff,$023c7ffa,$04787feb,$06b37fd2,$08ee7faf,$0b287f82
 dc.l $0d617f4b,$0f997f0b,$11d07ec0,$14067e6c,$163a7e0d,$186c7da5
 dc.l $1a9d7d33,$1ccb7cb7,$1ef77c32,$21217ba2,$23487b0a,$256c7a67
 dc.l $278e79bb,$29ac7906,$2bc77847,$2ddf777f,$2ff376ad,$320375d2
 dc.l $341074ee,$36187401,$381c730b,$3a1c720c,$3c177104,$3e0e6ff3
 dc.l $3fff6ed9,$41ec6db7,$43d46c8c,$45b66b59,$47936a1d,$496a68d9
 dc.l $4b3c678d,$4d086639,$4ecd64dd,$508d6379,$5246620d,$53f9609a
 dc.l $55a55f1f,$574b5d9c,$58ea5c13,$5a825a82,$5c1358ea,$5d9c574b
 dc.l $5f1f55a5,$609a53f9,$620d5246,$6379508d,$64dd4ecd,$66394d08
 dc.l $678d4b3c,$68d9496a,$6a1d4793,$6b5945b6,$6c8c43d4,$6db741ec
 dc.l $6ed93fff,$6ff33e0e,$71043c17,$720c3a1c,$730b381c,$74013618
 dc.l $74ee3410,$75d23203,$76ad2ff3,$777f2ddf,$78472bc7,$790629ac
 dc.l $79bb278e,$7a67256c,$7b0a2348,$7ba22121,$7c321ef7,$7cb71ccb
 dc.l $7d331a9d,$7da5186c,$7e0d163a,$7e6c1406,$7ec011d0,$7f0b0f99
 dc.l $7f4c0d61,$7f820b28,$7faf08ee,$7fd206b3,$7feb0478,$7ffa023c
 dc.l $7fff0000,$7ffafdc4,$7febfb88,$7fd2f94d,$7faff712,$7f82f4d8
 dc.l $7f4bf29f,$7f0bf067,$7ec0ee30,$7e6cebfa,$7e0de9c6,$7da5e794
 dc.l $7d33e563,$7cb7e335,$7c32e109,$7ba2dedf,$7b0adcb8,$7a67da94
 dc.l $79bbd872,$7906d654,$7847d439,$777fd221,$76add00d,$75d2cdfd
 dc.l $74eecbf0,$7401c9e8,$730bc7e4,$720cc5e4,$7104c3e9,$6ff3c1f2
 dc.l $6ed9c000,$6db7be14,$6c8cbc2c,$6b59ba4a,$6a1db86d,$68d9b696
 dc.l $678db4c4,$6639b2f8,$64ddb133,$6379af73,$620dadba,$609aac07
 dc.l $5f1faa5b,$5d9ca8b5,$5c13a716,$5a82a57e,$58eaa3ed,$574ba264
 dc.l $55a5a0e1,$53f99f66,$52469df3,$508d9c87,$4ecd9b23,$4d0899c7
 dc.l $4b3c9873,$496a9727,$479395e3,$45b694a7,$43d49374,$41ec9249
 dc.l $40009127,$3e0e900d,$3c178efc,$3a1c8df4,$381c8cf5,$36188bff
 dc.l $34108b12,$32038a2e,$2ff38953,$2ddf8881,$2bc787b9,$29ac86fa
 dc.l $278e8645,$256c8599,$234884f6,$2121845e,$1ef783ce,$1ccb8349
 dc.l $1a9d82cd,$186c825b,$163a81f3,$14068194,$11d08140,$0f9980f5
 dc.l $0d6180b5,$0b28807e,$08ee8051,$06b3802e,$04788015,$023c8006
 dc.l $00008001,$fdc48006,$fb898015,$f94d802e,$f7128051,$f4d8807e
 dc.l $f29f80b4,$f06780f5,$ee308140,$ebfa8194,$e9c681f3,$e794825b
 dc.l $e56482cd,$e3358349,$e10983ce,$dedf845d,$dcb884f6,$da948599
 dc.l $d8738645,$d65486fa,$d43987b9,$d2228881,$d00d8953,$cdfd8a2e
 dc.l $cbf18b12,$c9e88bff,$c7e48cf5,$c5e48df4,$c3e98efc,$c1f2900d
 dc.l $c0019127,$be149249,$bc2c9374,$ba4a94a7,$b86d95e3,$b6969727
 dc.l $b4c49873,$b2f999c7,$b1339b23,$af739c87,$adba9df3,$ac079f66
 dc.l $aa5ba0e1,$a8b5a264,$a716a3ed,$a57ea57e,$a3eea716,$a264a8b5
 dc.l $a0e2aa5a,$9f67ac07,$9df3adba,$9c87af73,$9b23b132,$99c7b2f8
 dc.l $9873b4c4,$9727b695,$95e3b86d,$94a7ba4a,$9374bc2c,$9249be13
 dc.l $9127c000,$900ec1f2,$8efdc3e9,$8df5c5e4,$8cf5c7e4,$8bffc9e8
 dc.l $8b12cbf0,$8a2ecdfd,$8953d00d,$8882d221,$87b9d439,$86fad654
 dc.l $8645d872,$8599da93,$84f6dcb8,$845ededf,$83cee109,$8349e335
 dc.l $82cde563,$825be793,$81f3e9c6,$8194ebfa,$8140ee2f,$80f5f066
 dc.l $80b5f29e,$807ef4d8,$8051f712,$802ef94d,$8015fb88,$8006fdc4
 dc.l $80010000,$8006023b,$80150477,$802e06b2,$805108ed,$807e0b27
 dc.l $80b40d61,$80f50f99,$814011d0,$81941405,$81f31639,$825b186c
 dc.l $82cd1a9c,$83491cca,$83ce1ef7,$845d2120,$84f62347,$8599256c
 dc.l $8645278d,$86fa29ab,$87b92bc6,$88812dde,$89532ff2,$8a2e3203
 dc.l $8b12340f,$8bff3617,$8cf5381c,$8df43a1b,$8efc3c17,$900d3e0d
 dc.l $91273fff,$924941ec,$937443d3,$94a745b6,$95e34793,$9727496a
 dc.l $98734b3b,$99c74d07,$9b234ecd,$9c87508c,$9df35246,$9f6653f9
 dc.l $a0e155a5,$a263574b,$a3ed58e9,$a57e5a81,$a7165c12,$a8b55d9c
 dc.l $aa5a5f1e,$ac066099,$adb9620d,$af736378,$b13264dc,$b2f86639
 dc.l $b4c4678d,$b69568d9,$b86c6a1d,$ba496b58,$bc2c6c8c,$be136db6
 dc.l $c0006ed9,$c1f26ff2,$c3e87103,$c5e4720b,$c7e3730a,$c9e77401
 dc.l $cbf074ee,$cdfc75d2,$d00d76ad,$d221777e,$d4387847,$d6537906
 dc.l $d87279bb,$da937a67,$dcb87b09,$dedf7ba2,$e1087c32,$e3347cb7
 dc.l $e5637d33,$e7937da5,$e9c57e0d,$ebf97e6b,$ee2f7ec0,$f0667f0b
 dc.l $f29e7f4b,$f4d77f82,$f7127faf,$f94c7fd2,$fb887feb,$fdc37ffa
;--------------------------------------------
linetab:	ds.b	200*16


;---------------------------------------------
; starfield
;---------------------------------------------
stars_count		= 105

setupStarfield:		
		lea		slst0,a0
		move.w	#$30,d0		; y start
		lea		starGfx,a3
		move.w	#stars_count-1,d7
		bsr		setupSpritelist

		lea		slst1,a0
		moveq	#$31,d0
		lea		starGfx+4,a3
		move.w	#stars_count-1,d7
		bsr		setupSpritelist

		lea		slst2,a0
		moveq	#$30,d0
		lea		starGfx+8,a3
		move.w	#stars_count-1,d7
		bsr		setupSpritelist

		lea		slst3,a0
		moveq	#$31,d0
		lea		starGfx,a3
		move.w	#stars_count-1,d7
		bsr		setupSpritelist
	
		move.l	#slst0,d0
		lea		spoint+2,a0
		move.w	d0,4(a0)
		swap	d0
		move.w	d0,(a0)
		addq	#8,a0
		move.l	#slst1,d0
		move.w	d0,4(a0)
		swap	d0
		move.w	d0,(a0)
		addq	#8,a0
		move.l	#slst2,d0
		move.w	d0,4(a0)
		swap	d0
		move.w	d0,(a0)
		addq	#8,a0
		move.l	#slst3,d0
		move.w	d0,4(a0)
		swap	d0
		move.w	d0,(a0)
		rts
;---------------------------------------------
; a0: sprite list (output)
; a1: start x coords
; a2: prio (color and speed)
; d0: y start
; d7: # of stars

setupSpritelist:
		move.w	d0,d2
		addq	#1,d2
.loop:
		move.w	d0,d6
		bsr		getRandomNumber
		move.w	d0,d1
		and.w	#$1ff,d1
		move.w	d6,d0

		moveq	#0,d3
		moveq	#0,d5
		move.b	d1,d3
		and.b	#$01,d3
		move.w	d1,d5
		lsr.w	#1,d5

		cmp.w	#$ff,d0		; y start > 255?
		bls		.nvsrhi
		bset	#2,d3		; y start hi bit
.nvsrhi:		
		cmp.w	#$ff,d2		; y stop > 255?
		bls		.nvsthi
		bset	#1,d3		; y stop hi bit
.nvsthi:		
		move.l	d0,d4
		ror.w	#8,d4
		move.b	d5,d4
		swap	d4	
		move.b	d2,d4
		rol.w	#8,d4
		move.b	d3,d4
		move.l	d4,(a0)+

		move.l	(a3),(a0)+	; gfx

		; scroller copperbar coord. skip
		cmp.w	#$cc,d0			; scrollerbar = cf - e0
		ble		.noScrollerBar
		cmp.w	#$e0,d0
		bhi		.noScrollerBar
		add.w	#$22,d0
		add.w	#$22,d2
.noScrollerBar

		addq	#2,d0		; next v start
		addq	#2,d2		; next v stop
		dbf		d7,.loop

		move.l	#0,(a0)+	; end of sprite list
		rts
;---------------------------------------------
updateStars:		
		moveq	#1,d0
		move.w	#stars_count-1,d7
		lea		slst0+1,a0
.loop:
		eor.b	d0,2(a0)
		btst	#0,2(a0)
		bne.s	.noinc
		add.b	d0,(a0)

		eor.b	d0,stars_count*8+2+4(a0)
		btst	#0,stars_count*8+2+4(a0)
		bne.s	.noinc
		add.b	d0,stars_count*8+4(a0)

		eor.b	d0,stars_count*16+2+8(a0)
		btst	#0,stars_count*16+2+8(a0)
		bne.s	.noinc
		add.b	d0,stars_count*16+8(a0)

		eor.b	d0,stars_count*24+2+12(a0)
		btst	#0,stars_count*24+2+12(a0)
		bne.s	.noinc
		add.b	d0,stars_count*24+12(a0)
.noinc
		lea		8(a0),a0
		dbf		d7,.loop	
		rts
		rts
		
starGfx:	
		dc.l	$00010000,$00000001,$00010001

; sprite lists
slst0:		ds.b	stars_count*8
			dc.l	0
slst1:		ds.b	stars_count*8
			dc.l	0
slst2:		ds.b	stars_count*8
			dc.l	0
slst3:		ds.b	stars_count*8
			dc.l	0
