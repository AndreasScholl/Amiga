		INCDIR      "include"
		INCLUDE     "hw.i"
		INCLUDE     "funcdef.i"
		INCLUDE     "exec/exec_lib.i"
		INCLUDE     "graphics/graphics_lib.i"
		INCLUDE     "hardware/cia.i"

src_adr			= $6e000		; scroll buffer source adress
src_line 		= $32			; source line width

screenHeight	= 128
; see postEffect - 1 uses the generated unrolled twist
TWIST_UNROLLED	= 1
; first buffer line that needs clearing every frame. the asteroids game
; draws into the top of the buffer now, so this has to stay at 0. if the
; game is ever removed again it can go back up to 30 (the scroll band
; starts at line 35 and the dots only ever fall downwards from there).
clearTop		= 0
li				= $2e			; screen line size in bytes

; --- where the game area starts on the raster -------------------------
; the logo bobs up and down, so its bottom edge is not fixed. logoEndWait
; is ((logoPos+8)>>4) + logoY - 16 + logo_area_height, and logoPos settles
; into 0..576, so the >>4 contributes at most 36. gameTop sits one raster
; line below the lowest the logo ever reaches.
;
; THIS HAS NO SLACK. If you change the logo bob (the asr.w #4 or the
; cmp.w #48 in updateLogoPos) recompute logoBobMax, or the copper will
; still be waiting on logoEndWait when it should already be starting the
; game area, and the whole lower half of the screen drops out for a frame.
logoBobMax		= 36			; max of (logoPos+8)>>4
logoBottom		= logoBobMax+logoY-16+logo_area_height	; $8d, lowest logo row
gameTop			= logoBottom+1	; $8e
gameShift		= $9c-gameTop	; 14 raster lines gained at the top

sc_offset		= 58+gameShift	; scroller dest y offset. pushed down in the
								; buffer by the same amount the window moved
								; up, so the scroll text stays put on screen
ho				= li*sc_offset	; dst height start offset
yTop			= sc_offset-23	; scroller top y pos (for copy and pixel effect)
sc_top			= yTop*li		;

ss		 		= $6e014		; source start of scoller turn
ds		 		= $14			; destination start	of scroller turn

; --- where the scroll text stops being drawn and turns into dots -------
; postEffect draws the scroller from dissolveByte rightwards, so the
; leftmost column it puts down is dissolveX. addPoints samples exactly
; that column every frame and spawns a dot for each lit pixel, which is
; what makes the letters appear to crumble there.
;   must be even (the block copy moves longs)
;   must be less than $14, where the twist columns take over
;   the visible screen starts at x 32, so below byte 4 the dissolve
;   happens off the left edge
; bigger value = shorter text, longer visible dot trail.
dissolveByte	= 14
dissolveX		= dissolveByte*8	; = 64 pixels

; --- dissolve point system -------------------------------------------
; a point stays alive until it leaves the play area, or until it is
; among the oldest when the pool overflows. numPoints therefore sets
; the length of the trail (there is no explicit lifetime counter any
; more - it cost ~30 cycles per point per frame and the pool was
; permanently saturated anyway, so it never actually expired).
; numPoints		= 160		; max points kept alive after an update pass
numPoints		= 128		; max points kept alive after an update pass
maxSpawn		= 8			; max points that can be spawned in one frame
pointsMax		= numPoints+maxSpawn

; --- point area definition
; game_height MUST stay <= screenHeight, otherwise y*li+x/8 runs past
; the end of the scroll buffer (the old value of 160 did exactly that)
game_width		= 352
game_height		= screenHeight

		section "code",data,chip
initScroller::
        moveq   #0,d1
        bsr.s   updateLogoPointers

		bsr		buildLogoColors
		bsr		introInit		; stash the finished colours, start from black

		lea		spoint(pc),a5
		jsr		setupStarfield	; starfield
		bsr		setupScroller
		bsr		initPoints
		jsr		initGameObjects		; asteroids share this part's bitplane

 		move.l	#clist,$dff080
		clr.w	$dff088
		rts
;-------
; --- intro build up ---------------------------------------------------
; everything below is measured in frames from the first frame of the part
; (50 frames == 1 second at PAL), so the whole sequence can be lined up
; against the music by editing these five numbers.
;
;   0                nothing but the starfield
;   introLogoStart   logo fades up out of black
;   introGameStart   first name starts zooming in, ship flies in after it
;   introBarStart    scroller bar fades up
;   introScrollStart scroll text starts moving in from the right
;
introLogoStart   = 100      ; logo begins to appear
introLogoLines   = 21       ; gradient lines stepped per frame. the fade
                            ; takes logo_area_height*15/this frames, so
                            ; 21 is about one second. lower = slower.
introGameStart   = 350      ; first name begins to appear
introBarStart    = 500      ; scroller bar begins to appear
introBarSpeed    = 4        ; frames per step, 15 steps -> 60 frames
introScrollStart = 600      ; scroll text begins to appear

stateStarted = 0
stateEnd     = 1
scrollerState:  dc.w    stateStarted
;-------
logoY			= $30       ; logo start y
logo_height      = 96       ; logo gfx height
logo_area_height = 73       ; logo visible (copperlist) height
logo_color_count = 10   ;14
; the bottom of the gradient never fades below this level (0..256), so the
; logo stays a faint silhouette rather than a hole that swallows the sprite
; stars behind it. this is a floor on the FADE LEVEL, not a colour added to
; the components - the result is a straight scale of the original colour,
; so hues survive instead of everything sliding towards neutral grey.
; 0 restores the old fade-to-black.
logo_minfade     = 32

; d1: offset in bytes
updateLogoPointers:
		move.l	#logo,d0
        add.l   d1,d0
		move.l	#(320/8)*logo_height,d1
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
        bsr     clearScroller		; starts the screen clear blit

		bsr		introUpdate			; build up sequencer

; --- the clear blit is now running. everything down to the bbusy inside
;     "scroll" is work that never touches the scroll buffer, so it runs
;     for free instead of the CPU spinning in bbusy.
;
;     NOTE: this assumes updateStars does not use the blitter itself.
;     if it does, move the "jsr updateStars" down below postEffect.
		; bsr		updateLogoColors		; super slow :(
		bsr		updateLogoPos
		jsr		updateStars
		; move.w	#$882,$180(a6)

		; --- debug key stuff for point movement
		bsr		getkey

		cmp.b	#$50,kcode
		bne.s	.nxd
		sub.l	#1<<9,accelX
.nxd:		
		cmp.b	#$51,kcode
		bne.s	.nxi
		add.l	#1<<9,accelX
.nxi:		
		cmp.b	#$52,kcode
		bne.s	.nyd
		sub.l	#1<<9,accelY
.nyd:		
		cmp.b	#$53,kcode
		bne.s	.nyi
		add.l	#1<<9,accelY
.nyi:	
		cmp.b	#$54,kcode
		bne.s	.nxToggle
		cmp.w	#3,noiseX
		bne.s	.nX1
		move.w	#7,noiseX
		bra.s	.nxToggle
.nX1
		cmp.w	#7,noiseX
		bne.s	.nX2
		move.w	#15,noiseX
		bra.s	.nxToggle
.nX2
		cmp.w	#15,noiseX
		bne.s	.nxToggle
		move.w	#3,noiseX
.nxToggle:		

; --- from here on we need the cleared buffer. "scroll" starts with a
;     bbusy, which is where the blitter is finally waited for - by now
;     it has had the whole block above to finish the clear.
        ; cmp.w   #stateEnd,scrollerState
        ; beq.s   .scrollerEnded
		lea		$dff000,a6			; updateStars/getkey may have trashed a6

		; --- scroll text. until its time comes none of this runs, so the
		;     source buffer stays empty and the text walks in from the right
		;     on its own the moment it starts.
		cmp.w	#introScrollStart,introTime
		blo.s	.noScroller
		bsr		scroll
		; move.w	#$424,$180(a6)
		bsr		postEffect

		lea		$dff000,a6
		; move.w	#$266,$180(a6)
		bsr		addPoints
		bsr		drawPoints
		; move.w	#$000,$180(a6)
.noScroller:

; --- asteroids last: objects_draw leaves BLTAFWM/BLTALWM at $ffff0000 and
;     puts the blitter in line mode, and clearScroller resets both at the
;     top of the next frame. it also has to come after addPoints, which
;     scans column 8 of the buffer and would otherwise spawn dots from the
;     vector graphics.

		; move.w	#$aaa,$dff180
		; --- asteroids. the first call spawns the first word, and ship_auto
		;     keeps the ship parked off screen until that word is complete.
		cmp.w	#introGameStart,introTime
		blo.s	.noGame
		jsr		updateGameObjects
		; move.w	#$000,$dff180

		lea		$dff000,a6
.noGame:
.scrollerEnded:
		clr.b	kcode
        rts
;-------
initPoints:
		clr.w	activeCount
		bsr		buildYTable
		rts
;-------
; y -> byte offset lookup. kills the mulu #li in the plot inner loop.
buildYTable:
		lea		yTable,a0
		moveq	#0,d0
		move.w	#screenHeight-1,d7
.loop:
		move.w	d0,(a0)+
		add.w	#li,d0
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
		move.l	screenlocScroller,screenloc	; asteroids module draws here too
		bsr		bbusy
		move.l	screenlocScroller,d0
		add.l	#clearTop*li,d0
		move.l	d0,$54(a6)
		move.l	#-1,$44(a6)
		move.l	#0,$64(a6)
		move.l	#$01000000,$40(a6)
		move.w	#((screenHeight-clearTop)<<6)+(li/2),$58(a6)
		rts
;---------------------------------------------
screenToggleScroller:		
		dc.w	0
screenlocScroller		
		dc.l	$70000
;-------
; move + plot every point.
;
; everything is 16.16 fixed point in longs, so the integer pixel
; position is a single "swap" instead of an lsr.w #7 (20 cycles each).
; the struct is 16 bytes and is loaded/stored with movem - 4 longs cost
; 44+40 cycles instead of ~132 for eleven move.w d16(An).
;
; the array is compacted in place while we walk it: survivors are written
; back at a4, dead points are simply not written and vanish. that keeps
; the array contiguous AND sorted oldest-first, which is what lets the
; overflow handling below just skip the front.
;
; registers:
;   a0 screen base   a1 y table   a2/a3 accel x/y   a4 write   a5 read
;   d5/d6 clip limits            d7 counter
drawPoints:
; --- accel from a time table (16.16 longs now, accelTable must be dc.l)
; 		move.b	accelDuration,d0
; 		sub.b	#1,d0
; 		move.b	d0,accelDuration
; 		tst.b	d0
; 		bne.s	.noNextAccel
; 		move.b	#80,accelDuration
; 		lea		accelTable,a0
; 		move.b	accelOffset,d0
; 		ext.w	d0
; 		move.l	(a0,d0.w),accelX
; 		move.l	4(a0,d0.w),accelY
; 		add.w	#8,d0
; 		and.w	#$3f,d0
; 		move.b	d0,accelOffset
; .noNextAccel

		move.w	activeCount,d7
		beq		.done

		lea		points,a4			; write (compaction) pointer
		move.l	a4,a5				; read pointer

		sub.w	#numPoints,d7		; more alive than we want to keep?
		ble.s	.noOverflow
		move.w	d7,d0				; -> retire that many of the oldest
		lsl.w	#4,d0				; * point_len
		add.w	d0,a5
		move.w	#numPoints,d7
		bra.s	.gotCount
.noOverflow:
		move.w	activeCount,d7
.gotCount:
		subq.w	#1,d7

		move.l	screenlocScroller,a0	; plot base
		lea		yTable,a1				; y -> y*li
		move.l	accelX,a2				; acceleration, 16.16
		move.l	accelY,a3
		move.l	#game_width<<16,d5		; clip limits
		move.l	#game_height<<16,d6
.loop:
		movem.l	(a5)+,d0-d3			; x, y, vx, vy
		add.l	d2,d0				; x += vx
		add.l	d3,d1				; y += vy
		cmp.l	d5,d0				; unsigned -> catches < 0 as well
		bhs.s	.kill
		cmp.l	d6,d1
		bhs.s	.kill
		add.l	a2,d2				; vx += ax
		add.l	a3,d3				; vy += ay
		movem.l	d0-d3,(a4)			; survivor -> keep it
		lea		point_len(a4),a4

		swap	d0					; d0.w = x in pixels
		swap	d1					; d1.w = y in pixels
		add.w	d1,d1
		move.w	(a1,d1.w),d3		; y * li
		move.w	d0,d2
		lsr.w	#3,d0				; x / 8
		eor.w	#7,d2				; bit number, msb = leftmost pixel
		add.w	d0,d3
		bset	d2,(a0,d3.w)
.kill:
		dbf		d7,.loop

		move.l	a4,d0				; survivors -> new active count
		sub.l	#points,d0
		lsr.l	#4,d0
		move.w	d0,activeCount
.done:
		rts

noiseX:
		dc.w	$7f
noiseY:
		dc.w	15
startAddX:
		dc.w	$60
startAddY:
		dc.w	8

; acceleration in 16.16 pixels/frame^2.
; 1<<9 is exactly the old "1" in 9.7 units (1/128 pixel per frame).
; later this can be fed from a time table without touching drawPoints.
accelX:
		dc.l	3<<9
accelY:
		dc.l	1<<9

accelDuration:
		dc.b	1
accelOffset:
		dc.b	0

accelTable:
		dc.b	-4,-4,2,2,3,3,4,4
		dc.b	2,4,-4,-3,4,-5,7,3
		even

;-------
addPoints:
		move.l	screenlocScroller,a1
		add.l	#sc_top+dissolveByte,a1	; the column the text stops at
		moveq	#yTop,d7			; first scroller line
		moveq	#6-1,d6				; how many lines dissolve
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
addPoint:				; add single point at screen line d7
		move.w	activeCount,d0
		cmp.w	#pointsMax,d0
		bhs.s	.full				; can't happen with maxSpawn headroom, but be safe
		move.w	d0,d1
		addq.w	#1,d0
		move.w	d0,activeCount
		lsl.w	#4,d1				; * point_len
		lea		points,a5
		add.w	d1,a5				; append at the end (= youngest)

		move.l	#(dissolveX+1)<<16,point_x(a5)	; start x, no fraction

		moveq	#0,d0				; start y = scroller line
		move.w	d7,d0
		swap	d0
		move.l	d0,point_y(a5)

		moveq	#0,d0				; x speed
		jsr		getRandomNumber
		and.w	noiseX,d0
		add.w	startAddX,d0
		neg.w	d0
		ext.l	d0
		lsl.l	#8,d0				; 9.7 -> 16.16 (<<9)
		add.l	d0,d0
		move.l	d0,point_xvelo(a5)

		moveq	#0,d0				; y speed
		jsr		getRandomNumber
		and.w	noiseY,d0
		add.w	startAddY,d0
		ext.l	d0
		lsl.l	#8,d0				; 9.7 -> 16.16 (<<9)
		add.l	d0,d0
		move.l	d0,point_yvelo(a5)
.full:
		moveq	#0,d0
		rts



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

; --- twist columns ---------------------------------------------------
; table2 further down stays the source of truth for the twist geometry.
; the unrolled block is produced from it by gentwist.py, which rewrites
; the code between the BEGIN/END GENERATED TWIST markers in this file.
; retune table2, re-run the generator, done.
;   TWIST_UNROLLED = 0 -> table driven loop, easy to poke at
;   TWIST_UNROLLED = 1 -> generated straight line code, ~2900 cycles faster
		IFEQ	TWIST_UNROLLED
		lea		table2,a2
		moveq	#((tabend2-table2)/12)-1,d7
		move.l	screenlocScroller,d6
copyloop2:
		move.l	(a2)+,a0
		move.w	(a2)+,d1
		move.l	(a2)+,a1
		add.l	d6,a1
		move.w	(a2)+,d2
; copyColumnShift inlined here - the bsr/rts pair cost 34 cycles
; per table entry, 26 entries per frame
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
		dbf		d7,copyloop2
		ELSE
; >>> BEGIN GENERATED TWIST
; Generated by gentwist.py from table2 - do not hand edit.
; Edit table2 and re-run the generator instead.
;   26 entries -> 12 (source, shift) groups
;   a0 = ss (source base), a1 = screen buffer (destination base)
		lea		ss,a0
		move.l	screenlocScroller,a1

; --- ss+4, shift 8, 6 entries
		move.w	ss+4-ss(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$3f00,d1
		or.w	d1,ds+ho-(li*2)+2(a1)
		move.w	d0,d1
		and.w	#$c000,d1
		or.w	d1,ds+ho-(li*3)+2(a1)
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*3)(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*4)(a1)
		move.w	d0,d1
		and.w	#$0060,d1
		or.w	d1,ds+ho-(li*5)(a1)
		and.w	#$0080,d0
		or.w	d0,ds+ho-(li*6)(a1)
		move.w	ss+4-ss+src_line*1(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$3f00,d1
		or.w	d1,ds+ho-(li*2)+2+li*1(a1)
		move.w	d0,d1
		and.w	#$c000,d1
		or.w	d1,ds+ho-(li*3)+2+li*1(a1)
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*3)+li*1(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*4)+li*1(a1)
		move.w	d0,d1
		and.w	#$0060,d1
		or.w	d1,ds+ho-(li*5)+li*1(a1)
		and.w	#$0080,d0
		or.w	d0,ds+ho-(li*6)+li*1(a1)
		move.w	ss+4-ss+src_line*2(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$3f00,d1
		or.w	d1,ds+ho-(li*2)+2+li*2(a1)
		move.w	d0,d1
		and.w	#$c000,d1
		or.w	d1,ds+ho-(li*3)+2+li*2(a1)
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*3)+li*2(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*4)+li*2(a1)
		move.w	d0,d1
		and.w	#$0060,d1
		or.w	d1,ds+ho-(li*5)+li*2(a1)
		and.w	#$0080,d0
		or.w	d0,ds+ho-(li*6)+li*2(a1)
		move.w	ss+4-ss+src_line*3(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$3f00,d1
		or.w	d1,ds+ho-(li*2)+2+li*3(a1)
		move.w	d0,d1
		and.w	#$c000,d1
		or.w	d1,ds+ho-(li*3)+2+li*3(a1)
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*3)+li*3(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*4)+li*3(a1)
		move.w	d0,d1
		and.w	#$0060,d1
		or.w	d1,ds+ho-(li*5)+li*3(a1)
		and.w	#$0080,d0
		or.w	d0,ds+ho-(li*6)+li*3(a1)
		move.w	ss+4-ss+src_line*4(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$3f00,d1
		or.w	d1,ds+ho-(li*2)+2+li*4(a1)
		move.w	d0,d1
		and.w	#$c000,d1
		or.w	d1,ds+ho-(li*3)+2+li*4(a1)
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*3)+li*4(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*4)+li*4(a1)
		move.w	d0,d1
		and.w	#$0060,d1
		or.w	d1,ds+ho-(li*5)+li*4(a1)
		and.w	#$0080,d0
		or.w	d0,ds+ho-(li*6)+li*4(a1)
		move.w	ss+4-ss+src_line*5(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$3f00,d1
		or.w	d1,ds+ho-(li*2)+2+li*5(a1)
		move.w	d0,d1
		and.w	#$c000,d1
		or.w	d1,ds+ho-(li*3)+2+li*5(a1)
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*3)+li*5(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*4)+li*5(a1)
		move.w	d0,d1
		and.w	#$0060,d1
		or.w	d1,ds+ho-(li*5)+li*5(a1)
		and.w	#$0080,d0
		or.w	d0,ds+ho-(li*6)+li*5(a1)

; --- ss+2, shift 8, 2 entries
		move.w	ss+2-ss(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*7)(a1)
		and.w	#$0002,d0
		or.w	d0,ds+ho-(li*13)(a1)
		move.w	ss+2-ss+src_line*1(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*7)+li*1(a1)
		and.w	#$0002,d0
		or.w	d0,ds+ho-(li*13)+li*1(a1)
		move.w	ss+2-ss+src_line*2(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*7)+li*2(a1)
		and.w	#$0002,d0
		or.w	d0,ds+ho-(li*13)+li*2(a1)
		move.w	ss+2-ss+src_line*3(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*7)+li*3(a1)
		and.w	#$0002,d0
		or.w	d0,ds+ho-(li*13)+li*3(a1)
		move.w	ss+2-ss+src_line*4(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*7)+li*4(a1)
		and.w	#$0002,d0
		or.w	d0,ds+ho-(li*13)+li*4(a1)
		move.w	ss+2-ss+src_line*5(a0),d0
		ror.w	#8,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*7)+li*5(a1)
		and.w	#$0002,d0
		or.w	d0,ds+ho-(li*13)+li*5(a1)

; --- ss+2, shift 9, 1 entry
		move.w	ss+2-ss(a0),d0
		rol.w	#7,d0
		and.w	#$0100,d0
		or.w	d0,ds+ho-(li*8)(a1)
		move.w	ss+2-ss+src_line*1(a0),d0
		rol.w	#7,d0
		and.w	#$0100,d0
		or.w	d0,ds+ho-(li*8)+li*1(a1)
		move.w	ss+2-ss+src_line*2(a0),d0
		rol.w	#7,d0
		and.w	#$0100,d0
		or.w	d0,ds+ho-(li*8)+li*2(a1)
		move.w	ss+2-ss+src_line*3(a0),d0
		rol.w	#7,d0
		and.w	#$0100,d0
		or.w	d0,ds+ho-(li*8)+li*3(a1)
		move.w	ss+2-ss+src_line*4(a0),d0
		rol.w	#7,d0
		and.w	#$0100,d0
		or.w	d0,ds+ho-(li*8)+li*4(a1)
		move.w	ss+2-ss+src_line*5(a0),d0
		rol.w	#7,d0
		and.w	#$0100,d0
		or.w	d0,ds+ho-(li*8)+li*5(a1)

; --- ss+2, shift 10, 2 entries
		move.w	ss+2-ss(a0),d0
		rol.w	#6,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*9)(a1)
		and.w	#$0001,d0
		or.w	d0,ds+ho-(li*13)(a1)
		move.w	ss+2-ss+src_line*1(a0),d0
		rol.w	#6,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*9)+li*1(a1)
		and.w	#$0001,d0
		or.w	d0,ds+ho-(li*13)+li*1(a1)
		move.w	ss+2-ss+src_line*2(a0),d0
		rol.w	#6,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*9)+li*2(a1)
		and.w	#$0001,d0
		or.w	d0,ds+ho-(li*13)+li*2(a1)
		move.w	ss+2-ss+src_line*3(a0),d0
		rol.w	#6,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*9)+li*3(a1)
		and.w	#$0001,d0
		or.w	d0,ds+ho-(li*13)+li*3(a1)
		move.w	ss+2-ss+src_line*4(a0),d0
		rol.w	#6,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*9)+li*4(a1)
		and.w	#$0001,d0
		or.w	d0,ds+ho-(li*13)+li*4(a1)
		move.w	ss+2-ss+src_line*5(a0),d0
		rol.w	#6,d0
		move.w	d0,d1
		and.w	#$0100,d1
		or.w	d1,ds+ho-(li*9)+li*5(a1)
		and.w	#$0001,d0
		or.w	d0,ds+ho-(li*13)+li*5(a1)

; --- ss+2, shift 12, 2 entries
		move.w	ss+2-ss(a0),d0
		rol.w	#4,d0
		move.w	d0,d1
		and.w	#$0080,d1
		or.w	d1,ds+ho-(li*10)(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*14)+2(a1)
		move.w	ss+2-ss+src_line*1(a0),d0
		rol.w	#4,d0
		move.w	d0,d1
		and.w	#$0080,d1
		or.w	d1,ds+ho-(li*10)+li*1(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*14)+2+li*1(a1)
		move.w	ss+2-ss+src_line*2(a0),d0
		rol.w	#4,d0
		move.w	d0,d1
		and.w	#$0080,d1
		or.w	d1,ds+ho-(li*10)+li*2(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*14)+2+li*2(a1)
		move.w	ss+2-ss+src_line*3(a0),d0
		rol.w	#4,d0
		move.w	d0,d1
		and.w	#$0080,d1
		or.w	d1,ds+ho-(li*10)+li*3(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*14)+2+li*3(a1)
		move.w	ss+2-ss+src_line*4(a0),d0
		rol.w	#4,d0
		move.w	d0,d1
		and.w	#$0080,d1
		or.w	d1,ds+ho-(li*10)+li*4(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*14)+2+li*4(a1)
		move.w	ss+2-ss+src_line*5(a0),d0
		rol.w	#4,d0
		move.w	d0,d1
		and.w	#$0080,d1
		or.w	d1,ds+ho-(li*10)+li*5(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*14)+2+li*5(a1)

; --- ss+2, shift 14, 2 entries
		move.w	ss+2-ss(a0),d0
		rol.w	#2,d0
		move.w	d0,d1
		and.w	#$0040,d1
		or.w	d1,ds+ho-(li*11)(a1)
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*15)+2(a1)
		move.w	ss+2-ss+src_line*1(a0),d0
		rol.w	#2,d0
		move.w	d0,d1
		and.w	#$0040,d1
		or.w	d1,ds+ho-(li*11)+li*1(a1)
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*15)+2+li*1(a1)
		move.w	ss+2-ss+src_line*2(a0),d0
		rol.w	#2,d0
		move.w	d0,d1
		and.w	#$0040,d1
		or.w	d1,ds+ho-(li*11)+li*2(a1)
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*15)+2+li*2(a1)
		move.w	ss+2-ss+src_line*3(a0),d0
		rol.w	#2,d0
		move.w	d0,d1
		and.w	#$0040,d1
		or.w	d1,ds+ho-(li*11)+li*3(a1)
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*15)+2+li*3(a1)
		move.w	ss+2-ss+src_line*4(a0),d0
		rol.w	#2,d0
		move.w	d0,d1
		and.w	#$0040,d1
		or.w	d1,ds+ho-(li*11)+li*4(a1)
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*15)+2+li*4(a1)
		move.w	ss+2-ss+src_line*5(a0),d0
		rol.w	#2,d0
		move.w	d0,d1
		and.w	#$0040,d1
		or.w	d1,ds+ho-(li*11)+li*5(a1)
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*15)+2+li*5(a1)

