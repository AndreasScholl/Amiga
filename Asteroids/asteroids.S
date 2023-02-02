*
* ASTEROIDS'92.
* just a vector game, no commercial purpose !
*

 org	$40000
 load	$40000

g:		
		move.l	#st,$80
		trap	#0

		move.l	$4,a6
		move.l	#lib,a1
		clr.l	d0
		jsr	-552(a6)
		move.l	d0,a4
		move.l	38(a4),$dff080
		clr.w	$dff088
		move.w	#$8020,$dff096
		illegal

st:
		move.w	#$2700,sr

		lea	$70000,a0
.cls:		clr.l	(a0)+
		cmp.l	#$7b000,a0
		bne.s	.cls

		bsr	game_init

		move.w	$dff01c,d0		;get intena
		or.w	#$8000,d0
		move.w	d0,intena
		move.w	#$7fff,$dff09a		;disable ints.
		move.w	#$7fff,$dff09c
		move.l	$6c.w,lev3		;save level 3
		move.l	#vblank,$6c.w		;set my level 3
		move.w	#$c020,$dff09a		;allow level 3
		move.w	#$2200,sr

 		move.l	#clist,$dff080
		clr.w	$dff088

		bsr.l	main

		move.w	#$7fff,$dff09a
		move.w	#$7fff,$dff09c
		move.l	lev3,$6c
		move.w	intena,$dff09a

		rte
;--------------------------------------------------------------
main:		
		cmp.b	#$ff,$dff006
		bne.s	main

		btst	#6,$bfe001
		bne.s	main
		rts
;--------------------------------------------------------------
vblank:		
		btst	#5,$dff01f		;vbl int.?
		beq.s	.nvbl
		move.w	#$0020,$dff096

		movem.l	d0-d7/a0-a6,-(a7)

		cmp.b	#$50,kcode
		bne.s	.ncol
		move.w	#$444,$dff180
.ncol:		bsr	getkey
		bsr	game
		move.w	#0,$dff180

		tst.l	enemy_con
		bne.s	.hmm
		bsr	game_init
.hmm:

		movem.l	(a7)+,d0-d7/a0-a6
		move.w	#$0020,$dff09c
.nvbl:		rte
;---------------------------------------------------
lev3:		dc.l	0
intena:		dc.w	0
;-----------------------------------		
lib:		dc.b	'graphics.library',0
 even
;---------------------------------------------
game:		
		bsr	clear			;clear screen

					;<enemys>
		lea	linetab(pc),a6		
		bsr	enemys_set
		clr.w	(a6)		
		bsr	objects_draw

		lea	linetab(pc),a6

		tst.b	ship_next
		bne.s	.nsdraw
		move.l	a6,-(a7)
		bsr	shipcoll		;collision
		move.l	(a7)+,a6
		bsr	ship_set
.nsdraw:	bsr	ship_explode
		bsr	shots_set
		clr.w	(a6)
		bsr	objects_draw

		cmp.b	#$45,kcode
		bne.s	.nrestart
		clr.b	kcode
		tst.b	ship_next
		beq.s	.nrestart
		sf	ship_next
		bsr	game_init
.nrestart:

		rts
**********************************************************************
*vector object_class                                                 *
*
		rsreset
obj_xc:		rs.w	1		;x-coordinate
obj_yc:		rs.w	1		;y-coordinate
obj_xfloat:	rs.w	1		;x-coordinate (floating)
obj_yfloat:	rs.w	1		;y-coordinate (floating)
obj_angle:	rs.w	1		;angle
obj_coords:	rs.l	1		;pointer on coord-table
obj_xvelo:	rs.w	1		:x velocity
obj_yvelo:	rs.w	1		:y velocity
obj_name:	rs.w	1		;name (identification)
obj_len:	rs.w	0
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
		lea	coord_tabs(pc),a1
		move.l	(a1,d5.w),obj_coords(a0)
		rts
;---------------------------------------------
obj_slowdown:
		tst.w	obj_xvelo(a0)
		beq.s	.xng
		bpl.s	.xvp2
		addq.w	#1,obj_xvelo(a0)
		bra.s	.xng
.xvp2:		subq.w	#1,obj_xvelo(a0)
.xng:
		tst.w	obj_yvelo(a0)
		beq.s	.yng
		bpl.s	.yvp2
		addq.w	#1,obj_yvelo(a0)
		bra.s	.yng
