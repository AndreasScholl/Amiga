
        INCDIR      "include"
        INCLUDE     "hw.i"
        INCLUDE     "funcdef.i"
        INCLUDE     "exec/exec_lib.i"
        INCLUDE     "graphics/graphics_lib.i"
        INCLUDE     "hardware/cia.i"

lines = 240

        section "code",data,chip
        
initCopper::        
        move.w  #$0f01,d0
        lea     colors,a0
        lea     colorData,a1
        move.l  #240-1,d7
.loop:
        move.w  d0,(a0)+
        move.w  #$fffe,(a0)+
        move.w  #$0180,(a0)+
        move.w  (a1)+,(a0)+
        move.w  #$0182,(a0)+
        move.w  (a1),(a0)+
        add.w   #$0100,d0
        dbf     d7,.loop

        move.l	#clist,$dff080
        clr.w	$dff088
; .loop2:
;         move.w  d0,$dff180
;         add.w   #$110,d0
;         bra.s   .loop2

        rts

updateCopper::
        move.l  colorPointer,a1
        move.l  a1,a2
        add.l   #240*2,a2
        ; add.l   #180*2,a2
        lea     colors+6,a0
        move.l  #240-1,d7
        moveq   #0,d2
.loop:
        move.w  (a1)+,(a0)        
        move.w  (a2),d0
        cmp.w   #$222,d0
        bge.s   .skip
        move.w  #$808,d0
.skip:
        move.w  d0,4(a0)
        lea     12(a0),a0
        ; not.b   d2
        ; beq.s   .noadd
        ; lea     -4(a2),a2
        lea     -2(a2),a2
; .noadd:
        dbf     d7,.loop

        cmp.l   #colorEnd,a1
        bne.s   .noEnd
        move.l  #colorData,a1
.noEnd:
        move.l  a1,colorPointer

        ; --- scroll
        bsr	scroll
        bsr	clearscroll
        jsr	bbusy
        bsr	sinscroll
        rts

colorPointer:
        dc.l    colorData

corcount:	dc.w	$0000
oldm:		dc.w	$00
wait:		dc.w	$0
blcount:	dc.w	$0

sinscroll:	
		lea	coords,a0
		sub.w	#4,corcount
		and.w	#$1ff,corcount
		move.w	corcount,d6

		move.l	#$60000,a1	
		moveq	#19,d2
		moveq	#0,d3
		move.w	#$c000,d0
		move.l	screenloc,fred+2
sinloop:
		moveq	#7,d1	

		move.w	42(a1),d5	
		move.w	84(a1),d7
		move.w	168(a1),a6
		move.w	210(a1),a5
		move.w	252(a1),a4
wordloop:
		clr.w	d3
		move.b	(a0,d6.w),d3    ; scroll y coord
                lsr.w   #1,d3           ; scale coord

		add.w	#2,d6
		and.w	#$1ff,d6
		lsl	#6,d3
fred:		lea	$60000,a2
		add.w	d3,a2

		move.w	(a1),d4
		and.w	d0,d4
		or.w	d4,(a2)	

		move.w	d5,d4
		and.w	d0,d4
		or.w	d4,64(a2)	

		move.w	d7,d4
		and.w	d0,d4
		or.w	d4,128(a2)	

		move.w	126(a1),d4
		and.w	d0,d4
		or.w	d4,192(a2)	

		move.w	a6,d4
		and.w	d0,d4
		or.w	d4,256(a2)	

		move.w	a5,d4
		and.w	d0,d4
		or.w	d4,320(a2)	

		move.w	a4,d4
		and.w	d0,d4
		or.w	d4,384(a2)	

		move.w	336(a1),d4
		and.w	d0,d4
		or.w	d4,448(a2)	

		move.w	378(a1),d4
		and.w	d0,d4
		or.w	d4,512(a2)	

		move.w	378+42(a1),d4
		and.w	d0,d4
		or.w	d4,512+64(a2)	

		move.w	378+84(a1),d4
		and.w	d0,d4
		or.w	d4,512+128(a2)	

		move.w	378+84+42(a1),d4
		and.w	d0,d4
		or.w	d4,512+192(a2)	

		move.w	378+84+84(a1),d4
		and.w	d0,d4
		or.w	d4,512+256(a2)	

		move.w	378+84+84+42(a1),d4
		and.w	d0,d4
		or.w	d4,512+256+64(a2)	

		move.w	378+84+84+84(a1),d4
		and.w	d0,d4
		or.w	d4,512+256+128(a2)	
test:
		ror.w	#2,d0	
	
		dbf	d1,wordloop
		addq.w	#2,fred+4
		addq	#2,a1
		dbf	d2,sinloop
		rts