; --- ss+2, shift 0, 3 entries
		move.w	ss+2-ss(a0),d0
		move.w	d0,d1
		and.w	#$0020,d1
		or.w	d1,ds+ho-(li*11)(a1)
		move.w	d0,d1
		and.w	#$4000,d1
		or.w	d1,ds+ho-(li*17)+2(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*18)+2(a1)
		move.w	ss+2-ss+src_line*1(a0),d0
		move.w	d0,d1
		and.w	#$0020,d1
		or.w	d1,ds+ho-(li*11)+li*1(a1)
		move.w	d0,d1
		and.w	#$4000,d1
		or.w	d1,ds+ho-(li*17)+2+li*1(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*18)+2+li*1(a1)
		move.w	ss+2-ss+src_line*2(a0),d0
		move.w	d0,d1
		and.w	#$0020,d1
		or.w	d1,ds+ho-(li*11)+li*2(a1)
		move.w	d0,d1
		and.w	#$4000,d1
		or.w	d1,ds+ho-(li*17)+2+li*2(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*18)+2+li*2(a1)
		move.w	ss+2-ss+src_line*3(a0),d0
		move.w	d0,d1
		and.w	#$0020,d1
		or.w	d1,ds+ho-(li*11)+li*3(a1)
		move.w	d0,d1
		and.w	#$4000,d1
		or.w	d1,ds+ho-(li*17)+2+li*3(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*18)+2+li*3(a1)
		move.w	ss+2-ss+src_line*4(a0),d0
		move.w	d0,d1
		and.w	#$0020,d1
		or.w	d1,ds+ho-(li*11)+li*4(a1)
		move.w	d0,d1
		and.w	#$4000,d1
		or.w	d1,ds+ho-(li*17)+2+li*4(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*18)+2+li*4(a1)
		move.w	ss+2-ss+src_line*5(a0),d0
		move.w	d0,d1
		and.w	#$0020,d1
		or.w	d1,ds+ho-(li*11)+li*5(a1)
		move.w	d0,d1
		and.w	#$4000,d1
		or.w	d1,ds+ho-(li*17)+2+li*5(a1)
		and.w	#$8000,d0
		or.w	d0,ds+ho-(li*18)+2+li*5(a1)

