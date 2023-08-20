
		INCDIR      "include"
		INCLUDE     "hw.i"
		INCLUDE     "funcdef.i"
		INCLUDE     "exec/exec_lib.i"
		INCLUDE     "graphics/graphics_lib.i"
		INCLUDE     "hardware/cia.i"

src_adr		= 	$6e000	; scroll buffer source adress
src_line 	= 	$32		; source line width

ss		 	=	$6e014
ds		 	=	$70014	; destination start
li			=	$2e		; dst line size in bytes
ho			=	li*23	; dst height start offset

		section "code",data,chip

init:
		move.l	#st,$80
		trap	#0

		move.l	$4,a6
		move.l	#lib,a1
		clr.l	d0
		jsr	-552(a6)
		move.l	d0,a4
		move.l	38(a4),$dff080
		clr.w	$dff088
		moveq	#0,d0
		rts

lib:	dc.b	'graphics.library',0
		even

st:		
		move.w	#$2700,sr
		move.l	#clist,$dff080
		clr.w	$dff088
		bsr		mctab
		move.w	#$0020,$dff096

begin:	
		lea		$dff000,a6
rwait:		
		cmp.b	#$50,$006(a6)
		bne.s	rwait
;rwait2:		cmp.b	#$30,$006(a6)
;		bne.s	rwait2
		
;		move.w	#-1,$dff180
		bsr		scroll
		bsr		postEffect
;		move.w	#0,$dff180

.pause:		
		btst	#6,$bfe001
		beq		.pause

		bra		begin
		rte

;-------
postEffect:
		lea		$70000,a0
		move.l	#$2e*8,d7
clear:		
		clr.l	(a0)+
;		move.l 	#-1,(a0)+
		dbf		d7,clear
;		rts					; test
;---
		bsr		bbusy

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
copyloop2:
		move.l	(a2)+,a0
		move.w	(a2)+,d1
		move.l	(a2)+,a1
		move.w	(a2)+,d2
		bsr		copyColumnShift
		dbf		d7,copyloop2

;		rts
; copy rest of scroller (for now with processor)

leftblock_words = 10
		lea		src_adr,a0
		lea 	$70000,a1
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
		lea 	ds+ho-(li*1)+2+1,a1	; dest
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
		or.w	d0,$2e*1(a1)		

		move.w	src_line*2(a0),d0
		and.w	d1,d0
		or.w	d0,$2e*2(a1)		

		move.w	src_line*3(a0),d0
		and.w	d1,d0
		or.w	d0,$2e*3(a1)		

		move.w	src_line*4(a0),d0
		and.w	d1,d0
		or.w	d0,$2e*4(a1)		

		move.w	src_line*5(a0),d0
		and.w	d1,d0
		or.w	d0,$2e*5(a1)		

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
		or.w	d0,$2e*1(a1)		

		move.w	src_line*2(a0),d0
		and.w	d1,d0
		ror.w	d2,d0
		or.w	d0,$2e*2(a1)		

		move.w	src_line*3(a0),d0
		and.w	d1,d0
		ror.w	d2,d0
		or.w	d0,$2e*3(a1)		

		move.w	src_line*4(a0),d0
		and.w	d1,d0
		ror.w	d2,d0
		or.w	d0,$2e*4(a1)		

		move.w	src_line*5(a0),d0
		and.w	d1,d0
		ror.w	d2,d0
		or.w	d0,$2e*5(a1)		

		rts

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

text:
;		dc.b	"                                                               "
		dc.b    "hi, this is zeronine on the waescheline calling out to everyone in the kraeckertalk chat --- "
		dc.b    " i fixed the scroller and added some copper colors to make it look like real 3d --- "
		dc.b	" shout out to equalizer for intruducing me to the visual studio code workflow --- ",0
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

clist:		
		dc.w	$0180,$0000

		dc.w	$0100,$0200		; bitplanes off

		dc.w	$c001,$fffe
		dc.w	$0100,$1200		; 1 bitplanes on
		dc.w	$00e0,$0007		; bitplane 0 
		dc.w	$00e2,$0000		;

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
		dc.w	$00e6,($002e*15)-2		; + lines offset to adjust shadow pos
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
		dc.w	$dc01,$fffe
		dc.w	$0100,$0200		; bitplanes off

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