.yvp2:		subq.w	#1,obj_yvelo(a0)
.yng:		rts
;---------------------------------------------
obj_addangle:				;<increase angle>
		add.w	d1,obj_angle(a0)
		cmp.w	#360,obj_angle(a0)
		blt.s	.angleok
		sub.w	#360,obj_angle(a0)
.angleok:	rts
;---------------------------------------------
obj_subangle:				;<decrease angle>
		sub.w	d1,obj_angle(a0)
		bpl.s	.angleok
		add.w	#360,obj_angle(a0)
.angleok:	rts
;---------------------------------------------
obj_thrust:				;<accelerate object, value in d2>
		move.w	obj_angle(a0),d1
		sub.w	#90,d1
		bpl.s	.angleok
		add.w	#360,d1
.angleok:
		lsl.w	#2,d1
		lea	sctab(pc),a3

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
		
		move.w	obj_xfloat(a0),d0	;x floating
		add.w	obj_xvelo(a0),d0	;+ x velocity

		cmp.w	#[320+16]*128,d0	;x coord too high?
		bls.s	.nhx
		cmp.w	#[320+16+16]*128,d0
		bhi.s	.nhx
		sub.w	#[320+16+16]*128,d0
.nhx:		
		cmp.w	#-16*128,d0		;x coord too low?
		bhi.s	.nlx
		cmp.w	#[320+16+16]*128,d0
		bls.s	.nlx
		add.w	#[320+16+16]*128,d0
.nlx:

		move.w	d0,obj_xfloat(a0)	;store x floating
		lsr.w	#7,d0			;convert to integer
		move.w	d0,obj_xc(a0)		;x integer

		move.w	obj_yfloat(a0),d0	;y floating
		add.w	obj_yvelo(a0),d0	;+ y velocity

;		add.w	#128,d0

		cmp.w	#[256+16]*128,d0	;y coord too high?
		bls.s	.nhy
		cmp.w	#[256+16+16]*128,d0
		bhi.s	.nhy
		sub.w	#[256+16+16]*128,d0
.nhy:		
		cmp.w	#-16*128,d0		;y coord too low?
		bhi.s	.nly
		cmp.w	#[256+16+16]*128,d0
		bls.s	.nly
		add.w	#[256+16+16]*128,d0
.nly:
		move.w	d0,obj_yfloat(a0)	;store y floating
		lsr.w	#7,d0			;convert to integer
		move.w	d0,obj_yc(a0)		;y integer
		
		move.l	obj_coords(a0),a1	;pointer to coord tab
		move.l	a1,d0
		bne.s	.lineobj		;point or lines ?
		move.w	obj_xc(a0),d0
		move.w	obj_yc(a0),d1
		bsr	set_point
		rts
.lineobj:	
		move.w	obj_angle(a0),d0
		cmp.w	#$8000,d0		;rotate?
		beq.s	.norotobj
		lsl.w	#2,d0
		lea	sctab(pc),a3
		movem.w	(a3,d0.w),d4/d5		;sin,cos

		move.w	(a1)+,d7
		subq.w	#1,d7
.lines:		movem.w	(a1)+,d0-d3
		move.w	d7,-(a7)
		bsr	rotate
		add.w	obj_xc(a0),d0
		add.w	obj_xc(a0),d2
		add.w	obj_yc(a0),d1
		add.w	obj_yc(a0),d3
		bsr	set_line
		move.w	(a7)+,d7
		dbf	d7,.lines
		rts
.norotobj:				;<object without rotation>
		move.w	(a1)+,d7
		subq.w	#1,d7
.norotlines:	movem.w	(a1)+,d0-d3
		add.w	obj_xc(a0),d0
		add.w	obj_xc(a0),d2
		add.w	obj_yc(a0),d1
		add.w	obj_yc(a0),d3
		move.w	d7,-(a7)
		bsr	set_line
		move.w	(a7)+,d7
		dbf	d7,.norotlines
		rts
*                                                                    *
**********************************************************************
;---------------------------------------------
*object names
ship	=	0		;own spaceship
shot	=	1		;own shot
big	=	2		;big asteroid
medium	=	3		;medium asteroid
small	=	4		;small asteroid
;---------------------------------------------
coord_tabs:
		dc.l	ship_coords
		dc.l	0
		dc.l	astb_coords
		dc.l	astm_coords
		dc.l	asts_coords
		dc.l	0