; --- ss+2, shift 2, 1 entry
		move.w	ss+2-ss(a0),d0
		ror.w	#2,d0
		and.w	#$0010,d0
		or.w	d0,ds+ho-(li*12)(a1)
		move.w	ss+2-ss+src_line*1(a0),d0
		ror.w	#2,d0
		and.w	#$0010,d0
		or.w	d0,ds+ho-(li*12)+li*1(a1)
		move.w	ss+2-ss+src_line*2(a0),d0
		ror.w	#2,d0
		and.w	#$0010,d0
		or.w	d0,ds+ho-(li*12)+li*2(a1)
		move.w	ss+2-ss+src_line*3(a0),d0
		ror.w	#2,d0
		and.w	#$0010,d0
		or.w	d0,ds+ho-(li*12)+li*3(a1)
		move.w	ss+2-ss+src_line*4(a0),d0
		ror.w	#2,d0
		and.w	#$0010,d0
		or.w	d0,ds+ho-(li*12)+li*4(a1)
		move.w	ss+2-ss+src_line*5(a0),d0
		ror.w	#2,d0
		and.w	#$0010,d0
		or.w	d0,ds+ho-(li*12)+li*5(a1)

; --- ss+2, shift 4, 1 entry
		move.w	ss+2-ss(a0),d0
		ror.w	#4,d0
		and.w	#$0008,d0
		or.w	d0,ds+ho-(li*12)(a1)
		move.w	ss+2-ss+src_line*1(a0),d0
		ror.w	#4,d0
		and.w	#$0008,d0
		or.w	d0,ds+ho-(li*12)+li*1(a1)
		move.w	ss+2-ss+src_line*2(a0),d0
		ror.w	#4,d0
		and.w	#$0008,d0
		or.w	d0,ds+ho-(li*12)+li*2(a1)
		move.w	ss+2-ss+src_line*3(a0),d0
		ror.w	#4,d0
		and.w	#$0008,d0
		or.w	d0,ds+ho-(li*12)+li*3(a1)
		move.w	ss+2-ss+src_line*4(a0),d0
		ror.w	#4,d0
		and.w	#$0008,d0
		or.w	d0,ds+ho-(li*12)+li*4(a1)
		move.w	ss+2-ss+src_line*5(a0),d0
		ror.w	#4,d0
		and.w	#$0008,d0
		or.w	d0,ds+ho-(li*12)+li*5(a1)

