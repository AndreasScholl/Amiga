		INCDIR      "include"
		INCLUDE     "hw.i"
		INCLUDE     "funcdef.i"
		INCLUDE     "exec/exec_lib.i"
		INCLUDE     "graphics/graphics_lib.i"
		INCLUDE     "hardware/cia.i"

src_adr			= $6e000		; scroll buffer source adress
src_line 		= $32			; source line width

screenHeight	= 128
li				= $2e			; screen line size in bytes

sc_offset		= 58			; scroller dest y offset
ho				= li*sc_offset	; dst height start offset
yTop			= sc_offset-23	; scroller top y pos (for copy and pixel effect)
sc_top			= yTop*li		;

ss		 		= $6e014		; source start of scoller turn
ds		 		= $14			; destination start	of scroller turn

lifetime        = 120
numPoints		= 128           ; # of points for scroller dissolve effect
;numPoints		= 64			

; --- point area definition
game_width		= 352
game_height		= 160

		section "code",data,chip
initScroller::
        moveq   #0,d1
        bsr.s   updateLogoPointers

		bsr		buildLogoColors

		lea		spoint(pc),a5
		jsr		setupStarfield	; starfield
		bsr		setupScroller
		bsr		initPoints

 		move.l	#clist,$dff080
		clr.w	$dff088
		rts
;-------
stateStarted = 0
stateEnd     = 1
scrollerState:  dc.w    stateStarted
;-------
logoY			= $31       ; logo start y
;logo_height = 64
logo_height = 73
logo_color_count = 11   ;14

; d1: offset in bytes
updateLogoPointers:
		move.l	#logo,d0
        add.l   d1,d0
		move.l	#(320/8)*73,d1
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
		; add.l	d1,d0
		; move.w	d0,logobp4l
		; swap	d0
		; move.w	d0,logobp4h
        rts
;-------
updateScroller::
		lea		$dff000,a6
        bsr     clearScroller

        cmp.w   #stateEnd,scrollerState
        beq.s   .scrollerEnded
		bsr		scroll
		; move.w	#$424,$180(a6)
		bsr		postEffect

		; move.w	#$266,$180(a6)
		lea		$dff000,a6
		bsr		addPoints
		bsr		drawPoints