;---------------------------------------------
shot_con:	dc.w	0
shot_times:	ds.w	16
shot_structs:	ds.b	obj_len*16
enemy_con:	dc.l	0
enemy_structs:	ds.b	obj_len*32
ship_struct:	ds.b	obj_len
ship_estruct:	ds.b	obj_len*$15
ship_next:	dc.b	0
ship_exploding:	dc.b	0
even
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
enemys_set:
		move.l	enemy_con(pc),d0
		lea	enemy_structs(pc),a0
		moveq	#31,d7
.setenemys:	btst	d7,d0
		beq.s	.nenemy
		movem.l	d0/d7,-(a7)
		bsr	obj_move
		movem.l	(a7)+,d0/d7
.nenemy:	lea	obj_len(a0),a0
		dbf	d7,.setenemys
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
;---------------------------------------------
enemy_init:				;<initialize a enemy (asteroid/ufo)>
		move.l	a0,-(a7)
		move.l	enemy_con(pc),d6
		lea	enemy_structs(pc),a0
		moveq	#31,d7
.findfree:	btst	d7,d6
		beq.s	.free
		lea	obj_len(a0),a0
		dbf	d7,.findfree
		bra.s	.nofree
.free:
		move.w	#$8000,d2
		bsr	obj_init
		bset	d7,d6
		move.l	d6,enemy_con

.nofree:	move.l	(a7)+,a0
		rts
;---------------------------------------------
shots_set:	
		move.w	shot_con(pc),d0
		lea	shot_structs(pc),a0
		lea	shot_times(pc),a1
		moveq	#15,d7
.setshots:	btst	d7,d0
		beq.s	.nshot
		subq.w	#1,(a1)			;shot duration
		bne.s	.flying
		bclr	d7,d0			;switch shot off
		bra.s	.nshot
.flying:
		movem.w	d0/d7,-(a7)
		move.l	a1,-(a7)
		bsr	obj_move
		bsr	shot_collision
		move.l	(a7)+,a1
		movem.w	(a7)+,d0/d7
		
		tst.w	d1			;collision?
		beq.s	.nocoll
		bclr	d7,d0			;switch shot off
.nocoll:

.nshot:		lea	obj_len(a0),a0
		addq.w	#2,a1
		dbf	d7,.setshots
		move.w	d0,shot_con
		rts
;---------------------------------------------
shot_collision:
		move.w	obj_xc(a0),d0
		move.w	obj_yc(a0),d1

		lea	enemy_structs(pc),a3
		move.l	enemy_con(pc),d7
		moveq	#31,d6
.shotcoll:	move.l	d7,a5
		btst	d6,d7
		beq.w	.nocoll

		move.w	obj_xc(a3),d2
		move.w	obj_yc(a3),d3
		move.w	d2,d4
		move.w	d3,d5

		move.w	obj_name(a3),d7
		lsl.w	#2,d7
		neg.w	d7
		add.w	#22,d7

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

		addq.w	#1,obj_name(a3)
		cmp.w	#small,obj_name(a3)
		ble.s	.nlast
		move.l	a5,d7
		bclr	d6,d7
		move.l	d7,enemy_con
		rts
.nlast:
		move.w	obj_name(a3),d0
		lsl.w	#2,d0
		lea	coord_tabs(pc),a4
		move.l	(a4,d0.w),obj_coords(a3)
		add.w	#32,obj_xvelo(a3)
		add.w	#32,obj_yvelo(a3)
		neg.w	obj_yvelo(a3)

		move.w	obj_xc(a3),d0
		move.w	obj_yc(a3),d1
		move.w	obj_xvelo(a3),d3
		neg.w	d3
		move.w	obj_yvelo(a3),d4
		neg.w	d4
		move.w	obj_name(a3),d5
		moveq	#0,d2
		bsr	enemy_init
		rts

.nocoll:	move.l	a5,d7
		lea	obj_len(a3),a3
		dbf	d6,.shotcoll
.colldone:	moveq	#0,d1
		rts
;---------------------------------------------
ship_explode:
		tst.b	ship_next
		beq.w	.noinit
		tst.b	ship_exploding
		bne.s	.noinit

		lea	ship_struct(pc),a0
		move.w	obj_xc(a0),d5
		move.w	obj_yc(a0),d6
		move.w	obj_xvelo(a0),d3
		move.w	obj_yvelo(a0),d4
		moveq	#0,d3
		moveq	#0,d4
		move.w	obj_angle(a0),a4

		lea	ship_estruct(pc),a0
		lea	ship_ptab(pc),a1
		lea	sctab(pc),a3

		move.w	(a1)+,d7
		subq.w	#1,d7
		move.w	#270,d2			;angle