; --- ss+2, shift 6, 1 entry
		move.w	ss+2-ss(a0),d0
		ror.w	#6,d0
		and.w	#$0004,d0
		or.w	d0,ds+ho-(li*12)(a1)
		move.w	ss+2-ss+src_line*1(a0),d0
		ror.w	#6,d0
		and.w	#$0004,d0
		or.w	d0,ds+ho-(li*12)+li*1(a1)
		move.w	ss+2-ss+src_line*2(a0),d0
		ror.w	#6,d0
		and.w	#$0004,d0
		or.w	d0,ds+ho-(li*12)+li*2(a1)
		move.w	ss+2-ss+src_line*3(a0),d0
		ror.w	#6,d0
		and.w	#$0004,d0
		or.w	d0,ds+ho-(li*12)+li*3(a1)
		move.w	ss+2-ss+src_line*4(a0),d0
		ror.w	#6,d0
		and.w	#$0004,d0
		or.w	d0,ds+ho-(li*12)+li*4(a1)
		move.w	ss+2-ss+src_line*5(a0),d0
		ror.w	#6,d0
		and.w	#$0004,d0
		or.w	d0,ds+ho-(li*12)+li*5(a1)

; --- ss+2, shift 15, 1 entry
		move.w	ss+2-ss(a0),d0
		rol.w	#1,d0
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*16)+2(a1)
		move.w	ss+2-ss+src_line*1(a0),d0
		rol.w	#1,d0
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*16)+2+li*1(a1)
		move.w	ss+2-ss+src_line*2(a0),d0
		rol.w	#1,d0
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*16)+2+li*2(a1)
		move.w	ss+2-ss+src_line*3(a0),d0
		rol.w	#1,d0
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*16)+2+li*3(a1)
		move.w	ss+2-ss+src_line*4(a0),d0
		rol.w	#1,d0
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*16)+2+li*4(a1)
		move.w	ss+2-ss+src_line*5(a0),d0
		rol.w	#1,d0
		and.w	#$4000,d0
		or.w	d0,ds+ho-(li*16)+2+li*5(a1)