.scrollerEnded:        
		; move.w	#$882,$180(a6)
		; bsr		updateLogoColors		; super slow :(

		bsr		updateLogoPos
		jsr		updateStars
;		move.w	#$882,$180(a6)
        rts
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
clearScroller:				;<switch screens and clear>
		lea		$dff000,a6
		not.b	screenToggleScroller
		bne.s	.s0
		move.w	#0,bp0+2
		move.l	#$78000,screenlocScroller
		bra.s	.s1
.s0:		
		move.w	#$8000,bp0+2
		move.l	#$70000,screenlocScroller
.s1:
		bsr		bbusy
		move.l	screenlocScroller,$54(a6)
		move.l	#-1,$44(a6)
		move.l	#0,$64(a6)
		move.l	#$01000000,$40(a6)
		move.w	#(screenHeight<<6)+(li/2),$58(a6)
		rts
;---------------------------------------------
screenToggleScroller:		
		dc.w	0
screenlocScroller		
		dc.l	$70000
;-------
drawPoints:
		move.l	screenlocScroller,a0
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
		move.l	screenlocScroller,a1
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
		move.w	#lifetime,point_life(a5)

		move.w	#(8*8)+1,d0
		lsl.w	#7,d0
		move.w	d0,point_xfloat(a5)

		move.w	d7,d0			; y offset
		lsl.w	#7,d0
		move.w	d0,point_yfloat(a5)

		moveq	#0,d0			; x speed
		jsr		getRandomNumber
		and.w	#$7f,d0
		add.w	#$60,d0
;		move.w	#$80,d0
		neg.w	d0
		move.w	d0,point_xvelo(a5)

		move.w	#0,d0			; test y speed
		jsr		getRandomNumber
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
		move.l	screenlocScroller,d6
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
		move.l	screenlocScroller,a1
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
		move.l	screenlocScroller,a1
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
;------------
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
;------------------------
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
		jsr		bbusy

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
		add.w	(a4),a0                 ; + text char offset
		addq.w	#1,(a4)
		moveq	#43,d1
		move.b	(a0),d0                 ; end of text?
		bne.s	.notextfin
;		clr.w	(a4)	                ; restart
		subq.w	#1,(a4)                 ; stay on end of text
        cmp.w   #stateStarted,scrollerState
        bne.s   .noStateChange
        move.w   #stateEnd,scrollerState        
.noStateChange
		bra.s 	.textfin
.notextfin:
		lea		rchartab,a1
		move.b	(a1,d0.w),d1
.textfin:	
		lea		char(pc),a2
		add.w	d1,a2
		lea		src_adr+src_line-2,a1	; offset to end of line (putchar destination)
		add.w	d7,a1

		jsr		bbusy

		move.b	(a2),(a1)
		move.b	050(a2),1*src_line(a1)
		move.b	100(a2),2*src_line(a1)
		move.b	150(a2),3*src_line(a1)
		move.b	200(a2),4*src_line(a1)
		move.b	250(a2),5*src_line(a1)
		rts	

        		rsreset
point_life:	    rs.w	1		;life time
point_xfloat:	rs.w	1		;x-coordinate (floating)
point_yfloat:	rs.w	1		;y-coordinate (floating)
point_xvelo:	rs.w	1		;x velocity
point_yvelo:	rs.w	1		;y velocity
point_len:	    rs.w	0

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

			move.w	#((logoY+1)<<8)+1,d4
;			move.w	#256-(44*fadeIncrease),d7		; fade level

			move.w	#logo_height-1,d5
			bra		.skipWait				; first entry has no wait
.loop:
			move.w	d4,(a1)+				; copper wait
			move.w	#$fffe,(a1)+			;
			add.w	#$0100,d4
.skipWait:			
			move.w	(a2)+,d2				; color add value
			move.w	(a3)+,d7				; fade level
;			move.w	#256,d7

			lea		logoColorsOrig,a0
			move.w	#logo_color_count-1,d3
.colorLoop:
			move.w	(a0)+,(a1)+				; color reg
			move.w	(a0)+,d0
			or.w	d2,d0                   ; color blend add

			bsr		colorFade
            ; move.w  d0,d6

			move.w	d6,(a1)+				; final color value
			dbf		d3,.colorLoop

			dbf		d5,.loop
			rts

; updateLogoColors:
; 			lea		logoColors+2,a1
; 			lea		colorAdd,a2
; 			lea		fadeLevel,a3

; 			move.w	#44-1,d5
; 			bra		.noWait				; first entry has no wait
; .loop:
; 			lea		4(a1),a1				; skip wait
; .noWait:			
; 			clr.w	d2
; 			move.w	(a2)+,d2				; color add
; 			add.w	colorAddVar,d2

; 			move.w	(a3)+,d7				; fade level
; 			add.w	colorFadeVar,d7
; 			cmp.w	#256,d7
; 			ble		.noHighFade
; 			move.w	#256,d7
; .noHighFade

; 			lea		logoColorsOrig+2,a0
; 			move.w	#logo_color_count-1,d3
; .colorLoop:
; 			move.w	(a0),d0
; 			lea		4(a0),a0				; next source color value
; 			or.w	d2,d0
; 			bsr		colorFade
; 			move.w	d6,(a1)					; color value
; 			lea		4(a1),a1
; 			dbf		d3,.colorLoop

; 			dbf		d5,.loop

; 			add.w	#$001,colorAddVar

; 			move.w	colorFadeDir,d0
; 			add.w	d0,colorFadeVar

; 			add.w	#1,colorFadeDirCount
; 			cmp.w	#32,colorFadeDirCount
; 			bne		.noColFadeToggle
; 			move.w	#0,colorFadeDirCount
; 			neg.w	colorFadeDir
; .noColFadeToggle
; 			rts

; colorFadeDir:
; 			dc.w	4

; colorFadeDirCount:
; 			dc.w	1

; colorFadeVar:
; 			dc.w	0

; colorAddVar:
; 			dc.w	0

colorAdd:
			dc.w	$f		; 0
			dc.w	$f
			dc.w	$e
			dc.w	$e
			dc.w	$d
			dc.w	$d
			dc.w	$c
			dc.w	$c
			dc.w	$b
			dc.w	$b
			dc.w	$a		; 10
			dc.w	$a
			dc.w	$8
			dc.w	$8
			dc.w	$7
			dc.w	$7
			dc.w	$6
			dc.w	$6
			dc.w	$5
			dc.w	$5
			dc.w	$4	    ; 20
			dc.w	$4
			dc.w	$3
			dc.w	$3
			dc.w	$2
			dc.w	$2
			dc.w	$1
			dc.w	$1
			dc.w	$0
			dc.w	$0
			dc.w	$0	    ; 30
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0
			dc.w	$0	    ; 40
			dc.w	$0
			dc.w	$100
			dc.w	$101
			dc.w	$201
			dc.w	$202
			dc.w	$302
			dc.w	$303
			dc.w	$403
			dc.w	$404
			dc.w	$504	    ; 50
			dc.w	$505
			dc.w	$606
			dc.w	$606
			dc.w	$706
			dc.w	$707
			dc.w	$807
			dc.w	$808
			dc.w	$909
			dc.w	$909
			dc.w	$a09	    ; 60
			dc.w	$a0a
			dc.w	$b0a
			dc.w	$b0b
			dc.w	$c0b
			dc.w	$c0c
			dc.w	$d0c
			dc.w	$d0d
			dc.w	$e0d
			dc.w	$e0e
			dc.w	$f0e    ; 70
			dc.w	$f0f
			dc.w	$000
			dc.w	$000
			dc.w	$000

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
			dc.w	11*22
			dc.w	11*22
			dc.w	11*22
			dc.w	11*23
			dc.w	11*23
			dc.w	11*23
			dc.w	11*23       ; 30
			dc.w	11*23
			dc.w	11*23
			dc.w	11*23
			dc.w	11*23
			dc.w	11*23
			dc.w	11*23
			dc.w	11*23
			dc.w	11*23
			dc.w	11*23
			dc.w	11*23       ; 40
			dc.w	11*21
			dc.w	11*21
			dc.w	11*21
			dc.w	11*20
			dc.w	11*20
			dc.w	11*19	
			dc.w	11*19
			dc.w	11*18
			dc.w	11*17
			dc.w	11*16       ; 50
			dc.w	11*15
			dc.w	11*14
			dc.w	11*13
			dc.w	11*12
			dc.w	11*11
			dc.w	11*10
			dc.w	11*9
			dc.w	11*9
			dc.w	11*7
			dc.w	11*6       ; 60
			dc.w	11*5
			dc.w	11*4
			dc.w	11*3
			dc.w	11*2
			dc.w	11*1
			dc.w	11*1
			dc.w	11*0
			dc.w	11*0
			dc.w	11*0
			dc.w	11*0       ; 70
			dc.w	11*0
			dc.w	11*0
			dc.w	11*0


; in  d0: color value
; out d6: faded color value
colorFadeOut:
            moveq   #0,d6
			move.w	d0,d1
			lsr.w	#8,d1		; r (nibble)
            beq.s   .doneR
            subq.w  #1,d1
			lsl.w	#8,d1		; shift r into right spot
			or.w	d1,d6			
.doneR:
			move.w	d0,d1
			lsr.w	#4,d1		; g (nibble)
			and.w	#$0f,d1
            beq.s   .doneG
            subq.w  #1,d1
			lsl.w	#4,d1		; shift g into right spot
			or.w	d1,d6
.doneG:
			move.w	d0,d1
			and.w	#$0f,d1		; b (nibble)
            beq.s   .doneB
            subq    #1,d1
			or.w	d1,d6
.doneB:
			rts

logoFadeLine:
            dc.w    0
logoFadeRepeat:
            dc.w    0

updateLogoPos:
            cmp.w   #stateEnd,scrollerState
            bne.s   .notEnded
            bsr     fadeOutLogo
            bsr     fadeOutBar
            rts
.notEnded:            
			move.w	logoMoveDir,d0
			add.w	d0,logoMoveSpeed

			move.w	logoMoveSpeed,d0
			add.w	d0,logoPos

			add.w	#1,logoMoveDirCount
			cmp.w	#48,logoMoveDirCount
			bne		.noToggle
			move.w	#0,logoMoveDirCount
			neg.w	logoMoveDir
.noToggle:
.updateClist:
            ; --- update copperlist from logo pos
			move.w	logoPos,d0
            ; move.w  #-256,d0                 ; debug test
			addq	#8,d0
			asr.w	#4,d0
            tst.w   d0
            bge     .noNegativePos
            ; if logo pos < 0 -> increase bitplane pointers
            neg.w   d0
            mulu.w  #(320/8),d0             ; logo line in bytes
            ext.l   d0
            move.l  d0,d1
            bsr     updateLogoPointers
            moveq   #0,d0
.noNegativePos
;			add.w	#logoY-16,d0
			add.w	#logoY-7,d0
			move.b	d0,logoStartWait
			add.w	#logo_height,d0
			move.b	d0,logoEndWait
			rts
; ---------------------------------------------
fadeOutLogo:
            moveq   #20,d4
.lineFader:
            ; fade out logo line by line
            lea     logoColors+2,a0         ; first color value
            move.w  logoFadeLine,d0
            mulu.w  #(2*2)+(logo_color_count*2*2),d0
            ext.l   d0
            add.l   d0,a0
            moveq   #logo_color_count-1,d7
            moveq   #1,d5                   ; line done flag
.fadeColor:
            move.w  (a0),d0
            bsr     colorFadeOut
            move.w  d6,(a0)
            tst.w   d6
            beq.s   .colorDone
            moveq   #0,d5                   ; line not done (not faded out)
.colorDone
            lea     4(a0),a0
            dbf     d7,.fadeColor

            ; tst.w   d5
            ; beq.s   .noNextLine
            cmp.w   #logo_height-5,logoFadeLine
            bne.s   .noRestart
            clr.w   logoFadeLine
            add.w   #1,logoFadeRepeat
            bra.s   .noNextLine
.noRestart
            add.w   #1,logoFadeLine
.noNextLine:
            dbf     d4,.lineFader           ; loop for faster fade

            cmp.w   #8,logoFadeRepeat
            bne.s   .noPrioSwitch
            move.w   %100100,playfieldPrio	; set playfield prios -> sprites in front of playfields
.noPrioSwitch

            cmp.w   #15,logoFadeRepeat
            bne.s   .noPartSwitch
            ; --- switch to game
            jsr     initGame
            move.l  #updateGamePart,d0
            move.l  d0,updateFunction
.noPartSwitch:
            rts
; --------------------
fadeOutBar:
            lea     clist,a0
            lea     barcolorOffsets,a1
            moveq   #19-1,d7
.barfade:
            move.w  (a1)+,d2            ; color value offset relative to clist
            move.w  (a0,d2.w),d0        ; get color value
            bsr     colorFadeOut
            move.w  d6,(a0,d2.w)        ; store faded color value

            dbf     d7,.barfade
            rts

logoMoveDir:
			dc.w	1
logoMoveDirCount:
			dc.w	24
logoMoveSpeed:
			dc.w	0
logoPos:
			dc.w	0

text:
		dc.b    "quadlite and thrust present something ..... "
        dc.b    "                                                                  ",0
		dc.b	"zeronine says hi to --- major rom --- mark ii ---- equalizer --- exciter --- "
		dc.b	"dandee -- lord performer --- exolon --- phil --- doctor soft --- kongoman and all the others ........ ",0
		even

logo:
;        INCBIN	"thrust-quadlite_green_lo4.bin"
;        INCBIN	"thrust-quadlite_logo.bin"
        INCBIN	"thrust-quadlite_16.bin"

;	palette for: thrust-quadlite
;	Mon Mar 18 2024 22:38:46 GMT+0100 (Mitteleuropäische Normalzeit)
logoColorsOrig:
;	palette for: thrust-quadlite_16
;	Mon Mar 18 2024 23:17:02 GMT+0100 (Mitteleuropäische Normalzeit)
	dc.w	$0182,$0463
	dc.w	$0184,$0777
	dc.w	$0186,$0999
	dc.w	$0188,$0bbb
	dc.w	$018a,$02a4
	dc.w	$018c,$0050
	dc.w	$018e,$0020
	dc.w	$0190,$0ddd
	dc.w	$0192,$06e6
	dc.w	$0194,$0fff

	dc.w	$0182,$0554
	dc.w	$0184,$0777
	dc.w	$0186,$0997
	dc.w	$0188,$0999
	dc.w	$018a,$0bbb
	dc.w	$018c,$0697
	dc.w	$018e,$0371
	dc.w	$0190,$0050
	dc.w	$0192,$0020
	dc.w	$0194,$0694
	dc.w	$0196,$0091
	dc.w	$0198,$0ddd
	dc.w	$019a,$0052
	dc.w	$019c,$0070
	dc.w	$019e,$0094
	dc.w	$01a0,$09f7
	dc.w	$01a2,$09b9
	dc.w	$01a4,$06d6
	dc.w	$01a6,$03f6
	dc.w	$01a8,$03b4
	dc.w	$01aa,$0fff
	dc.w	$01ac,$0375
	dc.w	$01ae,$0cfc
	dc.w	$01b0,$0ffd
	dc.w	$01b2,$00d3
	dc.w	$01b4,$08d9

; palette for: thrust-quadlite_green
;logoColorsOrig:
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

; copperlist
clist:		
		dc.w	BPLCON0,$0200		; bitplanes off

		dc.w	$0108,$0000		; even bitplanes modulo
		dc.w	$010a,$0000		; odd bitplanes modulo

		dc.w	DDFSTRT,$0038
		dc.w	DDFSTOP,$00d0

		; dc.w	$0104,%100100	; set playfield prios
		dc.w	$0104
playfieldPrio:
        dc.w    %000000	; set playfield prios	(sprites behind playfields)

spoint:		
		; sprite pointers
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

; 		dc.w	$00f0
; logobp4h:	
; 		dc.w	0	
; 		dc.w	$00f2
; logobp4l:	
; 		dc.w	0	

		dc.w	$2001,$fffe			; stars start
		dc.w	$0182,$0000	   ; black plane
		dc.w	BPLCON0,$1200		; one plane
		dc.w	$00e0,$0006
		dc.w	$00e2,$e000-li
		dc.w	$0108,$ffd8			; even bitplanes modulo

logoStartWait:
 		dc.w	$4001,$fffe
		dc.w	BPLCON0,$4200		; 5 bitplanes
		dc.w	$0108,$0000			; even bitplanes modulo

        ; note: logo bp0 has to be set here as we have a empty bitplane 0
        ;       before the logo starts or else the sprites (stars) won't display
		dc.w	$00e0               
logobp0h:	
		dc.w	0	
		dc.w	$00e2
logobp0l:	
		dc.w	0

logoColors:
	; dc.w	$0182,$0463
	; dc.w	$0184,$0777
	; dc.w	$0186,$0999
	; dc.w	$0188,$0bbb
	; dc.w	$018a,$02a4
	; dc.w	$018c,$0050
	; dc.w	$018e,$0020
	; dc.w	$0190,$0ddd
	; dc.w	$0192,$06e6
	; dc.w	$0194,$0fff
		blk.w	((2+(logo_color_count*2))*logo_height)-2,0

logoEndWait:
 		dc.w	$6c01,$fffe			; logo end wait
		dc.w	BPLCON0,$0200		; bitplanes off

;		dc.w	$0180,$0fff	   ; debug test
		dc.w	$0182,$0000	   ; black plane
		dc.w	BPLCON0,$1200		; one plane
		dc.w	$00e0,$0006
		dc.w	$00e2,$e000-li
		dc.w	$0108,$ffd8			; even bitplanes modulo

		; dc.w	$8401,$fffe		; start of "game" area
		dc.w	$9c01,$fffe		; start of "game" area
		dc.w	BPLCON0,$1200	; 1 bitplanes on
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
barc1:	dc.w	$0180,$0112	; flat scrollarea anti alias line ;)
		dc.w	$0182,$0858
		dc.w	$010a,$ffd2		; negative odd bitplanes modulo -> repeat last line
		dc.w	$0102,$00c0		; scroll
		dc.w	$0192,$0112		; shadow color
		dc.w	$d001,$fffe