.initpoints:	move.w	(a1)+,d0
		move.w	(a1)+,d1
		movem.l	d4-d7,-(a7)
		move.w	a4,d6
		lsl.w	#2,d6
		movem.w	(a3,d6.w),d4/d5
		bsr	point_rotate
		movem.l	(a7)+,d4-d7

		add.w	d5,d0
		add.w	d6,d1

		movem.l	d0-a3,-(a7)

		moveq	#shot,d5
		bsr	obj_init
		moveq	#50,d2
		bsr	obj_thrust
		movem.l	(a7)+,d0-a3

		add.w	#23,d2
		cmp.w	#360,d2
		blt.s	.hang
		sub.w	#360,d2
.hang:
		lea	obj_len(a0),a0
		dbf	d7,.initpoints

		st	ship_exploding
.noinit:

		tst.b	ship_exploding
		beq.s	.noexplosion

		lea	ship_estruct(pc),a0		
		move.w	ship_ptab(pc),d7
		subq.w	#1,d7
.setpoints:	
		tst.w	obj_xvelo(a0)
		bne.s	.set
		tst.w	obj_yvelo(a0)
		beq.s	.next
.set:
		bsr	obj_move
		bsr	obj_slowdown
.next:		
		lea	obj_len(a0),a0
		dbf	d7,.setpoints
.noexplosion:	rts
;---------------------------------------------
ship_set:				;<set ship, keyboard control>
		lea	ship_struct(pc),a0

		move.b	jkcode(pc),d0
		btst	#3,d0
		beq.s	.ntleft
		moveq	#4,d1
		bsr	obj_subangle
.ntleft:
		btst	#1,d0
		beq.s	.ntright
		moveq	#4,d1
		bsr	obj_addangle
.ntright:
		btst	#2,d0
		beq.s	.nthrust
		moveq	#8,d2
		bsr	obj_thrust
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
		lea	sctab(pc),a3

		move.w	#256,d3			;thrust value
		muls	2(a3,d2.w),d3		;xvelo=cos(angle)*value
		lsl.l	#1,d3
		swap	d3

		move.w	#256,d4
		muls	(a3,d2.w),d4		;yvelo=sin(angle)*value
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
game_init:				;<initialize game>
		bsr	shots_init
		bsr	ship_init
		clr.l	enemy_con
		sf	ship_exploding
		bsr	asteroids_init
		rts
;---------------------------------------------
asteroids_init:
		move.w	#60,d0			;x
		move.w	#28,d1			;y
		move.w	#0,d2			;angle
		move.w	#40,d3			;x velo
		move.w	#20,d4			;y velo
		moveq	#big,d5			;name
		bsr	enemy_init

		move.w	#280,d0			;x
		move.w	#128,d1			;y
		move.w	#-25,d3			;x velo
		move.w	#10,d4			;y velo
		moveq	#big,d5			;name
		bsr	enemy_init

		move.w	#145,d0			;x
		move.w	#13,d1			;y
		move.w	#-12,d3			;x velo
		move.w	#14,d4			;y velo
		moveq	#big,d5			;name
		bsr	enemy_init

		move.w	#14,d0			;x
		move.w	#942,d1			;y
		move.w	#32,d3			;x velo
		move.w	#5,d4			;y velo
		moveq	#big,d5			;name
		bsr	enemy_init
		rts
;---------------------------------------------
shots_init:				;<initialize shot status>
		clr.w	shot_con
		rts
;---------------------------------------------
ship_pcoords:				;<get point coords>
		lea	ship_struct(pc),a0
		move.w	#16,d0			;x
		move.w	#16,d1			;y
		move.w	#0,d2			;angle
		move.w	#0,d3			;x velo
		move.w	#0,d4			;y velo
		moveq	#ship,d5
		bsr	obj_init

		lea	linetab(pc),a6
		bsr	obj_move
		clr.w	(a6)
		bsr	objects_draw

		lea	ship_ptab,a1
		bsr	get_pcoords
		rts
;---------------------------------------------
get_pcoords:
		move.l	a1,a2
		clr.w	(a1)+

		moveq	#0,d1			;ycoord