; --- ss, shift 0, 4 entries
		move.w	ss-ss(a0),d0
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*19)(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*20)(a1)
		move.w	d0,d1
		and.w	#$01e0,d1
		or.w	d1,ds+ho-(li*21)(a1)
		and.w	#$fe00,d0
		or.w	d0,ds+ho-(li*22)(a1)
		move.w	ss-ss+src_line*1(a0),d0
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*19)+li*1(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*20)+li*1(a1)
		move.w	d0,d1
		and.w	#$01e0,d1
		or.w	d1,ds+ho-(li*21)+li*1(a1)
		and.w	#$fe00,d0
		or.w	d0,ds+ho-(li*22)+li*1(a1)
		move.w	ss-ss+src_line*2(a0),d0
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*19)+li*2(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*20)+li*2(a1)
		move.w	d0,d1
		and.w	#$01e0,d1
		or.w	d1,ds+ho-(li*21)+li*2(a1)
		and.w	#$fe00,d0
		or.w	d0,ds+ho-(li*22)+li*2(a1)
		move.w	ss-ss+src_line*3(a0),d0
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*19)+li*3(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*20)+li*3(a1)
		move.w	d0,d1
		and.w	#$01e0,d1
		or.w	d1,ds+ho-(li*21)+li*3(a1)
		and.w	#$fe00,d0
		or.w	d0,ds+ho-(li*22)+li*3(a1)
		move.w	ss-ss+src_line*4(a0),d0
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*19)+li*4(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*20)+li*4(a1)
		move.w	d0,d1
		and.w	#$01e0,d1
		or.w	d1,ds+ho-(li*21)+li*4(a1)
		and.w	#$fe00,d0
		or.w	d0,ds+ho-(li*22)+li*4(a1)
		move.w	ss-ss+src_line*5(a0),d0
		move.w	d0,d1
		and.w	#$0003,d1
		or.w	d1,ds+ho-(li*19)+li*5(a1)
		move.w	d0,d1
		and.w	#$001c,d1
		or.w	d1,ds+ho-(li*20)+li*5(a1)
		move.w	d0,d1
		and.w	#$01e0,d1
		or.w	d1,ds+ho-(li*21)+li*5(a1)
		and.w	#$fe00,d0
		or.w	d0,ds+ho-(li*22)+li*5(a1)