scount:		dc.w	$00
tcount:		dc.w	$00

clearscroll:	jsr	bbusy	
cloc:		move.l	#$61000,$dff054
		move.l	#$01f00000,$dff040
		move.l	#$ffffffff,$dff044
		move.l	#$0000,$dff064
		move.w	#0,$dff074
		move.w	#%0001100000000000,$dff058
		rts
scroll:		
		bsr	switch
		jsr	bbusy	
		move.l	#$60000,$dff050
		move.l	#$60000-2,$dff054
		move.l	#$e9f00000,$dff040
		move.l	#$ffffffff,$dff044
		move.l	#$0000,$dff064
		move.w	#%0000010000010111,$dff058

		add.w	#2,scount
		cmp.w	#$10,scount
		bne	nonewchar	
		move.w	#$00,scount
		
		add.w	#1,tcount
		lea	text,a0
		add.w	tcount,a0
		move.b	(a0),d0
		tst.b	d0
		bne	textfin
		clr.w	tcount		
		move.w	#42,d1
		bra	textfin2
textfin:
		lea	chartab,a1
		clr.l	d1
getchar:	cmp.b	(a1),d0
		beq	gotchar
		add.w	#1,d1
		tst.b	(a1)+
		bne	getchar
gotchar:	
textfin2:
		jsr	bbusy
		lea	char,a2
		lsl	#1,d1
		add.w	d1,a2
		
		lea	$60028,a1
		moveq	#15,d1
		move.w	#42,d0
copychar:	move.w	(a2),(a1)
		add.w	d0,a1
		add.w	#92,a2
		dbf	d1,copychar		
nonewchar:	rts	

screenloc:	dc.l	$60000
switchbyte:	dc.w	$00


switch:		not.b	switchbyte
		tst.b	switchbyte
		bne	screen1
		move.l	#$61000,screenloc
		move.l	#$61000,cloc+2
		move.w	#$0f80,bp0+2
		
		bra	screen0
screen1:	move.l	#$69000,screenloc
		move.l	#$69000,cloc+2
		move.w	#$8f80,bp0+2
screen0:	rts

text:		
        dc.b	"   zeronine the mega-coder at revision 2024     ",0
        dc.b	0
chartab:
        dc.b	"abcdefghijklmnopqrstuvwxyz0123456789,-./:! (')",0
        even