.vert:		moveq	#0,d0			;xcoord
.horiz:		bsr	check_point
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
		mulu	#40,d1
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
		lea	$dff000,a6
		not.b	screen
		bne.s	.s0
		move.w	#0,bp0+2
		move.l	#$78000,screenloc
		bra.s	.s1
.s0:		move.w	#$8000,bp0+2
		move.l	#$70000,screenloc
.s1:
		bsr	bbusy
		move.l	screenloc,$54(a6)
		move.l	#-1,$44(a6)
		move.l	#0,$64(a6)
		move.l	#$01000000,$40(a6)
		move.w	#256*64+$14,$58(a6)
		rts
;---------------------------------------------
screen:		dc.w	0
screenloc:	dc.l	$70000
;---------------------------------------------
set_line:
		movem.w	d4-d5,-(a7)
onceag:		
		moveq	#0,d6
		tst.w	d1			;y1 < 0 ?
		bmi.s	.y11
		tst.w	d3			;y2 < 0 ?
		bmi.s	.y12
		move.w	#255,d6
		cmp.w	d6,d1			;y1 > 255 ?
		bgt.s	.y21
		cmp.w	d6,d3			;y2 > 255 ?
		bgt.s	.y22

		moveq	#0,d6
		tst.w	d0			;x1 < 0 ?
		bmi.s	.x11
		tst.w	d2			;x2 < 0 ?
		bmi.s	.x12
		move.w	#319,d6
		cmp.w	d6,d0			;x1 > 319 ?
		bgt.s	.x21
		cmp.w	d6,d2			;x2 > 319 ?
		bgt.s	.x22
		bra.s	drawline		
.y11:
		tst.w	d3			;y2 auch < 0 ?
		bmi.s	clpend			;dann gar nix
		bsr.s	clipy
		move.w	d4,d0			;neues x1
		moveq	#0,d1			;y1 = 0
		bra.s	onceag
.y12:		
		bsr.s	clipy
		move.w	d4,d2			;neues x2
		moveq	#0,d3			;y2 = 0
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
.l3:		moveq	#1,d7
		exg	d1,d0
		bra.s	.l4
.l2:		neg.w	d1
		cmp.w	d0,d1
		bge.s	.l5
		moveq	#$19,d7
		bra.s	.l4
.l5:		moveq	#$5,d7
		exg	d1,d0
		bra.s	.l4
.l1:		neg.w	d0
		tst.w	d1
		blt.s	.l6
		cmp.w	d0,d1
		bge.s	.l7
		moveq	#$15,d7
		bra.s	.l4
.l7:		moveq	#$9,d7
		exg	d1,d0
		bra.s	.l4
.l6:		neg.w	d1
		cmp.w	d0,d1
		bge.s	.l8
		moveq	#$1d,d7
		bra.s	.l4
.l8:		moveq	#$0d,d7
		exg	d1,d0
						;BltStart nach d6
.l4:		
		move.l	screenloc(pc),a4
		mulu	#$28,d3
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
		cmp.w	#320-1,d0
		bhi.s	.npoint
		cmp.w	#256-1,d1
		bhi.s	.npoint

		move.w	#-1,(a6)		;set flag for point (not line)
		mulu	#40,d1
		move.w	d0,d2
		eor.w	#$07,d2
		lsr.w	#3,d0
		add.l	d0,d1
		add.l	screenloc(pc),d1
		move.l	d1,2(a6)
		move.w	d2,6(a6)
		lea	16(a6),a6
.npoint:	rts
;-------------------------------------------------------
bbusy:		move.w	#$8400,$96(a6)
.bb:		btst	#6,$02(a6)
		bne.s	.bb
		move.w	#$0400,$96(a6)
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
		swap	d0			;new x

		muls	d4,d6			;x*sin
		move.w	d1,d7			;y
		muls	d5,d7			;*cos
		add.l	d7,d6			;x*sin - y*cos
		lsl.l	#1,d6
		swap	d6			;new y
		move.w	d6,d1

		move.w	d2,d6			;x
		muls	d5,d2			;*cos
		move.w	d3,d7			;y
		muls	d4,d7			;*sin
		sub.l	d7,d2			;x*cos - y*sin
		lsl.l	#1,d2
		swap	d2			;new x

		muls	d4,d6			;*sin
		move	d3,d7			;y
		muls	d5,d7			;*cos
		add.l	d7,d6			;x*sin - y*cos
		lsl.l	#1,d6
		swap	d6			;new y
		move.w	d6,d3
		rts
