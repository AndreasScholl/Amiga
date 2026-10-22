		INCDIR      "include"
		INCLUDE     "hw.i"
		INCLUDE     "switches.i"		; (the ending's switches)
		INCLUDE     "funcdef.i"
		INCLUDE     "exec/exec_lib.i"
		INCLUDE     "graphics/graphics_lib.i"
		INCLUDE     "hardware/cia.i"

; src_adr: the scroll buffer's source, in chip memory the system gives us
; (section "screens" at the end; it was the fixed address $6e000, never
; reserved - the loaded program could lie there and get drawn over)
src_line 		= $32			; source line width

; screenHeight (the buffer height) is defined further down, after gameTop

; --- raster time meter. 1 paints the background in a colour per stage of
;     updateScroller, so the CPU time each part takes shows up as a band:
;       red    logo, stars, intro       yellow  scroll text + twist
;       green  dots (add + draw)        blue    asteroids
;     where the blue ends is where the frame's work is done. if a band ever
;     wraps round past the bottom of the screen the frame overran. the
;     copper sets colour 0 itself in the bar, so bands are hidden there.
rasterDebug		= 0

RASTER	macro
		IFNE	rasterDebug
		move.w	#\1,$dff180
		ENDC
		endm
; see postEffect - 1 uses the generated unrolled twist
TWIST_UNROLLED	= 1
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

; the buffer runs from gameTop down to the bottom of the display window
; (the PAL default DIWSTOP $2cc1 -> last visible line $12b), so the dots
; can fall all the way to the bottom edge. was 128, which ended 30 lines
; short at raster $10e - every dot vanished on that one invisible line.
screenBottom	= $12c
screenHeight	= screenBottom-gameTop	; 158

; --- the full screen game buffer -------------------------------------
; the asteroids game uses the whole screen, so its bitplane starts at the
; top of the display window (fullTop) and the scroller's buffer is just
; the lower part of it: scroller line 0 is game line topLines. everything
; the scroller does stays relative to screenlocScroller as before.
;   bufA/bufB         game line 0, raster fullTop
;   + topLines*li     scroller line 0 = screenlocScroller, raster gameTop
;   + screenHeight*li ember plane, see emberTop
; above gameTop the game line is shown as plane 4 - over the logo, and
; with three empty planes in front of it above and below the logo - see
; gamebpl4 in clist. one pointer at the top of the frame is all it takes,
; the plane runs on by itself down to gameTop.
; the game plane runs from the top of the display window by itself, so the
; window has to start exactly at fullTop - clist sets DIWSTRT/DIWSTOP
; rather than living with whatever the system left there. $20 is as high
; as the logo ever bobs (logoY-16), so the logo is never cut off.
fullTop			= $20			; first line of the display window
topLines		= gameTop-fullTop	; 110
gameLines		= topLines+screenHeight	; 268, asteroids.s game_height
; bufA/bufB: section "screens" at the end (were the fixed $70000/$78000)
scrollA			= bufA+topLines*li
scrollB			= bufB+topLines*li
; planes 2 of the empty rows above and below the logo read this. it can not
; just repeat the blank line like planes 1 and 3 do, because plane 2 shares
; its modulo with the game plane 4.
zeroLines		= 40			; >= the most rows above (36) or below (32) the logo

sc_offset		= 58+gameShift	; scroller dest y offset. pushed down in the
								; buffer by the same amount the window moved
								; up, so the scroll text stays put on screen
ho				= li*sc_offset	; dst height start offset
yTop			= sc_offset-23	; scroller top y pos (for copy and pixel effect)
sc_top			= yTop*li		;

ss		 		= src_adr+$14	; source start of scoller turn
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
; the dots stay white while they fall through the scroller's copper bar
; and only start to glow out (orange, red, gone) once they are below it,
; in front of the black background. below the bar each one stays white
; for a random wait and then glows out, the later ones faster, so some go
; out right under the bar and some are still bright near the bottom:
;   group 0  wait  0..15, glow 32 frames
;   group 1  wait 12..27, glow 16 frames
;   group 2  wait 20..35, glow 16 frames
;   group 3  wait 28..43, glow  8 frames
;
; the life counter rides in the low byte of the y velocity: accelY only
; ever changes bit 9 and up, so that byte is never touched by the
; physics, and the struct stays 16 bytes for movem. the extra bits it
; adds to y are < 1/256 pixel a frame. it counts down once a frame:
;   $80+n .. $80     white hot, plane 1 only (sign bit set after the subq
;                    -> the fast path)
;   $7f              still above emberTop? then back to $80+wait with a
;                    fresh group and wait from y's fraction bits, and stay
;                    white. the pick made on the last frame inside the bar
;                    is the one that counts. the group's glow step - 1
;                    goes into vx's low byte, which is just as free.
;   $7f ..           glowing out, emberFrames life steps of 1, 2 or 4 a
;                    frame on the ember plane: orange (plane 1 + ember),
;                    red (ember only), then red flickering at random
;   emberDead        burnt out, dropped
; a dot spawns with pointHot, a little less than the fastest one needs to
; reach emberTop (~90 frames), so the hold above only runs for the last
; few frames before the bar's end.
;
; gravity makes every dot about equally fast at the bar's end (~0.85
; pixels a frame), with ~55 frames left to screenBottom. wait + glow has
; to stay inside that so a dot CAN fall to the bottom but never arrives
; there still glowing: the groups above top out at 47, 43, 51 and 51.
;
; pool size = spawn rate * lifetime. if dense text spawns faster than
; that, the pool overflows and the oldest points get dropped in mid air.
; to stop that, addPoints only spawns while it has credit: spawnRate
; credits come in per frame, each point costs one. spawnRate is worked
; out from the LONGEST life, so the pool can never overflow and every dot
; burns out on its own.
;   spawnCap:  credit saved up in gaps (spaces) - limits the burst at
;              the start of the next letter.
; numPoints raises density, at ~150 cycles each.
; numPoints		= 160		; max points kept alive after an update pass
numPoints		= 120		; max points kept alive after an update pass (128
							; before: a few less for the EQUALIZER frames)
maxSpawn		= 8			; max points that can be spawned in one frame
pointsMax		= numPoints+maxSpawn
emberOrange		= 10		; life steps orange (white plane + ember plane)
emberRed		= 11		; life steps red (ember plane only)
emberFlicker	= 11		; life steps flickering red, the last glimmer
emberFrames		= emberOrange+emberRed+emberFlicker	; must stay 32, see
								; .emberStep / .emberBase in drawPoints
emberDead		= $7f-emberFrames			; life byte at which a dot is gone
emberWait		= $0f		; mask, random part of the wait below the bar
pointHot		= 80		; < frames the fastest dot needs to reach emberTop
pointLife		= 103+52	; longest life: the slowest dot leaves the bar
								; after ~103, wait + glow is at most 52
; dots are kept in x minus borderX. the visible screen starts at x 32, so
; a dot that flies off to the left dies right at the border instead of
; flying on unseen and curving back in further down, still white.
borderX			= 32
spawnRate		= (numPoints<<8)/pointLife	; credits per frame, 8.8
spawnCap		= 4<<8		; must stay <= maxSpawn<<8
dissolveLines	= 6			; scroller lines that dissolve
; the logo destruction sequence blows the scroll text apart into the same
; dots, far more of them at once than the dissolve ever spawns. the array
; has room for them, and drawPoints keeps pointKeep alive instead of
; numPoints while it runs (~150 cycles a dot - there are no letters on
; screen then to pay for it).
pointsPool		= 320		; storage
seqKeep			= 150		; dots kept alive during the sequence

; --- point area definition
; game_height MUST stay <= screenHeight, otherwise y*li+x/8 runs past
; the end of the scroll buffer (the old value of 160 did exactly that)
game_width		= 352
game_height		= screenHeight

; --- ember plane: the glowing-out colours of the dots ------------------
; one extra plane, shown as dual playfield plane 3 (PF1's second plane)
; from raster $ef down - the first black line under the scroller bar,
; where the copper switches it on (gamePlanes3). it is only stored from
; emberTop down, placed right behind plane 1 in the same buffer, so ONE
; clear blit wipes both. ember line y lives at plane1 base + emberOffset
; + y*li.
;   scrollA/scrollB       plane 1, screenHeight lines
;   + screenHeight*li     ember plane, lines emberTop..screenHeight-1
; drawPoints never lets a dot glow above emberTop, otherwise its ember
; pixel would land in the bottom of plane 1.
emberTop		= $ef-gameTop					; the $ef01 wait in clist
; the plane is shown from the bar's top on too (gamePlanes2 at $c4, three
; planes there): the dots still glow only below emberTop, but the
; fireworks burn out in colour in the bar as well (drawLattice)
emberFwTop		= $c4-gameTop					; the $c401 wait (gamePlanes2)
emberOffset		= (screenHeight-emberFwTop)*li
clearLines		= screenHeight+screenHeight-emberFwTop	; 262

		section "code",data,chip
initScroller::
		sf		sfxWide					; (music.s) one channel for the effects
	ifne	tvLate
		sf		flickPhase
	endc
		bsr		patchScreens		; the screens' addresses into the copper
		bsr		buildLogoPadded
		move.l	#zeroArea,d0		; plane 2 above and below the logo
		move.w	d0,topZero2l
		move.w	d0,midZero2l
		swap	d0
		move.w	d0,topZero2h
		move.w	d0,midZero2h

        moveq   #0,d1
        bsr.s   updateLogoPointers

		bsr		buildLogoColors	; lays out the waits and colour registers
		bsr		introInit		; start from black
		bsr		logoPaletteInit

		lea		spoint,a5		; (too far for (pc) now)
		jsr		setupStarfield	; starfield
		lea		spoint,a5
		jsr		warpInit		; ... and its way into depth later (warp.i)
		bsr		setupScroller
		bsr		initPoints
		bsr		buildDebrisRnd
		jsr		initGameObjects		; asteroids share this part's bitplane
		bsr		glitchScan			; the bar's BPLCON1 moves, for the tears
		bsr		tvScan				; ... and tvList's colour moves

 		move.l	#clist,$dff080
		clr.w	$dff088
		rts
; the screens are where the system put them (section "screens"): their
; addresses into the copper lists, once
patchScreens:
		move.l	#src_adr-li,d0		; the blank line above and below the logo
		move.w	d0,blankTop1l
		move.w	d0,blankTop3l
		move.w	d0,blankMid1l
		move.w	d0,blankMid3l
		swap	d0
		move.w	d0,blankTop1h
		move.w	d0,blankTop3h
		move.w	d0,blankMid1h
		move.w	d0,blankMid3h
		move.l	#scrollA+(li*(51+gameShift))-2,d0	; the bar's shadow plane
		move.w	d0,shadowL
		move.w	d0,tvShadowL
		swap	d0
		move.w	d0,shadowH
		move.w	d0,tvShadowH
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
introLogoStart   = 128      ; logo begins to appear
introGameStart   = 500      ; first name begins to appear
introBarStart    = 2000      ; scroller bar begins to appear
introScrollStart = 2500      ; scroll text begins to appear

introLogoLines   = 15       ; gradient lines stepped per frame. the fade
                            ; takes logo_area_height*15/this frames, so
                            ; 21 is about one second. lower = slower.
introBarSpeed    = 4        ; frames per step, 15 steps -> 60 frames
scrollFullTime   = 400      ; frames from introScrollStart until the text runs
                            ; across the whole bar - the logo destruction
                            ; waits for that (scrollReady)

stateStarted = 0
stateEnd     = 1
scrollerState:  dc.w    stateStarted
;-------
logoY			= $30       ; logo start y
logo_height      = 96       ; logo gfx height (3 bitplanes)
logo_area_height = 73       ; logo visible (copperlist) height
logo_color_count = 10   ;14 ; colour MOVEs per gradient line. only 1..7 are
                            ; used by the 3 plane logo, logoColorEngine
                            ; relies on the 44 byte line stride
; the bottom of the gradient never fades below this level (0..256), so the
; logo stays a faint silhouette rather than a hole that swallows the sprite
; stars behind it. this is a floor on the FADE LEVEL, not a colour added to
; the components - the result is a straight scale of the original colour,
; so hues survive instead of everything sliding towards neutral grey.
; 0 restores the old fade-to-black.
logo_minfade     = 32

;-------
; the logo is 40 bytes a line, the game plane it now shares the logo rows
; with is 46 (li). the two share a modulo, so the logo is copied once into
; li wide lines: DDFSTRT $28 fetches 4 bytes earlier than the $38 the logo
; was drawn for, so it goes in at +4, and the 6 spare bytes of each line
; are behind the left and right border.
buildLogoPadded:
		lea		logo,a0
		lea		logoPadded+4,a1
		move.w	#3*logo_height-1,d7		; all three planes, line by line
.line:
		REPT	320/8/4
		move.l	(a0)+,(a1)+
		ENDR
		lea		li-(320/8)(a1),a1
		dbf		d7,.line
		rts
;-------
; d1: offset in bytes
updateLogoPointers:
		move.l	#logoPadded,d0
        add.l   d1,d0
		move.l	#li*logo_height,d1
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
        rts
;-------
updateScroller::
		lea		$dff000,a6
		RASTER	$0f00
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
		bsr		logoPaletteKick
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
		; --- F10: straight to the logo destruction. the word on screen is
		;     still finished off, then the ship gets bored (see seq_pilot).
		;     the scroll text is started right away if it is not running yet.
		cmp.b	#$59,kcode
		bne.s	.noSeqKey
		st		namesLooped
		cmp.w	#introScrollStart,introTime
		bhs.s	.noSeqKey
		move.w	#introScrollStart,introTime
.noSeqKey:
		tst.b	seq_hits			; the sequence is blowing the text apart:
		beq.s	.normalKeep			; keep the dots that makes alive
		move.w	#seqKeep,pointKeep
.normalKeep:

		; --- the asteroids game thinks here, while the clear blit is still
		;     running - it does not touch the buffer, only builds its draw
		;     table. drawGameObjects at the end draws it.
		cmp.w	#introGameStart,introTime
		blo.s	.noGameLogic
		RASTER	$000f
		jsr		updateGameLogic
.noGameLogic:

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
		tst.b	scrollerOff			; switched off for the TV effect: only
		bne.s	.scrollOff			; the dots and blasts still in the air
		RASTER	$0ff0
		bsr		scroll
		bsr		postEffect
		tst.b	seq_hits			; the ship's shots against the text as it
		beq.s	.noShots			; is shown this frame (textShot)
		jsr		seqShotScan
.noShots:

		lea		$dff000,a6
		RASTER	$00f0
		tst.w	scrollStepped		; the text only crumbles when it moves: a
		beq.s	.scrollOn			; hanging scroller would put the same
		bsr		addPoints			; column into dots again and again, and
		bra.s	.scrollOn			; the pool would drop the glowing ones
.scrollOff:
		jsr		bbusy				; scroll did this wait for the clear
.scrollOn:
		bsr		drawPoints
		bsr		drawBlastFx			; after addPoints, which would make dots
									; out of their pixels
		tst.b	seqTextOff
		beq.s	.noScroller
		bsr		checkScrollGone
.noScroller:
		bsr		glitchFrame			; the scroller breaking, tearing
		bsr		barFlicker			; the bar going wrong (the Defender ending)
		bsr		tvUpdate			; the TV switch off, once it is started
		bsr		inkFade				; ... and the text's colours, once it is all shot
		lea		$dff000,a6

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
		RASTER	$000f
		jsr		drawGameObjects

		lea		$dff000,a6
.noGame:
	ifne	elite3
		; --- the Elite ending's flight is worked out ahead in what is left
		;     of the frame (morph.i), last of all
		jsr		morphSimRun
	endc
.scrollerEnded:
		RASTER	$0000
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
		move.l	#bufA,d0					; show A ...
		move.l	#scrollB,screenlocScroller	; ... draw B
		move.l	#bufB,screenloc				; asteroids draw on the whole screen
		bra.s	.s1
.s0:
		move.l	#bufB,d0
		move.l	#scrollA,screenlocScroller
		move.l	#bufA,screenloc
.s1:	; the shown buffer into the copper (high words too: the buffers are
		; where the system put them)
		move.w	d0,gamebpl4
		swap	d0
		move.w	d0,gamebpl4h
		swap	d0
		add.l	#topLines*li,d0				; the scroller part
		move.w	d0,bp0+2
		swap	d0
		move.w	d0,gamebp0h
		swap	d0
		add.l	#screenHeight*li,d0			; the ember plane
		move.w	d0,emberbpl
		swap	d0
		move.w	d0,emberbplh
	ifne	elite3
		tst.b	s3Cop				; (the Elite ending: its own copper list,
		beq.s	.ne					; stars3d.i)
		jsr		s3Flip
.ne:
	endc
		bsr		bbusy
		move.l	screenloc,$54(a6)			; game top, scroller, ember
		move.l	#-1,$44(a6)
		move.l	#0,$64(a6)
		move.l	#$01000000,$40(a6)
		move.w	#((topLines+clearLines)<<6)+(li/2),$58(a6)
		rts
;---------------------------------------------
screenToggleScroller:
		dc.w	0
screenlocScroller
		dc.l	scrollA
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

		sub.w	pointKeep,d7		; more alive than we want to keep?
		ble.s	.noOverflow
		add.w	d7,pointsRetired	; (testing)
		move.w	d7,d0				; -> retire that many of the oldest
		lsl.w	#4,d0				; * point_len
		add.w	d0,a5
		move.w	pointKeep,d7
		bra.s	.gotCount
.noOverflow:
		move.w	activeCount,d7
.gotCount:
		subq.w	#1,d7

		move.l	screenlocScroller,a0	; plot base. x is stored minus borderX,
		addq.l	#borderX/8,a0			; the byte offset comes back in here
		lea		emberOffset(a0),a6		; ember plane, same y*li+x/8 offsets
		lea		yTable,a1				; y -> y*li
		move.l	accelX,a2				; acceleration, 16.16
		move.l	accelY,a3
		move.l	#(game_width-borderX)<<16,d5	; clip limits
		move.l	#game_height<<16,d6