char:
        dc.l $1fffffe0,$1fffffe0,$ffffffff,$1ffff03c,$0ff003ff,$f00ff000
        dc.l $fc7ff03f,$1fff7ff0,$1fff7ff0,$ffffffff,$f03ff03f,$f03fc00f
        dc.l $781e7fff,$8fff81e0,$7fffffff,$bc0f7fff,$ffffffff,$ffffffff
        dc.l $80000000,$00000003,$00000780,$000003f8,$03f01fc0,$7ffffff8
        dc.l $7ffffff8,$ffffffff,$7ffff03c,$0ff003ff,$f01ff000,$fefff83f
        dc.l $7fff7ffc,$7fff7ffc,$ffffffff,$f03ff03f,$f03fe01f,$781e7fff
        dc.l $bfff83e0,$7fffffff,$bc0f7fff,$ffffffff,$ffffffff,$80000000
        dc.l $00000007,$00000780,$00000ff8,$07f01ff0,$f000003c,$fc00003c
        dc.l $00000000,$f000f03c,$00000000,$f03ef000,$ffe0fc3c,$f800783e
        dc.l $f800783e,$00000000,$f03cf03c,$f03cf03e,$781e0000,$7c0007e0
        dc.l $00000000,$3c0f0000,$00000000,$0000001e,$00000000,$0000000e
        dc.l $00000780,$00001f80,$0fe001f8,$f000003c,$f800003c,$00000000
        dc.l $f000f03c,$00000000,$f07cf000,$ffc0fe3c,$f000781e,$f000781e
        dc.l $00000000,$f03cf03c,$f03cf87c,$781e0000,$78000fe0,$00000000
        dc.l $3c0f0000,$00000000,$0000001e,$00000000,$0000001c,$00000780
        dc.l $00001f00,$0fc000f8,$f03cf03c,$f000f03c,$f000f000,$f000f03c
        dc.l $03c000f0,$f0f8f000,$f7bcff3c,$f03c781e,$f03c781e,$f00003c0
        dc.l $f03cf03c,$f03c7ff8,$781e001e,$787c1de0,$001e001e,$3c0f7800
        dc.l $7800001e,$781e781e,$00000000,$00000038,$03c00780,$00001e00
        dc.l $0f800078,$f03cf03c,$f000f03c,$f000f000,$f000f03c,$03c000f0
        dc.l $f1f0f000,$f33cffbc,$f03c783e,$f03c783e,$f80003c0,$f03cf03c
        dc.l $f03c3ff0,$7c1e003e,$78fe19e0,$003e001e,$3c0f7c00,$7800003e
        dc.l $781e7c1e,$00000000,$00000070,$03c007c0,$00001e00,$0f000078
        dc.l $f3fcf3fc,$f000f03c,$f3f0f3f0,$f1f8f3fc,$03c000f0,$f3f0f000
        dc.l $f03cf7dc,$f03c79fc,$f33c79fc,$7fe003c0,$f03cf03c,$f03c0780
        dc.l $3f9e007c,$79de01e0,$0ffc1f9e,$3c0f3ff0,$7ff007fe,$7ffe7ffe
        dc.l $00003ffc,$000000f0,$03c007e0,$00001e00,$00000078,$f3fcf3f8
        dc.l $f000f03c,$f3f0f3f0,$f1fcf3fc,$03c000f0,$f3f0f000,$f03cf3ec
        dc.l $f03c79f8,$f3bc79fc,$3ff803c0,$f03cf03c,$f03c0300,$1f9e00f8
        dc.l $7b9e01e0,$3ff81f9e,$3e0f1ffc,$7ffc07fe,$7ffe3ffe,$00003ffc
        dc.l $000001f0,$03c007e0,$00001e00,$00000078,$f03cf03c,$f800f03c
        dc.l $f000f000,$f03cf03c,$03c000f0,$f07cf800,$f0fcf1f4,$f03c7800
        dc.l $f1fc783e,$007c03c0,$f03cf87c,$f33c3cf0,$001e01f0,$7f1e01e0
        dc.l $7c00001e,$1fff001e,$781e01fc,$781e003e,$00003f00,$000003e0
        dc.l $000007e0,$00001f00,$000000f8,$f03cf03c,$fc00f07c,$f000f000
        dc.l $f03cf03c,$03c000f0,$f03cfc00,$f0fcf0f8,$f87c7800,$f8fc781e
        dc.l $003c03c0,$f87c7cf8,$f33c7cf8,$001e03e0,$7e3e01e0,$7800003e
        dc.l $0fff001e,$7c3e03f8,$7c3e001e,$00003f00,$000007c0,$000007e0
        dc.l $00001f80,$000001f8,$f0fcf3fc,$fffcf3fc,$fffcf000,$fffcf0fc
        dc.l $3ffc03fc,$fc3cfffc,$f0fcf0fc,$fffc7e00,$fffc7e1e,$fffc3ffc
        dc.l $fffc7ff8,$fffcfcfc,$003e07fe,$7ffe1ffe,$7ffe7ffe,$007f7ffe
        dc.l $7ffe07f0,$7ffe7ffe,$03c00000,$00000fc0,$00000000,$00001ff8
        dc.l $00001ff8,$f0fcf3fc,$fffcf3fc,$fffcf000,$fffcf0fc,$3ffc03fc
        dc.l $fc3cfffc,$f0fcf0fc,$fffc7e00,$fffc7e1e,$fffc3ffc,$fffc3ff0
        dc.l $fffcfcfc,$007e0ffe,$7ffe1ffe,$7ffe7ffe,$003f7ffe,$7ffe0fe0
        dc.l $7ffe7ffe,$03c00000,$00001fc0,$00000000,$00001ff8,$00001ff8
        dc.l $f0fcf3fc,$fffcf3fc,$fffcf000,$fffcf0fc,$3ffce3fc,$fc3cfffc
        dc.l $f0fcf0fc,$fffc7e00,$fffc7e1e,$fffc3ffc,$fffc3ff0,$fffcfcfc
        dc.l $7ffe1ffe,$7ffe1ffe,$7ffe7ffe,$003f7ffe,$7ffe1fc0,$7ffe7ffe
        dc.l $03c00000,$0fc03f80,$03c007e0,$00001ff8,$00001ff8,$f0fcf3fc
        dc.l $fffcf3fc,$fffcf000,$fffcf0fc,$3ffcf3fc,$fc3cfffc,$f0fcf0fc
        dc.l $fffc7e00,$fffc7e1e,$fffc3ffc,$fffc1fe0,$fffcfcfc,$7ffe3ffe
        dc.l $7ffe1ffe,$7ffe7ffe,$003f7ffe,$7ffe3f80,$7ffe7ffe,$07c00000
        dc.l $0fc07f00,$03c007e0,$00001ff8,$00001ff8,$f0fcf3f8,$7ffcf3f8
        dc.l $7ffcf000,$7ff8f0fc,$3ffc7ffc,$fc3c7ffc,$f0fcf0fc,$7ff87e00
        dc.l $7ffc7e1e,$fff83ffc,$7ffc1fe0,$fcfcfcfc,$7ffc7ffe,$3ffc1ffe
        dc.l $7ffe7ffc,$003f7ffc,$3ffc7f00,$3ffc7ffc,$0f800000,$0fc0fe00
        dc.l $03c007e0,$00000ff8,$00001ff0,$f0fcf3e0,$1ffcf3e0,$1ffcf000
        dc.l $1fe0f0fc,$3ffc3ffc,$fc3c1ffc,$f0fcf0fc,$1fe07e00,$1ff87e1e
        dc.l $ffe03ffc,$1ffc0fc0,$f87cfcfc,$7ff87ffe,$0ff01ffe,$7ffe7ff0
        dc.l $003f7ff0,$0ff07e00,$0ff07ff0,$0f000000,$0fc0fc00,$03c007e0
        dc.l $000003f8,$00001fc0,$64632e6c,$20243166,$66666666,$65302c24