; <<< END GENERATED TWIST
		ENDC

;		rts
; copy rest of scroller (for now with processor)

; leftblock_words = 10
; 		lea		src_adr,a0
; 		lea 	$70000,a1
; the left block runs from dissolveByte up to byte $14, where the twist
; column table takes over, so its width follows the dissolve position
leftblock_words = ($14-dissolveByte)/2
 		lea		src_adr+dissolveByte,a0
 		;  lea 	$70000+8,a1							; dst
		move.l	screenlocScroller,a1
		add.l 	#sc_top+dissolveByte,a1				; dest
		move.l	#src_line-(leftblock_words*2),d4	; src modulo
		move.l	#li-(leftblock_words*2),d5			; dst modulo
		moveq	#7-1,d6			; height
lineloop:
			REPT	leftblock_words/2	; both ends are even, so move longs
			move.l	(a0)+,(a1)+
			ENDR
			IFNE	leftblock_words&1	; ... plus a word if the count is odd
			move.w	(a0)+,(a1)+
			ENDC
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
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
			move.b	(a0)+,(a1)+
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
		clr.w	(a4)	                ; restart
		; subq.w	#1,(a4)                 ; stay on end of text
        ; cmp.w   #stateStarted,scrollerState
        ; bne.s   .noStateChange
        ; move.w   #stateEnd,scrollerState
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
point_x:		rs.l	1		; x position, 16.16 fixed point
point_y:		rs.l	1		; y position, 16.16 fixed point
point_xvelo:	rs.l	1		; x velocity in pixels/frame, 16.16
point_yvelo:	rs.l	1		; y velocity in pixels/frame, 16.16
point_len:		rs.b	0		; = 16 bytes -> movem friendly, lsl #4 to index

		even
points:		ds.b	point_len*pointsMax
activeCount:
		dc.w	0

		even
yTable:		ds.w	screenHeight	; y -> y*li, built once by buildYTable

; setPointScroller was inlined into drawPoints - the bsr/rts pair alone
; was 34 cycles per point, and the mulu #li another ~50.

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

			move.w	#logo_area_height-1,d5
			bra		.skipWait				; first entry has no wait
.loop:
			move.w	d4,(a1)+				; copper wait
			move.w	#$fffe,(a1)+			;
			add.w	#$0100,d4
.skipWait:			
			move.w	(a2)+,d2				; color add value
			move.w	(a3)+,d7				; fade level
;			move.w	#256,d7

			; never let the ramp reach zero. scaling the whole colour keeps
			; its hue, where adding a flat value to r, g and b would drag
			; every colour towards grey.
			cmp.w	#logo_minfade,d7
			bge.s	.fadeOk
			move.w	#logo_minfade,d7
.fadeOk:

			lea		logoColorsOrig,a0
			move.w	#logo_color_count-1,d3
.colorLoop:
			move.w	(a0)+,(a1)+				; color reg
			move.w	(a0)+,d0
            
            move.w  d2,d6                   ; save coloradd
            move.w  d0,d1
            and.w   #$00f,d1
            move.w  d6,d2
            and.w   #$00f,d2
            add.w   d2,d1
            cmp.w   #$00f,d1
            ble.s   .noHiB
            move.w  #$00f,d1
.noHiB:
            and.w   #$ff0,d0
            or.w    d1,d0

            move.w  d0,d1
            and.w   #$0f0,d1
            move.w  d6,d2
            and.w   #$0f0,d2
            add.w   d2,d1
            cmp.w   #$0f0,d1
            ble.s   .noHiG
            move.w  #$0f0,d1
.noHiG:
            and.w   #$f0f,d0
            or.w    d1,d0

            move.w  d0,d1
            and.w   #$f00,d1
            move.w  d6,d2
            and.w   #$f00,d2
            add.w   d2,d1
            cmp.w   #$f00,d1
            ble.s   .noHiR
            move.w  #$f00,d1