barc2:	dc.w	$0180,$0234	; flat scrollarea start
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
barc3:	dc.w	$0180,$0567	; wall downwards start
		dc.w	$df01,$fffe
barc4:	dc.w	$0180,$0356	; wall 
		dc.w	$e001,$fffe
barc5:	dc.w	$0180,$0355	; wall 
		dc.w	$e101,$fffe
barc6:	dc.w	$0180,$0345	; wall 
		dc.w	$e201,$fffe
barc7:	dc.w	$0180,$0245	; wall 
		dc.w	$e301,$fffe
barc8:	dc.w	$0180,$0244	; wall 
		dc.w	$e401,$fffe
barc9:	dc.w	$0180,$0234	; wall 
		dc.w	$e501,$fffe
barc10:	dc.w	$0180,$0134	; wall 
		dc.w	$e601,$fffe
barc11:	dc.w	$0180,$0133	; wall 
		dc.w	$e701,$fffe
barc12:	dc.w	$0180,$0123	; wall 
		dc.w	$e801,$fffe
barc13:	dc.w	$0180,$0023	; wall 
		dc.w	$e901,$fffe
barc14:	dc.w	$0180,$0022	; wall 
		dc.w	$ea01,$fffe
barc15:	dc.w	$0180,$0012	; wall 
		dc.w	$eb01,$fffe