;-------------------------------------------------------
shipcoll:
		lea	$dff000,a6
		bsr	bbusy
		move.l	screenloc(pc),a0
		lea	ship_struct(pc),a1
		movem.w	obj_xc(a1),d0/d1
		subq.w	#2,d0
		cmp.w	#319,d0
		bhi.s	.nc
		subq.w	#2,d1
		cmp.w	#255,d1
		bhi.s	.nc
		moveq	#$0f,d3
		and.w	d0,d3
		lsr.w	#3,d0
		mulu	#40,d1
		add.w	d0,d1
		add.w	d1,a0

		move.l	a0,$4c(a6)
;		move.l	a0,$54(a6)
		move.l	#$04c00000,$40(a6)		;$5fc for or!
		move.l	#$f0000000,d4
		lsr.l	d3,d4
		move.l	d4,$44(a6)
		move.w	#$0024,$62(a6)
;		move.w	#$0024,$66(a6)
		move.w	#-1,$74(a6)
		move.w	#5*64+2,$58(a6)

		bsr	bbusy

		btst	#5,$02(a6)
		bne.w	.nc
		tst.b	ship_next
		bne.s	.nc
		st	ship_next
.nc:
		rts
;-------------------------------------------------------
objects_draw:
		lea	linetab(pc),a0

		lea	$dff000,a6
		bsr	bbusy
		move.w	#$28,$60(a6)
		move.w	#$28,$66(a6)
		move.l  #$ffff0000,$44(a6)
		move.w	#$8000,$74(a6)
		move.w	#-1,$72(a6)

.objects:	tst.w	(a0)
		beq.s	.end		
		bpl.s	.line			;point or line?
					;<draw point>
		move.l	2(a0),a4
		move.w	6(a0),d3
		bset	d3,(a4)
		lea	16(a0),a0
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

		bsr	bbusy
		move.l	a4,$48(a6)
		move.l	a4,$54(a6)
		move.w	d3,$52(a6)
		movem.w	d4/d7,$40(a6)
		movem.w	d1/a5,$62(a6)
		move.w	d5,$58(a6)		;zeinchen der linie
		bra.s	.objects		
	
.end:		rts
;----------------------------------------
getkey:					;<get rawkey routine>
		lea	$bfe000,a5
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
.nok1:		cmp.b	#$4d,d0			;$4d ?
		bne.s	.nok2
		bset	#0,d7
		bclr	#2,d7
.nok2:		cmp.b	#$32,d0			;$4e ?
		bne.s	.nok3
		bset	#1,d7
		bclr	#3,d7
.nok3:		cmp.b	#$31,d0			;$4f ?
		bne.s	.nok4
		bset	#3,d7
		bclr	#1,d7
.nok4:		bra.s	.norelease

.release:				;<key released!>
		bclr	#7,d0
		cmp.b	#$3a,d0			;return
		bne.s	.nojkr
		sf	jkbutt
.nojkr:		cmp.b	#$39,d0			;$4c ?
		bne.s	.nokr1
		bclr	#2,d7
.nokr1:		cmp.b	#$4d,d0			;$4d ?
		bne.s	.nokr2
		bclr	#0,d7
.nokr2:		cmp.b	#$32,d0			;$4e ?
		bne.s	.nokr3
		bclr	#1,d7
.nokr3:		cmp.b	#$31,d0			;$4f ?
		bne.s	.nokr4
		bclr	#3,d7
.nokr4:		
.norelease:	move.b	d7,jkcode

		bset	#6,$e01(a5) 
		move.w	#$80,d1		
.shake:		dbf	d1,.shake	 
		bclr	#6,$e01(a5)
		move.b	kcode(pc),d0
.nkpress:	rts
;-----------------------------------------
kcode:		dc.b	0
jkcode:		dc.b	0
jkbutt:		dc.b	0
		even
;-------------------------------------------------------
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
;-------------------------------------------------------
clist:		
;		dc.w	$0180,0
		dc.w	$0182,$fff
		dc.w	$0100,$1200
		dc.w	$0102,$0000
		dc.w	$0108,0
		dc.w	$010a,0
		dc.w	$008e,$2c81
		dc.w	$0090,$2ce1
		dc.w	$0092,$0038
		dc.w	$0094,$00d0
		dc.w	$104,0;%100100
		dc.w	$2c01,$fffe
		dc.w	$0e0,$0007
bp0:		dc.w	$0e2,$0000
		dc.l	-2
;--------------------------------------------