.noHiR:
            and.w   #$0ff,d0
            or.w    d1,d0

            move.w  d6,d2                   ; retore coloradd

;			or.w	d2,d0                   ; color blend add

			bsr		colorFade
;            move.w  d2,d6

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
			dc.w	$9
			dc.w	$9
			dc.w	$8
			dc.w	$8
			dc.w	$7
			dc.w	$7
			dc.w	$6
			dc.w	$6
			dc.w	$5	    ; 20
			dc.w	$5
			dc.w	$4
			dc.w	$4
			dc.w	$3
			dc.w	$3
			dc.w	$2
			dc.w	$2
			dc.w	$1
			dc.w	$1
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
			dc.w	$101
			dc.w	$101
			dc.w	$202
			dc.w	$202
			dc.w	$303
			dc.w	$303
			dc.w	$404
			dc.w	$404
			dc.w	$505	    ; 50
			dc.w	$505
			dc.w	$606
			dc.w	$606
			dc.w	$707
			dc.w	$707
			dc.w	$808
			dc.w	$808
			dc.w	$909
			dc.w	$909
			dc.w	$a0a	    ; 60
			dc.w	$a0a
			dc.w	$b0b
			dc.w	$b0b
			dc.w	$c0c
			dc.w	$c0c
			dc.w	$d0d
			dc.w	$d0d
			dc.w	$e0e
			dc.w	$e0e
			dc.w	$f0f    ; 70
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
			add.w	#logoY-16,d0
			move.b	d0,logoStartWait
			add.w	#logo_area_height,d0
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
            cmp.w   #logo_area_height-5,logoFadeLine
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
			jsr		nextDemoPart
            ; jsr     initGame
            ; move.l  #updateGamePart,d0
            ; move.l  d0,updateFunction
.noPartSwitch:
            rts
;---------------------------------------------
; INTRO BUILD UP
;---------------------------------------------
; buildLogoColors has already produced the finished gradient by the time
; introInit runs, so the cheapest way to fade the logo up is to keep that
; result as the target, blank the live copperlist copy, and walk it back
; up one nibble at a time. Same trick for the bar. Nothing here does a
; multiply, and only a slice of the gradient is touched each frame.
;---------------------------------------------
introInit:
			; snapshot once only. initScroller runs again if the part is
			; restarted, and a second pass would capture the blanked copies
			; as the targets and nothing would ever fade up.
			tst.b	introTaken
			bne		introRestart
			st		introTaken

			clr.w	introTime
			clr.w	introLogoLine
			clr.w	introLogoPass
			clr.w	introBarTick
			sf		introLogoDone
			sf		introBarDone

			; --- stash the finished gradient. only the colour VALUES are
			;     read; the copper waits and the register numbers in between
			;     stay exactly where they are.
			lea		logoColors+2,a0			; first colour value
			lea		logoColorsTarget,a1
			move.w	#logo_area_height-1,d1
.line:
			move.l	a0,a2
			moveq	#logo_color_count-1,d0
.col:
			move.w	(a2),(a1)+
			lea		4(a2),a2
			dbf		d0,.col
			lea		(2*2)+(logo_color_count*2*2)(a0),a0
			dbf		d1,.line

			; --- same for the scroller bar
			lea		clist,a0
			lea		barcolorOffsets,a1
			lea		barColorsTarget,a2
			moveq	#19-1,d0
.bar:
			move.w	(a1)+,d1
			move.w	(a0,d1.w),(a2)+
			dbf		d0,.bar

introRestart:
			bsr		blankLogo
			clr.w	introTime
			clr.w	introLogoLine
			clr.w	introLogoPass
			clr.w	introBarTick
			sf		introLogoDone
			sf		introBarDone
			sf		introLogoShown
			bsr		blankBar
			bsr		introHideLogo
			rts

;---------------------------------------------
; A black logo is still a logo as far as the blitter... sorry, as far as
; the display hardware is concerned: the bitplanes are fetched, the pixels
; are drawn in colour 0, and playfield priority puts them in front of the
; sprites. So the starfield disappears behind a black rectangle. Hiding it
; properly means making the logo region look exactly like the empty single
; plane region above it - one plane, pointed at the blank line, modulo
; -40 so it repeats.
;---------------------------------------------
introHideLogo:
			move.w	#$1200,logoPlanes		; one plane instead of five
			move.w	#$ffd8,logoPlaneMod
			move.w	#$0006,logobp0h			; ... aimed at the empty line
			move.w	#$e000-li,logobp0l
			rts

introShowLogo:
			move.w	#$4200,logoPlanes
			move.w	#$0000,logoPlaneMod
			moveq	#0,d1
			bsr		updateLogoPointers		; bp0..bp3 back onto the logo
			rts

;---------------------------------------------
blankLogo:
			lea		logoColors+2,a0
			move.w	#logo_area_height-1,d1
.line:
			move.l	a0,a2
			moveq	#logo_color_count-1,d0
.col:
			clr.w	(a2)
			lea		4(a2),a2
			dbf		d0,.col
			lea		(2*2)+(logo_color_count*2*2)(a0),a0
			dbf		d1,.line
			rts

;---------------------------------------------
blankBar:
			lea		clist,a0
			lea		barcolorOffsets,a1
			moveq	#19-1,d0
.b:
			move.w	(a1)+,d1
			clr.w	(a0,d1.w)
			dbf		d0,.b
			rts

;---------------------------------------------
introUpdate:
			move.w	introTime,d0
			cmp.w	#$7000,d0			; stop counting, never wrap
			bhs.s	.noTick
			addq.w	#1,d0
			move.w	d0,introTime
.noTick:
			cmp.w	#introLogoStart,d0
			blo.s	.noLogo
			tst.b	introLogoShown		; switch the bitplanes on once, at the
			bne.s	.logoOn				; moment the fade starts
			st		introLogoShown
			bsr		introShowLogo
.logoOn:
			bsr		fadeInLogo
.noLogo:
			cmp.w	#introBarStart,d0
			bhs.s	.barTime
			bsr		blankBar			; held black until its cue, every frame,
			bra.s	.noBar				; so nothing can sneak it back in early
.barTime:
			subq.w	#1,introBarTick
			bpl.s	.noBar
			move.w	#introBarSpeed-1,introBarTick
			bsr		fadeInBar
.noBar:
			rts

;---------------------------------------------
; step one nibble of each colour towards its target
; d0 = current, d1 = target -> d6 = stepped. uses d2/d3.
;---------------------------------------------
colorFadeIn:
			moveq	#0,d6
			move.w	d0,d2
			and.w	#$00f,d2
			move.w	d1,d3
			and.w	#$00f,d3
			cmp.w	d3,d2
			bge.s	.bOk
			addq.w	#1,d2