barc16:	dc.w	$0180,$0012	; wall 
		dc.w	$ec01,$fffe
barc17: dc.w	$0180,$0011	; wall 
		dc.w	$ed01,$fffe
barc18:	dc.w	$0180,$0001	; wall 
		dc.w	$ee01,$fffe
barc19: dc.w	$0180,$0001	; wall 
		dc.w	$ef01,$fffe
		dc.w	$0180,$0000	; wall 

		; dc.w	$f001,$fffe
		; dc.w	$0180,$0000	; wall end


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

barcolorOffsets:
        dc.w    (barc1+2)-clist
        dc.w    (barc2+2)-clist
        dc.w    (barc3+2)-clist
        dc.w    (barc4+2)-clist
        dc.w    (barc5+2)-clist
        dc.w    (barc6+2)-clist
        dc.w    (barc7+2)-clist
        dc.w    (barc8+2)-clist
        dc.w    (barc9+2)-clist
        dc.w    (barc10+2)-clist
        dc.w    (barc11+2)-clist
        dc.w    (barc12+2)-clist
        dc.w    (barc13+2)-clist
        dc.w    (barc14+2)-clist
        dc.w    (barc15+2)-clist
        dc.w    (barc16+2)-clist
        dc.w    (barc17+2)-clist
        dc.w    (barc18+2)-clist
        dc.w    (barc19+2)-clist

;--------------------------------------------------------------
; lookup table for scroller chars
rchartab:	
		blk.w	256,0