.loop:
		movem.l	(a5)+,d0-d3			; x, y, vx, vy (+ life in vy's low byte)
		add.l	d2,d0				; x += vx
		add.l	d3,d1				; y += vy
		cmp.l	d5,d0				; unsigned -> catches < 0 as well, i.e.
		bhs.s	.clipped			; behind the left border
		cmp.l	d6,d1
		bhs.s	.clippedY
		add.l	a2,d2				; vx += ax
		add.l	a3,d3				; vy += ay, low byte of ay is 0
		subq.b	#1,d3				; one frame of life gone
		bpl.s	.ember				; dropped below $80 -> glowing out
.hot:
		movem.l	d0-d3,(a4)			; survivor -> keep it
		lea		point_len(a4),a4

		swap	d0					; d0.w = x in pixels
		swap	d1					; d1.w = y in pixels
		add.w	d1,d1
		move.w	(a1,d1.w),d3		; y * li
		move.w	d0,d2
		lsr.w	#3,d0				; x / 8
		not.w	d2					; bit number, msb = leftmost pixel. bset
									; only looks at the low 3 bits and ~x&7 is
									; 7-(x&7), so this is eor #7 for 4 cycles less
		add.w	d0,d3
		bset	d2,(a0,d3.w)		; white hot: plane 1 only
.kill:
		dbf		d7,.loop
		bra.s	.loopDone

; --- glowing out. same plot, but the life byte in d3 picks the planes, so
;     the pixel offset goes to d4 instead
.ember:
		cmp.l	#emberTop<<16,d1
		bhs.s	.glow
		; still over the bar: stay white. the glow group and the wait below
		; the bar are picked afresh from y's fraction bits every frame - the
		; pick made on the last frame inside the bar is the one that sticks
		moveq	#3,d4
		and.b	d1,d4				; group 0..3
		move.b	.emberStep(pc,d4.w),d2	; glow step-1 rides in vx's low byte
		move.b	d1,d3
		lsr.b	#2,d3
		and.b	#emberWait,d3		; 0..15
		add.b	.emberBase(pc,d4.w),d3
		btst	#8,d2					; a piece of a blast (addDebris): a
		beq.s	.dissolveDot			; quarter of the wait, it is meant to be
		lsr.b	#2,d3					; seen glowing as it falls
.dissolveDot:
		or.b	#$80,d3				; sign bit: white again
		bra.s	.hot
.emberStep:	dc.b	0,1,1,3			; glow takes 32, 16, 16, 8 frames ...
.emberBase:	dc.b	0,12,20,28		; ... after waiting this + 0..15 frames
.glow:
		sub.b	d2,d3				; late ones burn out faster
		cmp.b	#emberDead,d3
		bls.s	.burnt				; burnt out: not written back
		movem.l	d0-d3,(a4)
		lea		point_len(a4),a4

		swap	d0
		swap	d1
		add.w	d1,d1
		move.w	(a1,d1.w),d4
		move.w	d0,d2
		lsr.w	#3,d0
		not.w	d2
		add.w	d0,d4
		cmp.b	#emberDead+emberFlicker+emberRed,d3
		bhi.s	.orange
		cmp.b	#emberDead+emberFlicker,d3
		bhi.s	.red
		btst	#31,d1				; last glimmer: on y's half pixel bit,
		beq.s	.kill				; so about every other frame, at random
.red:
		bset	d2,(a6,d4.w)		; ember plane only
		dbf		d7,.loop
		bra.s	.loopDone
.orange:
		bset	d2,(a6,d4.w)		; ember + plane 1
		bset	d2,(a0,d4.w)
		dbf		d7,.loop
		bra.s	.loopDone
; (testing: what becomes of the blast's dots - vx bit 8, see addDebris)
.clippedY:
		btst	#8,d2
		beq.s	.kill
		btst	#7,d3
		beq.s	.kill
		addq.w	#1,whiteLostY
.clipped:
		btst	#8,d2
		beq.s	.kill
		btst	#7,d3				; gone off the edge while still white?
		beq.s	.kill
		addq.w	#1,whiteLost
		bra.s	.kill
.burnt:
		btst	#8,d2
		beq.s	.kill
		addq.w	#1,burntOut
		bra.s	.kill
.loopDone:

		move.l	a4,d0				; survivors -> new active count
		sub.l	#points,d0
		lsr.l	#4,d0
		move.w	d0,activeCount
.done:
		lea		$dff000,a6			; borrowed for the ember plane
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
accelX::						; (set every frame by updateStars, asteroids.s)
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
; spawns are rationed by spawnCredit (see the point system notes at the
; top). the scan starts on a different line every frame and wraps round,
; otherwise when credit is short the top lit line would always win and
; the crumbs would only ever come off the tops of the letters.
;   d4 scratch  d5 credit (8.8)  d6 counter  d7 screen line  a1 pixel
;   (addPoint/getRandomNumber only touch d0/d1/a5)
addPoints:
		move.w	spawnCredit,d5
		add.w	#spawnRate,d5
		cmp.w	#spawnCap,d5
		bls.s	.capOk
		move.w	#spawnCap,d5
.capOk:
		move.w	spawnLine,d4		; this frame's start line
		addq.w	#1,spawnLine
		cmp.w	#dissolveLines,spawnLine
		blo.s	.lineOk
		clr.w	spawnLine
.lineOk:
		cmp.w	#$100,d5			; not even one credit -> no scan
		blo.s	.out

		move.l	screenlocScroller,a1
		add.l	#sc_top+dissolveByte,a1	; the column the text stops at
		moveq	#yTop,d7
		add.w	d4,d7				; start line
		add.w	d4,d4
		lea		yTable,a0
		add.w	(a0,d4.w),a1
		moveq	#dissolveLines-1,d6
.addloop:
		tst.b	(a1)				; leftmost pixel is bit 7, the sign bit
		bpl.s	.nopixel
		bsr		addPoint
		sub.w	#$100,d5
		cmp.w	#$100,d5
		blo.s	.out				; budget spent for this frame
.nopixel
		lea		li(a1),a1			; next line
		addq.w	#1,d7
		cmp.w	#yTop+dissolveLines,d7
		bne.s	.noWrap
		moveq	#yTop,d7			; wrap back to the first line
		lea		-dissolveLines*li(a1),a1
.noWrap:
		dbf		d6,.addloop
.out:
		move.w	d5,spawnCredit
		rts

spawnCredit:
		dc.w	0
spawnLine:
		dc.w	0
;-------
addPoint:				; add single point at screen line d7
		move.w	activeCount,d0
		cmp.w	#pointsPool,d0
		bhs.s	.full				; can't happen with maxSpawn headroom, but be safe
		move.w	d0,d1
		addq.w	#1,d0
		move.w	d0,activeCount
		lsl.w	#4,d1				; * point_len
		lea		points,a5
		add.w	d1,a5				; append at the end (= youngest)

		move.l	#(dissolveX+1-borderX)<<16,point_x(a5)	; start x, no fraction

		moveq	#0,d0				; start y = scroller line
		move.w	d7,d0
		swap	d0
		move.l	d0,point_y(a5)

		; x speed. one random number feeds both speeds: x takes the low word, y the
		; high one. getRandomNumber is ~170 cycles, and up to 6 points spawn
		; per frame.
		jsr		getRandomNumber
		move.w	d0,d1
		and.w	noiseX,d1
		add.w	startAddX,d1
		neg.w	d1
		ext.l	d1
		lsl.l	#8,d1				; 9.7 -> 16.16 (<<9)
		add.l	d1,d1
		move.l	d1,point_xvelo(a5)

		swap	d0					; y speed
		and.w	noiseY,d0
		add.w	startAddY,d0
		ext.l	d0
		lsl.l	#8,d0				; 9.7 -> 16.16 (<<9)
		add.l	d0,d0
		move.b	#$80+pointHot,d0	; life rides in the (empty) low byte
		move.l	d0,point_yvelo(a5)
.full:
		moveq	#0,d0
		rts



;---------------------------------------------
; LOGO DESTRUCTION - the scroller's side
;---------------------------------------------
; seq_pilot in asteroids.s flies the ship, this side does what happens to
; the text:
;   scrollerHit  a shot meets the text: a blast (blastFx), the text under
;                it is gone, its pixels fall as glowing dots
;   feedNext     after the first attack the text is no longer the scroll
;                text: a pause, glitch salad, then the captain message
;   stutterStep  meanwhile the scroller hangs now and then, and tears
;                (glitchFrame), so it runs slower
;   findText     where the letters are, for the ship to aim at
;
; shots_set hands every shot in the air to scrollerHit. that runs in
; updateGameLogic while the screen clear blit is still going, so it tests
; the SOURCE text, which nothing writes to at that point. on screen the
; text is in three parts (see postEffect):
;   x 112..159  left block: source bytes dissolveByte..$13 as they are, on
;               scroller lines yTop.. (the top of the bar)
;   x 160..183  the twist: source bytes $14..$19, turned over from line
;               yTop down to the right block
;   x 184..     right block: source byte = screen byte + 3, on scroller
;               lines rightLine.. (the bottom of the bar)
;
; frame time: only one shot a frame may hit (seqHitDone - the others are
; tested again a frame later, still inside the text), seqKeep caps the
; dots alive and sparkMax the sparks.
hitTwistX		= $14*8			; 160
hitRightX		= $17*8			; 184, where the right block starts on screen
hitRows			= 7				; text lines per block (postEffect copies 7)
hitSlack		= 3				; lines above and below a block that count too
rightLine		= sc_offset-1	; scroller line of the right block's top row
debrisHot		= 8				; frames to the first ember check (drawPoints
								; .ember) - short, so the wait below the bar
								; is picked as the dot leaves it
debrisMaxDy		= 4				; lines from the centre that count, at most
debrisMinVy		= $1800		; at least 3/32 of a pixel down a frame
debrisDrop		= $5000		; + 5/16 pixel a frame downwards: out of the bar
								; quickly, to glow below it
debrisRndCount	= 64			; random longs in debrisRndTab, power of two
; the x speed of a dot starts at the scroll's own -1 pixel a frame, so the
; pieces carry on the way the text was going, and the wind (accelX) bends
; them back round like the dissolve dots.

;---------------------------------------------
; THE BLASTS
;---------------------------------------------
; no two alike. every blast rolls
;   a power      1 small, 2 medium, 3 big - sparks, their speed, the size
;                of the shock ring, how much text goes (blastPowers)
;   a ring       round, flat, tall, a star of rays, or a double ring
;   a direction  the sparks go all round, on along the shot, back at the
;                shooter, or up as a fountain
sparkMax		= 40			; sparks in the air at once
spark_len		= 18			; x, y, vx, vy (16.16), life
sparkLife		= 8				; frames, + 0..7
sparkDrag		= 3				; v -= v >> this, every frame
sparkFall		= $600			; a little gravity, 16.16
ringMax			= 6				; shock rings at once
ring_len		= 8				; x.w, line, age, kind, step, frames, pad
ringKinds		= 5
bigOdds			= 40			; out of 256: a big one ...
medOdds			= 120			; ... a medium one, the rest small
bigSparkRoom	= 20			; a big one only while this many sparks are
								; still free (else it is medium)

; per power: sparks, speed (1/16 px a frame, + 0..31), ring step (radius
; per frame), ring frames, shock rings (one after the other, 2 frames
; apart), every n-th pixel of the letter a dot, dot x speed per pixel from
; the middle, dot y speed per line
				rsreset
bp_sparks:		rs.b	1
bp_speed:		rs.b	1
bp_ringStep:	rs.b	1
bp_ringFrames:	rs.b	1
bp_rings:		rs.b	1
bp_every:		rs.b	1
bp_spreadX:		rs.w	1
bp_spreadY:		rs.w	1
bp_len:			rs.b	0
blastPowers:
		dc.b	10,24,3,5,1,3
		dc.w	$2000,$1800
		dc.b	16,32,4,6,2,3
		dc.w	$2800,$2000
		dc.b	24,44,5,6,3,2
		dc.w	$3800,$2800

;---------------------------------------------
; THE SHOTS AGAINST THE TEXT
;---------------------------------------------
; seqShotScan (asteroids.s) hands every shot in the air to textShot, every
; frame, right after postEffect has put this frame's text into the buffer -
; so the test is against the pixels exactly as they are shown. the white
; text is plane 1, and plane 1 is shown 1:1 in the bar: the line doubling
; and the 16 pixel shift there are on the shadow plane only (BPL2MOD and
; the playfield 2 delay). the ship and its shots are drawn into the same
; plane, so where a shot meets a letter in the buffer, it meets it on
; screen.
; the whole way the shot came this frame is walked pixel by pixel, in the
; text's own frame - if the text moved a pixel left meanwhile, the start
; of the way moves with it - and the first lit pixel is the hit. nothing
; can slip through between two frames.
; the letter that was hit goes completely (blastAt): its columns are found
; in the buffer, every one of its pixels is taken out of this frame's
; picture and out of the source text, and the blast sits on it - its
; dots at once, its sparks and rings a frame later (fxPending), which
; spreads the work. one blast a frame: another hit waits in hitQueue -
; the shot is gone at once all the same.
blastsPerFrame	= 1				; (a blast is ~25000 cycles)
hitQueueMax		= 8
queueSearch		= 3				; a queued hit looks this far for its letter

; once a frame, before the shots: the hits held over from last frame
textShotBegin::
		clr.w	blastsDone
		tst.b	fxPending				; last frame's blast still owes its
		beq.s	.noFx					; sparks and rings: they come now, and
		sf		fxPending				; that is this frame's blast - any hit
	ifne	fwAll						; waits in the queue
		bsr		latticeAdd				; (switches.i fwAll: a firework, as the
	else								; laser's letters have)
		bsr		blastFx
	endc
		move.w	#blastsPerFrame,blastsDone
		rts
.noFx:
		move.w	hitQueueN,d7
		beq.s	.none
		clr.w	hitQueueN
		subq.w	#1,d7
		lea		hitQueue,a4
		movem.w	(a4)+,d0/d1				; the oldest one
		sub.w	scrollStepped,d0		; (the text has moved on since)
		move.w	d7,hitQueueN			; the others wait on
		beq.s	.last
		lea		hitQueue,a3
		subq.w	#1,d7
.shift:
		move.l	(a4)+,(a3)+
		dbf		d7,.shift
.last:
		addq.w	#1,blastsDone
		bra		blastAt
.none:
		rts

; in:  d0/d1 = where the shot was last frame, d2/d3 = where it is now
;      (game coordinates), d4/d5 = its velocity
; out: d0 non zero if it hit
; keeps a0/a5/a6
textShot::
		movem.w	d4/d5,blastVx
		add.w	scrollStepped,d0		; the start, in the text's frame
		sub.w	#topLines,d1			; -> scroller lines
		sub.w	#topLines,d3
		move.w	d2,d4
		sub.w	d0,d4					; dx
		move.w	d3,d5
		sub.w	d1,d5					; dy
		move.w	d4,d6
		bpl.s	.ax
		neg.w	d6
.ax:
		move.w	d5,d7
		bpl.s	.ay
		neg.w	d7
.ay:
		cmp.w	d7,d6
		bhs.s	.n
		move.w	d7,d6
.n:
		tst.w	d6						; d6 = steps, at least one
		bne.s	.n1
		moveq	#1,d6
.n1:
		cmp.w	#24,d6					; it went round the screen edge (the
		bls.s	.walkOk					; play area wraps): no walk right across
		moveq	#0,d0					; the screen - 40000 cycles for nothing
		rts
.walkOk:
		ext.l	d4
		asl.l	#8,d4
		divs	d6,d4					; x step, 8.8
		ext.l	d4
		ext.l	d5
		asl.l	#8,d5
		divs	d6,d5					; y step, 8.8
		ext.l	d5
		moveq	#0,d2
		move.w	d0,d2
		ext.l	d2
		asl.l	#8,d2
		add.l	#128,d2					; x, 8.8, rounded
		move.w	d1,d3
		ext.l	d3
		asl.l	#8,d3
		add.l	#128,d3					; line, 8.8
		move.l	screenlocScroller,a1
		lea		yTable,a2
.walk:
		move.l	d3,d1
		asr.l	#8,d1					; line
		cmp.w	#yTop,d1
		blt.s	.next
		cmp.w	#rightLine+hitRows,d1
		bge.s	.next
		move.l	d2,d0
		asr.l	#8,d0					; x
		cmp.w	#dissolveX,d0
		blt.s	.next
		cmp.w	#game_width,d0
		bge.s	.next
		move.w	d1,d7
		add.w	d7,d7
		move.w	(a2,d7.w),d7			; line * li
		move.w	d0,a3
		lsr.w	#3,d0
		add.w	d0,d7
		move.w	a3,d0
		not.w	d0						; bit 7-(x&7)
		btst	d0,(a1,d7.w)
		bne.s	.hit
.next:
		add.l	d4,d2
		add.l	d5,d3
		dbf		d6,.walk
		moveq	#0,d0
		rts
.hit:
		move.w	a3,d0					; x, d1 = line
		move.w	blastsDone,d7
		cmp.w	#blastsPerFrame,d7
		bhs.s	.queue
		addq.w	#1,blastsDone
		bsr		blastAt
		moveq	#1,d0
		rts
.queue:
		move.w	hitQueueN,d7
		cmp.w	#hitQueueMax,d7
		bhs.s	.full
		addq.w	#1,hitQueueN
		lsl.w	#2,d7
		lea		hitQueue,a3
		add.w	d7,a3
		move.w	d0,(a3)+
		move.w	d1,(a3)
.full:
		moveq	#1,d0
		rts

; is column d0 of the buffer lit in any of the 7 text rows from line d6?
; -> Z clear if so. a1 = buffer, a2 = yTable. uses d2/d3/d7
colLit:
		move.w	d0,d2
		lsr.w	#3,d2
		move.w	d0,d3
		not.w	d3
		move.w	d6,d7
		add.w	d7,d7
		move.w	(a2,d7.w),d7
		add.w	d2,d7
		btst	d3,(a1,d7.w)
		bne.s	.yes
		add.w	#li,d7
		btst	d3,(a1,d7.w)
		bne.s	.yes
		add.w	#li,d7
		btst	d3,(a1,d7.w)
		bne.s	.yes
		add.w	#li,d7
		btst	d3,(a1,d7.w)
		bne.s	.yes
		add.w	#li,d7
		btst	d3,(a1,d7.w)
		bne.s	.yes
		add.w	#li,d7
		btst	d3,(a1,d7.w)
		bne.s	.yes
		add.w	#li,d7
		btst	d3,(a1,d7.w)
		bne.s	.yes
		moveq	#0,d7
		rts
.yes:
		moveq	#1,d7
		rts

; the letter at buffer x d0, line d1 is blown up: all of it, and the
; blast on it. keeps a0/a5/a6
blastAt:
		move.l	d0,-(a7)
		moveq	#2,d0					; the boom (music.s sfxPlay, SFX_BOOM)
		jsr		sfxPlay
		move.l	(a7)+,d0
		move.l	screenlocScroller,a1
		lea		yTable,a2
		; --- which part of the text: the bottom row ...
		cmp.w	#rightLine,d1
		blt.s	.notRight
		cmp.w	#rightLine+hitRows,d1
		bge.s	.notRight
		cmp.w	#hitRightX,d0
		blo.s	.notRight
		moveq	#rightLine,d6			; its first line
		move.w	#hitRightX,a3			; its columns ...
		move.w	#game_width-1,a4
		moveq	#24,d5					; ... and source x = buffer x + 24
		bra.s	.letter
.notRight:
		; ... the top row, before the twist ...
		cmp.w	#yTop,d1
		blt		.twist
		cmp.w	#yTop+hitRows,d1
		bge		.twist
		cmp.w	#dissolveX,d0
		blo		.twist
		cmp.w	#hitTwistX,d0
		bhs		.twist
		moveq	#yTop,d6
		move.w	#dissolveX,a3
		move.w	#hitTwistX-1,a4
		moveq	#0,d5
		; --- the column hit (a queued hit may be a pixel or two off)
.letter:
		move.w	d0,d4
		bsr		colLit
		bne.s	.found
		moveq	#1,d1
.search:
		move.w	d4,d0
		sub.w	d1,d0
		bsr		colLit
		bne.s	.found
		move.w	d4,d0
		add.w	d1,d0
		bsr		colLit
		bne.s	.found
		addq.w	#1,d1
		cmp.w	#queueSearch,d1
		bls.s	.search
		rts								; nothing there any more
.found:
		; --- the letter: lit columns either side, up to a blank one
		move.w	d0,d4					; first column
		move.w	d0,d1					; last column
.left:
		cmp.w	a3,d4
		bls.s	.leftDone
		move.w	d4,d0
		subq.w	#1,d0
		bsr		colLit
		beq.s	.leftDone
		subq.w	#1,d4
		bra.s	.left
.leftDone:
.right:
		cmp.w	a4,d1
		bhs.s	.rightDone
		move.w	d1,d0
		addq.w	#1,d0
		bsr		colLit
		beq.s	.rightDone
		addq.w	#1,d1
		bra.s	.right
.rightDone:
		; --- the blast, on the middle of it
		bsr		pickPower
		move.w	d4,d0
		add.w	d1,d0
		lsr.w	#1,d0
		move.w	d0,debrisCx
		move.w	d6,d0
		addq.w	#hitRows/2,d0
		move.w	d0,debrisCy
		st		fxPending				; its sparks and rings: next frame
		addq.w	#1,hitTotal
		; --- every pixel of it out of the picture and out of the source,
		;     and every n-th one a glowing dot
		lea		src_adr,a3
		moveq	#hitRows-1,d7
.row:
		move.w	d4,d3					; x
.col:
		move.w	d6,d0
		add.w	d0,d0
		move.w	(a2,d0.w),d0
		move.w	d3,d2
		lsr.w	#3,d2
		add.w	d2,d0
		move.w	d3,d2
		not.w	d2
		bclr	d2,(a1,d0.w)			; out of this frame's picture
		beq.s	.noPix
		move.w	d3,d0
		add.w	d5,d0
		move.w	d0,d2
		lsr.w	#3,d0
		not.w	d2
		bclr	d2,(a3,d0.w)			; and out of the text
	ifne	fwAll						; (with the fireworks: they are the dots,
		bra.s	.noPix					; no crumbs - and the frame can afford them)
	endc
		tst.b	blastNoCrumbs			; (the laser's: its firework is the dots)
		bne.s	.noPix
		subq.b	#1,debrisSkip
		bne.s	.noPix
		move.b	debrisEvery,debrisSkip
		bsr		addDebris				; (x d3, line d6)
.noPix:
		addq.w	#1,d3
		cmp.w	d1,d3
		bls.s	.col
		addq.w	#1,d6
		lea		src_line(a3),a3
		dbf		d7,.row
		rts

		; --- the twist, 48 source pixels squeezed into 24 on screen and
		;     turned over top to bottom (see table2). it is only ever hit in
		;     the first attack: the pixels round the hit go from the
		;     picture, and the two source bytes for that line from the text
.twist:
		move.w	d0,d4
		move.w	d1,d6
		bsr		pickPower
		move.w	d4,debrisCx
		move.w	d6,debrisCy
		st		fxPending
		addq.w	#1,hitTotal
		; the picture: 12 x 9 pixels round the hit
		move.w	d6,d0
		subq.w	#4,d0
		cmp.w	#yTop,d0
		bge.s	.ty0
		moveq	#yTop,d0
.ty0:
		move.w	d0,d6
		moveq	#9-1,d7
.trow:
		cmp.w	#rightLine+hitRows,d6
		bge.s	.tsrc
		move.w	d4,d3
		subq.w	#6,d3
		moveq	#12-1,d1
.tcol:
		move.w	d6,d0
		add.w	d0,d0
		move.w	(a2,d0.w),d0
		move.w	d3,d2
		lsr.w	#3,d2
		add.w	d2,d0
		move.w	d3,d2
		not.w	d2
		bclr	d2,(a1,d0.w)
		beq.s	.tno
	ifne	fwAll						; (the firework is the dots)
		bra.s	.tno
	endc
		subq.b	#1,debrisSkip
		bne.s	.tno
		move.b	debrisEvery,debrisSkip
		bsr		addDebris
.tno:
		addq.w	#1,d3
		dbf		d1,.tcol
		addq.w	#1,d6
		dbf		d7,.trow
.tsrc:
		; the source: p ~ line*16/7 -> two bytes of $14..$19, every row
		move.w	debrisCy,d1
		sub.w	#yTop+3,d1
		bpl.s	.tPos
		moveq	#0,d1
.tPos:
		mulu	#73,d1
		lsr.w	#8,d1
		subq.w	#1,d1
		bpl.s	.tOk
		moveq	#0,d1
.tOk:
		cmp.w	#6-2,d1
		ble.s	.tOk2
		moveq	#6-2,d1
.tOk2:
		lea		src_adr+$14,a3
		add.w	d1,a3
		moveq	#hitRows-1,d7
.tclr:
		clr.b	(a3)
		clr.b	1(a3)
		lea		src_line(a3),a3
		dbf		d7,.tclr
		rts

; how many letters ahead can shots on one line hit, one after the other?
; in:  d0/d1 = screen x from/to (the bottom row), d2 = the shots' line
; out: d0 = the letters from the first one on that have a pixel on that
;      line - counting stops at one that has none (a shot would pass it,
;      and it would stay). works on the source, a byte at a time
lettersOnLine::
		movem.l	d1-d7/a0-a1,-(a7)
		moveq	#0,d6					; letters
		sub.w	#rightLine,d2			; -> text row
		cmp.w	#hitRows,d2
		bhs		.out					; (unsigned: above as well)
		cmp.w	#hitRightX,d0
		bge.s	.lo
		move.w	#hitRightX,d0
.lo:
		add.w	#24,d0					; -> source x
		add.w	#24,d1
		lsr.w	#3,d0					; source bytes
		lsr.w	#3,d1
		cmp.w	#src_line-1,d1
		ble.s	.hi
		moveq	#src_line-1,d1
.hi:
		sub.w	d0,d1
		bmi		.out
		lea		src_adr,a0
		add.w	d0,a0					; row 0 of the first byte
		mulu	#src_line,d2
		lea		(a0,d2.w),a1			; the shots' row
		moveq	#0,d5					; 0 out of a letter, 1 in one, 2 in one
										; that has a pixel on the line
.byte:
		move.b	(a0),d3					; the 7 rows together
		or.b	src_line(a0),d3
		or.b	2*src_line(a0),d3
		or.b	3*src_line(a0),d3
		or.b	4*src_line(a0),d3
		or.b	5*src_line(a0),d3
		or.b	6*src_line(a0),d3
		move.b	(a1)+,d4				; the line
		addq.l	#1,a0
		moveq	#8-1,d7
.bit:
		add.b	d4,d4
		scs		d2						; on the line?
		add.b	d3,d3
		bcc.s	.blank
		tst.w	d5
		bne.s	.inLetter
		moveq	#1,d5
.inLetter:
		tst.b	d2
		beq.s	.nextBit
		moveq	#2,d5
		bra.s	.nextBit
.blank:
		tst.w	d5
		beq.s	.nextBit
		cmp.w	#2,d5
		bne.s	.out					; a letter shots on this line would miss
		addq.w	#1,d6
		moveq	#0,d5
.nextBit:
		dbf		d7,.bit
		dbf		d1,.byte
		cmp.w	#2,d5					; one going on at the end of the range
		bne.s	.out
		addq.w	#1,d6
.out:
		move.w	d6,d0
		movem.l	(a7)+,d1-d7/a0-a1
		rts

;---------------------------------------------
; THE HYPER POWER BLAST
;---------------------------------------------
; the last attack: seq_run (asteroids.s) fires one plasma blast along the
; bottom text row (launchTorpedo) - a muzzle flash at the nose, then a huge
; pulsing blob of plasma with sparks streaming off behind it. nothing
; stops it: it goes along the row at one speed, torpSpeed, and out of the
; screen. each letter goes off the moment the blast's front gets to that
; letter's last column - against the text as it is shown this frame. only
; if the frame has already had its blast (a blast and its sparks take two
; frames, fxPending) does a letter go off a frame late; detLate* count it.
; the rest of the sentence, still coming in after the blast has gone, runs
; into its wake (wakeOn): each letter goes off as soon as it is all on
; screen.
; a blast's sparks and rings come a frame after it (fxPending), so with
; detGap at 2 or more there is never more than one blast's work a frame.
torpSpeed		= $28000		; 2.5 px a frame (16.16), always
torpHead		= 4				; its front, from torpX
torpHalf		= 4				; lines above and below its line it hits on
torpRingGap		= 6				; a shock ring every this many frames in text
detMax			= 32
detGap			= 0				; extra frames between the letters going off (a
								; blast and its sparks take two anyway)
wakeLastX		= game_width-1	; in the wake a letter goes off once its last
								; column is on screen

; d0/d1 = the ship's nose (game coordinates), d2 = the ship's x speed
; (1/128 px a frame)
launchTorpedo::
		movem.l	d0-d7/a0-a3,-(a7)
		moveq	#0,d3
		move.w	d0,d3
		swap	d3
		move.l	d3,torpX				; 16.16
		sub.w	#topLines,d1
		move.w	d1,torpLine
		move.l	#torpSpeed,torpVX		; (the ship's speed does not come into it)
		st		torpOn
		clr.w	torpAge
		clr.w	torpInText
		move.w	#-1,torpNextEnd
		clr.w	detN
		clr.w	detTimer
		; --- the muzzle flash: a small blast at the nose, forwards
		move.w	d0,debrisCx
		move.w	d1,debrisCy
		move.l	#flashPower,blastPow
		move.w	#256,blastVx
		clr.w	blastVy
		bsr		blastFx
		movem.l	(a7)+,d0-d7/a0-a3
		rts

; every frame after postEffect, from textFrame: the blast goes on at its
; one speed, and the first letter ahead goes off the moment the blast's
; front gets to that letter's last column
torpedoStep:
		tst.b	torpOn
		beq		.out
		addq.w	#1,torpAge
		move.l	torpX,d2
		add.l	torpVX,d2
		move.l	d2,torpX
		swap	d2						; x now
		cmp.w	#game_width+28,d2		; (its tail out as well)
		bge		.gone
		bsr		torpTrail
		; --- a shock ring now and then while it is in the text
		tst.w	torpInText
		beq.s	.noRing
		move.w	torpAge,d0
		ext.l	d0
		divu	#torpRingGap,d0
		swap	d0
		tst.w	d0
		bne.s	.noRing
		bsr		torpRing
.noRing:
		; --- the first letter on the row, and its last column - found
		;     once and kept (in text terms, + scrollSteps) until it is gone
		move.w	torpNextEnd,d4
		bmi.s	.find
		sub.w	scrollSteps,d4
		bra.s	.ended
.find:
		moveq	#0,d0
		bsr		firstLitCol
		tst.w	d0
		bmi		.out
		move.l	screenlocScroller,a1
		lea		yTable,a2
		moveq	#rightLine,d6
		move.w	d0,d4
.end:
		cmp.w	#game_width-1,d4
		bhs.s	.ended0
		move.w	d4,d0
		addq.w	#1,d0
		bsr		colLit
		beq.s	.ended0
		addq.w	#1,d4
		bra.s	.end
.ended0:
		cmp.w	#game_width-1,d4		; (cut off by the border: not kept,
		bhs.s	.ended					; it is still coming in)
		move.w	d4,d0
		add.w	scrollSteps,d0
		move.w	d0,torpNextEnd
.ended:
		move.l	torpX,d0
		swap	d0
		addq.w	#torpHead,d0			; the blast's front
		cmp.w	d4,d0
		blt.s	.notYet
		; --- there: it goes off now - unless this frame has had its blast
		;     (the last one's sparks), then the next frame
		tst.b	fxPending
		bne.s	.wait
		tst.w	blastsDone
		bne.s	.wait
		move.w	d4,d0
		move.w	#rightLine+hitRows/2,d1
		move.b	#1,bigBlast
		addq.w	#1,blastsDone
		bsr		blastAt
		move.w	#-1,torpNextEnd			; the next one
		addq.w	#1,torpInText
		; (testing: how late it went off)
		moveq	#0,d0
		tst.b	detWaiting
		beq.s	.onTime
		move.w	introTime,d0
		sub.w	detWaitFrom,d0
		addq.w	#1,detLateN
		add.w	d0,detLateFrames
.onTime:
		sf		detWaiting
		move.w	detLogN,d1
		cmp.w	#32,d1
		bhs.s	.out
		addq.w	#1,detLogN
		add.w	d1,d1
		add.w	d1,d1
		lea		detLog,a3
		add.w	d1,a3
		move.w	introTime,(a3)+			; frame it went off
		move.w	d0,(a3)					; frames after the blast got there
		rts
.wait:
		tst.b	detWaiting
		bne.s	.out
		st		detWaiting
		move.w	introTime,detWaitFrom
		rts
.notYet:
.out:
		rts
.gone:
		sf		torpOn
		st		wakeOn					; anything still coming in: the wake
		rts

; the letters it went through go off, one every detGap frames - and once it
; has gone, the ones that come in after it
detStep:
		tst.b	fxPending				; the last blast's sparks are due
		bne		.out
		tst.w	blastsDone
		bne		.out
		tst.w	detTimer
		beq.s	.ready
		subq.w	#1,detTimer
		rts
.ready:
		move.w	detN,d7
		beq.s	.wake
		; --- the oldest on the list (the leftmost)
		lea		detQueue,a3
		move.w	(a3),d0
		sub.w	scrollSteps,d0			; where it is now
		subq.w	#1,d7
		move.w	d7,detN
		beq.s	.popped
		subq.w	#1,d7
.shift:
		move.w	2(a3),(a3)+
		dbf		d7,.shift
.popped:
		move.w	#rightLine+hitRows/2,d1
		move.b	#1,bigBlast
		addq.w	#1,blastsDone
		bsr		blastAt
		move.w	#detGap,detTimer
.out:
		rts
		; --- the wake: a letter coming in goes off once it is all in
.wake:
		tst.b	wakeOn
		beq.s	.out
		moveq	#0,d0
		bsr		firstLitCol				; the first letter on the row
		tst.w	d0
		bmi.s	.none
		move.l	screenlocScroller,a1
		lea		yTable,a2
		moveq	#rightLine,d6
		move.w	d0,d4
.end:
		move.w	d4,d0					; its last column - on screen?
		addq.w	#1,d0
		bsr		colLit
		beq.s	.ended
		addq.w	#1,d4
		cmp.w	#wakeLastX,d4
		blo.s	.end
		rts								; still coming in: wait
.ended:
		move.w	d4,d0
		move.w	#rightLine+hitRows/2,d1
		move.b	#1,bigBlast
		addq.w	#1,blastsDone
		bsr		blastAt
		move.w	#detGap,detTimer
		rts
.none:
		tst.b	msgEnded				; nothing more to come: it is over
		beq.s	.out
		jsr		msgLeftX
		tst.w	d0
		bpl.s	.out
		sf		wakeOn
		rts

; the first lit column of this frame's bottom text row in the buffer, from
; screen x d0 up to the right border -> d0, -1 if none. a byte at a time
firstLitCol:
		movem.l	d1-d3/a0-a1,-(a7)
		cmp.w	#hitRightX,d0
		bge.s	.lo
		move.w	#hitRightX,d0
.lo:
		move.l	screenlocScroller,a0
		add.w	#rightLine*li,a0
		move.w	d0,d1
		lsr.w	#3,d1
		add.w	d1,a0
.byte:
		cmp.w	#game_width,d0
		bge.s	.none
		move.b	(a0),d3
		or.b	li(a0),d3
		or.b	2*li(a0),d3
		or.b	3*li(a0),d3
		or.b	4*li(a0),d3
		or.b	5*li(a0),d3
		or.b	6*li(a0),d3
		move.w	d0,d2
		and.w	#7,d2
		lsl.b	d2,d3					; the bits left of d0 in this byte go
		beq.s	.nextByte
.bit:
		add.b	d3,d3
		bcs.s	.found
		addq.w	#1,d0
		bra.s	.bit
.nextByte:
		or.w	#7,d0
		addq.w	#1,d0
		addq.l	#1,a0
		bra.s	.byte
.found:
		cmp.w	#game_width,d0
		blt.s	.out
.none:
		moveq	#-1,d0
.out:
		movem.l	(a7)+,d1-d3/a0-a1
		rts

; is column d0 lit on any of the blast's lines (from line d6, 2*torpHalf
; + 1 of them)? -> Z clear if so. uses d3/d5/d7
torpCol:
		move.w	d0,d5
		lsr.w	#3,d5
		move.w	d0,d3
		not.w	d3
		move.w	d6,d7
		add.w	d7,d7
		move.w	(a2,d7.w),d7
		add.w	d5,d7
		moveq	#2*torpHalf,d5
.l:
		btst	d3,(a1,d7.w)
		bne.s	.yes
		add.w	#li,d7
		dbf		d5,.l
		moveq	#0,d7
		rts
.yes:
		moveq	#1,d7
		rts

; two sparks streaming off behind the blast, short lived. d2 = its x
torpTrail:
		movem.l	d0-d4/a0-a1,-(a7)
		move.w	sparkNum,d4
		cmp.w	#sparkMax-2,d4
		bhs.s	.out
		addq.w	#2,sparkNum
		mulu	#spark_len,d4
		lea		sparks,a0
		add.l	d4,a0
		moveq	#2-1,d4
.s:
		bsr		debrisRandom
		moveq	#0,d1
		move.w	d2,d1
		sub.w	#10,d1
		swap	d1
		move.l	d1,(a0)+				; x, off its tail
		moveq	#7,d1
		and.w	d0,d1
		subq.w	#3,d1
		add.w	torpLine,d1
		swap	d1
		clr.w	d1
		move.l	d1,(a0)+				; y, round its line
		move.w	d0,d1
		and.l	#$ffff,d1
		sub.l	#$18000,d1				; x speed: back, -1.5..-0.5 px
		move.l	d1,(a0)+
		swap	d0
		move.w	d0,d1
		ext.l	d1						; y speed: -0.5..0.5 px
		move.l	d1,(a0)+
		move.w	#5,(a0)+				; life
		dbf		d4,.s
.out:
		movem.l	(a7)+,d0-d4/a0-a1
		rts

; a small shock ring at the blast, thrown off as it ploughs
torpRing:
		movem.l	d0/a0,-(a7)
		move.w	ringCount,d0
		cmp.w	#ringMax,d0
		bhs.s	.out
		addq.w	#1,ringCount
		lsl.w	#3,d0
		lea		rings,a0
		add.w	d0,a0
		move.l	torpX,d0
		swap	d0
		move.w	d0,(a0)+				; x
		move.b	torpLine+1,(a0)+		; line
		clr.b	(a0)+					; age
		move.b	#1,(a0)+				; flat
		move.b	#3,(a0)+				; step
		move.b	#4,(a0)+				; frames
.out:
		movem.l	(a7)+,d0/a0
		rts

; the blast itself, from drawBlastFx: a huge blob of plasma, nine lines
; high, that pulses (a0 = buffer, a1 = yTable). a row at a time, a byte at
; a time
drawTorpedo:
		tst.b	torpOn
		beq		.out
		move.l	torpX,d2
		swap	d2						; x
		lea		torpShape,a2
		btst	#1,torpAge+1			; two shapes, swapping every 2 frames
		beq.s	.shape
		lea		torpShape2-torpShape(a2),a2
.shape:
		lea		torpRowX-torpShape(a2),a3
		move.w	torpLine,d3
		subq.w	#torpHalf,d3
		moveq	#2*torpHalf,d6
.row:
		move.b	(a3)+,d4				; this row: from x + n ...
		ext.w	d4
		add.w	d2,d4					; x0
		moveq	#0,d5
		move.b	(a2)+,d5
		add.w	d4,d5
		subq.w	#1,d5					; x1
		cmp.w	#screenHeight,d3
		bhs.s	.nextRow
		cmp.w	#game_width-1,d5		; clipped to the buffer line
		ble.s	.c1
		move.w	#game_width-1,d5
.c1:
		tst.w	d4
		bpl.s	.c0
		moveq	#0,d4
.c0:
		cmp.w	d4,d5
		blt.s	.nextRow
		move.w	d3,d0
		add.w	d0,d0
		move.w	(a1,d0.w),d7
		lea		(a0,d7.w),a4			; the line
		move.w	d4,d0
		lsr.w	#3,d0					; first byte
		move.w	d5,d1
		lsr.w	#3,d1					; last byte
		moveq	#7,d7
		and.w	d4,d7
		move.b	.lmask(pc,d7.w),d7		; first byte's bits
		cmp.w	d0,d1
		beq.s	.one
		or.b	d7,(a4,d0.w)
		addq.w	#1,d0
.mid:
		cmp.w	d1,d0
		bhs.s	.last
		st		(a4,d0.w)
		addq.w	#1,d0
		bra.s	.mid
.last:
		moveq	#7,d7
		and.w	d5,d7
		move.b	.rmask(pc,d7.w),d7
		or.b	d7,(a4,d1.w)
		bra.s	.nextRow
.one:
		moveq	#7,d0
		and.w	d5,d0
		and.b	.rmask(pc,d0.w),d7		; first and last in one byte
		or.b	d7,(a4,d1.w)
.nextRow:
		addq.w	#1,d3
		dbf		d6,.row
.out:
		rts
.lmask:	dc.b	$ff,$7f,$3f,$1f,$0f,$07,$03,$01
.rmask:	dc.b	$80,$c0,$e0,$f0,$f8,$fc,$fe,$ff
; per row of the blob: how wide it is, and (9 bytes on) where it starts
; from x - a fat head with a long tail of plasma behind it. two of them,
; it swaps between them
torpShape:
		dc.b	5,11,16,20,23,20,16,11,5
torpRowX:
		dc.b	-3,-8,-12,-16,-18,-16,-12,-8,-3
torpShape2:
		dc.b	7,13,18,22,25,22,18,13,7
		dc.b	-4,-9,-14,-18,-20,-18,-14,-9,-4
		even

;---------------------------------------------
; THE DEFENDER LASER (seq_deffire, asteroids.s): from the ship's nose
; along the bottom text row, the way Defender's goes - a white streak that
; shoots out (laserSpeed a frame), solid at its head and broken up behind
; it, shedding white dots that sink out of the bar and glow out like the
; letters' crumbs. where it meets the message the word goes up, letter by
; letter as fast as the blasts allow (one a frame, their sparks the frame
; after), with the blasts as ever; then the streak pulls away from the
; ship after its head (laserFade a frame) and is gone. one word a shot: a
; gap of laserWordGap px or more ends the word. a letter still coming in
; over the right edge waits till all of it is in. each shot is a zap
; (music.s sfxLaser)
laserSpeed		= 32
laserFade		= 40
laserWordGap	= 7
laserSolid		= 28			; px of solid streak at its head
laserEmberGap	= 3				; a dot shed every this many frames
laserPace		= 3				; frames a letter
laserGlow		= 120			; px of dense glow behind the head
laserFlashT		= 8				; frames of muzzle flash

; d0/d1 = the nose (game coordinates). keeps every register
launchLaser::
		move.w	d1,-(a7)
		sf		laserObj
		move.w	d0,laserNose
		move.w	d0,laserTail
		move.w	d0,laserFront
		cmp.w	#181,d1					; (on the text, wherever the nose is)
		bge.s	.l0
		move.w	#181,d1
.l0:
		cmp.w	#184,d1
		ble.s	.l1
		move.w	#184,d1
.l1:
		bra.s	laserGo
	ifne	defWords
; the same at any height, at the game's letters (switches.i defWords,
; asteroids.s seq_defwords): d0/d1 = the nose. keeps every register
launchLaserAt::
		move.w	d1,-(a7)
		st		laserObj
		clr.w	defWantWord				; (asteroids.s: any word, till one is hit)
		move.w	d0,laserNose
		move.w	d0,laserTail
		move.w	d0,laserFront
	endc
laserGo:
		move.w	d1,laserY
		sub.w	#topLines,d1
		move.w	d1,laserLine
		clr.w	laserPhase
		clr.w	laserAge
		clr.w	laserWait
		move.w	#-1,laserLast
		st		laserOn
		move.l	d0,-(a7)
		moveq	#3,d0					; the zap (music.s sfxPlay, SFX_LASER)
		jsr		sfxPlay
		move.l	(a7)+,d0
		move.w	(a7)+,d1
		rts

; every frame, from textFrame (after postEffect, the text as it is shown)
laserStep:
		tst.b	laserOn
		beq		.out
		addq.w	#1,laserAge
		move.w	laserPhase,d0
		beq.s	.shoot
		subq.w	#1,d0
		beq.s	.burn
		; --- the word is gone: the streak pulls away after its head
		add.w	#laserFade,laserTail
		move.w	laserTail,d0
		cmp.w	laserFront,d0
		blt		.out
		sf		laserOn
		rts
		; --- out it shoots, till it meets the message
.shoot:
		move.w	laserFront,d0
		add.w	#laserSpeed,d0
		cmp.w	#game_width,d0
		blt.s	.f
		move.w	#game_width,d0
.f:
		move.w	d0,laserFront
	ifne	defWords
		tst.b	laserObj			; at the game's letters?
		bne		.oShoot
	endc
		bsr		laserAhead
		bmi.s	.miss
		cmp.w	laserFront,d0
		bgt.s	.miss					; not there yet
		move.w	d0,laserFront
		move.w	#1,laserPhase
		bra.s	.burn
.miss:
		cmp.w	#game_width,laserFront
		blt		.out
		move.w	#2,laserPhase			; (nothing in its way)
		rts
		; --- the word, a letter at a time
.burn:
	ifne	defWords
		tst.b	laserObj
		bne		.oBurn
	endc
		bsr		laserAhead				; the next letter
		bmi.s	.wordGone
		move.w	laserLast,d1			; still the same word? the gap after
		bmi.s	.same					; the last letter gone
		sub.w	scrollSteps,d1
		move.w	d0,d2
		sub.w	d1,d2
		cmp.w	#laserWordGap,d2
		bge.s	.wordGone
.same:
		move.w	d0,laserFront
		tst.w	laserWait				; a letter every laserPace frames: the
		beq.s	.due					; blast, its sparks, and a frame free
		subq.w	#1,laserWait
		rts
.due:
		tst.b	fxPending				; one blast a frame
		bne		.out
		tst.w	blastsDone
		bne		.out
		move.l	screenlocScroller,a1	; its last column - all of it in?
		lea		yTable,a2
		moveq	#rightLine,d6
		move.w	d0,d4
.end:
		cmp.w	#game_width-1,d4
		bhs		.out					; still coming in: wait
		move.w	d4,d0
		addq.w	#1,d0
		bsr		colLit
		beq.s	.ended
		addq.w	#1,d4
		bra.s	.end
.ended:
		move.w	d4,d0
		move.w	#rightLine+hitRows/2,d1
		add.w	scrollSteps,d4			; (blastAt has d4 for its own)
		move.w	d4,laserLast
		move.w	#laserPace-1,laserWait
		move.b	#3,bigBlast				; (pickPower: fat, not the biggest)
		addq.w	#1,blastsDone
		st		blastNoCrumbs
		bsr		blastAt
		sf		blastNoCrumbs
		sf		fxPending				; not its sparks and rings: the Defender
		bsr		latticeAdd				; lattice instead (debrisCx/Cy: blastAt)
		addq.w	#1,laserHits			; (testing)
		rts
.wordGone:
		move.w	#2,laserPhase
		addq.w	#1,laserWords			; (testing)
.out:
		rts
	ifne	defWords
		; --- the game's letters (asteroids.s defLetterAt): the first in the
		;     beam's line ...
.oShoot:
		move.w	laserNose,d0
		move.w	laserY,d1
		move.w	laserFront,d2
		add.w	#12,d2
		jsr		defLetterAt
		bmi		.miss
		sub.w	#12,d0
		cmp.w	laserNose,d0
		bge.s	.oFront
		move.w	laserNose,d0
.oFront:
		move.w	d0,laserFront
		move.w	#-1,laserLast
		clr.w	laserWait
		move.w	#1,laserPhase
		; ... then the rest of its word, a letter every laserPace frames
.oBurn:
		tst.w	laserWait
		beq.s	.oDue
		subq.w	#1,laserWait
		rts
.oDue:
		move.w	laserLast,d0			; (-1: the first, from the head on)
		bpl.s	.oNext
		move.w	laserFront,d0
		move.w	d0,d2
		add.w	#24,d2
		bra.s	.oFind
.oNext:
		move.w	d0,d2
		add.w	#defObjGap,d2
		addq.w	#1,d0
.oFind:
		move.w	laserY,d1
		jsr		defLetterAt
		bmi		.wordGone
		jsr		defLetterKill			; d0/d1: where it was
		move.w	d0,laserLast
		move.w	d0,laserFront
		move.w	d0,debrisCx
		sub.w	#topLines,d1
		move.w	d1,debrisCy
		bsr		latticeAdd				; the firework
		moveq	#2,d0					; the boom (music.s sfxPlay, SFX_BOOM)
		jsr		sfxPlay
		move.w	#laserPace-1,laserWait
		addq.w	#1,laserHits			; (testing)
		rts
	endc

; -> d0 = the first lit column of the message on the row, to the pixel,
; -1 (N set) if none. msgFrom finds it a byte at a time in the source;
; from a byte before that firstLitCol finds the column in the picture, but
; never left of where the message starts
laserAhead:
		move.l	d1,-(a7)
		move.w	laserNose,d0
		bsr		msgFrom
		tst.w	d0
		bmi.s	.out
		subq.w	#8,d0
		move.w	msgStartAbs,d1
		sub.w	scrollSteps,d1
		cmp.w	d1,d0
		bge.s	.from
		move.w	d1,d0
.from:
		bsr		firstLitCol
.out:
		move.l	(a7)+,d1
		tst.w	d0
		rts

; the streak, from drawBlastFx (a0 = buffer, a1 = yTable): two lines,
; solid for laserSolid px at its head, broken up behind it in a pattern
; that runs along it; and the dots it sheds
drawLaser:
		tst.b	laserOn
		bne.s	.on
		tst.b	laserCol				; gone: its lines' colours back to the
		beq		.out					; text's
		sf		laserCol
		bra		laserColsBack
.on:
		; --- its colours: the TV is off, the copper runs the bar through
		;     tvList - the colour 1 of the beam's four lines burns white,
		;     yellow, orange, red and back, a step a frame, the outer lines
		;     a few steps behind (the text on them burns along with it)
		tst.b	tvState
		beq		.noCol
	ifne	defWords
		tst.b	laserObj				; (at another height: none of the
		beq.s	.colRow					; text's lines to colour)
		move.w	laserY,d0
		sub.w	#181,d0
		cmp.w	#3,d0
		bhi		.noCol
.colRow:
	endc
		st		laserCol
		bsr		laserColsBack			; (the beam may be on other lines now)
		lea		tvBeamTab,a3			; its four lines: from the one above
		move.w	laserLine,d0			; its core (game y 181..184 -> 0..3)
		add.w	#topLines-181,d0
		lsl.w	#2,d0
		add.w	d0,a3
		lea		laserHot(pc),a2
		move.w	laserAge,d0
		moveq	#15,d1
		and.w	d0,d1
		add.w	d1,d1
		move.l	4(a3),a4				; the core ...
		move.w	(a2,d1.w),(a4)
		addq.w	#4,d1
		and.w	#31,d1
		move.l	8(a3),a4
		move.w	(a2,d1.w),(a4)
		addq.w	#8,d1					; ... and the glow either side
		and.w	#31,d1
		move.w	(a2,d1.w),d0
		move.l	(a3),a4
		move.w	d0,(a4)
		move.l	12(a3),a4
		move.w	d0,(a4)
.noCol:
		move.w	laserTail,d4
		move.w	laserFront,d5
		cmp.w	#borderX,d4
		bge.s	.t
		moveq	#borderX,d4
.t:
		cmp.w	#game_width-1,d5
		ble.s	.fr
		move.w	#game_width-1,d5
.fr:
		cmp.w	d4,d5
		ble		.out
		movem.w	d4/d5,-(a7)
		; --- the core, two lines: one solid all the way, one solid too
		;     with a fine break-up running along it
		move.w	laserLine,d3
		st		d1
		bsr		laserSpan
		addq.w	#1,d3
		move.w	laserAge,d0
		and.w	#7,d0
		move.b	#$f7,d1
		ror.b	d0,d1
		bsr		laserSpan
		; --- the glow either side, a line above and one below: broken,
		;     the breaks racing along it, dense at the head, sparse behind
		move.w	d5,d2
		sub.w	#laserGlow,d2
		cmp.w	d4,d2
		bge.s	.g
		move.w	d4,d2
.g:
		move.w	d4,-(a7)
		move.w	d2,d4
		move.w	laserAge,d0
		add.w	d0,d0
		and.w	#7,d0
		move.b	#$cc,d1
		rol.b	d0,d1
		move.w	laserLine,d3
		subq.w	#1,d3
		bsr		laserSpan
		addq.w	#3,d3
		ror.b	#2,d1
		bsr		laserSpan
		move.w	(a7)+,d4
		move.w	d2,d5
		subq.w	#1,d5
		cmp.w	d4,d5
		blt.s	.flare
		move.w	laserAge,d0
		and.w	#7,d0
		move.b	#$81,d1
		ror.b	d0,d1
		subq.w	#3,d3
		bsr		laserSpan
		addq.w	#3,d3
		bsr		laserSpan
		; --- the head: a flare, a spike up and down that flickers
.flare:
		movem.w	(a7),d4/d5
		btst	#0,laserAge+1
		bne.s	.muzzle
		move.w	d5,d4
		subq.w	#1,d4
		cmp.w	#borderX,d4
		blt.s	.muzzle
		move.w	laserLine,d3
		subq.w	#3,d3
		st		d1
		moveq	#8-1,d2
.spike:
		bsr		laserSpan
		addq.w	#1,d3
		dbf		d2,.spike
		; --- the muzzle: a blast of light at the nose as it fires, the
		;     first frames, pulsing
.muzzle:
		move.w	laserAge,d0
		cmp.w	#laserFlashT,d0
		bhs.s	.embers
		lea		laserFlash(pc),a2
		btst	#0,d0
		beq.s	.mf
		lea		laserFlash2-laserFlash(a2),a2
.mf:
		move.w	laserLine,d3
		subq.w	#3,d3
		moveq	#8-1,d2
		st		d1
.mrow:
		moveq	#0,d0
		move.b	(a2)+,d0				; half its width on this row
		move.w	laserNose,d4
		addq.w	#3,d4
		move.w	d4,d5
		sub.w	d0,d4
		add.w	d0,d5
		cmp.w	#borderX,d4
		bge.s	.m0
		moveq	#borderX,d4
.m0:
		cmp.w	d4,d5
		blt.s	.mnext
		bsr		laserSpan
.mnext:
		addq.w	#1,d3
		dbf		d2,.mrow
.embers:
		movem.w	(a7)+,d4/d5
		cmp.w	#2,laserPhase			; (shedding while it is out)
		beq.s	.out
		move.w	laserAge,d0
		ext.l	d0
		divu	#laserEmberGap,d0
		swap	d0
		tst.w	d0
		bne.s	.out
		move.l	#laserPower,blastPow
		move.w	d5,d2
		sub.w	d4,d2					; its length
		moveq	#1-1,d7
.e:
		bsr		debrisRandom
		mulu	d2,d0
		swap	d0
		add.w	d4,d0
		move.w	d0,d3					; somewhere along it ...
		move.w	d0,debrisCx
		move.w	laserLine,d6
		move.w	d6,d0
		subq.w	#3,d0					; ... sinking
		move.w	d0,debrisCy
		bsr		addDebris
		dbf		d7,.e
.out:
		rts

;---------------------------------------------
; THE DEFENDER EXPLOSION (the laser's letters): a firework. the thing
; bursts into sparks - a ring of 12 and an inner one of 6, a little uneven
; - that fly out fast and slow down (drag), while the whole burst pops up
; and then falls, ever faster (gravity). three sizes, each its life. white
; hot, then under the bar orange, red (the ember plane), and over its last
; third the sparks twinkle out at random. only the scroller's buffer, so it
; never gets up onto the logo. cheap: no state per spark - where they are
; for every age is a table (fw.i, fwgen.py), the burst is a centre, a size,
; a pop and an age
latMax			= 10			; (long lives: more of them at once - 24 sparks
								; each: 10 is what a frame can draw)
latKick0		= 0				; the pop up: this + 0..latKickR (8.8 a frame) -
latKickR		= 0				; none now: the table has the fall (fwgen.py)
latGrav			= 0				; (the fall at run time, 8.8: off, see above)
latLife0		= 40			; life: this + 0..15 frames - a fast burst, then
								; the sparks hang glowing and sink as they burn out
				rsreset
lat_x:			rs.w	1
lat_line:		rs.w	1
lat_age:		rs.w	1
lat_life:		rs.b	1
lat_n:			rs.b	1			; the size, 0..2 (fwTab)
lat_kick:		rs.w	1			; the pop upwards, 8.8 a frame
lat_size:		rs.b	0			; 10

; a burst at debrisCx/debrisCy. keeps every register
latticeAdd:
		movem.l	d0-d1/a2,-(a7)
		move.w	latCount,d1
		cmp.w	#latMax,d1
		bhs.s	.out
		addq.w	#1,latCount
		mulu	#lat_size,d1
		lea		lattices,a2
		add.w	d1,a2
		move.w	debrisCx,lat_x(a2)
		move.w	debrisCy,lat_line(a2)
		clr.w	lat_age(a2)
		bsr		debrisRandom
		moveq	#0,d1
		move.b	d0,d1
		mulu	#fwVariants,d1			; which: 4 kinds x 3 sizes (fwgen.py)
		lsr.w	#8,d1
		move.b	d1,lat_n(a2)
		lsr.w	#8,d0
		and.w	#15,d0
		add.w	#latLife0,d0			; 40..55 frames (fwAges 56)
		move.b	d0,lat_life(a2)
		bsr		debrisRandom
		and.w	#latKickR,d0
		add.w	#latKick0,d0			; (none: the table falls)
		move.w	d0,lat_kick(a2)
.out:
		movem.l	(a7)+,d0-d1/a2
		rts

; every burst a frame on and drawn (from drawBlastFx: a0 = buffer, a1 =
; yTable). spark by spark: the table's offset + the centre (+ the fall),
; on the screen? a bset
drawLattice:
		move.w	latCount,d0
		beq		.out
		subq.w	#1,d0
		move.w	d0,latLeft
		lea		lattices,a2				; read
		move.l	a2,a3					; write
		lea		emberOffset(a0),a5		; the ember plane, same offsets
.lat:
		addq.w	#1,lat_age(a2)
		moveq	#0,d0
		move.b	lat_life(a2),d0
		cmp.w	lat_age(a2),d0
		bls		.drop
		move.l	(a2)+,(a3)+				; keep it (in place, packed)
		move.l	(a2)+,(a3)+
		move.w	(a2)+,(a3)+
		lea		-lat_size(a3),a4
		; how it looks: white the first half, then orange, the last quarter
		; red - under the bar (the ember plane), white over it. the last
		; third it twinkles: every spark has a 50:50 chance a frame
		moveq	#0,d3					; (no twinkle)
		move.w	lat_age(a4),d5			; (twinkling from half its life on: the
		move.w	d5,d4					; glow breaking up as it burns out)
		add.w	d4,d4					; age*2
		cmp.w	d0,d4					; life
		blo.s	.noTw
		bsr		debrisRandom
		move.l	d0,d3
		moveq	#0,d0
		move.b	lat_life(a4),d0
.noTw:
		move.w	d5,d4					; white hot the first quarter, orange to
		add.w	d4,d4					; 3/5, then red - glowing out a long time
		add.w	d4,d4					; age*4
		moveq	#0,d6
		cmp.w	d0,d4
		blo.s	.col
		moveq	#1,d6
		add.w	d5,d4					; age*5
		move.w	d0,d2
		add.w	d2,d2
		add.w	d0,d2					; life*3
		cmp.w	d2,d4
		blo.s	.col
		moveq	#2,d6
		move.w	lat_age(a4),d0			; red, the last glow: every other frame
		add.w	lat_x(a4),d0			; (bursts in turn) - it flickers out, and
		btst	#0,d0					; costs half
		bne		.next
.col:
		; --- the centre (the fall is in the table, fwgen.py): x less the
		;     border, so one unsigned compare clips it (the byte offset gets
		;     the border's 4 bytes back in the addressing), and its line as
		;     an offset - the table has dy * li, so no y table per spark, and
		;     one unsigned compare clips that too
		move.w	lat_x(a4),d4
		sub.w	#borderX,d4
		move.w	lat_line(a4),d5
		add.w	d5,d5
		move.w	(a1,d5.w),d5			; line * li
		; --- the table row: (variant * fwAges + age) * fwSparks * 4
		moveq	#0,d0
		move.b	lat_n(a4),d0
		mulu	#fwAges,d0
		add.w	lat_age(a4),d0
		mulu	#fwSparks*4,d0
		lea		fwTab,a6
		add.l	d0,a6
		moveq	#fwSparks-1,d7
		tst.w	d6
		bne.s	.cDot
		; --- white hot (the first quarter: no twinkle, no ember plane yet)
.wDot:
		move.w	(a6)+,d0
		add.w	d4,d0					; x - borderX
		move.w	(a6)+,d2
		cmp.w	#game_width-borderX,d0
		bhs.s	.wSkip
		add.w	d5,d2					; line * li
		cmp.w	#screenHeight*li,d2
		bhs.s	.wSkip
		move.w	d0,d1
		lsr.w	#3,d1					; its byte
		add.w	d1,d2
		not.w	d0						; its bit
		bset	d0,borderX/8(a0,d2.w)
.wSkip:
		dbf		d7,.wDot
		bra		.next
		; --- orange, then red - the ember plane (shown from the bar's top
		;     on), the second half twinkling
.cDot:
		move.w	(a6)+,d0
		add.w	d4,d0
		move.w	(a6)+,d2
		lsr.l	#1,d3					; twinkling: this one off now?
		bcs.s	.cSkip
		cmp.w	#game_width-borderX,d0
		bhs.s	.cSkip
		add.w	d5,d2
		cmp.w	#screenHeight*li,d2
		bhs.s	.cSkip
		move.w	d0,d1
		lsr.w	#3,d1
		add.w	d1,d2
		not.w	d0
		cmp.w	#emberFwTop*li,d2		; (a byte of x on it never makes a line)
		blo.s	.cWhite
		bset	d0,borderX/8(a5,d2.w)	; the ember plane ...
		cmp.w	#1,d6
		bne.s	.cSkip					; (red: that only)
.cWhite:
		bset	d0,borderX/8(a0,d2.w)	; ... and orange: plane 1 too
.cSkip:
		dbf		d7,.cDot
		bra.s	.next
.drop:
		lea		lat_size(a2),a2			; gone: not written back
		subq.w	#1,latCount
.next:
		subq.w	#1,latLeft
		bpl		.lat
.out:
		rts
	ifne	defWords
	ifeq	defWordsVec
;---------------------------------------------
; THE LOOSE WORDS (switches.i defWords): the TV is off, the "magnetic
; field" that held the running text on its row is gone - the words of the
; captain's message come in at all heights, in the scroller's own font
; (each row twice, as tall as on the bar), drifting a little, each word on
; its own. the Defender ship goes after them (asteroids.s seq_defwords),
; the laser takes them out (laserObj: defLetterAt, defLetterKill). they
; are drawn every frame with drawBlastFx's buffer, moved there too
				rsreset
fw_x:			rs.w	1			; left edge, 1/16 px
fw_y:			rs.w	1			; top line (game y), 1/16 px
fw_dy:			rs.w	1			; drift, 1/16 px a frame
fw_text:		rs.l	1
fw_len:			rs.w	1
fw_alive:		rs.w	1			; bit i: letter i still there
fw_id:			rs.w	1			; the word's number (defWantWord), 0: free
fw_size:		rs.b	0			; 16
fwMax			= 4
fwSpeed			= 18			; 1.125 px a frame to the left (1/16 px)
fwLane0			= 134			; top line: game y 134 ...
fwLaneH			= 84			; ... to 217
fwDrift			= 1				; up or down, at most (1/16 px a frame)
fwH				= 12			; 6 font rows, each twice

; the next word of fwWordTab, at the right edge, at a random height
defWordSpawn::
		movem.l	d0-d2/a0-a2,-(a7)
		move.l	fwWordPtr,a1
		tst.b	(a1)
		beq.s	.out
		lea		flyWords,a0
		moveq	#fwMax-1,d1
.find:
		tst.w	fw_id(a0)
		beq.s	.free
		lea		fw_size(a0),a0
		dbf		d1,.find
		bra.s	.out					; (no room: next time)
.free:
		move.l	a1,fw_text(a0)
		moveq	#0,d1
.len:
		tst.b	(a1)+
		beq.s	.lenDone
		addq.w	#1,d1
		bra.s	.len
.lenDone:
		move.l	a1,fwWordPtr
		move.w	d1,fw_len(a0)
		moveq	#1,d2
		lsl.l	d1,d2
		subq.w	#1,d2
		move.w	d2,fw_alive(a0)
		move.w	#game_width*16,fw_x(a0)
		jsr		getRandomNumber
		moveq	#0,d1
		move.b	d0,d1
		mulu	#fwLaneH,d1
		lsr.w	#8,d1
		add.w	#fwLane0,d1
		lsl.w	#4,d1
		move.w	d1,fw_y(a0)
		lsr.w	#8,d0
		and.w	#2*fwDrift,d0			; -1 or +1
		subq.w	#fwDrift,d0
		move.w	d0,fw_dy(a0)
		addq.w	#1,fwWordNo
		move.w	fwWordNo,fw_id(a0)
.out:
		movem.l	(a7)+,d0-d2/a0-a2
		rts

; -> d1 = letters still there (all words)
defWordsLeft::
		movem.l	d0/d2/a0,-(a7)
		moveq	#0,d1
		lea		flyWords,a0
		moveq	#fwMax-1,d2
.w:
		tst.w	fw_id(a0)
		beq.s	.n
		move.w	fw_alive(a0),d0
.b:
		beq.s	.n
		addq.w	#1,d1
		move.w	d0,-(a7)
		subq.w	#1,d0
		and.w	(a7)+,d0				; (the lowest bit off)
		bra.s	.b
.n:
		lea		fw_size(a0),a0
		dbf		d2,.w
		movem.l	(a7)+,d0/d2/a0
		rts

; -> Z clear while words are still to come
defWordsMore::
		move.l	a1,-(a7)
		move.l	fwWordPtr,a1
		tst.b	(a1)
		movem.l	(a7)+,a1				; (the flags stay)
		rts

; -> d0/d1 = the middle of the leftmost letter there is, d0 = -1 (N) if
; none; d2 non zero while its word is not all in yet
defWordsTarget::
		movem.l	d3-d7/a0,-(a7)
		move.w	#$7fff,d0
		moveq	#0,d1
		moveq	#0,d2
		lea		flyWords,a0
		moveq	#fwMax-1,d7
.w:
		tst.w	fw_id(a0)
		beq.s	.n
		move.w	fw_alive(a0),d5
		beq.s	.n
		moveq	#0,d6					; its first letter still there
.b:
		btst	d6,d5
		bne.s	.got
		addq.w	#1,d6
		bra.s	.b
.got:
		move.w	fw_x(a0),d3
		asr.w	#4,d3
		move.w	d6,d4
		lsl.w	#3,d4
		add.w	d4,d3
		addq.w	#4,d3					; its middle
		cmp.w	d0,d3
		bge.s	.n
		move.w	d3,d0
		move.w	fw_y(a0),d1
		asr.w	#4,d1
		addq.w	#fwH/2,d1
		move.w	fw_x(a0),d2				; all of the word in?
		asr.w	#4,d2
		move.w	fw_len(a0),d4
		lsl.w	#3,d4
		add.w	d4,d2
		cmp.w	#game_width,d2
		shi		d2
		ext.w	d2
.n:
		lea		fw_size(a0),a0
		dbf		d7,.w
		cmp.w	#$7fff,d0
		bne.s	.out
		moveq	#-1,d0
.out:
		movem.l	(a7)+,d3-d7/a0
		tst.w	d0
		rts

; for the laser: d0 = from x, d1 = the beam's game y, d2 = to x -> d0 =
; the middle of the leftmost letter in there that is near the line (-1, N
; set, if none), d1 its middle's y; defLetterKill takes it out. only the
; word defWantWord once one is hit. keeps d2-d7/a0-a6
defLetterAt::
		movem.l	d2-d7/a0,-(a7)
		move.w	#$7fff,d5				; best x
		lea		flyWords,a0
		moveq	#fwMax-1,d7
.w:
		tst.w	fw_id(a0)
		beq		.n
		move.w	defWantWord,d3
		beq.s	.any
		cmp.w	fw_id(a0),d3
		bne		.n
.any:
		move.w	fw_y(a0),d3				; near the line?
		asr.w	#4,d3
		addq.w	#fwH/2,d3
		sub.w	d1,d3
		bpl.s	.ay
		neg.w	d3
.ay:
		cmp.w	#defLane,d3
		bhi.s	.n
		move.w	fw_x(a0),d3
		asr.w	#4,d3
		addq.w	#4,d3					; letter 0's middle
		move.w	fw_alive(a0),d4
		moveq	#0,d6
.b:
		btst	d6,d4
		beq.s	.nb
		cmp.w	d0,d3
		blt.s	.nb
		cmp.w	d2,d3
		bgt.s	.n						; (further right: none of these)
		cmp.w	d5,d3
		bge.s	.n
		move.w	d3,d5
		move.l	a0,fwHitWord
		move.w	d6,fwHitLetter
		bra.s	.n						; (the first in the word is its leftmost)
.nb:
		addq.w	#8,d3
		addq.w	#1,d6
		cmp.w	fw_len(a0),d6
		blo.s	.b
.n:
		lea		fw_size(a0),a0
		dbf		d7,.w
		cmp.w	#$7fff,d5
		beq.s	.none
		move.w	d5,d0
		move.l	fwHitWord,a0
		move.w	fw_y(a0),d1
		asr.w	#4,d1
		addq.w	#fwH/2,d1
		bra.s	.out
.none:
		moveq	#-1,d0
		clr.l	fwHitWord
.out:
		movem.l	(a7)+,d2-d7/a0
		tst.w	d0
		rts

; -> d0/d1 = the middle of the letter defLetterAt found; it is gone, and the
; laser goes on along its word. keeps d2-d7/a0-a6
defLetterKill::
		movem.l	d2/a0,-(a7)
		move.l	fwHitWord,a0
		move.l	a0,d0
		beq.s	.out
		move.w	fwHitLetter,d2
		move.w	fw_alive(a0),d0
		bclr	d2,d0
		move.w	d0,fw_alive(a0)
		move.w	fw_id(a0),defWantWord
		move.w	fw_x(a0),d0
		asr.w	#4,d0
		lsl.w	#3,d2
		add.w	d2,d0
		addq.w	#4,d0
		move.w	fw_y(a0),d1
		asr.w	#4,d1
		addq.w	#fwH/2,d1
		clr.l	fwHitWord
.out:
		movem.l	(a7)+,d2/a0
		rts

; every frame, from drawBlastFx (a0 = buffer, a1 = yTable): the words on,
; the ones that got past the left edge gone, and drawn - a font row twice,
; shifted into place a byte pair at a time
drawFlyWords:
		lea		flyWords,a2
		moveq	#fwMax-1,d7
.w:
		tst.w	fw_id(a2)
		beq		.next
		sub.w	#fwSpeed,fw_x(a2)
		move.w	fw_dy(a2),d0
		add.w	d0,fw_y(a2)
		move.w	fw_alive(a2),d5
		bne.s	.live
		clr.w	fw_id(a2)				; all gone: the slot is free
		bra		.next
.live:
		move.w	fw_y(a2),d3				; its top as a scroller line
		asr.w	#4,d3
		sub.w	#topLines,d3
		bmi		.next					; (never up there - the lanes)
		cmp.w	#screenHeight-fwH,d3
		bhi		.next
		add.w	d3,d3
		move.w	(a1,d3.w),d3			; y * li
		lea		(a0,d3.w),a3			; its top line
		move.w	fw_x(a2),d4
		asr.w	#4,d4					; letter 0's x
		move.l	fw_text(a2),a4
		moveq	#0,d6					; letter
.l:
		btst	d6,d5
		beq.s	.nextL
		cmp.w	#8,d4					; past the left edge: gone
		bge.s	.in
		bclr	d6,d5
		bra.s	.nextL
.in:
		cmp.w	#game_width-8,d4		; still coming in over the right edge
		bgt.s	.nextL
		moveq	#0,d0
		move.b	(a4,d6.w),d0
		lea		rchartab,a5
		moveq	#0,d1
		move.b	(a5,d0.w),d1			; its glyph
		lea		char,a5
		add.w	d1,a5
		move.w	d4,d2
		lsr.w	#3,d2					; byte
		lea		(a3,d2.w),a6
		moveq	#7,d1
		and.w	d4,d1					; shift
		move.w	d7,-(a7)
		moveq	#6-1,d7
.row:
		moveq	#0,d0
		move.b	(a5),d0
		lsl.w	#8,d0
		lsr.w	d1,d0
		move.w	d0,d2
		lsr.w	#8,d2
		or.b	d2,(a6)
		or.b	d0,1(a6)
		or.b	d2,li(a6)
		or.b	d0,li+1(a6)
		lea		2*li(a6),a6
		lea		charStride(a5),a5
		dbf		d7,.row
		move.w	(a7)+,d7
.nextL:
		addq.w	#8,d4
		addq.w	#1,d6
		cmp.w	fw_len(a2),d6
		blo.s	.l
		move.w	d5,fw_alive(a2)
.next:
		lea		fw_size(a2),a2
		dbf		d7,.w
		rts

fwWordTab:
		dc.b	"CAPTAIN,",0,"WHAT",0,"THE",0,"FUCK",0,"HAPPENS",0,"HERE",0,0
		even
fwWordPtr:		dc.l	fwWordTab
fwHitWord:		dc.l	0
fwHitLetter:	dc.w	0
fwWordNo:		dc.w	0
defWantWord::	dc.w	0		; the laser's word, 0: any
flyWords:		ds.b	fw_size*fwMax
	endc
	endc

; colour 1 of the lines the beam can be on, as the text has it (tvList)
laserColsBack:
		lea		tvBeamTab,a3
		lea		tvBeamOrig,a2
		moveq	#8-1,d0
.c:
		move.l	(a3)+,a4
		move.w	(a2)+,(a4)
		dbf		d0,.c
		rts
tvBeamTab:
		dc.l	tvBD4,tvBD5,tvBeam0,tvBeam1,tvBeam2,tvBeam3,tvBDA,tvBDB
tvBeamOrig:
		dc.w	$0777,$0888,$0988,$0a99,$0baa,$0dcc,$0ddd,$0eee

; the scroller all shot (seq_deffire sets inkOff): colour 1 under the bar -
; the text's shading, which the ship and the letters get there too - goes
; over to the game's own colour, as above the bar. a step every inkStepT
; frames, once the last explosions and the beam are gone
inkStepT		= 3
inkColor		= $0eee			; (clist: the game area's colour 1)
inkFade:
		tst.b	inkOff
		beq.s	.out
		tst.w	latCount
		bne.s	.out
		tst.b	laserOn
		bne.s	.out
		tst.b	laserCol
		bne.s	.out
		subq.w	#1,inkTick
		bpl.s	.out
		move.w	#inkStepT-1,inkTick
		move.w	tvInkCount,d7
		beq.s	.done
		subq.w	#1,d7
		lea		tvInkAddr,a2
		moveq	#1,d5					; all there?
.c:
		move.l	(a2)+,a3
		move.w	(a3),d0
		move.w	#inkColor,d1
		cmp.w	d0,d1
		beq.s	.there
		moveq	#0,d5
		bsr		colorStepTo
		move.w	d6,(a3)
.there:
		dbf		d7,.c
		tst.w	d5
		beq.s	.out
.done:
		sf		inkOff
		lea		tvBeamOrig,a2			; (and so it stays)
		moveq	#8-1,d7
.b:
		move.w	#inkColor,(a2)+
		dbf		d7,.b
.out:
		rts
inkOff::		dc.b	0
				even
inkTick:		dc.w	0
tvInkCount:		dc.w	0
tvInkAddr:		ds.l	128

; one line d3 of the streak from x d4 to d5, d1.b the bits of each byte
; that are lit. keeps d1-d5
laserSpan:
		movem.w	d4-d5,-(a7)
		cmp.w	#screenHeight,d3
		bhs.s	.out
		move.w	d3,d0
		add.w	d0,d0
		move.w	(a1,d0.w),d0
		lea		(a0,d0.w),a4			; the line
		moveq	#7,d6
		and.w	d4,d6
		move.b	laserLMask(pc,d6.w),d6	; first byte's bits
		moveq	#7,d7
		and.w	d5,d7
		move.b	laserRMask(pc,d7.w),d7	; last byte's
		lsr.w	#3,d4
		lsr.w	#3,d5
		cmp.w	d4,d5
		beq.s	.one
		and.b	d1,d6
		or.b	d6,(a4,d4.w)
		move.w	d5,d0					; the bytes between
		sub.w	d4,d0
		subq.w	#2,d0
		bmi.s	.last
		lea		1(a4,d4.w),a5
.mid:
		or.b	d1,(a5)+
		dbf		d0,.mid
.last:
		and.b	d1,d7
		or.b	d7,(a4,d5.w)
		bra.s	.out
.one:
		and.b	d7,d6
		and.b	d1,d6
		or.b	d6,(a4,d5.w)
.out:
		movem.w	(a7)+,d4-d5
		rts
; the beam's colours, round and round: white hot, yellow, orange, red
laserHot:
		dc.w	$0fff,$0ffd,$0ffa,$0fe7,$0fd5,$0fb4,$0f93,$0f72
		dc.w	$0e52,$0f72,$0f93,$0fb4,$0fd5,$0fe7,$0ffa,$0ffd
; the muzzle flash, half widths of its 8 rows, two of them in turn
laserFlash:	dc.b	1,3,6,9,9,6,3,1
laserFlash2:	dc.b	0,2,4,6,6,4,2,0
laserLMask:	dc.b	$ff,$7f,$3f,$1f,$0f,$07,$03,$01
laserRMask:	dc.b	$80,$c0,$e0,$f0,$f8,$fc,$fe,$ff
; the dots it sheds: no sparks, no ring, a gentle sinking (blastPowers'
; layout)
laserPower:
		dc.b	0,0,0,0,0,1
		dc.w	$0400,$0c00

;---------------------------------------------
; THE BAR GOES WRONG (the Defender ending: seq_defgo sets barFlickOn). the
; bar's background colours - every $0180 move of the bar, barColorAddr -
; are put back from barColorsTarget every frame through a fault: brighter
; and darker in fits, now and then a dropout or a flash, and every so often
; the colour itself goes: red and blue swapped, the guns turned round,
; the colour lost (green only), no green, a negative, noise on each line.
; it builds up over barFlickRamp frames, and tvStart puts it all back
barFlickRamp	= 150
barFlickOdds	= 20			; dropouts and flashes: out of 256, at the worst
; (switches.i tvLate) flickPhase 1: it dies - over barDieT frames fewer and
; fewer changes, darker and darker, the text with it, then 2: all black.
; 3: it has risen again - dark (a quarter), faulty, a short bright flash
; now and then, the text barInkLift sixteenths above the bar's brightness
barDieT			= 160
barInkLift		= 9
barReviveFlash	= 63			; mask: a bright frame 1 in 64

barFlicker:
		tst.b	barFlickOn
		beq		.out
		tst.b	tvState
		bne		.out
		tst.w	blastsDone				; a frame with a blast or its sparks and
		bne		.out					; rings is heavy: it holds its colours then
	ifne	tvLate
		cmp.b	#2,flickPhase			; dead: dark, nothing to do
		beq		.out
		cmp.b	#1,flickPhase			; dying: fewer and fewer changes, darker
		bne.s	.notDying				; and darker, then dark
		addq.w	#1,flickDieT
		move.w	flickDieT,d0
		cmp.w	#barDieT,d0
		blo.s	.dGo
		bsr		barBlack
		move.b	#2,flickPhase
		bra		.out
.dGo:
		subq.w	#1,flickGapT
		bpl		.out					; (holds what it shows)
		lsr.w	#4,d0
		move.w	d0,flickGapT			; 0 .. 9 frames between changes
.notDying:
	endc
		addq.w	#1,flickT
		; --- how bad it is by now: 0..256
		move.w	flickT,d6
		cmp.w	#barFlickRamp,d6
		blo.s	.r
		move.w	#barFlickRamp,d6
.r:
		lsl.w	#8,d6
		ext.l	d6
		divu	#barFlickRamp,d6
		; --- the brightness, 16 = as it is: a swell 12..19, a jitter on
		;     it - and dropouts and flashes, a frame or two
		move.w	flickT,d5
		lsr.w	#2,d5
		and.w	#15,d5
		cmp.w	#8,d5
		blo.s	.sw
		neg.w	d5
		add.w	#15,d5
.sw:
		add.w	#12,d5
		bsr		debrisRandom
		move.w	d0,d1
		and.w	#7,d1
		subq.w	#3,d1
		add.w	d1,d1
		muls	d6,d1
		asr.l	#8,d1
		add.w	d1,d5
		tst.w	flickHold
		beq.s	.free
		subq.w	#1,flickHold
		move.w	flickHoldB,d5
		bra.s	.bright
.free:
		move.w	d0,d1
		lsr.w	#8,d1
		move.w	d6,d2
		mulu	#barFlickOdds,d2
		lsr.w	#8,d2
		cmp.w	d2,d1
		bhs.s	.bright
		move.w	#3,flickHoldB			; a dropout ...
		btst	#4,d0
		beq.s	.drop
		move.w	#30,flickHoldB			; ... or a flash
.drop:
		move.w	#1,flickHold
		move.w	flickHoldB,d5
.bright:
		tst.w	d5
		bpl.s	.b0
		moveq	#0,d5
.b0:
	ifne	tvLate
		move.w	d5,flickInkB			; (the text's own, see .ink)
		cmp.b	#1,flickPhase
		bne.s	.notFade
		move.w	#barDieT,d1				; dying: it all fades to black
		sub.w	flickDieT,d1
		mulu	d1,d5
		divu	#barDieT,d5
		move.w	d5,flickInkB
		bra.s	.phased
.notFade:
		cmp.b	#3,flickPhase
		bne.s	.phased
		lsr.w	#2,d5					; risen again: dark, a quarter (a flash
		move.w	d5,d1					; only 7) - the text dim but there - and
		add.w	#barInkLift,d1			; now and then, a frame long, bright
		move.w	d1,flickInkB
		move.l	d0,-(a7)
		bsr		debrisRandom
		and.w	#barReviveFlash,d0
		bne.s	.noFl
		moveq	#13,d5
.noFl:
		move.l	(a7)+,d0
.phased:
	endc
		; --- the colour fault: another one every 20..83 frames, once it is
		;     bad enough
		subq.w	#1,flickModeT
		bpl.s	.mode
		swap	d0
		move.w	d0,d1
		and.w	#63,d1
		add.w	#20,d1
		move.w	d1,flickModeT
		lsr.w	#6,d0
		and.w	#7,d0
		cmp.w	#7,d0
		blo.s	.m
		moveq	#0,d0
.m:
		cmp.w	#100,d6
		bhs.s	.setMode
		moveq	#0,d0
.setMode:
		move.w	d0,flickMode
.mode:
		; --- the brightness as a table, 0..15 -> * d5/16, 0..15
		lea		flickLut,a3
		moveq	#0,d1
		moveq	#16-1,d2
.lut:
		move.w	d1,d0
		mulu	d5,d0
		lsr.w	#4,d0
		cmp.w	#15,d0
		bls.s	.l0
		moveq	#15,d0
.l0:
		move.b	d0,(a3)+
		addq.w	#1,d1
		dbf		d2,.lut
		lea		flickLut,a3
		; --- every colour of the bar through it (black stays black: the
		;     last one is the black under the bar)
		move.w	barColorCount,d7
		beq		.out
		subq.w	#1,d7
		lea		barColorAddr,a1
		lea		barColorsTarget,a2
		move.w	flickMode,d4
.c:
		move.l	(a1)+,a0
		move.w	(a2)+,d0
		beq.s	.set
		moveq	#15,d3					; b
		and.w	d0,d3
		lsr.w	#4,d0
		moveq	#15,d2					; g
		and.w	d0,d2
		lsr.w	#4,d0
		moveq	#15,d1					; r
		and.w	d0,d1
		add.w	d4,d4
		move.w	.fault(pc,d4.w),d0
		lsr.w	#1,d4
		jmp		.fault(pc,d0.w)
.fault:
		dc.w	.lit-.fault,.f1-.fault,.f2-.fault,.f3-.fault
		dc.w	.f4-.fault,.f5-.fault,.f6-.fault
.f1:
		exg		d1,d3					; red and blue swapped
		bra.s	.lit
.f2:
		move.w	d1,d0					; the guns turned round
		move.w	d2,d1
		move.w	d3,d2
		move.w	d0,d3
		bra.s	.lit
.f3:
		cmp.w	d1,d2					; the colour lost: green only
		bhs.s	.g1
		move.w	d1,d2
.g1:
		cmp.w	d3,d2
		bhs.s	.g2
		move.w	d3,d2
.g2:
		moveq	#0,d1
		moveq	#0,d3
		bra.s	.lit
.f4:
		moveq	#0,d2					; no green
		bra.s	.lit
.f5:
		eor.w	#15,d1					; a negative, dim
		lsr.w	#1,d1
		eor.w	#15,d2
		lsr.w	#1,d2
		eor.w	#15,d3
		lsr.w	#1,d3
		bra.s	.lit
.f6:
		bsr		debrisRandom			; noise on the line
		moveq	#1,d6
		and.w	d0,d6
		add.w	d6,d1
		lsr.w	#3,d0
		moveq	#1,d6
		and.w	d0,d6
		add.w	d6,d2
		lsr.w	#3,d0
		moveq	#1,d6
		and.w	d0,d6
		add.w	d6,d3
		cmp.w	#15,d1
		bls.s	.n1
		moveq	#15,d1
.n1:
		cmp.w	#15,d2
		bls.s	.n2
		moveq	#15,d2
.n2:
		cmp.w	#15,d3
		bls.s	.lit
		moveq	#15,d3
.lit:
		moveq	#0,d0					; the brightness, and back together
		move.b	(a3,d1.w),d0
		lsl.w	#4,d0
		or.b	(a3,d2.w),d0
		lsl.w	#4,d0
		or.b	(a3,d3.w),d0
.set:
		move.w	d0,2(a0)
		dbf		d7,.c
	ifne	tvLate
		; --- the text's colour (colour 1 of the bar) with it, no fault, at its
		;     own brightness, once it is dying (before, it is left alone)
		tst.b	flickPhase
		beq.s	.out
		move.w	flickInkB,d5
		cmp.w	#16,d5
		bls.s	.ib
		moveq	#16,d5
.ib:
		lea		flickLut,a3
		moveq	#0,d1
		moveq	#16-1,d2
.ilut:
		move.w	d1,d0
		mulu	d5,d0
		lsr.w	#4,d0
		cmp.w	#15,d0
		bls.s	.il0
		moveq	#15,d0
.il0:
		move.b	d0,(a3)+
		addq.w	#1,d1
		dbf		d2,.ilut
		lea		flickLut,a3
		move.w	barInkCount,d7
		beq.s	.out
		subq.w	#1,d7
		lea		barInkAddr,a1
		lea		barInkTarget,a2
.ic:
		move.l	(a1)+,a0
		move.w	(a2)+,d0
		moveq	#15,d3
		and.w	d0,d3
		lsr.w	#4,d0
		moveq	#15,d2
		and.w	d0,d2
		lsr.w	#4,d0
		and.w	#15,d0
		move.b	(a3,d0.w),d0
		lsl.w	#4,d0
		or.b	(a3,d2.w),d0
		lsl.w	#4,d0
		or.b	(a3,d3.w),d0
		move.w	d0,2(a0)
		dbf		d7,.ic
	endc
.out:
		rts
	ifne	tvLate
; (asteroids.s seq_defgo) the flicker dies: slower and darker, then dark
barDie::
		clr.w	flickDieT
		clr.w	flickGapT
		move.b	#1,flickPhase
		rts
; (seq_defgo) ... and five seconds later it rises again
barRevive::
		move.w	#$0112,barShadow+2
		move.b	#3,flickPhase
		rts
; the bar and its text all black: the TV is off - it seems (barFlicker)
barBlack:
		clr.w	barShadow+2			; (the text's shadow too)
		move.w	barColorCount,d7
		beq.s	.ink
		subq.w	#1,d7
		lea		barColorAddr,a1
.c:
		move.l	(a1)+,a0
		clr.w	2(a0)
		dbf		d7,.c
.ink:
		move.w	barInkCount,d7
		beq.s	.out
		subq.w	#1,d7
		lea		barInkAddr,a1
.i:
		move.l	(a1)+,a0
		clr.w	2(a0)
		dbf		d7,.i
.out:
		rts
	endc
; the bar's colours as they should be, and the flicker off (tvStart)
barFlickStop:
		tst.b	barFlickOn
		beq.s	.out
		sf		barFlickOn
		move.w	barColorCount,d7
		beq.s	.out
		subq.w	#1,d7
		lea		barColorAddr,a1
		lea		barColorsTarget,a2
.c:
		move.l	(a1)+,a0
		move.w	(a2)+,2(a0)
		dbf		d7,.c
	ifne	tvLate
		move.w	barInkCount,d7			; (and the text's colour)
		beq.s	.out
		subq.w	#1,d7
		lea		barInkAddr,a1
		lea		barInkTarget,a2
.i:
		move.l	(a1)+,a0
		move.w	(a2)+,2(a0)
		dbf		d7,.i
	endc
.out:
		rts

; once a frame, after postEffect (seqShotScan): held over hits, the blast,
; the letters it set off, the laser
textFrame::
		bsr		textShotBegin
		bsr		torpedoStep
		bsr		laserStep
		bra		detStep

; the muzzle flash, and the blasts of the letters the power blast takes:
; fat (blastPowers' layout)
flashPower:
		dc.b	10,24,3,4,2,4
		dc.w	$1000,$1000
chainPower:
		dc.b	10,48,4,6,2,4
		dc.w	$3800,$2800
;-------
; roll the power of the next blast -> a3 = its blastPowers entry, and
; debrisEvery, blastPow set from it. uses d0
pickPower:
		move.b	bigBlast,d0				; the power blast's letters (1): one of
		beq.s	.normal					; the three fat ones, at random - the
		sf		bigBlast				; laser's (3): the two lighter ones
		cmp.b	#3,d0
		bne.s	.fat
		bsr		debrisRandom
		lea		chainPower,a3
		and.w	#3,d0					; (1 in 4 medium)
		bne.s	.set
		lea		blastPowers+bp_len,a3
		bra.s	.set
.fat:
		bsr		debrisRandom
		lea		chainPower,a3
		and.w	#3,d0
		beq.s	.set
		lea		blastPowers+bp_len,a3	; (medium)
		cmp.w	#1,d0
		beq.s	.set
		cmp.w	#sparkMax-bigSparkRoom,sparkNum
		bhi.s	.set
		lea		bp_len(a3),a3			; (big)
		bra.s	.set
.normal:
		bsr		debrisRandom
		lea		blastPowers,a3
		and.w	#$ff,d0
		cmp.w	#bigOdds,d0
		blo.s	.big
		cmp.w	#bigOdds+medOdds,d0
		blo.s	.med
		bra.s	.set
.big:
		cmp.w	#sparkMax-bigSparkRoom,sparkNum
		bhi.s	.med					; no room for its sparks
		lea		2*bp_len(a3),a3
		bra.s	.set
.med:
		lea		bp_len(a3),a3
.set:
		move.l	a3,blastPow
		move.b	bp_every(a3),debrisEvery
		move.b	bp_every(a3),debrisSkip
		rts

;-------
; one piece of a blast: a dot at x d3, scroller line d6, flying out from
; debrisCx/debrisCy. keeps every register
addDebris:
		movem.l	d0-d2/a3/a5,-(a7)
		move.w	activeCount,d0
		cmp.w	#pointsPool,d0
		bhs		.full
		move.w	d0,d1
		addq.w	#1,d0
		move.w	d0,activeCount
		bsr		debrisRandom
		lsl.w	#4,d1					; * point_len
		lea		points,a5
		add.w	d1,a5
		moveq	#0,d1
		move.w	d3,d1
		sub.w	#borderX,d1				; dots are kept minus borderX
		swap	d1
		move.l	d1,(a5)+				; x
		moveq	#0,d1
		move.w	d6,d1
		swap	d1
		move.b	d0,d1					; a random fraction - drawPoints picks
		move.l	d1,(a5)+				; the ember group from it. y
		move.l	blastPow,a3
		; --- x speed
		move.w	d3,d1
		sub.w	debrisCx,d1
		muls	bp_spreadX(a3),d1
		sub.l	#$10000,d1				; the scroll's -1 pixel a frame
		move.w	d0,d2
		lsr.w	#2,d2
		and.w	#$3fff,d2
		sub.w	#$2000,d2				; noise, -1/8..1/8
		ext.l	d2
		add.l	d2,d1
		; near the right edge not so fast to the right that it goes off it
		; still white: it can take ~70 frames to sink out of the bar, and
		; accelX alone takes it ~60 px to the right in that time
		move.w	#game_width-64,d2
		sub.w	d3,d2
		ext.l	d2
		asl.l	#8,d2
		asl.l	#2,d2					; room / 64, 16.16
		cmp.l	d2,d1
		ble.s	.vxOk
		move.l	d2,d1
.vxOk:
		move.w	d3,d2					; and the same to the left
		sub.w	#borderX+4,d2
		ext.l	d2
		asl.l	#8,d2
		asl.l	#3,d2
		neg.l	d2
		cmp.l	d2,d1
		bge.s	.vxOk2
		move.l	d2,d1
.vxOk2:
		and.w	#$fe00,d1				; glow step rides in the low byte, see
		or.w	#$0100,d1				; drawPoints - and bit 8 says: a piece of
		move.l	d1,(a5)+				; a blast (it glows out sooner)
		; --- y speed
		move.w	d6,d1
		sub.w	debrisCy,d1
		cmp.w	#debrisMaxDy,d1
		ble.s	.dyLo
		moveq	#debrisMaxDy,d1
.dyLo:
		cmp.w	#-debrisMaxDy,d1
		bge.s	.dyHi
		moveq	#-debrisMaxDy,d1
.dyHi:
		muls	bp_spreadY(a3),d1
		add.l	#debrisDrop,d1
		swap	d0
		and.l	#$7fff,d0
		sub.l	#$2000,d0				; noise, -1/8..3/8
		add.l	d0,d1
		cmp.l	#debrisMinVy,d1			; not up into the logo: there it would
		bge.s	.vyOk					; stay white (it only glows below the
		move.l	#debrisMinVy,d1			; bar) and drift off the screen so
.vyOk:
		move.b	#$80+debrisHot,d1		; life rides in the low byte
		move.l	d1,(a5)
.full:
		movem.l	(a7)+,d0-d2/a3/a5
		rts

; -> d0 = a random long out of debrisRndTab, ~40 cycles where
; getRandomNumber takes ~180. keeps everything else
debrisRandom::
		move.l	a5,-(a7)
		move.w	debrisRnd,d0
		addq.w	#4,d0
		and.w	#(debrisRndCount-1)*4,d0
		move.w	d0,debrisRnd
		lea		debrisRndTab,a5
		move.l	(a5,d0.w),d0
		move.l	(a7)+,a5
		rts

;-------
; the blast at debrisCx/debrisCy with the power in blastPow: a shock ring
; and the sparks. keeps every register
blastFx:
		movem.l	d0-d7/a0-a3,-(a7)
		move.l	blastPow,a3
		move.w	debrisCx,d5
		move.w	debrisCy,d6
		; --- the shock rings: one, two or three, two frames apart, each
		;     of its own kind
		moveq	#0,d1
		move.b	bp_rings(a3),d1
		subq.w	#1,d1
		moveq	#0,d2					; the first one's age (later ones
.ring:									; start below 0 and wait)
		move.w	ringCount,d0
		cmp.w	#ringMax,d0
		bhs.s	.noRing
		addq.w	#1,ringCount
		lsl.w	#3,d0					; * ring_len
		lea		rings,a0
		add.w	d0,a0
		move.w	d5,(a0)+				; x
		move.b	d6,(a0)+				; line
		move.b	d2,(a0)+				; age
		bsr		debrisRandom
		and.w	#7,d0
		cmp.w	#ringKinds,d0
		blo.s	.kind
		moveq	#0,d0					; the round one the most often
.kind:
		move.b	d0,(a0)+
		move.b	bp_ringStep(a3),(a0)+
		move.b	bp_ringFrames(a3),(a0)+
		subq.w	#2,d2
		dbf		d1,.ring
.noRing:
		; --- the way the sparks go: 0 all round, 1 on along the shot,
		;     2 back at the shooter, 3 up like a fountain
		bsr		debrisRandom
		and.w	#3,d0
		move.w	d0,d4
		beq.s	.dirDone
		cmp.w	#3,d4
		bne.s	.shotDir
		moveq	#12,d4					; straight up (sparkDir 12)
		bra.s	.dirSet
.shotDir:
		; the sparkDir entry nearest the shot's direction
		lea		sparkDir,a1
		moveq	#0,d1					; index
		moveq	#0,d2					; best so far
		move.l	#$80000000,d3			; ... and its dot product
.dir:
		move.w	(a1)+,d0
		muls	blastVx,d0
		move.w	(a1)+,d7
		muls	blastVy,d7
		add.l	d7,d0
		cmp.l	d3,d0
		ble.s	.notBest
		move.l	d0,d3
		move.w	d1,d2
.notBest:
		addq.w	#1,d1
		cmp.w	#16,d1
		blo.s	.dir
		cmp.w	#2,d4
		bne.s	.along
		addq.w	#8,d2					; back the other way
.along:
		move.w	d2,d4
.dirSet:
		or.w	#$100,d4				; a cone round d4
.dirDone:
		; --- the sparks, each at its own speed
		move.w	sparkNum,d7
		move.w	d7,d0
		mulu	#spark_len,d0
		lea		sparks,a0
		add.l	d0,a0
		moveq	#0,d3
		move.b	bp_sparks(a3),d3
		subq.w	#1,d3
.spark:
		cmp.w	#sparkMax,d7
		bhs		.full
		addq.w	#1,d7
		bsr		debrisRandom
		move.w	d0,d1
		btst	#8,d4
		bne.s	.cone
		and.w	#15,d1					; anywhere round
		bra.s	.dirOk
.cone:
		and.w	#3,d1					; +-2 steps (45 degrees) round d4
		subq.w	#2,d1
		add.w	d4,d1
		and.w	#15,d1
.dirOk:
		lsl.w	#2,d1
		lea		sparkDir,a1
		add.w	d1,a1
		lsr.w	#4,d0
		moveq	#31,d2
		and.w	d0,d2
		moveq	#0,d1
		move.b	bp_speed(a3),d1
		add.w	d1,d2					; 1/16 pixel a frame
		moveq	#0,d1
		move.w	d5,d1
		swap	d1
		move.l	d1,(a0)+				; x, absolute here (not minus borderX)
		moveq	#0,d1
		move.w	d6,d1
		swap	d1
		move.l	d1,(a0)+				; y
		move.w	(a1)+,d1				; cos * 256
		muls	d2,d1					; * speed/16 -> 1/4096 pixel
		asl.l	#4,d1					; -> 16.16
		sub.l	#$8000,d1				; carried along by the text a little
		move.l	d1,(a0)+
		move.w	(a1),d1					; sin * 256
		muls	d2,d1
		asl.l	#4,d1
		move.l	d1,(a0)+
		swap	d0
		and.w	#7,d0
		add.w	#sparkLife,d0
		move.w	d0,(a0)+				; life
		dbf		d3,.spark
.full:
		move.w	d7,sparkNum
		movem.l	(a7)+,d0-d7/a0-a3
		rts

;-------
; sparks and shock rings, every frame, into the scroller buffer (plane 1)
drawBlastFx:
		move.l	screenlocScroller,a0
		lea		yTable,a1
		; --- sparks. moved, braked, plotted, the dead ones dropped
		move.w	sparkNum,d7
		beq		.noSparks
		subq.w	#1,d7
		lea		sparks,a4				; write
		move.l	a4,a5					; read
.sLoop:
		movem.l	(a5)+,d0-d3
		move.w	(a5)+,d4
		subq.w	#1,d4
		bmi.s	.sKill
		add.l	d2,d0
		add.l	d3,d1
		move.l	d2,d5					; air brake
		asr.l	#sparkDrag,d5
		sub.l	d5,d2
		move.l	d3,d5
		asr.l	#sparkDrag,d5
		sub.l	d5,d3
		add.l	#sparkFall,d3
		cmp.l	#game_width<<16,d0		; off the right
		bhs.s	.sKill
		cmp.l	#borderX<<16,d0			; behind the left border
		blo.s	.sKill
		cmp.l	#screenHeight<<16,d1	; above or below the buffer
		bhs.s	.sKill
		movem.l	d0-d3,(a4)
		move.w	d4,16(a4)
		lea		spark_len(a4),a4
		swap	d0
		swap	d1
		add.w	d1,d1
		move.w	(a1,d1.w),d5
		move.w	d0,d6
		lsr.w	#3,d0
		not.w	d6
		add.w	d0,d5
		bset	d6,(a0,d5.w)
.sKill:
		dbf		d7,.sLoop
		move.l	a4,d0
		sub.l	#sparks,d0
		divu	#spark_len,d0
		move.w	d0,sparkNum
.noSparks:
		; --- rings, one radius a frame
		move.w	ringCount,d7
		beq		.noRings
		subq.w	#1,d7
		lea		rings,a4				; write
		move.l	a4,a5					; read
.rLoop:
		movem.w	(a5)+,d2-d5				; x, line:age, kind:step, frames:pad
		move.b	d3,d0
		ext.w	d0						; age, below 0 while it waits
		lsr.w	#8,d3					; line
		and.w	#$ff,d3
		move.w	d5,d1
		lsr.w	#8,d1					; frames
		and.w	#$ff,d1
		cmp.w	d1,d0
		bge		.rKill
		move.w	d2,(a4)+
		move.w	d3,d1
		lsl.w	#8,d1
		move.b	d0,d1
		addq.b	#1,d1
		move.w	d1,(a4)+				; line, age + 1
		move.w	d4,(a4)+
		move.w	d5,(a4)+
		tst.w	d0
		bmi		.rWait					; not yet
		; radius = 2 + age * step
		moveq	#0,d1
		move.b	d4,d1					; step
		mulu	d0,d1
		addq.w	#2,d1
		cmp.w	#24,d1
		bls.s	.rOk
		moveq	#24,d1
.rOk:
		lsr.w	#8,d4					; kind
		move.w	d4,ringKind
		move.w	d7,-(a7)
		moveq	#2,d6					; every point
		cmp.w	#1,d4
		beq.s	.flat
		cmp.w	#2,d4
		beq.s	.tall
		cmp.w	#3,d4
		beq.s	.star
		; --- round, and the double one: round with a second one inside
		bsr		ringRound
		cmp.w	#4,ringKind
		bne.s	.rNext
		subq.w	#6,d1
		bmi.s	.rNext
		bsr		ringRound
		bra.s	.rNext
.flat:
		move.w	d1,d4
		lsr.w	#1,d4
		add.w	d1,d4					; rx = 3/2 r
		cmp.w	#24,d4
		bls.s	.fOk
		moveq	#24,d4
.fOk:
		move.w	d1,d5
		lsr.w	#2,d5					; ry = r/4
		bsr		ringDraw
		bra.s	.rNext
.tall:
		move.w	d1,d4
		lsr.w	#1,d4					; rx = r/2
		move.w	d1,d5					; ry = r
		bsr		ringDraw
		bra.s	.rNext
.star:
		moveq	#4,d6					; every other direction ...
		bsr		ringRound
		subq.w	#3,d1					; ... twice, a ray each
		bmi.s	.rNext
		bsr		ringRound
.rNext:
		move.w	(a7)+,d7
.rWait:
		dbf		d7,.rLoop
		bra.s	.rDone
.rKill:
		dbf		d7,.rLoop
.rDone:
		move.l	a4,d0
		sub.l	#rings,d0
		lsr.w	#3,d0					; / ring_len
		move.w	d0,ringCount
.noRings:
	ifne	defWords
	ifeq	defWordsVec
		bsr		drawFlyWords			; the loose words (a0/a1 stay)
	endc
	endc
		bsr		drawTorpedo
		bsr		drawLaser
		bsr		drawLattice
		lea		$dff000,a6
		rts

; a round ring (a little flat) of radius d1. keeps d1
ringRound:
		move.w	d1,-(a7)
		move.w	d1,d4
		move.w	d1,d5
		lsr.w	#2,d5
		neg.w	d5
		add.w	d1,d5					; ry = 3/4 r
		bsr.s	ringDraw
		move.w	(a7)+,d1
		rts

; one ring: centre d2/d3, radii d4/d5 (0..24), d6 = 2 for all 16 points
; of ringPts, 4 for every other. a0 = buffer, a1 = yTable. uses d0/d1,
; keeps d2-d7
ringDraw:
		movem.l	d4-d7/a2-a3,-(a7)
		cmp.w	#4,ringCount			; a lot of rings at once: 8 points
		bhs.s	.thin					; each (the frame time)
		cmp.w	#10,d4					; a small ring: 8 points are plenty
		bhi.s	.big
.thin:
		cmp.w	#4,d6
		bhs.s	.big
		moveq	#4,d6
.big:
		lea		ringPts,a2
		lsl.w	#5,d4
		add.w	d4,a2					; x offsets from line rx
		lea		ringPts+1,a3
		lsl.w	#5,d5
		add.w	d5,a3					; y offsets from line ry
		moveq	#0,d7
.p:
		move.b	(a2,d7.w),d0
		ext.w	d0
		add.w	d2,d0					; x
		move.b	(a3,d7.w),d1
		ext.w	d1
		add.w	d3,d1					; line
		cmp.w	#game_width,d0
		bhs.s	.no
		cmp.w	#borderX,d0
		blo.s	.no
		cmp.w	#screenHeight,d1
		bhs.s	.no
		add.w	d1,d1
		move.w	(a1,d1.w),d5
		move.w	d0,d4
		lsr.w	#3,d0
		not.w	d4
		add.w	d0,d5
		bset	d4,(a0,d5.w)
.no:
		add.w	d6,d7
		cmp.w	#32,d7
		blo.s	.p
		movem.l	(a7)+,d4-d7/a2-a3
		rts

; 16 directions round the circle, cos and sin * 256 (y down: 4 is down,
; 12 is up)
sparkDir:
		dc.w	251,50,213,142,142,213,50,251,-50,251,-142,213,-213,142,-251,50
		dc.w	-251,-50,-213,-142,-142,-213,-50,-251,50,-251,142,-213,213,-142,251,-50

; ringPts: radius 0..24, 16 directions round the circle (as sparkDir),
; x and y offset bytes. a ring with radii rx/ry takes x from line rx
; and y from line ry, so the same table makes ellipses
ringPts:
		dc.b	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
		dc.b	1,0,1,1,1,1,0,1,0,1,-1,1,-1,1,-1,0,-1,0,-1,-1,-1,-1,0,-1,0,-1,1,-1,1,-1,1,0
		dc.b	2,0,2,1,1,2,0,2,0,2,-1,2,-2,1,-2,0,-2,0,-2,-1,-1,-2,0,-2,0,-2,1,-2,2,-1,2,0
		dc.b	3,1,2,2,2,2,1,3,-1,3,-2,2,-2,2,-3,1,-3,-1,-2,-2,-2,-2,-1,-3,1,-3,2,-2,2,-2,3,-1
		dc.b	4,1,3,2,2,3,1,4,-1,4,-2,3,-3,2,-4,1,-4,-1,-3,-2,-2,-3,-1,-4,1,-4,2,-3,3,-2,4,-1
		dc.b	5,1,4,3,3,4,1,5,-1,5,-3,4,-4,3,-5,1,-5,-1,-4,-3,-3,-4,-1,-5,1,-5,3,-4,4,-3,5,-1
		dc.b	6,1,5,3,3,5,1,6,-1,6,-3,5,-5,3,-6,1,-6,-1,-5,-3,-3,-5,-1,-6,1,-6,3,-5,5,-3,6,-1
		dc.b	7,1,6,4,4,6,1,7,-1,7,-4,6,-6,4,-7,1,-7,-1,-6,-4,-4,-6,-1,-7,1,-7,4,-6,6,-4,7,-1
		dc.b	8,2,7,4,4,7,2,8,-2,8,-4,7,-7,4,-8,2,-8,-2,-7,-4,-4,-7,-2,-8,2,-8,4,-7,7,-4,8,-2
		dc.b	9,2,7,5,5,7,2,9,-2,9,-5,7,-7,5,-9,2,-9,-2,-7,-5,-5,-7,-2,-9,2,-9,5,-7,7,-5,9,-2
		dc.b	10,2,8,6,6,8,2,10,-2,10,-6,8,-8,6,-10,2,-10,-2,-8,-6,-6,-8,-2,-10,2,-10,6,-8,8,-6,10,-2
		dc.b	11,2,9,6,6,9,2,11,-2,11,-6,9,-9,6,-11,2,-11,-2,-9,-6,-6,-9,-2,-11,2,-11,6,-9,9,-6,11,-2
		dc.b	12,2,10,7,7,10,2,12,-2,12,-7,10,-10,7,-12,2,-12,-2,-10,-7,-7,-10,-2,-12,2,-12,7,-10,10,-7,12,-2
		dc.b	13,3,11,7,7,11,3,13,-3,13,-7,11,-11,7,-13,3,-13,-3,-11,-7,-7,-11,-3,-13,3,-13,7,-11,11,-7,13,-3
		dc.b	14,3,12,8,8,12,3,14,-3,14,-8,12,-12,8,-14,3,-14,-3,-12,-8,-8,-12,-3,-14,3,-14,8,-12,12,-8,14,-3
		dc.b	15,3,12,8,8,12,3,15,-3,15,-8,12,-12,8,-15,3,-15,-3,-12,-8,-8,-12,-3,-15,3,-15,8,-12,12,-8,15,-3
		dc.b	16,3,13,9,9,13,3,16,-3,16,-9,13,-13,9,-16,3,-16,-3,-13,-9,-9,-13,-3,-16,3,-16,9,-13,13,-9,16,-3
		dc.b	17,3,14,9,9,14,3,17,-3,17,-9,14,-14,9,-17,3,-17,-3,-14,-9,-9,-14,-3,-17,3,-17,9,-14,14,-9,17,-3
		dc.b	18,4,15,10,10,15,4,18,-4,18,-10,15,-15,10,-18,4,-18,-4,-15,-10,-10,-15,-4,-18,4,-18,10,-15,15,-10,18,-4
		dc.b	19,4,16,11,11,16,4,19,-4,19,-11,16,-16,11,-19,4,-19,-4,-16,-11,-11,-16,-4,-19,4,-19,11,-16,16,-11,19,-4
		dc.b	20,4,17,11,11,17,4,20,-4,20,-11,17,-17,11,-20,4,-20,-4,-17,-11,-11,-17,-4,-20,4,-20,11,-17,17,-11,20,-4
		dc.b	21,4,17,12,12,17,4,21,-4,21,-12,17,-17,12,-21,4,-21,-4,-17,-12,-12,-17,-4,-21,4,-21,12,-17,17,-12,21,-4
		dc.b	22,4,18,12,12,18,4,22,-4,22,-12,18,-18,12,-22,4,-22,-4,-18,-12,-12,-18,-4,-22,4,-22,12,-18,18,-12,22,-4
		dc.b	23,4,19,13,13,19,4,23,-4,23,-13,19,-19,13,-23,4,-23,-4,-19,-13,-13,-19,-4,-23,4,-23,13,-19,19,-13,23,-4
		dc.b	24,5,20,13,13,20,5,24,-5,24,-13,20,-20,13,-24,5,-24,-5,-20,-13,-13,-20,-5,-24,5,-24,13,-20,20,-13,24,-5

;-------
buildDebrisRnd:
		lea		debrisRndTab,a0
		moveq	#debrisRndCount-1,d7
.rnd:
		jsr		getRandomNumber
		move.l	d0,(a0)+
		dbf		d7,.rnd
		rts

;-------
; the text has been cut off (seqTextOff): is any of it still in the part of
; the source that gets shown? -> scrollGone
checkScrollGone:
		tst.b	scrollGone			; (gone is gone: no new text comes)
		bne.s	.out
		lea		src_adr+dissolveByte,a0
		moveq	#0,d0
		moveq	#hitRows-1,d7
.line:
		REPT	(src_line-dissolveByte)/4
		or.l	(a0)+,d0
		ENDR
		lea		src_line-((src_line-dissolveByte)/4*4)(a0),a0
		dbf		d7,.line
		tst.l	d0
		seq		scrollGone
.out:	rts

;-------
; the first lit column of the right block between screen x d0 and d1
; (x up to 375 - the two bytes still behind the right border count)
; -> d0 = x of the middle of that byte, -1 if there is none. keeps the rest
findText::
		movem.l	d1/d3/a0,-(a7)
		cmp.w	#hitRightX,d0
		bge.s	.lo
		move.w	#hitRightX,d0
.lo:
		tst.w	d1
		bmi.s	.none
		lsr.w	#3,d0					; screen bytes
		lsr.w	#3,d1
		cmp.w	#src_line-1-3,d1
		ble.s	.hi
		moveq	#src_line-1-3,d1
.hi:
		cmp.w	d1,d0
		bgt.s	.none
		lea		src_adr+3,a0
		add.w	d0,a0
.col:
		move.b	(a0),d3
		or.b	1*src_line(a0),d3
		or.b	2*src_line(a0),d3
		or.b	3*src_line(a0),d3
		or.b	4*src_line(a0),d3
		or.b	5*src_line(a0),d3
		or.b	6*src_line(a0),d3
		bne.s	.found
		addq.l	#1,a0
		addq.w	#1,d0
		cmp.w	d1,d0
		ble.s	.col
.none:
		moveq	#-1,d0
		bra.s	.out
.found:
		lsl.w	#3,d0
		addq.w	#4,d0
.out:
		movem.l	(a7)+,d1/d3/a0
		rts

;-------
; like findText, but only a glyph with some body to it counts - at least
; solidMin lit pixels in a byte column of the source - a glyph that has
; scrolled across two bytes still has that on one side (a shot meets it, where it would
; pass between the specks of a dot, a colon or a dash). for the ship's
; shots at the glyph test. -> d0 = x of the middle of that byte, -1 if none.
; keeps the rest
solidMin		= 5
solidW			= 4				; ... and at least this wide
findSolid::
		movem.l	d1-d5/a0-a1,-(a7)
		cmp.w	#hitRightX,d0
		bge.s	.lo
		move.w	#hitRightX,d0
.lo:
		tst.w	d1
		bmi.s	.none
		lsr.w	#3,d0
		lsr.w	#3,d1
		cmp.w	#src_line-1-3,d1
		ble.s	.hi
		moveq	#src_line-1-3,d1
.hi:
		cmp.w	d1,d0
		bgt.s	.none
		lea		src_adr+3,a0
		add.w	d0,a0
		lea		popTab,a1
.col:
		moveq	#0,d3
		moveq	#0,d4
		move.b	(a0),d3
		move.b	(a1,d3.w),d4
		move.b	1*src_line(a0),d3
		add.b	(a1,d3.w),d4
		move.b	2*src_line(a0),d3
		add.b	(a1,d3.w),d4
		move.b	3*src_line(a0),d3
		add.b	(a1,d3.w),d4
		move.b	4*src_line(a0),d3
		add.b	(a1,d3.w),d4
		move.b	5*src_line(a0),d3
		add.b	(a1,d3.w),d4
		move.b	6*src_line(a0),d3
		add.b	(a1,d3.w),d4
		cmp.b	#solidMin,d4
		blo.s	.next
		bsr.s	.centre					; and wide enough?
		cmp.w	#solidW,d4
		bhs.s	.found
.next:
		addq.l	#1,a0
		addq.w	#1,d0
		cmp.w	d1,d0
		ble.s	.col
.none:
		moveq	#-1,d0
		bra.s	.out
.found:
		move.w	d3,d0
.out:
		movem.l	(a7)+,d1-d5/a0-a1
		rts
; to the pixel: the glyph's columns round the byte found (the source
; scrolls a pixel at a time, a glyph sits across two bytes - and the byte
; found may be its second half: from the byte before it)
; a0/d0 = the byte -> d3 = the glyph's middle (screen x), d4 its width.
; keeps d0/d1/a0/a1
.centre:
		move.l	a0,-(a7)
		subq.l	#1,a0
		bsr.s	.cols
		moveq	#0,d2
		move.b	d5,d2
		lsl.l	#8,d2
		addq.l	#1,a0
		bsr.s	.cols
		move.b	d5,d2
		lsl.l	#8,d2
		addq.l	#1,a0
		bsr.s	.cols
		move.b	d5,d2
		lsl.l	#8,d2					; bits 31..8: the three bytes
		move.l	(a7)+,a0
		move.w	d0,d3
		subq.w	#1,d3
		lsl.w	#3,d3
		moveq	#0,d4
		tst.l	d2
		beq.s	.cOut
.first:
		tst.l	d2
		bmi.s	.lit
		add.l	d2,d2
		addq.w	#1,d3
		bra.s	.first
.lit:
		tst.l	d2
		bpl.s	.half
		addq.w	#1,d4
		add.l	d2,d2
		bra.s	.lit
.half:
		move.w	d4,d5
		lsr.w	#1,d5
		add.w	d5,d3
.cOut:
		rts
; d5.b = the 7 rows of the source byte at a0 or-ed together
.cols:
		move.b	(a0),d5
		or.b	1*src_line(a0),d5
		or.b	2*src_line(a0),d5
		or.b	3*src_line(a0),d5
		or.b	4*src_line(a0),d5
		or.b	5*src_line(a0),d5
		or.b	6*src_line(a0),d5
		rts
; lit bits in a byte
popTab:
		dc.b	0,1,1,2,1,2,2,3,1,2,2,3,2,3,3,4
		dc.b	1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5
		dc.b	1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5
		dc.b	2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6
		dc.b	1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5
		dc.b	2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6
		dc.b	2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6
		dc.b	3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7
		dc.b	1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5
		dc.b	2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6
		dc.b	2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6
		dc.b	3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7
		dc.b	2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6
		dc.b	3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7
		dc.b	3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7
		dc.b	4,5,5,6,5,6,6,7,5,6,6,7,6,7,7,8
; -> d0 = x of the first lit column of the captain's message, -1 if none
; of it is on the right block (yet, or any more). keeps the rest
msgLeftX::
		move.w	#-32768,d0
; -> d0 = x of the first lit column of the message right of screen x d0,
; -1 if none. keeps the rest
msgFrom::
		tst.b	msgStarted
		beq.s	.none
		move.l	d1,-(a7)
		move.w	msgStartAbs,d1
		sub.w	scrollSteps,d1
		cmp.w	d1,d0
		bge.s	.from
		move.w	d1,d0
.from:
		move.w	#$7fff,d1
		tst.b	msgEnded
		beq.s	.open
		move.w	msgEndAbs,d1
		sub.w	scrollSteps,d1
.open:
		bsr		findText
		move.l	(a7)+,d1
		rts
.none:
		moveq	#-1,d0
		rts

;---------------------------------------------
; THE SCROLLER BREAKS - AND MENDS
;---------------------------------------------
; startGlitch (seq_pilot, after its first attack) hands the text over to
; feedScript, a list of commands feedNext works through a char at a time:
;   FS_SPACES n        n spaces
;   FS_LEVEL l         how broken the scroller is, 0..16 (glitchLevel).
;                      up at once, down a step every glitchRampChars chars
;   FS_SALAD text      a text with every glyph broken (corruptGlyph)
;   FS_TEXT text       a text as it is
;   FS_BROKEN text, o  a text on the mend: each glyph broken with odds
;                      o/256 (corruptGlyph), the rest as they are
;   FS_DOTS n, odds    n chars, each a lone dot with odds/256, else space
;   FS_MSG text        the captain's message: where it starts and ends is
;                      kept for the ship (msgFrom), and letters of it
;                      closer than stutterHoldX make the scroller hang
;                      until they are shot
;   FS_CALM            the scroller is mended at once: level 0, no hang,
;                      no tear, no noise, full speed
;   FS_CUE             msgCue for the ship: time to get into position
;   FS_END             the feed is off (seqTextOff), spaces from now on
; glitchLevel sets how often the scroller hangs (stutterStep), how often a
; band of the bar tears sideways and whether specks of noise get into the
; text (glitchFrame). glitchStop (seq_pilot, message gone) ends it all.
FEED_TEXT		= 0
FEED_SCRIPT		= 1
FEED_OFF		= 4
FS_END			= 0
FS_SPACES		= 1
FS_LEVEL		= 2
FS_SALAD		= 3
FS_TEXT			= 4
FS_DOTS			= 5
FS_MSG			= 6
FS_CALM			= 7				; all well again at once: glitchLevel 0
FS_CUE			= 8				; tells the ship the message is coming (msgCue)
FS_TESTLOOP		= 9				; a text over and over till the ship is ready
								; for the message (seq_defReady), then on
FS_TAIL			= 10			; with finalAttackOn: on with feedTailAttack
FS_BROKEN		= 11			; a text with some of its glyphs broken
msgGap			= 5				; spaces before the message (0.8 s)
cuePause		= 20			; spaces between the dashes and the message
glitchRampChars	= 2				; chars per glitchLevel step down
stutterPerLevel	= 7				; hang odds (out of 256) per level ...
tearPerLevel	= 5				; ... torn frame odds per level
noiseLevel		= 12			; specks of noise from this level up
noiseOdds		= 60			; ... with these odds (out of 256)
stutterHoldX	= 186			; message letters left of this: hang (the twist
								; starts at 184) - an emergency net only
msgHaltX		= 188			; the message stops with its first letter here:
								; all 20 chars of it on screen, to x 346
msgEaseD		= 12			; ... slowing down over the last 12 pixels
stutterMaxHang	= 120			; ... but never for longer than this
tearMax			= 24
shipClear		= 8				; raster lines round the ship never torn

; (called from seq_pilot: keeps every register. it used to hand a0 back
; pointing at barRegionEnd, and the ship's obj_move then wrote its position
; over the copper moves there - BPLCON0 never switched the ember plane on
; again, and the dots stayed white until the end)
startGlitch::
		movem.l	d0-d2/a0-a3,-(a7)
		bsr.s	.go
		movem.l	(a7)+,d0-d2/a0-a3
		rts
.go:
		move.b	#FEED_SCRIPT,feedMode
		move.l	#feedScript,feedPtr
		clr.w	feedPos
		move.w	#16,glitchLevel			; broken at once, the moment the last
		move.w	#16,glitchTarget		; letter is gone (feedScript goes on
		clr.w	rampCount				; from there)
		st		stutterOn
		bra		glitchInit

; -> d0 = the next char to put (0 = space). called from putchar
feedNext:
		; the level eases down towards its target, char by char
		move.w	glitchLevel,d0
		cmp.w	glitchTarget,d0
		bls.s	.cmd
		addq.w	#1,rampCount
		cmp.w	#glitchRampChars,rampCount
		blo.s	.cmd
		clr.w	rampCount
		subq.w	#1,glitchLevel
.cmd:
		move.l	feedPtr,a0
		move.w	(a0),d1
		beq		.off
		cmp.w	#FS_LEVEL,d1
		bne.s	.notLevel
		move.w	2(a0),d0
		move.w	d0,glitchTarget
		cmp.w	glitchLevel,d0
		bls.s	.lvSet
		move.w	d0,glitchLevel			; worse: at once
.lvSet:
		addq.l	#4,feedPtr
		clr.w	feedPos
		bra		.cmd
.notLevel:
		cmp.w	#FS_CALM,d1
		bne.s	.notCalm
		clr.w	glitchLevel
		clr.w	glitchTarget
		clr.w	stutterHold
		addq.l	#2,feedPtr
		bra		.cmd
.notCalm:
		cmp.w	#FS_CUE,d1
		bne.s	.notCue
		st		msgCue
		; where the message will start: after the dashes and the pause
		move.w	scrollSteps,d0
		add.w	#(src_line-2-3)*8+cueAhead*8,d0
		move.w	d0,msgPredAbs
		addq.l	#2,feedPtr
		bra		.cmd
.notCue:
		cmp.w	#FS_TAIL,d1
		bne.s	.notTail
		addq.l	#2,feedPtr
		tst.b	finalAttackOn
		beq		.cmd
		move.l	#feedTailAttack,feedPtr
		bra		.cmd
.notTail:
		cmp.w	#FS_TESTLOOP,d1
		bne		.notLoop
		move.l	insPtr,d0				; the cry from the bridge, put in
		bne.s	.ins
		tst.b	seq_defReady			; the ship is ready: on to the message
		bne		.next6
		move.l	2(a0),a1
		add.w	feedPos,a1
		moveq	#0,d0
		move.b	(a1),d0
		bne.s	.loopChar
		clr.w	feedPos					; round again
		move.l	2(a0),a1
		move.b	(a1),d0
.loopChar:
		addq.w	#1,feedPos
		cmp.b	#' ',d0					; the ship has opened fire (seq_defshoot):
		bne		.plain					; at the next gap between words the cry
		tst.b	whatHellReq				; comes in, once
		beq		.space
		tst.b	whatHellDone
		bne		.space
		st		whatHellDone
		move.l	#whatHellText,insPtr
		bra		.space
.ins:
		move.l	d0,a1
		moveq	#0,d0
		move.b	(a1)+,d0
		beq.s	.insEnd
		move.l	a1,insPtr
		bra		.plain
.insEnd:
		clr.l	insPtr					; the loop goes on where it was
		bra		.cmd
.notLoop:
		cmp.w	#FS_SPACES,d1
		bne.s	.notSpaces
		move.w	feedPos,d0
		cmp.w	2(a0),d0
		bhs.s	.next4
		addq.w	#1,feedPos
		bra		.space
.next4:
		addq.l	#4,feedPtr
		clr.w	feedPos
		bra		.cmd
.notSpaces:
		cmp.w	#FS_DOTS,d1
		bne.s	.notDots
		move.w	feedPos,d0
		cmp.w	2(a0),d0
		bhs.s	.next6
		addq.w	#1,feedPos
		bsr		debrisRandom
		and.w	#$ff,d0
		cmp.w	4(a0),d0
		bhs		.space
		moveq	#'.',d0
		rts
.next6:
		addq.l	#6,feedPtr
		clr.w	feedPos
		bra		.cmd
.notDots:
		cmp.w	#FS_BROKEN,d1
		bne.s	.notBroken
		move.l	2(a0),a1
		add.w	feedPos,a1
		moveq	#0,d0
		move.b	(a1),d0
		bne.s	.bChar
		addq.l	#8,feedPtr
		clr.w	feedPos
		bra		.cmd
.bChar:
		addq.w	#1,feedPos
		cmp.b	#' ',d0
		beq		.space
		move.w	d0,-(a7)
		bsr		debrisRandom
		and.w	#$ff,d0
		cmp.w	6(a0),d0
		bhs.s	.bOk
		st		saladChar				; this one still broken
.bOk:
		move.w	(a7)+,d0
		rts
.notBroken:
		; FS_SALAD, FS_TEXT or FS_MSG: the text is at 2(a0)
		move.l	2(a0),a1
		add.w	feedPos,a1
		moveq	#0,d0
		move.b	(a1),d0
		bne.s	.char
		cmp.w	#FS_MSG,d1				; the end of the message
		bne.s	.next6
		bsr		.slotX
		move.w	d0,msgEndAbs
		st		msgEnded
		bra.s	.next6
.char:
		cmp.w	#FS_MSG,d1
		bne.s	.notStart
		tst.w	feedPos
		bne.s	.notStart
		move.w	d0,-(a7)				; its first char
		bsr		.slotX
		move.w	d0,msgStartAbs
		st		msgStarted
		move.w	(a7)+,d0
.notStart:
		addq.w	#1,feedPos
		cmp.w	#FS_SALAD,d1
		bne.s	.plain
		st		saladChar				; putchar breaks the glyph
.plain:
		cmp.b	#' ',d0
		bne.s	.out
.space:
		moveq	#0,d0
.out:
		rts
.off:
		move.b	#FEED_OFF,feedMode
		st		seqTextOff
		bra.s	.space
; screen x of the byte putchar is about to fill (d7 = 0 or 1), as an
; absolute position: + scrollSteps
.slotX:
		moveq	#src_line-2-3,d0
		add.w	d7,d0
		lsl.w	#3,d0
		add.w	scrollSteps,d0
		rts

; a1 = the glyph putchar has just put down (6 rows) -> broken: every row
; is left alone, shoved a pixel left or right, or gets a few bits flipped
corruptGlyph:
		bsr		debrisRandom
		moveq	#6-1,d2
.row:
		moveq	#3,d1
		and.w	d0,d1
		beq.s	.next
		cmp.w	#1,d1
		bne.s	.notL
		move.b	(a1),d1
		lsl.b	#1,d1
		move.b	d1,(a1)
		bra.s	.next
.notL:
		cmp.w	#2,d1
		bne.s	.flip
		move.b	(a1),d1
		lsr.b	#1,d1
		move.b	d1,(a1)
		bra.s	.next
.flip:
		move.w	d0,d1
		lsr.w	#8,d1
		and.b	#$a5,d1
		eor.b	d1,(a1)
.next:
		ror.l	#5,d0
		lea		src_line(a1),a1
		dbf		d2,.row
		rts

; -> d0 non zero: hang this frame. called from scroll
stutterStep:
		tst.b	finalAttackOn			; (asteroids.s) no attack on the message:
		beq.s	.free					; it runs through, no halt, no hold
		; --- the message all put in: ease the scroller to a stop with all
		;     of it on screen (msgHalted) - it stands until it is gone
		tst.b	msgEnded
		beq.s	.noHalt
		tst.b	msgHalted				; (and on until the blast is out: the
		beq.s	.hold					; empty row may as well wait, it keeps
		tst.b	torpOn					; its last sparks' frames lighter)
		bne.s	.hangE
.hold:
		bsr		msgLeftX
		tst.w	d0
		bmi.s	.noHalt					; (all of it gone: on it goes)
		move.w	msgStartAbs,d0
		sub.w	scrollSteps,d0
		sub.w	#msgHaltX,d0			; how far from where it stops
		ble.s	.halted
		cmp.w	#msgEaseD,d0
		bhi.s	.noHalt
		move.w	#msgEaseD,d1			; the last msgEaseD pixels slower and
		sub.w	d0,d1					; slower: a step every 1, 2, 3, 4
		ext.l	d1						; frames
		divu	#3,d1
		addq.w	#1,d1
		addq.w	#1,haltTick
		cmp.w	haltTick,d1
		bhi.s	.hangE
		clr.w	haltTick
		moveq	#0,d0
		rts
.halted:
		st		msgHalted
.hangE:
		moveq	#1,d0
		rts
.noHalt:
		; a message letter close to the twist: hang until it is shot
		bsr		msgLeftX
		tst.w	d0
		bmi.s	.free
		cmp.w	#stutterHoldX,d0
		bhs.s	.free
		addq.w	#1,hangCount
		addq.w	#1,holdFrames			; (should never happen, see seq_run)
		cmp.w	#stutterMaxHang,hangCount
		blo.s	.hang
		clr.w	hangCount				; (a step through now and then, so it
		bra.s	.go						; can never lock up)
.free:
		clr.w	hangCount
		tst.w	stutterHold
		beq.s	.roll
		subq.w	#1,stutterHold
.hang:
		moveq	#1,d0
		rts
.roll:
		; a step now - and maybe a hang after it, 1..4 frames, now and then
		; a long one. how often depends on glitchLevel
		move.w	glitchLevel,d2
		beq.s	.go
		bsr		debrisRandom
		moveq	#0,d1
		move.b	d0,d1
		move.w	d2,d3
		lsr.w	#2,d3					; long ones: level/4 out of 256
		cmp.w	d3,d1
		bhs.s	.short
		move.w	#12,stutterHold
		bra.s	.go
.short:
		mulu	#stutterPerLevel,d2
		cmp.w	d2,d1
		bhs.s	.go
		lsr.w	#8,d0
		and.w	#3,d0
		addq.w	#1,d0
		move.w	d0,stutterHold
.go:
		moveq	#0,d0
		rts

; find the bar's BPLCON1 moves, and the raster line each one comes on, so
; glitchFrame can tear the lines
glitchInit:
		st		glitchOn				; (the moves were found at the start,
		rts								; glitchScan - a 14k scan the frame of the
										; first hit could not afford)
glitchScan:
		lea		barRegionStart,a0
		lea		tearAddr,a1
		lea		tearOrig,a2
		lea		tearLine,a3
		moveq	#0,d0
		moveq	#0,d2					; line of the last wait
.scan:
		cmp.l	#barRegionEnd,a0
		bhs.s	.done
		move.w	(a0),d1
		btst	#0,d1
		beq.s	.move
		lsr.w	#8,d1
		move.w	d1,d2
		bra.s	.next
.move:
		cmp.w	#$0102,d1
		bne.s	.next
		cmp.w	#tearMax,d0
		bhs.s	.next
		move.l	a0,(a1)+
		move.w	2(a0),(a2)+
		move.w	d2,(a3)+
		addq.w	#1,d0
.next:
		addq.l	#4,a0
		bra.s	.scan
.done:
		move.w	d0,tearCount
		rts

; every frame while glitchOn: put the BPLCON1 values back, then maybe tear
; a band of 2..5 of those lines sideways (playfield 1 delay: the text and
; the dots in it jump), and at the worst levels flip a speck of the source
; text. the lines round the ship are never torn (seq_shipY), it must not
; so much as twitch
glitchFrame:
		tst.b	glitchOn
		beq		.out
		lea		tearAddr,a1
		lea		tearOrig,a2
		move.w	tearCount,d7
		subq.w	#1,d7
		bmi		.out
.restore:
		move.l	(a1)+,a0
		move.w	(a2)+,2(a0)
		dbf		d7,.restore
		bsr		debrisRandom
		moveq	#0,d1
		move.b	d0,d1
		move.w	glitchLevel,d2
		mulu	#tearPerLevel,d2
		cmp.w	d2,d1
		bhs		.noTear
		move.w	tearCount,d5			; the last BPLCON1 move of the bar is
		subq.w	#1,d5					; never torn: it puts the delay back
		lsr.l	#8,d0					; for the rest of the bar
		moveq	#0,d2
		move.b	d0,d2
		mulu	d5,d2
		lsr.w	#8,d2					; first line of the band
		lsr.l	#8,d0
		moveq	#3,d3
		and.w	d0,d3
		addq.w	#1,d3					; 2..5 lines
		lsr.w	#2,d0
		moveq	#7,d4
		and.w	d0,d4
		addq.w	#2,d4					; 2..9 pixels
		move.w	seq_shipY,d6			; the ship's lines
		lea		tearAddr,a1
		lea		tearLine,a3
.tear:
		cmp.w	d5,d2
		bhs.s	.noTear
		move.w	d2,d1
		add.w	d1,d1
		move.w	2(a3,d1.w),d0			; this move holds until the next one
		subq.w	#1,d0
		add.w	#shipClear,d0
		cmp.w	d6,d0
		blt.s	.tearIt					; ends above the ship ...
		move.w	(a3,d1.w),d0
		sub.w	#shipClear,d0
		cmp.w	d6,d0
		ble.s	.skipShip				; ... or starts below it, else leave it
.tearIt:
		add.w	d1,d1
		move.l	(a1,d1.w),a0
		move.w	2(a0),d1
		and.w	#$fff0,d1
		or.w	d4,d1
		move.w	d1,d0					; the shadow (playfield 2) with it, as
		and.w	#$00f0,d0				; far as its own delay still goes - else
		lsl.w	#4,d4					; the torn text keeps a whole shadow
		add.w	d4,d0
		lsr.w	#4,d4
		cmp.w	#$00f0,d0
		bls.s	.pf2
		move.w	#$00f0,d0
.pf2:
		and.w	#$ff0f,d1
		or.w	d0,d1
		move.w	d1,2(a0)
.skipShip:
		addq.w	#1,d2
		dbf		d3,.tear
.noTear:
		cmp.w	#noiseLevel,glitchLevel
		blo.s	.out
		bsr		debrisRandom
		moveq	#0,d1
		move.b	d0,d1
		cmp.w	#noiseOdds,d1
		bhs.s	.out
		lsr.l	#8,d0
		moveq	#0,d1
		move.b	d0,d1
		mulu	#src_line-$1a,d1
		lsr.w	#8,d1
		add.w	#$1a,d1					; a byte of the right block
		lsr.l	#8,d0
		moveq	#7,d2
		and.w	d0,d2
		cmp.w	#hitRows,d2
		blo.s	.rowOk
		moveq	#0,d2
.rowOk:
		mulu	#src_line,d2
		add.w	d2,d1
		lea		src_adr,a0
		lsr.w	#3,d0
		and.b	#$99,d0
		eor.b	d0,(a0,d1.w)
.out:
		rts

; (called from seq_pilot: keeps every register)
glitchStop::
		movem.l	d7/a0-a2,-(a7)
		tst.b	glitchOn
		beq.s	.off
		lea		tearAddr,a1
		lea		tearOrig,a2
		move.w	tearCount,d7
		subq.w	#1,d7
		bmi.s	.off
.restore:
		move.l	(a1)+,a0
		move.w	(a2)+,2(a0)
		dbf		d7,.restore
.off:
		sf		glitchOn
		sf		stutterOn
		clr.w	glitchLevel
		movem.l	(a7)+,d7/a0-a2
		rts

; what happens to the scroller after the first attack
feedScript:
		dc.w	FS_LEVEL,16				; it all goes wrong at once
		dc.w	FS_SALAD
		dc.l	saladText
		dc.w	FS_LEVEL,12				; mending, a step at a time: the scene talk
		dc.w	FS_DOTS,4,48			; on the bridge comes through still broken,
		dc.w	FS_BROKEN				; fewer glyphs each time - and the tears
		dc.l	testText1				; and the stutter wear off with it
		dc.w	190
		dc.w	FS_LEVEL,8
		dc.w	FS_DOTS,3,32
		dc.w	FS_BROKEN
		dc.l	testText2
		dc.w	120
		dc.w	FS_LEVEL,4
		dc.w	FS_BROKEN
		dc.l	testText3
		dc.w	56
		dc.w	FS_TAIL					; (the old way, with finalAttackOn)
feedMended:
		dc.w	FS_CALM					; mended: from here it runs clean - and at
		dc.w	FS_CUE					; once the end is set up (seq_defshoot):
										; the ship comes over during a short
		dc.w	FS_TEXT					; word from the bridge, then the crews
		dc.l	glyphTest1				; come in - the little jerks only from the
										; first glyph shot out ...
		dc.w	FS_TESTLOOP
		dc.l	crewText
		dc.w	FS_CALM					; ... till the ship is ready for the
		dc.w	FS_TEXT					; message: a few question marks, and
		dc.l	whatText				; a pause, then it
		dc.w	FS_SPACES,msgGap
	ifeq	defWords				; (switches.i: with defWords the message
		dc.w	FS_MSG					; comes as the game's letters instead,
		dc.l	msgText					; asteroids.s seq_defwords)
	endc
		dc.w	FS_END
; the old ending: the message after the dashes and a long pause, for the
; power blast (seq_run)
feedTailAttack:
		dc.w	FS_CALM
		dc.w	FS_CUE
		dc.w	FS_TEXT
		dc.l	testText4
		dc.w	FS_SPACES,cuePause
		dc.w	FS_MSG
		dc.l	msgText
		dc.w	FS_END
; designed nonsense: system noise with a hint of an error report in it
saladText:
		dc.b	"#@?! 3RR*R ][/\\0X",0
; scene talk while it mends (it used to be a display test)
testText1:
		dc.b	"COPPER TO BLITTER: COME IN!  ",0
testText2:
		dc.b	"NO GURU TODAY!  ",0
testText3:
		dc.b	"50 FPS OR DIE!   ",0
; mended: a word from the bridge (short - the attack comes soon)
glyphTest1:
		dc.b	"   REAL CODERS USE THE COPPER!    ",0
; ... and then this round and round till the ship is ready for the message:
; the crews, and a few words from Thrust's Ottifant intro (1988)
crewText:
		dc.b	"   DISPLAY OK.   THRUST + QUADLITE ON THE BRIDGE AGAIN !!!    "
		dc.b	"STAY CLEAN AND NEVER TRUST A FROG ... TRUST THRUST !!!    "
		dc.b	"HELLO ZERONINE OF QUADLITE - COOL BLITTERROUTINE. WONT YOU "
		dc.b	"SEND US THE SOURCECODE ??    "
		dc.b	"IF THE SCROLLER IS TOO FAST ... NOT A BUG !!    "
		dc.b	"THIS IS NOT THE LARGEST SCROLLER IN THE WORLD - BUT THE ONE "
		dc.b	"WITH THE MOST HOLES IN IT !!    "
		dc.b	"THE REALLY LEADING TWO ARE: THRUST -- QUADLITE    "
		dc.b	"PREPARE FOR A LONG ENTERTAINING TEXT !!!    ",0
; put into it at the first shot of the ship (whatHellReq, seq_defshoot)
whatHellText:
		dc.b	"   ??? WHAT THE HELL ???      ",0
whatText:
		dc.b	"   ?    ??   ???",0
testText4:
		dc.b	"-      -   -    -          -- - - -    ---"
testText4End:
		dc.b	0
cueAhead		= testText4End-testText4+cuePause	; chars from the cue to
										; the message (see feedScript)
; it runs through like any text (with finalAttackOn the scroller stops for
; it, see stutterStep - the attack for a 20 char "CAPTAIN, WTF HAPPENS")
msgText:
		dc.b	"CAPTAIN, WHAT THE FUCK HAPPENS HERE"
msgTextEnd:
		dc.b	0
msgTextLen		= msgTextEnd-msgText
		even

;---------------------------------------------
; STEP 2 - SCROLLER OFF, THE TV SWITCHES OFF
;---------------------------------------------
; once the text is gone seq_pilot sets tvGo. the scroller stops, and the
; copper is sent through tvList instead of the bar's own part of clist:
; the same modulo and scroll tricks line for line (so everything below
; the bar stays where it is), but with a colour 0 move on EVERY line that
; tvUpdate rewrites each frame. then, like an old set being switched off:
;   collapse  the bar's colours squeeze into the middle line and burn up
;             to white (tvCollapseT frames)
;   line      a white line across the screen, two raster lines high
;   shrink    the line pulls in from both sides to a dot - the h waits
;             on the two middle lines
;   dot       the dot glows out through blue to black
; afterwards the bar is gone, the copper stays on tvList, all black.
tvTop			= $bf			; first line of tvList
tvLines			= $ef-tvTop+1	; 49, down to and with the $ef line
tvMid			= $df			; middle of the bar background ($cf..$ef)
tvCollapseT		= 22
tvLineT			= 10
tvShrinkT		= 20
tvDotT			= 18
tvHMid			= $90			; copper h position of the screen's middle
tvHWide			= $50			; ... half the screen, in the same units

TV_LINE	macro
		dc.w	(\1<<8)+$01,$fffe
		endm
TV_COL	macro					; the colour 0 move tvUpdate rewrites
		dc.w	$0180,$0000
		endm

tvUpdate:
		move.b	tvState,d0
		beq.s	.idle
		cmp.b	#1,d0
		beq		tvStart
		cmp.b	#5,d0
		beq.s	.idle					; done
		addq.w	#1,tvTime
		cmp.b	#2,d0
		beq		tvCollapse
		cmp.b	#3,d0
		beq		tvLine
		bra		tvShrink
.idle:
		tst.b	tvGo					; seq_pilot: off you go
		beq.s	.out
		tst.b	tvState
		bne.s	.out
		move.b	#1,tvState
.out:
		rts

; --- first frame: the copper goes through tvList from now on
tvStart:
		st		sfxWide					; Defender from here: the effects get
		moveq	#5,d0					; more channels - and the zap of the set
		jsr		sfxPlay					; going off (music.s sfxPlay, SFX_ZAP)
		bsr		barFlickStop			; the bar's own colours again first
		tst.b	tvKeepText				; (the monitor goes off, the text runs
		bne.s	.keep					; on - the Defender ending)
		st		scrollerOff
.keep:
		; colour 0 of every bar line as it is now, the base the collapse
		; squeezes. barc1 is $cf, barc2 holds from $d0 to $dd, barc3..19
		; are $de..$ee, $ef is black
		lea		tvBase,a0
		moveq	#$cf-tvTop-1,d7
.black:
		clr.w	(a0)+
		dbf		d7,.black
		move.w	barc1+2,(a0)+
		moveq	#$de-$d0-1,d7
.flat:
		move.w	barc2+2,(a0)+
		dbf		d7,.flat
		lea		barcolorOffsets+4,a1	; barc3 onwards
		lea		clist,a2
		moveq	#19-3,d7
.wall:
		move.w	(a1)+,d0
		move.w	(a2,d0.w),(a0)+
		dbf		d7,.wall
		clr.w	(a0)+					; $ef
		move.w	#256,d0					; same colours as the bar has now (no
		moveq	#0,d1					; stretch, no white)
		bra		tvStart2

; the line colour moves of tvList: a $0180 move after a wait at h
; position 1 (the h waits on the middle lines have their own). once, at
; the start (initScroller) - the frame the TV goes off has no room for it
tvScan:
		lea		tvList,a0
		lea		tvColAddr,a1
		lea		tvInkAddr,a2
		moveq	#0,d1					; h of the last wait
.scan:
		cmp.l	#tvListEnd,a0
		bhs.s	.scanned
		move.w	(a0),d0
		btst	#0,d0
		beq.s	.move
		move.b	d0,d1					; a wait
		bra.s	.next
.move:
		cmp.w	#$0182,d0				; colour 1: the text's, and what the ship
		bne.s	.notInk					; and the letters get there (inkFade)
		lea		2(a0),a3
		move.l	a3,(a2)+
		bra.s	.next
.notInk:
		cmp.w	#$0180,d0
		bne.s	.next
		cmp.b	#$01,d1
		bne.s	.next
		lea		2(a0),a3
		move.l	a3,(a1)+
.next:
		addq.l	#4,a0
		bra.s	.scan
.scanned:
		sub.l	#tvInkAddr,a2
		move.l	a2,d0
		lsr.w	#2,d0
		move.w	d0,tvInkCount
		rts
tvStart2:
		bsr		tvPaint
		move.w	gamePlanes2,tvPlanes2	; whatever the game has it at
		move.l	#barRegionEnd,d0		; the way back
		move.w	d0,tvBackL
		swap	d0
		move.w	d0,tvBackH
		move.l	#tvList,d0				; ... and the way in, last
		move.w	d0,tvJumpL
		swap	d0
		move.w	d0,tvJumpH
		move.w	#$0084,tvJump
		move.w	#$0086,tvJump+4
		move.w	#$008a,tvJump+8
		clr.w	tvTime
		move.b	#2,tvState
		rts

; --- d0 = vertical stretch 8.8 (256 = as it is), d1 = how far to white
;     (0..16). every line takes its colour from line mid+(line-mid)*d0/256
tvPaint:
		tst.w	d1						; the way to white as a table, 0..15
		beq.s	.noLut					; -> n + (15-n)*d1/16, once a frame
		lea		tvWLut,a1
		moveq	#0,d3
.lut:
		moveq	#15,d2
		sub.w	d3,d2
		mulu	d1,d2
		lsr.w	#4,d2
		add.w	d3,d2
		move.b	d2,(a1)+
		addq.w	#1,d3
		cmp.w	#16,d3
		blo.s	.lut
.noLut:
		lea		tvColAddr,a1
		lea		tvBase,a2
		moveq	#0,d5					; line index
.line:
		move.w	d5,d2
		sub.w	#tvMid-tvTop,d2			; distance from the middle
		muls	d0,d2
		asr.l	#8,d2
		add.w	#tvMid-tvTop,d2			; source line
		moveq	#0,d3
		cmp.w	#tvLines,d2
		bhs.s	.set					; outside: black
		add.w	d2,d2
		move.w	(a2,d2.w),d3
		tst.w	d1
		beq.s	.set
		bsr		tvWhiten
.set:
		move.l	(a1)+,a0
		move.w	d3,(a0)
		addq.w	#1,d5
		cmp.w	#tvLines,d5
		blo.s	.line
		; the h waits on the middle lines follow their line's colour
		move.l	tvColAddr+(tvMid-tvTop)*4,a0
		move.w	(a0),d3
		move.w	d3,tvH0c1
		move.w	d3,tvH0c2
		move.l	tvColAddr+(tvMid+1-tvTop)*4,a0
		move.w	(a0),d3
		move.w	d3,tvH1c1
		move.w	d3,tvH1c2
		rts

; d3 = colour -> d3 that far on the way to white (tvWLut, see tvPaint).
; uses d4/d6
tvWhiten:
		move.l	a3,-(a7)
		lea		tvWLut,a3
		moveq	#15,d4
		and.w	d3,d4
		moveq	#0,d6
		move.b	(a3,d4.w),d6			; b
		lsr.w	#4,d3
		moveq	#15,d4
		and.w	d3,d4
		move.b	(a3,d4.w),d4			; g
		lsl.w	#4,d4
		or.w	d4,d6
		lsr.w	#4,d3
		and.w	#15,d3
		move.b	(a3,d3.w),d4			; r
		lsl.w	#8,d4
		or.w	d4,d6
		move.w	d6,d3
		move.l	(a7)+,a3
		rts
tvCollapse:
		move.w	tvTime,d2
		cmp.w	#tvCollapseT,d2
		blo.s	.go
		move.b	#3,tvState
		clr.w	tvTime
		rts
.go:
		; stretch = T/(T-t), as 8.8, and t/T of the way to white
		move.l	#tvCollapseT*256,d0
		moveq	#tvCollapseT,d1
		sub.w	d2,d1
		divu	d1,d0
		moveq	#16,d1
		mulu	d2,d1
		divu	#tvCollapseT,d1
		bra		tvPaint

tvLine:
		cmp.w	#1,tvTime
		bne.s	.hold
		clr.w	tvShadowCol				; the bar is gone: its shadow (the dual
										; playfield's) with it
		; all black but the two middle lines, white
		move.w	#$7fff,d0				; stretched past everything
		moveq	#0,d1
		bsr		tvPaint
		move.w	#$0fff,d3
		move.l	tvColAddr+(tvMid-tvTop)*4,a0
		move.w	d3,(a0)
		move.l	tvColAddr+(tvMid+1-tvTop)*4,a0
		move.w	d3,(a0)
		move.w	d3,tvH0c1
		move.w	d3,tvH0c2
		move.w	d3,tvH1c1
		move.w	d3,tvH1c2
.hold:
		cmp.w	#tvLineT,tvTime
		blo.s	.done
		; from here the line is the h waits: black at the start of the two
		; lines, white from h0 to h1
		moveq	#0,d3
		move.l	tvColAddr+(tvMid-tvTop)*4,a0
		move.w	d3,(a0)
		move.l	tvColAddr+(tvMid+1-tvTop)*4,a0
		move.w	d3,(a0)
		move.w	d3,tvH0c2
		move.w	d3,tvH1c2
		move.w	#$0fff,tvH0c1
		move.w	#$0fff,tvH1c1
		move.w	#tvHWide,d0
		bsr		tvWidth
		move.b	#4,tvState
		clr.w	tvTime
.done:
		rts

tvShrink:
		move.w	tvTime,d2
		cmp.w	#tvShrinkT,d2
		bhs.s	.dot
		; half width falls off with the square of the time: slow, then fast
		moveq	#tvShrinkT,d0
		sub.w	d2,d0
		mulu	d0,d0
		mulu	#tvHWide,d0
		divu	#tvShrinkT*tvShrinkT,d0
		cmp.w	#2,d0
		bge		tvWidth
		moveq	#2,d0
		bra		tvWidth
.dot:
		sub.w	#tvShrinkT,d2
		cmp.w	#tvDotT,d2
		blo.s	.fade
		move.b	#5,tvState				; gone
		moveq	#0,d3
		move.w	d3,tvH0c1
		move.w	d3,tvH1c1
		rts
.fade:
		add.w	d2,d2
		lea		tvDotFade,a0
		move.w	(a0,d2.w),d3
		move.w	d3,tvH0c1
		move.w	d3,tvH1c1
		moveq	#2,d0
; d0 = half width of the line, in copper h units
tvWidth:
		and.w	#$fffe,d0				; copper h positions are even
		move.w	#tvHMid,d1
		sub.w	d0,d1
		move.b	d1,tvH0s+1
		move.b	d1,tvH1s+1
		or.b	#1,tvH0s+1
		or.b	#1,tvH1s+1
		move.w	#tvHMid,d1
		add.w	d0,d1
		move.b	d1,tvH0e+1
		move.b	d1,tvH1e+1
		or.b	#1,tvH0e+1
		or.b	#1,tvH1e+1
		rts

; the dot dies away, white through the blue of an old tube to black
tvDotFade:
		dc.w	$0fff,$0eef,$0ddf,$0cce,$0bbe,$0aad,$099c,$088b,$077a
		dc.w	$0669,$0558,$0447,$0336,$0225,$0114,$0003,$0002,$0001

tvState::		dc.b	0		; 0 off, 1 start, 2 collapse, 3 line, 4 shrink
								; and dot, 5 done
tvGo::			dc.b	0		; set by seq_pilot
tvKeepText::	dc.b	0		; ... and the text runs on through it
scrollerOff::	dc.b	0		; (warp.i too, once the text is all gone)
				even
tvTime:			dc.w	0
tvBase:			ds.w	tvLines
tvColAddr:		ds.l	tvLines
tvWLut:			ds.b	16		; tvPaint: the way to white

debrisCx:		dc.w	0
debrisCy:		dc.w	0
debrisRnd:		dc.w	0
debrisRndTab:	ds.l	debrisRndCount
blastPow:		dc.l	blastPowers		; power of the blast now
blastVx:		dc.w	0		; the velocity of the shot that caused it
blastVy:		dc.w	0
hitN:			dc.w	2		; text bytes the blast takes
hitTotal::		dc.w	0		; blasts so far (for testing)
blastsDone:		dc.w	0		; this frame
hitQueueN:		dc.w	0
hitQueue:		ds.w	2*hitQueueMax	; x, line of the hits held over
scrollStepped:	dc.w	0		; the text moved a pixel this frame
holdFrames:		dc.w	0		; frames the hold for the message caught (testing)
haltTick:		dc.w	0
detWaitFrom:	dc.w	0		; (testing: letters going off late)
detLateN:		dc.w	0
detLateFrames:	dc.w	0
detLogN:		dc.w	0
detLog:			ds.w	2*32	; frame it went off, frames late
whiteLost:		dc.w	0		; (testing) blast dots gone while still white
whiteLostY:		dc.w	0		; ... of them off the top or bottom
burntOut:		dc.w	0		; ... and burnt out as they should
laserNose:		dc.w	0		; the laser: where it starts ...
laserTail:		dc.w	0		; ... its tail and head now (screen x) ...
laserFront:		dc.w	0
laserY:			dc.w	0		; the laser's game y ...
laserLine:		dc.w	0		; ... the scroller line it is on
laserPhase::	dc.w	0		; 0 out it goes, 1 the word, 2 gone through
laserAge:		dc.w	0
laserLast:		dc.w	0		; the last letter's end, + scrollSteps
laserWait::		dc.w	0		; frames till the next letter
laserCol:		dc.b	0		; the beam's colours are on (tvBeam0..3)
				even
; the fall for every age, g*t*t/2 in pixels
latFall:
LA		set		0
		rept	22
		dc.w	(latGrav*LA*LA)>>9
LA		set		LA+1
		endr
latCount::		dc.w	0		; Defender explosions going on ...
lattices:		ds.b	lat_size*latMax		; ... drawLattice
latLeft:		dc.w	0
latEmber:		dc.l	0
latCols:		ds.l	7		; drawLattice: the columns, byte and bit
				even
laserHits:		dc.w	0		; (testing) letters it took ...
laserWords:		dc.w	0		; ... and words
flickT:			dc.w	0		; barFlicker: frames on ...
flickDieT:		dc.w	0		; ... dying (tvLate)
flickGapT:		dc.w	0
flickInkB:		dc.w	0		; ... the text's brightness
flickHold:		dc.w	0		; ... a dropout or flash: frames left ...
flickHoldB:		dc.w	0		; ... and its brightness
flickModeT:		dc.w	0		; ... frames left of the colour fault ...
flickMode:		dc.w	0		; ... and which one
flickLut:		ds.b	16		; ... the brightness, as a table
torpX:			dc.l	0		; 16.16
torpVX:			dc.l	0
torpLine:		dc.w	0
torpAge:		dc.w	0
torpInText:		dc.w	0		; letters it has gone through
torpNextEnd:	dc.w	-1		; the next letter's last column + scrollSteps
detN::			dc.w	0		; letters set to go off ...
detTimer:		dc.w	0
detQueue:		ds.w	detMax	; ... x + scrollSteps, the leftmost first

pointsRetired:	dc.w	0		; dots dropped at the cap (testing)
sparkNum:		dc.w	0
sparks:			ds.b	spark_len*sparkMax
ringCount:		dc.w	0
ringKind:		dc.w	0
rings:			ds.b	ring_len*ringMax
scrollSteps::	dc.w	0		; pixels the text has moved, ever
msgStartAbs::	dc.w	0		; screen x + scrollSteps of the message's start
msgPredAbs::	dc.w	0		; ... and where it will be, from the cue on
msgEndAbs:		dc.w	0		; ... and of its end
feedPtr:		dc.l	0		; feedScript command now
feedPos:		dc.w	0
insPtr:			dc.l	0		; FS_TESTLOOP: a text put in, char now (0: none)
whatHellReq::	dc.b	0		; seq_defshoot: it has opened fire - the cry
whatHellDone:	dc.b	0		; ... is in
glitchLevel::	dc.w	0		; how broken the scroller is, 0..16
glitchTarget::	dc.w	0
rampCount:		dc.w	0
hangCount:		dc.w	0
stutterHold:	dc.w	0
tearCount:		dc.w	0
tearAddr:		ds.l	tearMax
tearOrig:		ds.w	tearMax
tearLine:		ds.w	tearMax+1	; raster line of each, + an end
seqTextOff::	dc.b	0		; the feed is off: only spaces from now on
scrollGone::	dc.b	0		; ... and none of the old text is left
scrollReady::	dc.b	0		; the text runs across the whole bar
debrisSkip:		dc.b	4
debrisEvery:	dc.b	4		; every n-th lit pixel of a blast is a dot
feedMode:		dc.b	FEED_TEXT
saladChar:		dc.b	0		; putchar: break this glyph
stutterOn:		dc.b	0
glitchOn:		dc.b	0
msgStarted::	dc.b	0
msgEnded::		dc.b	0
msgCue::		dc.b	0		; FS_CUE: the message is next
msgHalted::		dc.b	0		; the scroller stands, all of the message on show
detWaiting:		dc.b	0
fxPending::		dc.b	0		; blastAt's sparks and rings are due
blastNoCrumbs:	dc.b	0		; blastAt: no glowing crumbs (the laser's)
bigBlast:		dc.b	0		; pickPower: 1 the chain's, 2 the torpedo's
torpOn::		dc.b	0		; the plasma torpedo is in the air
laserObj:		dc.b	0		; ... at the game's letters (launchLaserAt)
laserOn::		dc.b	0		; the Defender laser is out
barFlickOn::	dc.b	0
flickPhase::	dc.b	0		; (tvLate) 0 flicker, 1 dying, 2 dark, 3 risen again		; the bar goes wrong (barFlicker)
wakeOn::		dc.b	0		; the blast has gone: letters coming in go off
				even
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

		lea		src_adr-li,a0		; one more line for empty line -> sprite display
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

		; the scroller "breaking" in the destruction sequence: it hangs now
		; and then, see stutterStep
		clr.w	scrollStepped
		tst.b	stutterOn
		beq.s	.step
		bsr		stutterStep
		tst.w	d0
		beq.s	.step
		rts
.step:
		addq.w	#1,scrollSteps			; how far the text has moved, ever
		move.w	#1,scrollStepped		; ... and this frame (textShot)

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
		moveq	#43,d1					; glyph 43 is the space
		sf		saladChar
		tst.b	feedMode				; the destruction sequence feeds its own
		bne		.feed					; text, see feedNext
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
		move.b	charStride*1(a2),1*src_line(a1)
		move.b	charStride*2(a2),2*src_line(a1)
		move.b	charStride*3(a2),3*src_line(a1)
		move.b	charStride*4(a2),4*src_line(a1)
		move.b	charStride*5(a2),5*src_line(a1)
		tst.b	saladChar
		bne		corruptGlyph
		rts
.feed:
		bsr		feedNext				; -> d0 = char, 0 for a space
		moveq	#43,d1					; (feedNext uses d1)
		tst.b	d0
		beq.s	.textfin
		bra.s	.notextfin

				rsreset
point_x:		rs.l	1		; x position, 16.16 fixed point
point_y:		rs.l	1		; y position, 16.16 fixed point
point_xvelo:	rs.l	1		; x velocity in pixels/frame, 16.16
point_yvelo:	rs.l	1		; y velocity in pixels/frame, 16.16
point_len:		rs.b	0		; = 16 bytes -> movem friendly, lsl #4 to index

		even
points:		ds.b	point_len*pointsPool
activeCount:
		dc.w	0
pointKeep:	dc.w	numPoints	; seqKeep while the sequence blows things up

		even
yTable:		ds.w	screenHeight	; y -> y*li, built once by buildYTable

; setPointScroller was inlined into drawPoints - the bsr/rts pair alone
; was 34 cycles per point, and the mulu #li another ~50.

; one glyph per char, in font order. the font only has capitals, so the
; letters are matched in upper case and a lower case "o" is free to be
; the small ring. chars not in here come out as glyph 0 ("A").
; the -1 end marker takes the last (empty) glyph slot.
chartab:
		dc.b	"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,!()/: ?-+='<>*@[]#\\o",-1
ctend:
		even
charStride		= ctend-chartab		; glyphs per font row (incl. the empty one)

; 6 rows of charStride bytes, one byte (8 pixels) per glyph per row.
; row 5 is only used by the comma.
char:
; row 0
		dc.b	$78,$f8,$7c,$f8,$fc,$fc,$7c,$cc,$fc,$3c,$cc,$c0,$c6,$cc,$78,$f8
		dc.b	$78,$f8,$7c,$fc,$cc,$cc,$c6,$cc,$cc,$fc,$78,$30,$f8,$f8,$c0,$fc
		dc.b	$7c,$fc,$78,$78,$00,$00,$60,$30,$60,$0c,$00,$00,$78,$00,$00,$00
		dc.b	$0c,$18,$60,$a8,$78,$70,$70,$48,$c0,$00,$00
; row 1
		dc.b	$cc,$cc,$c0,$cc,$c0,$c0,$c0,$cc,$30,$18,$d8,$c0,$fe,$ec,$cc,$cc
		dc.b	$cc,$cc,$c0,$30,$cc,$cc,$c6,$78,$cc,$18,$cc,$f0,$0c,$0c,$d8,$c0
		dc.b	$c0,$0c,$cc,$cc,$00,$00,$60,$60,$30,$18,$60,$00,$cc,$00,$10,$78
		dc.b	$0c,$30,$30,$70,$cc,$60,$30,$fc,$60,$78,$00
; row 2
		dc.b	$fc,$f8,$c0,$cc,$f8,$f8,$dc,$fc,$30,$18,$f0,$c0,$d6,$fc,$cc,$cc
		dc.b	$cc,$cc,$78,$30,$cc,$78,$d6,$30,$78,$30,$cc,$30,$78,$38,$fc,$f8
		dc.b	$f8,$18,$78,$7c,$00,$00,$60,$60,$30,$30,$00,$00,$18,$38,$38,$00
		dc.b	$18,$60,$18,$f8,$dc,$60,$30,$48,$30,$cc,$00
; row 3
		dc.b	$cc,$cc,$c0,$cc,$c0,$c0,$cc,$cc,$30,$d8,$d8,$c0,$c6,$dc,$cc,$f8
		dc.b	$d8,$f8,$0c,$30,$cc,$78,$fe,$78,$30,$60,$cc,$30,$c0,$0c,$18,$0c
		dc.b	$cc,$30,$cc,$0c,$60,$60,$00,$60,$30,$60,$00,$00,$00,$00,$10,$78
		dc.b	$00,$30,$30,$70,$c0,$60,$30,$fc,$18,$78,$00
; row 4
		dc.b	$cc,$f8,$7c,$f8,$fc,$c0,$7c,$cc,$fc,$70,$cc,$fc,$c6,$cc,$78,$c0
		dc.b	$7c,$cc,$f8,$30,$78,$30,$c6,$cc,$30,$fc,$78,$fc,$fc,$f8,$18,$f8
		dc.b	$78,$60,$78,$f8,$60,$60,$60,$30,$60,$c0,$60,$00,$30,$00,$00,$00
		dc.b	$00,$18,$60,$a8,$7c,$70,$70,$48,$0c,$00,$00
; row 5
		dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
		dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
		dc.b	$00,$00,$00,$00,$00,$c0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
		dc.b	$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
		even

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
            mulu.w  #li,d0                  ; logo line in bytes (logoPadded)
            ext.l   d0
            move.l  d0,d1
            bsr     updateLogoPointers
            moveq   #0,d0
.noNegativePos
			add.w	#logoY-16,d0
			bsr		logoColorEngine			; sets logoStartWait, d0 = end - height
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
            cmp.w   #logo_area_height-1,logoFadeLine
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
; The logo fades up through logoColorEngine, which reads introLogoLine and
; introLogoPass and looks the colours up in a pre-computed fade table, so
; all fadeInLogo has to do is advance those two counters. The bar keeps
; the old trick: stash the finished colours as the target, blank the live
; copperlist copy, and walk it back up one nibble at a time.
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

			; --- the bar. rather than a hand written offset list this
			;     walks the copperlist between the two markers and picks up
			;     every colour write in it - $0180 for the flat background
			;     Only $0180. Colour 1 is what the ship, the letters and the
			;     bar shading are drawn in, so blanking that would make the
			;     game invisible in the lower half of the screen. Anything
			;     stray down there is dealt with by switching the bitplane
			;     off instead - see introHideGame.
			;     Copper instructions are four bytes whether they are MOVEs or
			;     WAITs, and a WAIT always has bit 0 set in its first word, so
			;     it can never be mistaken for a colour register.
			lea		barRegionStart,a0
			lea		barColorAddr,a1
			lea		barColorsTarget,a2
			lea		barInkAddr,a3
			lea		barInkTarget,a4
			moveq	#0,d0
			moveq	#0,d2
.scan:
			cmp.l	#barRegionEnd,a0
			bhs.s	.scanned
			move.w	(a0),d1
			cmp.w	#$0182,d1
			beq.s	.ink
			cmp.w	#$0180,d1
			bne.s	.nextInst
			move.l	a0,(a1)+		; where the value word lives
			move.w	2(a0),(a2)+		; ... and what it should end up as
			addq.w	#1,d0
			bra.s	.nextInst
.ink:
			move.l	a0,(a3)+		; colour 1 too: the text's shading, which
			move.w	2(a0),(a4)+		; the ship and the letters get in there
			addq.w	#1,d2
.nextInst:
			lea		4(a0),a0
			bra.s	.scan
.scanned:
			move.w	d0,barColorCount
			move.w	d2,barInkCount

introRestart:
			bsr		blankLogo
			clr.w	introTime
			clr.w	introLogoLine
			clr.w	introLogoPass
			clr.w	introBarTick
			sf		introLogoDone
			sf		introBarDone
			sf		introLogoShown
			sf		introGameOn
			bsr		blankBar
			bsr		introHideLogo
			bsr		introHideGame
			rts

;---------------------------------------------
; A black logo is still a logo as far as the blitter... sorry, as far as
; the display hardware is concerned: the bitplanes are fetched, the pixels
; are drawn in colour 0, and playfield priority puts them in front of the
; sprites. So the starfield disappears behind a black rectangle. Hiding it
; properly means making the logo region look exactly like the empty single
; plane region above it - one plane, pointed at the blank line, modulo
; -li so it repeats.
;---------------------------------------------
introHideLogo:
			move.w	#$1200,logoPlanes		; one plane instead of three
			move.w	#$ffd2,logoPlaneMod
			move.l	#src_adr-li,d0			; ... aimed at the empty line
			move.w	d0,logobp0l
			swap	d0
			move.w	d0,logobp0h
			rts

introShowLogo:
			move.w	#$3200,logoPlanes		; logo only, or with the game
			tst.b	introGameOn				; plane 4 in it once the game is up
			beq.s	.noGame
			move.w	#$4200,logoPlanes
.noGame:
			move.w	#$0000,logoPlaneMod
			moveq	#0,d1
			bsr		updateLogoPointers		; bp0..bp2 back onto the logo
			rts

;---------------------------------------------
; Nothing should be drawn in the game area before the game starts, so
; rather than blacking out colours - which would also black out the ship
; and the letters once they do appear - the bitplane is simply pointed at
; the blank line and the shadow playfield is switched off. clearScroller
; rewrites bp0 every frame, so the hide has to be reapplied each frame.
;---------------------------------------------
introHideGame:
			move.l	#src_adr-li,d0
			move.w	d0,bp0+2
			swap	d0
			move.w	d0,gamebp0h
			move.w	#$ffd2,gamePlaneMod		; -li, repeats the blank line
			move.w	#$1200,gamePlanes2		; one plane, no dual playfield
			move.w	#$1200,gamePlanes3
			move.w	#$1200,topPlanes		; no game plane 4 above gameTop
			move.w	#$1200,midPlanes
			tst.b	introLogoShown
			beq.s	.noLogo
			move.w	#$3200,logoPlanes
.noLogo:
			rts

introShowGame:
			move.w	#$0000,gamePlaneMod	; (gamebp0h: clearScroller, each frame)
			move.w	#$3600,gamePlanes2		; (+ the ember plane: the fireworks' colours)
			move.w	#$3600,gamePlanes3		; + ember plane, see emberTop
			move.w	#$4200,topPlanes		; game plane 4 above gameTop
			move.w	#$4200,midPlanes
			tst.b	introLogoShown
			beq.s	.noLogo
			move.w	#$4200,logoPlanes
.noLogo:
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
			move.w	barColorCount,d0
			beq.s	.none
			subq.w	#1,d0
			lea		barColorAddr,a1
.b:
			move.l	(a1)+,a0
			clr.w	2(a0)
			dbf		d0,.b
.none:
			; colour 1 of the bar (the text's shading - the ship and the
			; letters get it too in there): till the bar comes it is the
			; game's own colour, as above the bar. it goes over to the
			; shading with the bar's fade (fadeInBar)
			move.w	barInkCount,d0
			beq.s	.noInk
			subq.w	#1,d0
			lea		barInkAddr,a1
.i:
			move.l	(a1)+,a0
			move.w	#barInkPre,2(a0)
			dbf		d0,.i
.noInk:
			rts

;---------------------------------------------
; NOTE: every test below reads introTime straight out of memory rather
; than caching it in a register. fadeInLogo, fadeInBar, blankBar and
; updateLogoPointers all use d0 as scratch, so a cached copy would be a
; logo colour value by the time the bar gets tested - and colour values
; happen to be in the same numeric range as the cue times.
introUpdate:
			move.w	introTime,d0
			cmp.w	#$7000,d0			; stop counting, never wrap
			bhs.s	.noTick
			addq.w	#1,d0
			move.w	d0,introTime
.noTick:
			cmp.w	#introScrollStart+scrollFullTime,introTime
			blo.s	.notFull
			st		scrollReady			; the text runs across the whole bar now
.notFull:
			cmp.w	#introLogoStart,introTime
			blo.s	.noLogo
			tst.b	introLogoShown		; switch the bitplanes on once, at the
			bne.s	.logoOn				; moment the fade starts
			st		introLogoShown
			bsr		introShowLogo
.logoOn:
			bsr		fadeInLogo
.noLogo:
			cmp.w	#introGameStart,introTime
			bhs.s	.gameTime
			bsr		introHideGame		; every frame, clearScroller undoes it
			bra.s	.gameOn
.gameTime:
			tst.b	introGameOn
			bne.s	.gameOn
			st		introGameOn
			bsr		introShowGame
.gameOn:
			cmp.w	#introBarStart,introTime
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

; the same, but each nibble one up or down towards its target
; d0 = current, d1 = target -> d6 = stepped. uses d2/d3/d4.
colorStepTo::
			moveq	#0,d6
			move.w	#$00f,d4			; the nibble's mask: blue, green, red
.nib:
			move.w	d0,d2
			and.w	d4,d2
			move.w	d1,d3
			and.w	d4,d3
			cmp.w	d3,d2
			beq.s	.set
			bhi.s	.down
			move.w	d4,d3				; one step of this nibble: the mask's
			lsr.w	#3,d3				; lowest bit ($f>>3 = 1, $f0>>3 = $1e,
			and.w	d4,d3				; and the mask: $10 ...)
			add.w	d3,d2
			bra.s	.set
.down:
			move.w	d4,d3
			lsr.w	#3,d3
			and.w	d4,d3
			sub.w	d3,d2
.set:
			or.w	d2,d6
			lsl.w	#4,d4
			cmp.w	#$f000,d4
			bne.s	.nib
			rts

;---------------------------------------------
; lines above introLogoLine are one fade level ahead of the rest, so the
; brightness steps sweep down the logo. logoColorEngine does the colours.
fadeInLogo:
			tst.b	introLogoDone
			bne.s	.done
			moveq	#introLogoLines-1,d4
.lineFader:
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
			move.w	barColorCount,d7
			beq.s	.done
			subq.w	#1,d7
			lea		barColorAddr,a1
			lea		barColorsTarget,a2
			moveq	#1,d5				; assume everything has arrived
.barfade:
			move.l	(a1)+,a0
			move.w	2(a0),d0
			move.w	(a2)+,d1
			cmp.w	d0,d1
			beq.s	.arrived
			moveq	#0,d5
.arrived:
			bsr		colorFadeIn
			move.w	d6,2(a0)
			dbf		d7,.barfade
			move.w	barInkCount,d7		; colour 1 along with it, up or down
			beq.s	.inkDone
			subq.w	#1,d7
			lea		barInkAddr,a1
			lea		barInkTarget,a2
.ink:
			move.l	(a1)+,a0
			move.w	2(a0),d0
			move.w	(a2)+,d1
			cmp.w	d0,d1
			beq.s	.inkThere
			moveq	#0,d5
			bsr		colorStepTo
			move.w	d6,2(a0)
.inkThere:
			dbf		d7,.ink
.inkDone:
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
introGameOn:	dc.b	0		; game area bitplane switched on yet?
introTaken:		dc.b	0		; colour snapshot already taken?
				even
barColorCount:	dc.w	0		; how many colour writes the scan found
				even
barColorAddr:	blk.l	96,0	; address of each copper MOVE in the bar
barColorsTarget:
				blk.w	96,0	; ... and the value it should finish on
barInkCount:	dc.w	0		; the same for colour 1 ($0182) in the bar
barInkAddr:		blk.l	48,0
barInkTarget:	blk.w	48,0
barInkPre		= $0eee			; colour 1 there till the bar comes (as above it)

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

;---------------------------------------------
; LOGO COLOUR ENGINE
;---------------------------------------------
; Rewrites colours 1..7 and the copper wait of every logo gradient line,
; every frame. Colours 1, 2 and 5 (the greens) come straight out of
; logoLineTab, colours 3, 4, 6 and 7 (the chrome) are byte offsets into
; a 46 colour palette - one for the top 35 lines, one for the bottom 38.
; logoLineTab holds a set of 73 lines for every bob position, so the
; chrome reflection stays put on screen while the logo moves under it.
;
; While the logo fades up (introLogoDone clear) the same line data is
; looked up in logoFade at each line's fade level instead. The last fade
; level is palette 0, which is where the animation below starts off.
;
; Once the logo is up, the chrome cross fades to the next of 12 palettes
; every time the music bumps logoPalTarget (see musicPalTick in music.s).
;
; in:  d0 = raster line of the logo top
; out: d0 = raster line the logo window closes at, minus logo_area_height
;---------------------------------------------
logoLineSize	= 7*2				; bytes per line in logoLineTab
logoPalSize		= 2*46*2			; bytes per palette, top + bottom half
logoPalSteps	= 25				; blend steps stored per palette
logoPalCount	= 12
logoTopLines	= 35				; lines that use the top half palette
logoBlendTime	= $1b6				; blend countdown, -5 per frame (~88 frames)
logoFadeLit		= $746				; logoFade: colour -> row offset table first,
logoFadeLevels	= logoFadeLit+$1e0	; then the faded greens, then 16 faded palettes

; one gradient line. was a bsr/rts subroutine - inlined that is 34 cycles
; less per line, 73 lines per frame.
; a3 = line data, a4 = palette half, a0 = gradient line in the copperlist
LOGO_LINE	macro
			move.w	(a3)+,2(a0)				; colour 1
			move.w	(a3)+,6(a0)				; colour 2
			move.w	(a3)+,d1
			move.w	(a4,d1.w),10(a0)		; colour 3
			move.w	(a3)+,d1
			move.w	(a4,d1.w),14(a0)		; colour 4
			move.w	(a3)+,18(a0)			; colour 5
			move.w	(a3)+,d1
			move.w	(a4,d1.w),22(a0)		; colour 6
			move.w	(a3)+,d1
			move.w	(a4,d1.w),26(a0)		; colour 7
			endm

logoColorEngine:
			movem.l	d0-d7/a0-a6,-(a7)
			move.b	d0,logoStartWait
			move.w	d0,d3
			lsl.w	#8,d3
			add.w	#$0101,d3				; wait of the second gradient line

			; --- line data for this bob position
			move.w	d0,d1
			sub.w	#logoY-16,d1
			bpl.s	.posLow
			moveq	#0,d1
.posLow:
			cmp.w	#logoBobMax,d1
			bls.s	.posHigh
			move.w	#logoBobMax,d1
.posHigh:
			mulu.w	#logo_area_height*logoLineSize,d1
			lea		logoLineTab,a3
			add.l	d1,a3
			lea		logoColors,a0

			tst.b	introLogoDone
			beq		.fadeIn

			; --- new music cue? then start blending into the next palette
			move.w	logoPalBlend,d4
			bne.s	.blend
			move.w	logoPalTarget,d1
			cmp.w	logoPalSeen,d1
			beq.s	.render
			move.w	d1,logoPalSeen
			move.w	logoPalCur,d5
			move.w	logoPalNext,d2
			move.w	d2,logoPalCur
			addq.w	#1,d2
			cmp.w	#logoPalCount,d2
			blo.s	.noWrap
			moveq	#0,d2
.noWrap:
			move.w	d2,logoPalNext
			cmp.w	logoPalCur,d5
			beq.s	.render					; same palette, nothing to blend
			move.w	#logoBlendTime,d4
.blend:
			moveq	#0,d2
			move.w	#logoBlendTime,d2
			sub.w	d4,d2
			mulu.w	#logoPalSteps-1,d2
			divu.w	#logoBlendTime-3,d2		; -3: the last frame (d4 = 3) lands on step 24
			move.w	d2,logoPalStep
			subq.w	#5,d4
			bpl.s	.blendOk
			moveq	#0,d4
.blendOk:
			move.w	d4,logoPalBlend
.render:
			move.w	logoPalCur,d2
			mulu.w	#logoPalSteps,d2
			add.w	logoPalStep,d2

			; --- same bob position and same blend step as the last rewrite?
			;     then the copperlist already holds exactly these waits and
			;     colours. the bob only crosses a raster line on about two
			;     frames in three, so this skips ~17000 cycles on the rest
			;     (not while a palette blend is running - every step differs)
			cmp.w	logoDrawnPal,d2
			bne.s	.redraw
			cmp.w	logoDrawnPos,d0
			beq		.done
.redraw:
			move.w	d2,logoDrawnPal
			move.w	d0,logoDrawnPos

			mulu.w	#logoPalSize,d2
			lea		logoPalettes,a4
			add.l	d2,a4
			lea		logoPalSize/2(a4),a2	; bottom half
			move.w	#$0100,d6				; wait step, add.w d6 is 4 cycles faster
											; than add.w #$0100

			LOGO_LINE						; first line has no wait
			moveq	#logoTopLines-2,d7
.top:
			lea		(2*2)+(logo_color_count*2*2)(a0),a0
			move.w	d3,-4(a0)
			add.w	d6,d3
			LOGO_LINE
			dbf		d7,.top

			move.l	a2,a4
			moveq	#logo_area_height-logoTopLines-1,d7
.bottom:
			lea		(2*2)+(logo_color_count*2*2)(a0),a0
			move.w	d3,-4(a0)
			add.w	d6,d3
			LOGO_LINE
			dbf		d7,.bottom
			bra		.done

			; --- fade in. lines above introLogoLine are one level ahead
.fadeIn:
			move.w	#-1,logoDrawnPal		; the fade writes other colours, so
											; force a full rewrite once it is over
			lea		logoFade,a6
			lea		logoFadeLit(a6),a1
			lea		logoFadeLevels(a6),a2
			moveq	#0,d5					; line
.fadeLine:
			move.w	introLogoPass,d0
			cmp.w	introLogoLine,d5
			bhs.s	.levelOk
			addq.w	#1,d0
.levelOk:
			move.w	d0,d6
			add.w	d6,d6					; level -> column in the faded greens
			mulu.w	#logoPalSize,d0
			lea		(a2,d0.l),a4			; faded palette
			cmp.w	#logoTopLines,d5
			blo.s	.fadeTop
			lea		logoPalSize/2(a4),a4
.fadeTop:
			move.w	(a3)+,d1				; colour 1
			add.w	d1,d1
			move.w	(a6,d1.w),d1
			add.w	d6,d1
			move.w	(a1,d1.w),2(a0)
			move.w	(a3)+,d1				; colour 2
			add.w	d1,d1
			move.w	(a6,d1.w),d1
			add.w	d6,d1
			move.w	(a1,d1.w),6(a0)
			move.w	(a3)+,d1
			move.w	(a4,d1.w),10(a0)		; colour 3
			move.w	(a3)+,d1
			move.w	(a4,d1.w),14(a0)		; colour 4
			move.w	(a3)+,d1				; colour 5
			add.w	d1,d1
			move.w	(a6,d1.w),d1
			add.w	d6,d1
			move.w	(a1,d1.w),18(a0)
			move.w	(a3)+,d1
			move.w	(a4,d1.w),22(a0)		; colour 6
			move.w	(a3)+,d1
			move.w	(a4,d1.w),26(a0)		; colour 7

			addq.w	#1,d5
			cmp.w	#logo_area_height,d5
			bhs.s	.done
			lea		(2*2)+(logo_color_count*2*2)(a0),a0
			move.w	d3,-4(a0)
			add.w	#$0100,d3
			bra		.fadeLine

.done:
			movem.l	(a7)+,d0-d7/a0-a6
			; the new logo's art reaches 5 rows past the gradient, so the
			; window stays open 5 lines longer (on the last line's colours),
			; capped at logoBottom so it never runs into the game area
			addq.w	#5,d0
			cmp.w	#logoBobMax+logoY-16,d0
			bls.s	.endOk
			move.w	#logoBobMax+logoY-16,d0
.endOk:
			rts

;---------------------------------------------
; Palette 0 is already on screen when the fade in ends, so the first cue
; the engine sees only steps logoPalNext on to 1. Rather than burning a
; real music cue on that (the colours would then sit still for ~30
; seconds), fake one on the next 24 tick boundary of the music count.
;---------------------------------------------
logoPaletteKick:
			tst.b	introLogoDone
			bne.s	.up
			clr.w	logoKickState
			rts
.up:
			move.w	logoKickState,d1
			cmp.w	#2,d1
			beq.s	.done					; already kicked
			moveq	#0,d0
			move.w	musicPalCountdown,d0
			add.w	#23,d0
			divu.w	#24,d0
			tst.w	d1
			bne.s	.armed
			move.w	d0,logoKickSlot			; first frame up: remember the slot
			move.w	#1,logoKickState
			rts
.armed:
			cmp.w	logoKickSlot,d0
			beq.s	.done
			move.w	#2,logoKickState
			move.w	logoPalTarget,d0
			subq.w	#1,d0
			move.w	d0,logoPalSeen			; looks like a new cue to the engine
.done:
			rts

logoPaletteInit:
			clr.w	logoPalCur
			move.w	#logoPalSteps-1,logoPalStep	; = where the fade in ends
			clr.w	logoPalNext
			clr.w	logoPalBlend
			move.w	logoPalTarget,logoPalSeen
			clr.w	logoKickState
			move.w	#-1,logoDrawnPal
			rts

logoPalCur:		dc.w	0		; palette on screen
logoPalStep:	dc.w	logoPalSteps-1	; blend step into it, 24 = fully there
logoPalNext:	dc.w	0		; palette the next cue blends to
logoPalSeen:	dc.w	0		; last logoPalTarget the engine acted on
logoPalBlend:	dc.w	0		; blend countdown, 0 = not blending
logoKickState:	dc.w	0		; 0 = logo not up, 1 = armed, 2 = done
logoKickSlot:	dc.w	0
logoDrawnPal:	dc.w	-1		; palette*steps+step of the last full rewrite
logoDrawnPos:	dc.w	-1		; ... and the logo top raster line it was for

logoMoveDir:
			dc.w	1
logoMoveDirCount:
			dc.w	24
logoMoveSpeed:
			dc.w	0
logoPos:
			dc.w	0

text:
		dc.b	"<<< THRUST + QUADLITE >>> THE DISK BOOTS. NOBODY TOUCH ANYTHING! "
		dc.b	"* + * + * SUPREME WANTS MORE COLOURS.....................*******OOOOOOOOO "
		dc.b	"TRAITORS WANTS MORE SPEED. THREAT WANTS TO KNOW WHO MOVED THE ASTEROIDS. "
		dc.b	"o O @ O o THERE GO THE STARS: **** *** ** * . . * ** *** **** "
		dc.b	"ALL PRESENT? GOOD. SEND THEM BACK! <<< <<< >>> >>> "
		dc.b	"LORD PERFORMER SAYS THE COPPER IS INNOCENT. THE BLITTER REFUSES TO COMMENT. "
		dc.b	"/ / / \\ \\ \\ THIS IS A SCROLLTEST, SO HERE IS A SERIOUS TECHNICAL QUESTION: "
		dc.b	"WHO ATE THE LAST BISCUIT? [ ?! ] "
		dc.b	"GREETZ TO THE OLD CREW AND EVERYONE STILL FEEDING DISKS TO AN AMIGA. "
		dc.b	"ONE MORE PIXEL... NO, WAIT... TWO! # + * . * + # "
		dc.b	"THRUST / QUADLITE -- STILL NOT FINISHED!          ",0
		even

logo:
        INCBIN	"thrust-quadlite_3pl_update_final.bin"	; 320x96, 3 bitplanes

; base palette of the new logo. logoColorEngine overwrites colours 1..7 on
; every line every frame, these only seed the copperlist layout.
logoColorsOrig:
	dc.w	$0182,$0121		; green, dark
	dc.w	$0184,$0151		; green
	dc.w	$0186,$0555		; chrome
	dc.w	$0188,$0777		; chrome
	dc.w	$018a,$03a2		; green, light
	dc.w	$018c,$0abb		; chrome
	dc.w	$018e,$0eee		; chrome
	; the last three slots of every gradient line are dummies now: colours
	; 8..15 are the game plane over the logo and are set once at the top
	; of clist. $1fe is the copper's no-op register.
	dc.w	$01fe,$0000
	dc.w	$01fe,$0000
	dc.w	$01fe,$0000

gameColor		= $0eee		; ship, shots and letters, same as colour 1 below

; copperlist
;--------------------------------------------------------------
; the Elite ending's copper list (stars3d.i puts the copper over to it):
; the stars in planes 1..3 (colours 1..7: dim, middle, bright, and the
; engines' glow), the game's lines in plane 4 in front of them (8..15)
; from the top of the window to the bottom - one buffer each, no tricks.
; the logo is clist's own part: a jump there, and back here once it is
; through (stars3d.i s3Activate patches clist right after logoEndWait).
; the pointers: s3Flip (each frame), s3MidPatch (below the logo)
ELC1			= $0125		; dim (warp.i warpCol1)
ELC2			= $0371		; middle (warpCol2)
ELC3			= $0a20		; the glow's rim
ELC4			= $0842		; bright (warpCol3)
ELC5			= $0f60		; the glow
ELC6			= $0fb3
ELC7			= $0ffe		; ... its core
ELCOLS	macro
		dc.w	$0182,ELC1,$0184,ELC2,$0186,ELC3,$0188,ELC4
		dc.w	$018a,ELC5,$018c,ELC6,$018e,ELC7
		endm
		cnop	0,4
clistElite::
		dc.w	BPLCON0,$0200
		dc.w	$0102,$0000,$0104,$0024,$0108,$0000,$010a,$0000	; (the
							; sprites - the torpedoes' glows - in front)
		dc.w	DDFSTRT,$0028
		dc.w	DDFSTOP,$00d8
		dc.w	DIWSTRT,(fullTop<<8)+$81
		dc.w	DIWSTOP,((screenBottom&$ff)<<8)+$c1
elSpr::	dc.w	$120,0,$122,0,$124,0,$126,0
		dc.w	$128,0,$12a,0,$12c,0,$12e,0
		dc.w	$130,0,$132,0,$134,0,$136,0
		dc.w	$138,0,$13a,0,$13c,0,$13e,0
		dc.w	$0180,$0000
		dc.w	$01a2,ELC3,$01a4,ELC5,$01a6,ELC7	; the torpedoes' glows (morph.i
		dc.w	$01aa,ELC3,$01ac,ELC5,$01ae,ELC7	; morphTorpSpr: sprites 0, 1, 2):
									; rim, middle, core
elCol0::
		ELCOLS
		dc.w	$0190,gameColor,$0192,gameColor,$0194,gameColor,$0196,gameColor
		dc.w	$0198,gameColor,$019a,gameColor,$019c,gameColor,$019e,gameColor
		dc.w	((fullTop-1)<<8)+$01,$fffe
elTop::	dc.w	$00e0,0,$00e2,0,$00e4,0,$00e6,0
		dc.w	$00e8,0,$00ea,0,$00ec,0,$00ee,0
		dc.w	BPLCON0,$4200
		dc.w	$0084
elJmpH::
		dc.w	0
		dc.w	$0086
elJmpL::
		dc.w	0
		dc.w	$008a,$0000		; into clist for the logo
eliteMid::							; ... and back: the star planes again
		dc.w	$00e0,0,$00e2,0,$00e4,0,$00e6,0,$00e8,0,$00ea,0
		dc.w	BPLCON0,$4200
		dc.w	$0108,$0000
elCol1::
		ELCOLS
		dc.w	$ffdf,$fffe
		dc.w	((screenBottom&$ff)<<8)+$01,$fffe
		dc.w	BPLCON0,$0200
		dc.w	$ffff,$fffe

clist:		dc.w	BPLCON0,$0200		; bitplanes off
		dc.w	$0102,$0000		; no scroll delay. the bar sets its own per
								; line, and when glitchFrame tears its last
								; lines that would hang on into the logo

		dc.w	$0108,$0000		; even bitplanes modulo
		dc.w	$010a,$0000		; odd bitplanes modulo

		; one fetch width for the whole screen, the game plane's. the logo
		; was drawn for $38..$d0 and is padded to match (buildLogoPadded).
		dc.w	DDFSTRT,$0028
		dc.w	DDFSTOP,$00d8
		; the display window, see fullTop. horizontally the usual $81..$c1
		; (x 32..351 of the game plane), vertically fullTop..screenBottom
		dc.w	DIWSTRT,(fullTop<<8)+$81
		dc.w	DIWSTOP,((screenBottom&$ff)<<8)+$c1

		; colours 8..15 = the game pixel over any logo colour (game plane 4,
		; see the block at fullTop-1). colour 9 is the bar's shadow colour
		; further down, so it is put back every frame.
		dc.w	$0190,gameColor
		dc.w	$0192,gameColor
		dc.w	$0194,gameColor
		dc.w	$0196,gameColor
		dc.w	$0198,gameColor
		dc.w	$019a,gameColor
		dc.w	$019c,gameColor
		dc.w	$019e,gameColor

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

		; star colours - the original coloured set again (same as clistGame).
		; the grey toned set was $09ab, $0678, $0223, $0345
starColours::					; (warp.i fades these over to its ramp)
		dc.w	$01a2,$0842		; 1
		dc.w	$01a4,$0371		; 2
		dc.w	$01a6,$0fff
		dc.w	$01aa,$0125		; 4
		dc.w	$01ac,$0fff
		dc.w	$01ae,$0631		; 3

		; from fullTop down to gameTop the game is plane 4 of a 4 plane
		; screen, IN FRONT of the logo (colours 8..15, see above). no dual
		; playfield: 4 planes in lowres cost the CPU nothing.
		; above the logo: planes 1 and 3 repeat the blank line, plane 2 reads
		; zeroArea (it shares a modulo with the game plane 4, so it can not
		; repeat a line), plane 4 is the game. topPlanes is $1200 - just the
		; blank plane 1 - until the game starts.
		; the line BEFORE the window: when the logo starts right at the top
		; its own pointer block runs on the same line as this one would, and
		; both together no longer fit in before the first fetch.
		dc.w	((fullTop-1)<<8)+$01,$fffe
		; game plane 4 is only set here: it is fetched on every line from
		; the top of the window down to gameTop, so it runs on by itself.
		; NOT at the very top of clist: the copper runs that part at line 0,
		; before the VBL handler's clearScroller has flipped gamebpl4, so it
		; would show the buffer that is being cleared and redrawn right now
		; - the ship and letters flicker or vanish above gameTop. by line
		; fullTop-1 clearScroller (the first thing in the frame) is done.
		dc.w	$00ec
gamebpl4h:
		dc.w	0				; (clearScroller)
		dc.w	$00ee
gamebpl4:
		dc.w	0
		dc.w	$0182,$0000	   ; black plane
		dc.w	$00e0
blankTop1h:
		dc.w	0				; (the blank line: patchScreens)
		dc.w	$00e2
blankTop1l:
		dc.w	0
		dc.w	$00e8
blankTop3h:
		dc.w	0
		dc.w	$00ea
blankTop3l:
		dc.w	0
		dc.w	$00e4
topZero2h:
		dc.w	0
		dc.w	$00e6
topZero2l:
		dc.w	0
		dc.w	$0108,$ffd2			; odd planes modulo -li: repeat the blank line
		dc.w	BPLCON0
topPlanes:
		dc.w	$1200

; the logo start can be as high as fullTop itself, so this block must stay
; short enough to finish before DDFSTRT on that line.
logoStartWait::
 		dc.w	$4001,$fffe
        ; note: logo bp0 has to be set here as we have a empty bitplane 0
        ;       before the logo starts or else the sprites (stars) won't display
		; the pointers go first - all of them have to be in before the
		; first fetch at DDFSTRT $28
		dc.w	$00e0
logobp0h:
		dc.w	0
		dc.w	$00e2
logobp0l:
		dc.w	0
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
		dc.w	BPLCON0
logoPlanes:
		dc.w	$3200				; 3 bitplanes, $4200 with the game plane. patched
								; to $1200 while the logo is still hidden, so
								; the region behaves exactly like the empty
								; single plane above it and the sprites keep
								; showing through
		dc.w	$0108
logoPlaneMod:
		dc.w	$0000				; odd bitplanes modulo, patched to $ffd2

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

logoEndWait::
 		dc.w	$6c01,$fffe			; logo end wait
		; same as above the logo: empty planes 1..3, game plane 4 runs on.
		; eight moves, all done before the first fetch at DDFSTRT $28.
		dc.w	$00e0
blankMid1h:
		dc.w	0
		dc.w	$00e2
blankMid1l:
		dc.w	0
		dc.w	$00e8
blankMid3h:
		dc.w	0
		dc.w	$00ea
blankMid3l:
		dc.w	0
		dc.w	$00e4
midZero2h:
		dc.w	0
		dc.w	$00e6
midZero2l:
		dc.w	0
		dc.w	BPLCON0
midPlanes:
		dc.w	$1200
		dc.w	$0108,$ffd2			; odd planes modulo -li: repeat the blank line

		dc.w	(gameTop<<8)+1,$fffe	; start of "game" area
		dc.w	BPLCON0,$1200	; 1 bitplanes on
		dc.w	$00e0
gamebp0h:
		dc.w	0				; bitplane 0, patched to the blank line while
							; the game has not started yet
bp0:	dc.w	$00e2,$0000		;

		dc.w	$0108
gamePlaneMod:
		dc.w	$0000			; even bitplanes modulo, patched to -li
		dc.w	$010a,$0000		; odd bitplanes modulo

		dc.w	$0092,$0028
		dc.w	$0094,$00d8

		dc.w	$0182,$0eee	; game area before scroller color

		; ember plane (dual playfield plane 3, see emberTop). the pointer
		; is set up here while plane 3 is still off, so it sits untouched
		; until gamePlanes3 at $ef switches the plane on. emberbpl is
		; flipped with bp0.
		dc.w	$00e8
emberbplh:
		dc.w	0
		dc.w	$00ea
emberbpl:
		dc.w	0
		dc.w	$0186,$0f93	; dot glowing out, orange (plane 1 + ember)
		dc.w	$0184,$0a32	; dot glowing out, red (ember only)

		; the TV switch off sends the copper through tvList instead of the
		; bar (COP2LC + COPJMP2, and back the same way). no-ops until then,
		; tvStart patches them
tvJump:	dc.w	$01fe
tvJumpH:
		dc.w	0
		dc.w	$01fe
tvJumpL:
		dc.w	0
		dc.w	$01fe,0

barRegionStart:				; everything from here to barRegionEnd is the
								; scroller bar, background AND shading
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
		dc.w	$0100
gamePlanes2:
		dc.w	$3600			; 2 bitplanes on	(dual playfield mode), patched
							; to $1200 so the shadow plane is not fetched
							; before the game starts
		dc.w	$00e4
shadowH:
		dc.w	0				; bitplane 01 (patchScreens)
		; dc.w	$00e6,(li*75)-2		; + lines offset to adjust shadow pos
		; shifted with the rest of the buffer content so the shadow keeps
		; reading the same lines it used to
		dc.w	$00e6
shadowL:
		dc.w	0				; + lines offset to adjust shadow pos
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
barShadow:
		dc.w	$0192,$0112		; shadow color (barBlack: off with the bar)
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
barRegionEnd:
		dc.w	$0102,$0000		; and none below the bar either (the ship,
								; the dots) - a tear stays inside the bar
		dc.w	BPLCON0
gamePlanes3:
		dc.w	$3600			; black from here on: ember plane 3 joins in.
							; patched to $1200 like gamePlanes2

		; dc.w	$f001,$fffe
		; dc.w	$0180,$0000	; wall end


		dc.w	$ffdf,$fffe		; wait for end of line 255
		dc.w	$0001,$fffe
		; the buffer ends at screenBottom. below it plane 1 would run on
		; into the ember plane and show its dots again in white, and the
		; shadow plane into whatever follows - so switch the planes off
		; there, whatever the display window is set to.
		dc.w	((screenBottom&$ff)<<8)+$01,$fffe
		dc.w	BPLCON0,$0200	; bitplanes off
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

;--------------------------------------------------------------
; the bar for the TV switch off (see tvUpdate): every move of the bar
; region of clist on the same line, so the planes come out exactly the
; same, but no colour 0 gradient of its own - a TV_COL on every line
; instead, and on the two middle lines a pair of h waits for the line
; that shrinks to a dot.
tvList:
		TV_LINE	$bf
		dc.w	$0182,$0777
		TV_COL
		TV_LINE	$c0
		TV_COL
		TV_LINE	$c1
		dc.w	$0182,$0888
		TV_COL
		TV_LINE	$c2
		dc.w	$0182,$0999
		TV_COL
		TV_LINE	$c3
		dc.w	$0182,$0aaa
		TV_COL
		TV_LINE	$c4
		dc.w	$0182,$0bbb
		dc.w	$0100
tvPlanes2:
		dc.w	$3600
		dc.w	$00e4
tvShadowH:
		dc.w	0
		dc.w	$00e6
tvShadowL:
		dc.w	0
		dc.w	$0192,$0000
		TV_COL
		TV_LINE	$c5
		dc.w	$0182,$0ccc,$010a,$ffd2,$0102,$0050
		TV_COL
		TV_LINE	$c6
		dc.w	$0182,$0ddd,$010a,$0000,$0102,$0040
		TV_COL
		TV_LINE	$c7
		dc.w	$0182,$0ccc,$010a,$ffd2,$0102,$0030
		TV_COL
		TV_LINE	$c8
		dc.w	$0182,$0aaa,$010a,$0000,$0102,$0020
		TV_COL
		TV_LINE	$c9
		dc.w	$0182,$0989,$010a,$ffd2,$0102,$0010
		TV_COL
		TV_LINE	$ca
		dc.w	$0182,$0868,$010a,$0002,$0102,$0000
		TV_COL
		TV_LINE	$cb
		dc.w	$0182,$0868,$010a,$ffd2,$0102,$00f0
		TV_COL
		TV_LINE	$cc
		TV_COL
		TV_LINE	$cd
		TV_COL
		TV_LINE	$ce
		dc.w	$0182,$0858,$010a,$0000,$0102,$00e0
		TV_COL
		TV_LINE	$cf
		dc.w	$0182,$0858,$010a,$ffd2,$0102,$00c0,$0192
tvShadowCol:
		dc.w	$0112						; (the shadow, off with the TV: tvLine)
		TV_COL
		TV_LINE	$d0
		dc.w	$0182,$0868,$010a,$0000,$0102,$00b0
		TV_COL
		TV_LINE	$d1
		dc.w	$0182,$0767,$010a,$ffd2,$0102,$00a0
		TV_COL
		TV_LINE	$d2
		dc.w	$0182,$0656,$010a,$0000,$0102,$0090
		TV_COL
		TV_LINE	$d3
		dc.w	$0182,$0666,$010a,$ffd2,$0102,$0080
		TV_COL
		TV_LINE	$d4
		dc.w	$0182
tvBD4:	dc.w	$0777,$010a,$0000,$0102,$0070
		TV_COL
		TV_LINE	$d5
		dc.w	$0182
tvBD5:	dc.w	$0888,$010a,$ffd2,$0102,$0060
		TV_COL
		TV_LINE	$d6
		dc.w	$0182
tvBeam0:
		dc.w	$0988,$010a,$0000,$0102,$0050
		TV_COL
		TV_LINE	$d7
		dc.w	$0182
tvBeam1:
		dc.w	$0a99,$010a,$ffd2,$0102,$0040
		TV_COL
		TV_LINE	$d8
		dc.w	$0182
tvBeam2:
		dc.w	$0baa,$010a,$0000,$0102,$0030
		TV_COL
		TV_LINE	$d9
		dc.w	$0182
tvBeam3:
		dc.w	$0dcc,$010a,$ffd2,$0102,$0020
		TV_COL
		TV_LINE	$da
		dc.w	$0182
tvBDA:	dc.w	$0ddd,$010a,$0000,$0102,$0010
		TV_COL
		TV_LINE	$db
		dc.w	$0182
tvBDB:	dc.w	$0eee,$0102,$0000
		TV_COL
		TV_LINE	$dc
		TV_COL
		TV_LINE	$dd
		TV_COL
		TV_LINE	$de
		TV_COL
		TV_LINE	$df					; tvMid
		TV_COL
tvH0s:	dc.w	($df<<8)+$e1,$fffe	; from here ...
		dc.w	$0180
tvH0c1:	dc.w	0
tvH0e:	dc.w	($df<<8)+$e1,$fffe	; ... to here the line colour
		dc.w	$0180
tvH0c2:	dc.w	0
		TV_LINE	$e0
		TV_COL
tvH1s:	dc.w	($e0<<8)+$e1,$fffe
		dc.w	$0180
tvH1c1:	dc.w	0
tvH1e:	dc.w	($e0<<8)+$e1,$fffe
		dc.w	$0180
tvH1c2:	dc.w	0
		TV_LINE	$e1
		TV_COL
		TV_LINE	$e2
		TV_COL
		TV_LINE	$e3
		TV_COL
		TV_LINE	$e4
		TV_COL
		TV_LINE	$e5
		TV_COL
		TV_LINE	$e6
		TV_COL
		TV_LINE	$e7
		TV_COL
		TV_LINE	$e8
		TV_COL
		TV_LINE	$e9
		TV_COL
		TV_LINE	$ea
		TV_COL
		TV_LINE	$eb
		TV_COL
		TV_LINE	$ec
		TV_COL
		TV_LINE	$ed
		TV_COL
		TV_LINE	$ee
		TV_COL
		TV_LINE	$ef
		TV_COL
		dc.w	$0084				; back to clist, right after the bar
tvBackH:
		dc.w	0
		dc.w	$0086
tvBackL:
		dc.w	0
		dc.w	$008a,$0000
tvListEnd:

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

;--------------------------------------------------------------
; logo colour tables for logoColorEngine, taken from the "New Logo" build.
; only the CPU reads them, so they stay out of chip memory.
		section "logodata",data
logoLineTab:	incbin	"logo_lines.bin"	; 37 bob positions x 73 lines x 7 words
logoPalettes:	incbin	"logo_palettes.bin"	; 12 palettes x 25 blend steps x 92 colours
logoFade:		incbin	"logo_fade.bin"		; see logoFadeLit / logoFadeLevels
		even
		include	"fw.i"				; the fireworks' sparks (fwgen.py), 32k


;--------------------------------------------------------------
; chip memory the display reads, cleared by the loader
		section "scrollerchip",bss_c
logoPadded:		ds.b	3*logo_height*li	; the logo at the game plane's width
zeroArea:		ds.b	zeroLines*li		; plane 2 above and below the logo

;--------------------------------------------------------------
; the screens: the scroll text's source (with a blank line in front of it,
; which the empty planes repeat) and the two game buffers, one after the
; other as they were at $6e000-li, $6e000, $70000, $78000 - now in chip
; memory the system has given us, so the program itself never lies there
		section "screens",bss_c
		ds.b	li					; the blank line
src_adr::		ds.b	$2000
bufA::			ds.b	$8000
bufB::			ds.b	$8000