.bOk:
			or.w	d2,d6

			move.w	d0,d2
			and.w	#$0f0,d2
			move.w	d1,d3
			and.w	#$0f0,d3
			cmp.w	d3,d2
			bge.s	.gOk
			add.w	#$010,d2
.gOk:
			or.w	d2,d6

			move.w	d0,d2
			and.w	#$f00,d2
			move.w	d1,d3
			and.w	#$f00,d3
			cmp.w	d3,d2
			bge.s	.rOk
			add.w	#$100,d2
.rOk:
			or.w	d2,d6
			rts

;---------------------------------------------
fadeInLogo:
			tst.b	introLogoDone
			bne.s	.done
			moveq	#introLogoLines-1,d4
.lineFader:
			move.w	introLogoLine,d0

			lea		logoColors+2,a0		; live line, 44 bytes per line
			move.w	d0,d1
			mulu.w	#(2*2)+(logo_color_count*2*2),d1
			add.l	d1,a0

			lea		logoColorsTarget,a1	; target line, packed
			move.w	d0,d1
			mulu.w	#logo_color_count*2,d1
			add.l	d1,a1

			moveq	#logo_color_count-1,d7
.fadeColor:
			move.w	(a0),d0
			move.w	(a1)+,d1
			bsr		colorFadeIn
			move.w	d6,(a0)
			lea		4(a0),a0
			dbf		d7,.fadeColor

			addq.w	#1,introLogoLine
			cmp.w	#logo_area_height,introLogoLine
			blo.s	.noWrap
			clr.w	introLogoLine
			addq.w	#1,introLogoPass
			cmp.w	#15,introLogoPass	; $0 to $f is fifteen steps
			blo.s	.noWrap
			st		introLogoDone
			bra.s	.done
.noWrap:
			dbf		d4,.lineFader
.done:
			rts

;---------------------------------------------
fadeInBar:
			tst.b	introBarDone
			bne.s	.done
			lea		clist,a0
			lea		barcolorOffsets,a1
			lea		barColorsTarget,a2
			moveq	#19-1,d7
			moveq	#1,d5				; assume everything has arrived
.barfade:
			move.w	(a1)+,d4			; offset of the colour word in clist
			move.w	(a0,d4.w),d0
			move.w	(a2)+,d1
			cmp.w	d0,d1
			beq.s	.arrived
			moveq	#0,d5
.arrived:
			bsr		colorFadeIn
			move.w	d6,(a0,d4.w)
			dbf		d7,.barfade
			tst.w	d5
			beq.s	.done
			st		introBarDone
.done:
			rts

introTime:		dc.w	0		; frames since the part started
introLogoLine:	dc.w	0
introLogoPass:	dc.w	0
introBarTick:	dc.w	0
introLogoDone:	dc.b	0
introBarDone:	dc.b	0
introLogoShown:	dc.b	0		; logo bitplanes switched on yet?
introTaken:		dc.b	0		; colour snapshot already taken?
				even
logoColorsTarget:
				blk.w	logo_color_count*logo_area_height,0
barColorsTarget:
				blk.w	19,0

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
		dc.b	"zeronine says hi to --- major rom --- mark ii ---- equalizer --- exciter --- "
		dc.b	"dandee -- lord performer --- exolon --- phil --- doctor soft --- kongoman and all the others ........ ",0
		even

logo:
        INCBIN	"thrust-quadlite_16.bin"

logoColorsOrig:
	; dc.w	$0182,$0463
	; dc.w	$0184,$0777
	; dc.w	$0186,$0999
	; dc.w	$0188,$0bbb
	; dc.w	$018a,$02a4
	; dc.w	$018c,$0050
	; dc.w	$018e,$0130
	; dc.w	$0190,$0ddd
	; dc.w	$0192,$06e6
	; dc.w	$0194,$0fff

	dc.w	$0182,$0463
	dc.w	$0184,$0777
	dc.w	$0186,$0999
	dc.w	$0188,$0130
	dc.w	$018a,$0050
	dc.w	$018c,$0bbb
	dc.w	$018e,$02a4
	dc.w	$0190,$0ddd
	dc.w	$0192,$06e6
	dc.w	$0194,$0fff



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
		dc.w	BPLCON0
logoPlanes:
		dc.w	$4200				; 5 bitplanes. patched to $1200 while the logo
								; is still hidden, so the region behaves exactly
								; like the empty single plane above it and the
								; sprites keep showing through
		dc.w	$0108
logoPlaneMod:
		dc.w	$0000				; even bitplanes modulo, patched to $ffd8

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
		blk.w	((2+(logo_color_count*2))*logo_area_height)-2,0

logoEndWait:
 		dc.w	$6c01,$fffe			; logo end wait
		dc.w	BPLCON0,$0200		; bitplanes off

;		dc.w	$0180,$0fff	   ; debug test
		dc.w	$0182,$0000	   ; black plane
		dc.w	BPLCON0,$1200		; one plane
		dc.w	$00e0,$0006
		dc.w	$00e2,$e000-li
		dc.w	$0108,$ffd8			; even bitplanes modulo

		dc.w	(gameTop<<8)+1,$fffe	; start of "game" area
		dc.w	BPLCON0,$1200	; 1 bitplanes on
		dc.w	$00e0,$0007		; bitplane 0 
bp0:	dc.w	$00e2,$0000		;

		dc.w	$0108,$0000		; even bitplanes modulo
		dc.w	$010a,$0000		; odd bitplanes modulo

		dc.w	$0092,$0028
		dc.w	$0094,$00d8

		dc.w	$0182,$0eee	; game area before scroller color

		dc.w	$bf01,$fffe
		dc.w	$0182,$0777
		dc.w	$c101,$fffe
		dc.w	$0182,$0888
		dc.w	$c201,$fffe
		dc.w	$0182,$0999
		dc.w	$c301,$fffe
		dc.w	$0182,$0aaa

		dc.w	$c401,$fffe
		dc.w	$0182,$0bbb
		dc.w	$0100,$2600			; 2 bitplanes on	(dual playfield mode)
		dc.w	$00e4,$0007			; bitplane 01
		; dc.w	$00e6,(li*75)-2		; + lines offset to adjust shadow pos
		; shifted with the rest of the buffer content so the shadow keeps
		; reading the same lines it used to
		dc.w	$00e6,(li*(51+gameShift))-2	; + lines offset to adjust shadow pos
		dc.w	$0192,$0000	   ; shadow color

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