coords:	
        dc.l $4f505152,$53545556,$5758595a
        dc.l $5b5c5d5e,$5f606162,$62636465,$66676869,$6a6b6c6d,$6e6f7070
        dc.l $71727374,$75767777,$78797a7b,$7c7c7d7e,$7f808081,$82838484
        dc.l $85868687,$8889898a,$8b8b8c8d,$8d8e8e8f,$90909191,$92939394
        dc.l $94959596,$96979797,$98989999,$9a9a9a9b,$9b9b9c9c,$9c9d9d9d
        dc.l $9d9e9e9e,$9e9e9f9f,$9f9f9f9f,$a0a0a0a0,$a0a0a0a0,$a0a0a0a0
        dc.l $a0a0a0a0,$a0a0a09f,$9f9f9f9f,$9f9e9e9e,$9e9e9d9d,$9d9d9c9c
        dc.l $9c9b9b9b,$9a9a9a99,$99989897,$97979696,$95959494,$93939291
        dc.l $9190908f,$8e8e8d8d,$8c8b8b8a,$89898887,$86868584,$84838281
        dc.l $80807f7e,$7d7c7c7b,$7a797877,$77767574,$73727170,$706f6e6d
        dc.l $6c6b6a69,$68676665,$64636262,$61605f5e,$5d5c5b5a,$59585756
        dc.l $55545352,$51504f4e,$4d4c4b4a,$49484746,$45444342,$41403f3e
        dc.l $3e3d3c3b,$3a393837,$36353433,$32313030,$2f2e2d2c,$2b2a2929
        dc.l $28272625,$24242322,$2120201f,$1e1d1d1c,$1b1a1a19,$18171716
        dc.l $15151413,$13121211,$10100f0f,$0e0d0d0c,$0c0b0b0a,$0a090909
        dc.l $08080707,$06060605,$05050404,$04030303,$03020202,$02020101
        dc.l $01010101,$00000000,$00000000,$00000000,$00000000,$00000001
        dc.l $01010101,$01020202,$02020303,$03030404,$04050505,$06060607
        dc.l $07080809,$09090a0a,$0b0b0c0c,$0d0d0e0f,$0f101011,$12121313
        dc.l $14151516,$17171819,$1a1a1b1c,$1c1d1e1f,$20202122,$23242425
        dc.l $26272829,$292a2b2c,$2d2e2f30,$30313233,$34353637,$38393a3b
        dc.l $3c3d3d3e,$3f404142,$43444546,$4748494a,$4b4c4d4e
end:

clist:
	dc.w	BPLCON0,$0200		; bitplanes off	
        dc.w	$0096,$0020	        ; disable sprite dma
	
        dc.w	$00e0,$0006
bp0:		
        dc.w	$00e2,$0f80
        dc.w	$0182,$0999
        dc.w	$008e,$3541
        dc.w	$0090,$2ec1
        dc.w	$0092,$0038
        dc.w	$0094,$00d0
        dc.w	$0108,$0018
        dc.w	$010a,$0018
        dc.w	$0102,$0000
        dc.w	$0104,%000000
        dc.w	$0e01,$fffe
        dc.w	BPLCON0,$1200
colors:
        blk.w	lines*6,0
        dc.w	$ffdf,$fffe		; wait for end of line 255
        dc.w    $0180,$0000
        dc.w	BPLCON0,$0200
        dc.w	$ffff,$fffe

colorData:
        INCBIN	"colorData.bin"
colorEnd: