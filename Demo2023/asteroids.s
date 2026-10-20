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

;======================================================================
; TUNING CONSTANTS
;======================================================================
; Everything adjustable lives here. Order matters only where one
; constant is defined in terms of another, which is why the groups run
; geometry first and the autopilot last.
;
;----------------------------------------------------------------------
; screen and play area. game_height must stay at or below the number of
; buffer lines the display window actually shows, or objects spend part of
; their time drawn somewhere nobody can see.
;----------------------------------------------------------------------
; the game shares the scroller part's single bitplane buffer, so this MUST
; match scroller.s: screenHeight and li. clipping and the vertical wrap in
; obj_move are derived from it, and anything above it would draw past the
; end of the 5888 byte buffer.
game_width		= 352
; the game now covers the whole screen: buffer line 0 is raster $20 (the
; top of the display window scroller.s sets), line 267 the last visible
; one. scroller.s: gameLines, and screenloc is the top of that full screen
; buffer (the scroller part's own buffer starts game_top lines further down).
game_height		= 268
game_top		= 110			; scroller.s topLines: where the old, lower
								; game area started. the word row and the ship
								; start are kept at the same spot on screen
game_lineBytes	= $2e			; screen line size in bytes

; --- wrapping. everything that leaves one side comes back in on the other.
; the band an object is moved across is hidden: x 0..31 is behind the left
; border and 352.. behind the right one, and y < 0 or >= game_height is
; clipped. the bands are wider than half a letter, so a letter has fully
; gone before it reappears on the other side.
wrap_x0			= 16			; x wraps over wrap_x0..wrap_x1-1
wrap_x1			= game_width+16
wrap_my			= 20			; y wraps over -wrap_my..game_height+wrap_my-1

;----------------------------------------------------------------------
; object types and limits
;----------------------------------------------------------------------
max_objlines 	= 10
; object type ids, index into coord_tabs
ship	=	0		; own spaceship
shot	=	1		; own shot
big		=	2		; big asteroid
medium	=	3		; medium asteroid
small	=	4		; small asteroid
letter	=	5

;----------------------------------------------------------------------
; word and letter placement
;----------------------------------------------------------------------
ast_count = 8
ast_x_start		= 100			; for medium
ast_x_offset 	= 24			; the nominal slot width. letterAdvance below
								; is written as offsets from it, so changing this
								; still scales the whole word
; visible centre of the play area - DDFSTRT $28 puts bitplane pixel 0
; at hpos 97 while DIWSTRT is 129, so x 0..31 is behind the border
ast_x_center	= 192
ast_y_start		= game_top+16
wordGap			= 40		; frames after the last shot dies before the
							; next word is allowed to appear

;----------------------------------------------------------------------
; letter appear animation
;----------------------------------------------------------------------
appear_frames	= 30		; how long one letter zooms and spins
appear_astep	= 12		; degrees per frame (30*12 == one full turn)
appear_scale0	= 4			; start scale, 64 == full size
appear_sstep	= 2			; scale step (4 + 30*2 == 64)
appear_stagger	= 15		; frames between letters -> 3 spinning at once

;----------------------------------------------------------------------
; the player ship
;----------------------------------------------------------------------
; --- object placement (buffer lines, not raster lines)
; buffer lines, not raster lines. the window shows 0..101 and the
; scroll text sits at 50..77.
ship_start_x	= 16		; off the left edge - the visible window is x 32..351,
							; so the ship waits here until the first word is up
ship_start_y	= game_top+96	; 80 below the word row (ast_y_start, ai_idledy),
							; so flying in never goes through the letters
; AUTOPILOT
; Drives ship_struct through exactly the same four calls the keyboard
; path uses - obj_addangle, obj_subangle, obj_thrust, shot_init - so it
; cannot do anything a player could not.
;
; No atan2 anywhere. The ship's facing vector is
;     f = (cos(angle-90), sin(angle-90))
; straight out of sctab, and for the vector d to the target:
;
;     cross = fx*dy - fy*dx      sign says which way to turn
;     dot   = fx*dx + fy*dy      positive means the target is ahead
;
; d(f)/d(angle) has a positive cross product with f, so cross > 0 always
; means "increase obj_angle to turn towards d". And since
; |cross|/dot == tan(angle error), the alignment tests are a couple of
; shifts and a compare - no square roots, no division.
;
; The flying is deliberately lazy: thrust happens in short bursts with
; random lengths, then the ship coasts. Above a speed limit it gives up
; on aiming, turns to face its own reverse velocity and counter-thrusts
; until it has slowed down, which is what produces the drifting,
; over-correcting look of somebody actually playing.
obj_maxvelo		= 128+64	; per axis, in 1/128 pixel per frame

;----------------------------------------------------------------------
; starfield
;----------------------------------------------------------------------
; starfield
;stars_count		= 105
stars_count		= 120

;----------------------------------------------------------------------
; autopilot - flying
;----------------------------------------------------------------------
ai_turnrate		= 6			; degrees per frame (the keyboard player gets 4)
; The engine fires only when the ship is NOT turning - rotate first, then
; burn in a straight line. Burning part way through a turn sweeps the
; thrust round in an arc and the ship just circles.
;
; The turn itself has hysteresis: it stops once inside a narrow cone and
; only starts again outside a wider one. With a single threshold the ship
; jitters left-right-left as the bearing drifts across it, which is what a
; player never does. The two cones are hard coded as shift-and-add
; sequences in ai_turn (x8, about 7 degrees, and x6, about 9.5) because
; |cross| is a full longword and muls.w cannot scale it.
ai_thrust		= 8			; thrust impulse, same as the player gets
ai_maxspeed		= 300		; |xvelo|+|yvelo| above which it brakes
ai_slowspeed	= 110		; ... and below which it stops braking
ai_thrustodds	= 0			; out of 256 - chance of a burst while ATTACKING.
							; 0 means it holds position and shoots, which is
							; what a player does once lined up. Raising it
							; makes the ship wander off its station and the
							; worst case clear time climbs sharply.
ai_travelodds	= 256		; out of 256, i.e. always. Flying to a spot is a
							; deliberate act - once the nose is lined up there
							; is no reason to roll dice about it. Lower it if
							; the approach looks too mechanical.
ai_thrustbase	= 4			; + 0..7 frames of thrust per burst
ai_travelburst	= 3			; + 0..1 - shorter bursts while repositioning,
							; because a long burn overshoots the station
ai_coastbase	= 8			; + 0..31 frames of coasting
ai_keepaway		= 75		; don't burn straight at a letter closer than this

;----------------------------------------------------------------------
; autopilot - staying on screen
;----------------------------------------------------------------------
; The viewer is trying to follow the ship, so letting it wrap off an edge
; is worse than the small loss of asteroids authenticity. Every frame the
; position is projected ai_lookahead frames along the current velocity; if
; that lands outside the box the AI takes over the steering. It cannot
; just point at the middle and burn - at 4 degrees a frame a turn takes 45
; frames and it would be long gone - so it kills the drift first and only
; heads for the middle once it is slow.
ai_keepbox		= 1			; 0 to go back to free flight
ai_lookahead	= 40		; frames of prediction
ai_boxx0		= 72
ai_boxx1		= 280
ai_boxy0		= game_top+10
ai_boxy1		= game_top+68
ai_boxcx		= (ai_boxx0+ai_boxx1)/2
ai_boxcy		= (ai_boxy0+ai_boxy1)/2

;----------------------------------------------------------------------
; autopilot - the entrance
;----------------------------------------------------------------------
; --- entrance
ai_enterangle	= 90		; obj_angle that points due right
ai_enterspeed	= 90	; xvelo for the fly-in (128 == 1 pixel/frame)
ai_enterwait	= 240	; frames after the first word STARTS appearing
						; before the ship flies in. Triggering on the spawn
						; rather than on the finished word gives it the whole
						; zoom-in plus the read pause to reach its station,
						; instead of arriving late and ploughing through.

;----------------------------------------------------------------------
; autopilot - picking a target
;----------------------------------------------------------------------
ai_retargetms	= 90		; frames before looking for a nearer letter
; --- how often a word gets the tidy along-the-row treatment instead of a
; general brawl. 256 would be always, 0 never.
; the along-the-row attack is now permanent. The screen is far wider than
; it is tall, so working the word from one end both looks tidier and keeps
; the ship in the part of the play area where there is room to manoeuvre.
; ai_sidemode is set once at init and never cleared.
; --- side attack. the ship works along the row from one end instead of
; picking whatever letter happens to be nearest, so the letters go off in
; sequence. it holds station just outside the end of the word and a little
; BELOW the row - level with the row would mean flying through the letters.
; --- the station. This is the spot the ship flies to before it starts
; shooting: level with the target letter and ai_stationdx to the side of
; it, on whichever end of the word we are attacking from.
ai_stationdx	= 30		; sideways offset from the letter. A letter is
							; about 24 wide and the ship about 10, so 24 left
							; only a 7 pixel gap and the ship kept clipping the
							; end letter on the way in. 40 gives it room.
ai_stationdy	= 0			; and vertical - 0 keeps the shot along the row,
							; raise it if the ship clips the letters

; --- flying states. APPROACH flies to the station, ARRIVE turns round and
; brakes because it is about to get there too fast to stop, ATTACK sits
; still and shoots. The two distances overlap deliberately: entering
; ATTACK at ai_arrivedist and only leaving it past ai_leavedist stops the
; ship dithering between "fly there" and "shoot" on the boundary.
; --- debug overlay. 0 removes it completely (IFNE, so no runtime cost).
;       +   the station - the point the ship is flying to
;       X   the target letter - what it is aiming and shooting at
;     a bar bottom left shows the state: 1 segment APPROACH, 2 ARRIVE,
;     3 ATTACK, and a 4th appears while it is turning.
; --- HOVER
; Hold a spot near one side of the screen. Face it, burn, sail past it,
; turn round, burn again - there is no brake in this game so the position
; is held by oscillating about it rather than by stopping on it.
;
; The whole behaviour is just "aim at the point, thrust when lined up".
; The turn-around is not special cased: once the ship is past the point
; the vector to it reverses, so aiming at it IS aiming backwards, and the
; thrust becomes a brake. Only the speed needs limiting, because the
; overshoot is set by how far the ship drifts during the 45 frames a 180
; degree turn takes:
;      32 -> about 12 px      96 -> about 38 px
;      64 -> about 25 px     192 -> about 86 px
ai_hoveronly	= 1			; 1 = hover and nothing else, for tuning
ai_hovermargin	= 32		; gap from the visible screen edge (x 32..351)
ai_hoverleft	= 32+ai_hovermargin
ai_hoverright	= 351-ai_hovermargin
ai_hovery		= ast_y_start	; level with the letter row
; The hover runs as three phases rather than as a continuous correction:
;
;   ROTATE  swing the nose onto the point, no thrust
;   BURN    a fixed shove with the nose HELD STILL, no re-aiming
;   COAST   drift until close, or until we have sailed past
;
; Both halves of that matter. Re-aiming while the engine is lit sweeps the
; thrust vector round and the ship flies an arc. But the discrete cycle on
; its own is not enough either - measured with no drift correction it
; still settles into a 71..108 pixel orbit. Thrust towards a point only
; changes the velocity component along the line to it; the sideways
; component is never touched. So the ROTATE phase aims at the point minus
; our own drift, which is what a person does without thinking: if you are
; sliding past something you point somewhere between it and your own
; reverse heading.
HS_ROTATE		= 0
HS_BURN			= 1
HS_COAST		= 2
ai_hoverlead	= 64		; frames of drift to subtract when aiming
; How long each shove lasts. A FIXED length was the cause of three
; separate complaints: close in it is far too much thrust, so the ship
; races away (peak speed 216, a quarter of the time off screen), and the
; resulting wide miss means the closest-approach point arrives early and
; far out - which looks exactly like turning round before getting there.
; Scaling it with distance fixed all three at once: peak speed 35, off
; screen 0.7%.
;       frames = distance >> ai_hoverburnshift, clamped
; ai_hoverburnmin is what stops it becoming a twitch when it is nearly
; there - it sets how big the smallest correction looks.
ai_hoverburnshift = 2		; divide the distance by 4
ai_hoverburnmin	= 6
ai_hoverburnmax	= 16
ai_hovercoastmax = 60		; give up on a drift after this many frames

; Coasting until the closest approach is fine from a few pixels away, but
; from across the screen it means arriving at full speed, sailing a long
; way past, turning round and doing it again - slow and dull to watch.
; This ends the drift once the point is less than this many frames away at
; the current speed, so the turn-and-brake starts before arrival rather
; than after it. Measured from the far corner: 347 frames to settle
; without it, 235 with.
ai_hoverbrake	= 75		; start braking this many frames out

; --- ATTACK
; One pass along the row. Aim at the near end letter, one shove, then
; coast the whole length of the word shooting - the letters are in a line,
; so simulated over ten runs it clears all nine every time in 115..148
; frames without needing a single mid-run correction.
; Aim is straight at the letter, not drift corrected: shots go where the
; nose points, so pointing anywhere else means missing.
AS_HOVER		= 0
AS_ATTACK		= 1
ai_attackdelay	= 60		; frames the finished word must sit still first
; ...and the ship has to be READY as well, not just the word. Without
; these two the countdown ran while the ship was still crossing the screen
; at speed from the previous pass, so it launched its attack from wherever
; it happened to be and never got a clean run at the row.
ai_attackready	= 40		; must be this close to the hover point
ai_attackreadyspd = 70		; ...and this slow (|xvelo|+|yvelo|)
; A pass that has not worked is better abandoned than persisted with -
; going back to the hover point and setting up again is what gets a clean
; line, and it is the one thing this AI is now good at.
ai_attackmax	= 400		; give up on a pass after this many frames
ai_attackburn	= 16		; the one shove that carries us along the row
; Checking the aim every 40 frames against a lax 26 degree cone meant the
; ship shot down the wrong line for seconds at a time, and when it did
; correct it used the full ai_attackburn shove, which threw the trajectory
; out again. Checking four times as often against a 14 degree cone, and
; nudging rather than shoving, is what a player does. With realistic
; vertical jitter on the letters: 403 frames and 9 words in 12 cleared
; before, 142 frames and 12 in 12 after.
ai_attackregrip	= 6			; frames between "am I still lined up?" checks.
							; 12 was too slow to hold the line - the ship shot
							; down the wrong one long enough to sail past a
							; letter, and recovering from that is what caused
							; the re-hover. Verified on hardware at 6.
ai_attackfix	= 4			; a correction nudge, against ai_attackburn for
							; the launch (the cone is the two add.l in .arun,
							; x4, about 14 degrees)
ai_hoverdead	= 30		; close enough to stop and drift (manhattan)
ai_hoverwrap	= 0			; 1 = allowed to reach the hover point the short
							; way round the screen edge. Off by default: for
							; station keeping it just makes the ship vanish off
							; one side to reach a point near the other.

ai_debug		= 0
ai_marksize		= 5			; half width of the + and X

ST_APPROACH		= 0
ST_ARRIVE		= 1
ST_ATTACK		= 2
ai_arrivedist	= 40		; close enough to the station to stop flying at it
; MUST be larger than ai_arrivedist, which is why it is written as a
; multiple of it rather than as its own number. If it is smaller the
; hysteresis inverts: the ship enters ATTACK at, say, 39 and instantly
; satisfies "further than 35", so it flips state every single frame. The
; aim then jumps between the station, the reverse velocity and the letter
; frame by frame and the ship can never finish a turn - it just sits there
; rotating. Raise the multiplier to make it snipe from further out, lower
; it (but never below about 1.5) to make it close the gap more eagerly.
ai_leavedist	= ai_arrivedist*2
ai_arrivespeed	= 40		; brake to below this before settling in to shoot
ai_homex		= ast_x_center	; where it loiters while a word zooms in
ai_homey		= ship_start_y
ai_wrapx		= wrap_x1-wrap_x0			; obj_move's wrap periods
ai_wrapy		= game_height+2*wrap_my

;----------------------------------------------------------------------
; autopilot - shooting
;----------------------------------------------------------------------
ai_holdframes	= 40		; frames to admire a finished word before shooting
							; (50 == 1 second, 100 == 2 seconds)
ai_pbholdfire	= 1
ai_minclose		= 128		; a shot must close at least this fast (128 == 1 px
							; per frame) or it never gets there
ai_pointblank	= 40		; a letter this close gets shot at, full stop
ai_fireflat		= 3			; want |dy|*3 < |dx|, i.e. a shot along the row
ai_patience		= 20		; ... but take any shot after this many dry frames
; --- firing. a player does not line up every single shot, they point
; roughly the right way, squeeze off a burst and reposition. the strays
; are half the fun - they wander off and take out something else.
ai_burstlen		= 3			; shots per burst, plus 0..ai_burstvar
ai_burstvar		= 2			; must be 1,3,7... - used as an AND mask
ai_burstgap		= 5			; frames between shots inside a burst, + 0..gapvar
ai_gapvar		= 3			; ditto, an AND mask
ai_burstpause	= 10		; + 0..31 frames before the next burst
ai_firebase		= 9			; unused now - superseded by the burst timings

;----------------------------------------------------------------------
; the break up
;----------------------------------------------------------------------
; The first shot that hits a word does not destroy a letter. It breaks
; the word up, Asteroids style: every letter flies off on its own course
; across the whole screen, and from then on each letter dies to one hit.
; The course is away from where the shot struck - the further away a
; letter is the faster it goes - plus a random part. Half the speed of the
; first version (which reached 80 across and 64 up or down), plus 1/4.
; up and down alike, but a sum of two random numbers, so most go sideways
; or at an angle rather than straight up or down.
; velocities are 1/128 pixel per frame
sc_awayshift	= 3			; x speed = distance from the impact >> this ...
sc_awaymax		= 24		; ... clamped to this
sc_randx		= 31		; + random 0..31, centred (mask, 2^n-1): |vx| <= 40
sc_randy1		= 31		; y = random 0..31 + random 0..31 - sc_upmax,
sc_randy2		= 31		; so -31 (up) .. +31 (down)
sc_upmax		= 31
sc_minspeed		= 12		; |vx|+|vy| below this gets a push up or down
							; then everything + 1/4: |vx| <= 50, |vy| <= 39.
							; on average ~10% faster than the down-only set

;----------------------------------------------------------------------
; autopilot - the hunt (the whole word, and its pieces once it broke up)
;----------------------------------------------------------------------
; One behaviour for everything, the way a player flies Asteroids. Every
; frame:
;   - every letter, the ones still waiting to appear included, is checked
;     for a collision course: where will it be, relative to us, now and in
;     16 and 32 frames (just shifts of the relative velocity, no
;     multiplies)? The closest of those is its threat. Further ahead the
;     straight line guess is wrong anyway - the ship brakes on arrival.
;   - a threat that can be shot and is still a fair way off becomes the
;     target - shooting it removes it. Any other threat is dodged: off its
;     path, sideways to the way it is coming, and away from it.
;   - otherwise the nearest letter is the target, and the ship wants to sit
;     at a STATION near it: one of the spots in ai_offsets, diagonally
;     above or below it, straight above or below, or beside it. The one
;     nearest the ship wins, unless another letter is too close to it. A
;     whole word blocks the spots beside it, so the ship works a word from
;     above and below - that is where the vertical moves come from.
;   - flying is "rotate, burn, coast": the station gives a wanted velocity
;     (faster the further away, plus the target's own drift). Only once
;     ours is more than ai_corrstart off it does the ship turn the nose
;     into the difference and burn until it is under ai_corrstop. The rest
;     of the time the nose is on the target.
;   - fire when a shot would pass within ai_hitslack pixels of the lead
;     point. cross = |nose| * |d| * sin(error) and |nose| is 32767, so
;     cross >> 15 IS that lateral miss in pixels - no division needed.
;     Nothing is fired until the word has been complete for ai_holdframes.
;   - no word at all: stay clear of the row the next one appears on.
; velocities are 1/128 pixel per frame, distances manhattan pixels.
ai_dangerdist	= 44		; a letter coming this close is a threat (a letter
							; is +-12, the ship about +-6)
ai_shootthreat	= 70		; a shootable threat further away than this is
							; shot, a nearer one dodged
ai_evadespeed	= 128		; the velocity a dodge wants
ai_cruise		= 144		; the fastest we fly to a station
ai_stdead		= 14		; this close to the station is close enough
ai_engage		= 100		; a target nearer than this (and not a threat)
							; is shot from where we are - no station
ai_engagehyst	= 32		; ... and it is left again only past this much more
ai_drift		= 96		; ... drifting no faster than this meanwhile
; --- the start of the attack on a new word is a rush (ai_pilot)
ai_rushtime		= 350		; frames, or until the first hit breaks it up
ai_rushcruise	= 160		; faster than ai_cruise ...
ai_rushengage	= 72		; ... and closer in before it settles to shoot
ai_rushdx		= 80		; the way in along the row: this far out to the side
ai_rushdg		= 56		; the way in from above: this far out and up
ai_stagedx		= 90		; waiting for a word to come in along its row:
							; this far out beyond the end letter ...
ai_stagedx2		= 40		; ... or for one from above: this far out ...
ai_stagedy		= 70		; ... and this far above the row
ai_stagex0		= 40		; never further out than the visible screen
ai_stagex1		= 344
ai_stdiag		= 36		; station offsets, see ai_offsets
ai_stvert		= 50
ai_sthorz		= 50
ai_stclear		= 40
ai_stkeep		= 24		; the station side we are on wins unless another
							; is this much nearer		; a station this close to another letter is blocked
ai_offrepick	= 60		; frames before the station is chosen again
ai_corrstart	= 48		; velocity off by more than this: correct it
ai_corrstop		= 12		; ... until it is off by less than this
ai_burncone		= 3			; burn once |cross| * 2^(this-1) < dot: 1 is 45
							; degrees, 2 about 26, 3 about 14
ai_nudge		= 16		; while aiming, thrust if off by this much and
							; the nose points that way anyway
ai_corrmax		= 60		; give up correcting after this many frames ...
ai_aimhold		= 30		; ... and only aim and shoot for this many
ai_idledy		= 80		; ship_start_y is this far below the word row
; --- no word: patrol between random waypoints (see ai_wantVelo .idle)
ai_homex0		= 48		; waypoints x 48..334, the visible part
ai_homex1		= 336
ai_waytop		= 24		; now and then a waypoint over the logo, y 24..55
ai_waytoprange	= 31		; (mask)
ai_waybottom	= 212		; mostly the black below the scroller, y 212..243
ai_waybotrange	= 31		; (mask)
; --- where the ship is hard to see: in front of the logo (raster $20 up to
;     about $84) and of the scroller and its bar (raster $bc..$ee)
ai_logoy		= 100		; y < this
ai_scrolly0		= 156		; y in this..
ai_scrolly1		= 206		; ..this
ai_busymax		= 100		; frames there before it moves somewhere else
ai_busypen		= 48		; a station there counts this much further away
ai_waytime		= 250		; frames before giving up on a waypoint
ai_homedist		= 20		; that close is "reached"
ai_rowclear		= 48		; the next word may come once the ship is on
							; screen and this far from the word row
ai_homewait		= 60		; after this long out of the band will do ...
ai_homemax		= 100		; ... and after this long the word comes anyway.
							; (300 with no hard limit made the gap before a
							; word up to 12 seconds when the ship kept
							; patrolling through the band)
ai_huntrange	= 116		; px - no point firing at anything further
shot_frames		= 56		; a shot's life (was 80): ~130 px, and fewer shots
							; in the air means fewer collision tests
ai_hitslack		= 8		; px - allowed miss at the lead point (a letter's
							; hit box is +-12)
ai_huntgap		= 9			; frames between shots, + 0..3 - about the pace
							; of a player on the fire button
; --- the hunt after the break up, as a gunner (ai_pilot)
ai_gunnerfar	= 110		; px - a target further than this is flown at
ai_gunnerspeed	= 112		; ... until we close at this speed
ai_gunnertop	= 200		; faster than this: slow down first
ai_farpen		= 150		; target choice: a letter out of range counts as
							; this much further away (see ai_huntScan)
ai_maxshots		= 4			; shots in the air at once, at most - as in the
							; arcade game
ai_wrapslack	= 96		; px - the direct way is taken unless the way
							; round the screen edge is this much shorter
ai_wrappen		= 200		; px - a letter only reachable round the edge
							; counts this much further away as a target
ai_snapevery	= 2			; frames between checks for a chance shot at a
							; letter that is not the target
ai_snaprange	= 130		; px - how far away such a letter may be
ai_huntsticky	= 40		; px - a new nearest letter must be this much
							; nearer before the aim swaps over to it
ai_spinmax		= 210		; a turn held on past this is let go (ai_turnBy)
ai_leadmax		= 63		; frames of lead at most

;======================================================================

		section "code",data,chip

; --- inlined helpers for the autopilot's per letter loops
; d0/d1 -> the shortest way round the wrapped play area (ai_wrap)
AI_WRAP	macro
		cmp.w	#ai_wrapx/2,d0
		ble.s	.wa\@
		sub.w	#ai_wrapx,d0
		bra.s	.wb\@
.wa\@:
		cmp.w	#-ai_wrapx/2,d0
		bge.s	.wb\@
		add.w	#ai_wrapx,d0
.wb\@:
		cmp.w	#ai_wrapy/2,d1
		ble.s	.wc\@
		sub.w	#ai_wrapy,d1
		bra.s	.wd\@
.wc\@:
		cmp.w	#-ai_wrapy/2,d1
		bge.s	.wd\@
		add.w	#ai_wrapy,d1
.wd\@:
		endm
; d0/d1 -> d5 = |d0|+|d1|, uses d6 (ai_manhattan)
AI_MANH	macro
		move.w	d0,d5
		bpl.s	.ma\@
		neg.w	d5
.ma\@:
		move.w	d1,d6
		bpl.s	.mb\@
		neg.w	d6
.mb\@:
		add.w	d6,d5
		endm

; standalone entry point - owns the copperlist, the buffer swap and the
; sprite pointers. still reachable through demoParts for the hidden mode.
initGame::				;<initialize game>
		jsr		clear			;clear screen
		jsr		clear			;

		lea		spoint(pc),a5
		jsr		setupStarfieldPointers	; starfield

		bsr		initGameObjects
		st		gameStandalone		; we own the screen

 		move.l	#clistGame,$dff080
		clr.w	$dff088
		rts
;------
; integrated entry point - the scroller part owns the buffer, the copperlist,
; the starfield and the keyboard. this only sets up the game objects.
; screenloc is written by clearScroller every frame.
initGameObjects::
		st		ai_sidemode			; always work the word from one end
		bsr		buildYOffTab		; needed by drawline/set_point below

		; --- every enemy slot gets its own line cache block, for good
		lea		enemy_structs,a0
		lea		enemy_cache,a1
		moveq	#32-1,d0
.cachePtrs:
		move.l	a1,obj_cache(a0)
		move.l	#-1,obj_cachekey(a0)
		lea		obj_len(a0),a0
		lea		cache_len(a1),a1
		dbf		d0,.cachePtrs
		clr.w	collCount
		lea		rndTab,a0			; for initLineExplode
		move.w	#rndCount-1,d7
.rnd:	jsr		getRandomNumber
		move.l	d0,(a0)+
		dbf		d7,.rnd
		bsr		scaleLetters
		bsr		shots_init
		bsr		ship_init
		clr.l	enemy_con
		sf		ship_exploding
		sf		gameStandalone
		rts
;------
; integrated per frame update. must be called after the scroller has
; finished with the blitter (objects_draw leaves BLTAFWM/BLTALWM at
; $ffff0000, which the scroll blit would otherwise inherit).
updateGameObjects::
		sf		gameDeferDraw
		bsr		updateGame
		lea		$dff000,a6
		rts

; --- the same, split in two so the scroller can run all of the game's
;     thinking while its screen clear blit is still going (it used to sit
;     in bbusy for up to 20000 cycles there): updateGameLogic moves
;     everything and builds ONE draw table, drawGameObjects draws it once
;     the buffer is cleared and the scroller is done with the blitter.
updateGameLogic::
		st		gameDeferDraw
		bsr		updateGame
		lea		$dff000,a6
		rts

drawGameObjects::
		bsr		objects_draw		; leaves a6 = $dff000
		rts

gameDeferDraw:	dc.b	0
				even
homeWait:		dc.w	0		; frames the next word has waited for the ship
; number of set bits in a byte, for counting the shots in shot_con
bitCount:
BCN		set		0
		rept	256
		dc.b	(BCN&1)+((BCN>>1)&1)+((BCN>>2)&1)+((BCN>>3)&1)+((BCN>>4)&1)+((BCN>>5)&1)+((BCN>>6)&1)+((BCN>>7)&1)
BCN		set		BCN+1
		endr
		even
rndCount		= 256		; power of two
rndPos:			dc.w	0
rndTab:			ds.l	rndCount
;------
gameStandalone:
		dc.b	0
		even
;------
updateGamePart::				;<update game>
		cmp.b	#$50,kcode
		bne.s	.ncol
		move.w	#$444,$dff180
.ncol:		
		jsr		getkey

		jsr		clear			;clear screen
		jsr		updateStars
		sf		gameDeferDraw
 		bsr		updateGame

; 		tst.l	enemy_con		; all enemies gone?
; 		bne.s	.hmm
; 		bsr		initGame		; reset game
; .hmm:
		rts
;------
nameOffset:
		dc.l	0
names:
		dc.l	name1
		dc.l	name2
		dc.l	name3
		dc.l	name4
		dc.l	name5
		dc.l	name6
		dc.l	name7
		dc.l	name8
		dc.l	0

name1:
		dc.b	"zeronine",0
name2:
		dc.b	"exolon",0
name3:
		dc.b	"exciter",0
name4:
		dc.b	"dandee",0
name5:
		dc.b	"major rom",0
name6:
		dc.b	"equalizer",0
name7:
		dc.b	"l p a",0
name8:
		dc.b	"phil",0

		even
clistGame:		
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

		dc.w	$2001,$fffe			; stars start
		dc.w	$0180,$0000	   ; black plane
		dc.w	$0182,$0fff	   ; line color
		dc.w	$0192,$0558	   ; line anti alias color
		dc.w	BPLCON0,$1200		; one plane

		; dc.w	BPLCON0,$1200		; 1 bitplanes on
		dc.w	BPLCON0,$2600		; 2 bitplanes on	(dual playfield mode)
		dc.w	$00e0,$0007			; bitplane 0 
bp0:	dc.w	$00e2,$0000			;
		dc.w	$00e4,$0007			; bitplane 1
bp1:	dc.w	$00e6,$0000			;
		dc.w	$0102,$0010			; scroll

		dc.w	$0108,$0000			; even bitplanes modulo
		dc.w	$010a,$0000			; odd bitplanes modulo

		dc.w	$0092,$0028
		dc.w	$0094,$00d8

		dc.w	$ffff,$fffe
;--------------------------------------------------------------
updateGame:
		; enemys / asteroids
		lea		linetab(pc),a6
;		move.w	#$fff,$dff180
		bsr		updateEnemies
;		move.w	#$f00,$dff180
		tst.b	gameDeferDraw	; one table for everything, drawn later
		bne.s	.oneTable
		clr.w	(a6)			; end of draw table
		bsr		objects_draw
;		move.w	#$0f0,$dff180

		; player and shots
		lea		linetab(pc),a6
.oneTable:
		tst.b	ship_next
		bne.s	.nsdraw
		move.l	a6,-(a7)
;		bsr		shipcoll		; collision
		move.l	(a7)+,a6
		tst.b	ai_enabled			; autopilot or keyboard?
		beq.s	.manualShip
		jsr		ship_auto
		bra.s	.shipDone
.manualShip:
		jsr		ship_set
.shipDone:
.nsdraw:
		bsr		ship_explode
		bsr		shots_set
		IFNE	ai_debug
		bsr		ai_debugMarks
		ENDC
		clr.w	(a6)			; and of draw table
;		move.w	#$0ff,$dff180
		tst.b	gameDeferDraw
		bne.s	.drawLater
		bsr		objects_draw
.drawLater:
;		move.w	#$000,$dff180

		cmp.b	#$45,kcode		; escape key?
		bne.s	.nrestart
		clr.b	kcode
		tst.b	ship_next		; ship destroyed?
		beq.s	.nrestart
		sf		ship_next
		tst.b	gameStandalone		; don't reinstall clistGame when integrated
		beq.s	.restartObjects
		bsr		initGame
		bra.s	.nrestart
.restartObjects:
		bsr		initGameObjects
.nrestart:
		tst.l	enemy_con
		bne.s	.noLetterInit

		; --- word is gone. nothing new until the sky is clear, or a shot
		;     still in the air from the last word takes out a letter of the
		;     new one before the ship has even started firing.
		tst.w	shot_con
		beq.s	.noShotsLeft
		move.w	#wordGap,wordGapTimer
		bra.s	.noLetterInit
.noShotsLeft:
		tst.w	wordGapTimer
		beq.s	.gapOver
		subq.w	#1,wordGapTimer
		bra.s	.noLetterInit
.gapOver:
		; --- every name has been up once: no more words, the ship gets
		;     bored instead (seq_pilot). that needs the scroll text running
		;     right across the bar, so until then nothing comes at all.
		tst.b	seq_on
		bne		.noLetterInit
		tst.b	namesLooped
		beq.s	.noSeq
		tst.b	ai_entered			; (F10 that early: one word first, so
		beq.s	.noSeq				; that the ship flies in)
		tst.b	scrollReady
		beq		.noLetterInit
		st		seq_on
		bra		.noLetterInit
.noSeq:
		; --- and the autopilot has to have flown back home (ai_wantVelo),
		;     into the visible part of the screen. not for ever, though
		tst.b	ai_enabled
		beq.s	.homeOk
		tst.b	ai_entered
		beq.s	.homeOk
		tst.b	ai_home
		bne.s	.homeOk
		addq.w	#1,homeWait			; after a while out of the band will do,
		cmp.w	#ai_homewait,homeWait	; even if flying towards it ...
		blo		.noLetterInit
		cmp.w	#ai_homemax,homeWait	; ... and after a long while, in it
		bhs.s	.homeOk				; too - the letters zoom in, there is
		tst.b	ai_clear			; time to get out of their way
		beq		.noLetterInit
.homeOk:
		clr.w	homeWait
		move.w	#wordGap,wordGapTimer

		; letter counter and initialization
		; lea		letters_init,a0
		; tst.w	(a0)
		; beq		.noLetterInit
		; sub.w	#1,(a0)
		; bne		.noLetterInit
		; ; move.w	#6*50,(a0)		; delay for next letters
		; move.w	#60*50,(a0)		; delay for next letters
		clr.l	enemy_con		; free all enemies
		bsr		asteroids_init
.noLetterInit:

		rts
**********************************************************************
*vector object_class                                                 *
*

				rsreset
obj_xc:			rs.w	1		; x-coordinate
obj_yc:			rs.w	1		; y-coordinate
obj_xfloat:		rs.w	1		; x-coordinate (floating)
obj_yfloat:		rs.w	1		; y-coordinate (floating)
obj_angle:		rs.w	1		; angle
obj_scale:		rs.w	1		; scale

;obj_coords:		rs.l	1		; pointer on coord-table (i.e. lines)
obj_coords:		rs.w	(max_objlines*4)+1	; coord-table (i.e. lines)
obj_linespeed:	rs.w	(max_objlines*4)	; speed table for line explosion effect
obj_linecoords:	rs.w	(max_objlines*4)	; fixed point coord table for line explosion effect

obj_xvelo:		rs.w	1		; x velocity
obj_yvelo:		rs.w	1		; y velocity
obj_name:		rs.w	1		; name (identification)
obj_collsize:	rs.w	1
obj_appear:		rs.w	1
obj_wait:		rs.w	1
obj_flag:		rs.w    1		; flags (hit, ...)
obj_timer:		rs.w	1
obj_cache:		rs.l	1		; line cache block, enemy slots only (0 = none)
obj_cachekey:	rs.l	1		; xc:yc the cache was built for, -1 = stale
obj_len:		rs.w	0		; end

; --- line cache. a letter that has finished arriving neither rotates nor
;     scales, so its line list only changes when it moves onto another
;     pixel - every 8 frames at the very most, usually far less. obj_move
;     builds the list once, keeps a copy here, and replays it until xc:yc
;     changes. one block per enemy slot: a word count, then the linetab
;     entries (at most max_objlines lines of line_entry bytes).
line_entry		= 7*2			; bytes per line in linetab, see drawline
cache_len		= 2+(max_objlines*line_entry)
cache_m			= 16			; a letter this far inside every edge has no
								; clipped lines (they reach about +-12)

; --- collList entry, built by updateEnemies for shot_collision:
;     x0, x1, y0, y1 (words), struct pointer (long), enemy_con bit, pad
coll_len		= 16
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

		; copy line data to objects buffer
;		movem.l	d0-d7/a0-a6,-(a7)
		lea		obj_coords(a0),a3
		move.w	d5,obj_name(a0)
		lsl.w	#2,d5
		lea		coord_tabs(pc),a1
		move.l	(a1,d5.w),a2
		move.l	a2,d0
		bne.s	.copylinedata
		clr.w	(a3)				; no lines
		bra.s	.copydone
.copylinedata
		move.w	(a2)+,d1			; only the lines there are, not all
		move.w	d1,(a3)+			; max_objlines - a word spawns nine of
		subq.w	#1,d1				; these in one frame
		bmi.s	.copydone
.copy:
		move.l	(a2)+,(a3)+			; x1, y1
		move.l	(a2)+,(a3)+			; x2, y2
		dbf		d1,.copy
.copydone:
;		movem.l	(a7)+,d0-d7/a0-a6

		move.w	#64,obj_scale(a0)

		clr.w	obj_flag(a0)
		move.l	#-1,obj_cachekey(a0)	; new shape, whatever is cached is stale
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

		cmp.w	#obj_maxvelo,obj_xvelo(a0)	;x velocity too high?
		blt.s	.nhxv
		move.w	#obj_maxvelo,obj_xvelo(a0)
.nhxv:		
		cmp.w	#-obj_maxvelo,obj_xvelo(a0)	;x velocity too low?
		bgt.s	.nlxv
		move.w	#-obj_maxvelo,obj_xvelo(a0)
.nlxv:
		cmp.w	#obj_maxvelo,obj_yvelo(a0)	;y velocity too high?
		blt.s	.nhyv
		move.w	#obj_maxvelo,obj_yvelo(a0)
.nhyv:		
		cmp.w	#-obj_maxvelo,obj_yvelo(a0)	;y velocity too low?
		bgt.s	.nlyv
		move.w	#-obj_maxvelo,obj_yvelo(a0)
.nlyv:
		rts
;---------------------------------------------
obj_move:				;<calculate new object coords>
		tst.w	obj_flag(a0)			; skip move if flags are set (hit -> explode)
		bne.s	.doneMove

		move.w	obj_xfloat(a0),d0		; x floating
		add.w	obj_xvelo(a0),d0		; + x velocity

		; x never gets anywhere near 0 (wrap_x0 is far more than one
		; frame's movement), so plain unsigned compares will do
		cmp.w	#wrap_x1*128,d0			; off the right?
		blo.s	.nhx
		sub.w	#(wrap_x1-wrap_x0)*128,d0
.nhx:
		cmp.w	#wrap_x0*128,d0			; off the left?
		bhs.s	.nlx
		add.w	#(wrap_x1-wrap_x0)*128,d0
.nlx:
		move.w	d0,obj_xfloat(a0)		; store x floating
		lsr.w	#7,d0					; convert to integer
		move.w	d0,obj_xc(a0)			; x integer

		move.w	obj_yfloat(a0),d0		; y floating
		add.w	obj_yvelo(a0),d0		; + y velocity

		; y does go negative, as a word: -wrap_my..-1 is $f600..$ffff
		cmp.w	#(game_height+wrap_my)*128,d0	;y coord too high?
		bls.s	.nhy
		cmp.w	#(game_height+2*wrap_my)*128,d0
		bhi.s	.nhy
		sub.w	#(game_height+2*wrap_my)*128,d0
.nhy:
		cmp.w	#-wrap_my*128,d0			; y coord too low?
		bhi.s	.nly
		cmp.w	#(game_height+2*wrap_my)*128,d0
		bls.s	.nly
		add.w	#(game_height+2*wrap_my)*128,d0
.nly:
		move.w	d0,obj_yfloat(a0)		; store y floating
		lsr.w	#7,d0					; convert to integer
		move.w	d0,obj_yc(a0)			; y integer
.doneMove:		
		; --- set up for set_point / set_line / drawline. invariant for the
		;     whole object, so it is loaded here rather than on every line.
		;     there is no screen base any more: linetab holds offsets into
		;     the buffer and objects_draw adds screenloc, which is what lets
		;     a cached line list survive the double buffer swap.
		lea		yOffTab(pc),a5			; y -> y*game_lineBytes

		lea		obj_coords(a0),a1		; coord table
		move.w	(a1),d0					; no. of lines
		tst.w	d0
;		move.l	a1,d0
		bne.s	.lineobj				; got lines

		; no lines -> insert point obj to draw table
		move.w	obj_xc(a0),d0
		move.w	obj_yc(a0),d1
		bsr		set_point
		rts
.lineobj:	
		; insert line obj to draw table
		move.w	obj_angle(a0),d0
		cmp.w	#$8000,d0				; rotate?
		beq		.norotobj
		lsl.w	#2,d0
		lea		sctab(pc),a3
		movem.w	(a3,d0.w),d4/d5			; sin,cos

		; --- fold the object scale into sin/cos once per object instead of
		;     four muls + four asr per line. scale is 2..64 and sin/cos are
		;     +-32767, so sin*scale>>6 still fits in a signed word.
		move.w	obj_scale(a0),d6
		cmp.w	#64,d6					; full size? then sin*64>>6 == sin
		beq.s	.noScale
		muls.w	d6,d4
		asr.l	#6,d4
		muls.w	d6,d5
		asr.l	#6,d5
.noScale:

		; --- the letter coord tables are polylines: p1 of a line is usually
		;     p2 of the line before it. cache the last raw and rotated p2 so
		;     that shared vertex is only transformed once.
		lea		lineCache(pc),a3
		move.w	#$7fff,(a3)				; no coordinate can match this
		movem.w	d4-d5,8(a3)				; sin/cos live here now, not on the
										; stack around every set_line call

		move.w	(a1)+,d7				; no of lines
		subq.w	#1,d7
.lines:		
		movem.w	(a1)+,d0-d3		
		move.w	d7,-(a7)
		movem.w	8(a3),d4-d5				; reload sin/cos (clipy/clipx use them)

		cmp.w	(a3),d0					; same vertex as the previous p2?
		bne.s	.rotp1
		cmp.w	2(a3),d1
		bne.s	.rotp1
		movem.w	4(a3),d0-d1				; yes - reuse the rotated one
		bra.s	.gotp1
.rotp1:
		; --- rotate, inlined. MULS costs 38+2n on the 68000 where n counts
		;     bit transitions in the SOURCE operand, so the small coordinate
		;     goes in the source slot and the trig value in the destination.
		move.w	d5,d6
		muls	d0,d6					; x1*cos
		move.w	d4,d7
		muls	d1,d7					; y1*sin
		sub.l	d7,d6
		add.l	d6,d6
		swap	d6						; new x1
		move.w	d4,d7
		muls	d0,d7					; x1*sin
		move.w	d5,d0
		muls	d1,d0					; y1*cos
		add.l	d0,d7
		add.l	d7,d7
		swap	d7						; new y1
		move.w	d6,d0
		move.w	d7,d1
		add.w	obj_xc(a0),d0			; freshly rotated p1 still needs
		add.w	obj_yc(a0),d1			; translating; a cached one does not
.gotp1:
		movem.w	d2-d3,(a3)				; cache raw p2

		move.w	d5,d6
		muls	d2,d6					; x2*cos
		move.w	d4,d7
		muls	d3,d7					; y2*sin
		sub.l	d7,d6
		add.l	d6,d6
		swap	d6						; new x2
		move.w	d4,d7
		muls	d2,d7					; x2*sin
		move.w	d5,d2
		muls	d3,d2					; y2*cos
		add.l	d2,d7
		add.l	d7,d7
		swap	d7						; new y2
		move.w	d6,d2
		move.w	d7,d3

		add.w	obj_xc(a0),d2			; translate p2 first, then cache it -
		add.w	obj_yc(a0),d3			; a reused vertex then needs no adds
		movem.w	d2-d3,4(a3)

		bsr		set_line
		move.w	(a7)+,d7
		dbf		d7,.lines
		rts
.norotobj:
		; --- static shape: replay the cached line list if the object has
		;     not moved onto another pixel since it was built (see obj_cache).
		;     ~105 cycles a line instead of ~400 for clip + octant setup.
		move.l	obj_cache(a0),d0
		beq.s	.norotBuild				; not an enemy slot, no cache
		tst.w	obj_flag(a0)
		bne.s	.norotBuild				; exploding - lines change every frame
		move.l	d0,a3
		move.l	obj_xc(a0),d0			; xc:yc in one go
		move.l	obj_cachekey(a0),d1
		cmp.l	d1,d0
		bne.s	.cacheMoved
; --- a3 = the cache. the draw table only gets a pointer to its entries
;     (a -2 entry, see objects_draw), they are not copied any more
.cacheEmit:
		move.w	(a3)+,d7				; words cached
		beq.s	.cacheDone
		move.w	#-2,(a6)+
		move.l	a3,(a6)+				; first entry
		add.w	d7,d7
		add.w	d7,a3
		move.l	a3,(a6)+				; end
.cacheDone:
		rts

; --- moved onto another pixel. if the letter was well inside the screen
;     before and still is now, none of its lines were or are clipped, and
;     moving a line only changes where it starts: the buffer offset (whole
;     words across, lines down) and the start pixel in BLTCON0's top 4
;     bits. everything else in the entry stays. so shift the cached lines
;     instead of building them again - ~4 times cheaper, and it matters: a
;     whole word drifts as one, so every letter crosses a pixel on the
;     SAME frame, and broken up they move every frame.
.cacheMoved:
		move.w	d0,d2					; new y
		sub.w	#cache_m,d2
		cmp.w	#game_height-2*cache_m,d2
		bhs.s	.cacheFill
		move.w	d1,d2					; old y (-1 = never built: fails)
		sub.w	#cache_m,d2
		cmp.w	#game_height-2*cache_m,d2
		bhs.s	.cacheFill
		move.w	d0,d2
		add.w	d2,d2
		move.w	(a5,d2.w),d2			; new y * li
		move.w	d1,d3
		add.w	d3,d3
		sub.w	(a5,d3.w),d2			; d2 = dy * li
		move.l	d0,obj_cachekey(a0)		; (before the swaps)
		swap	d0
		swap	d1
		move.w	d0,d3					; new x
		sub.w	#cache_m,d3
		cmp.w	#game_width-2*cache_m,d3
		bhs.s	.cacheRefill
		move.w	d1,d3					; old x
		sub.w	#cache_m,d3
		cmp.w	#game_width-2*cache_m,d3
		bhs.s	.cacheRefill
		sub.w	d1,d0					; d0 = dx
		move.l	a3,a4					; (updateEnemies saves a4)
		move.w	(a3)+,d7				; words cached
		beq.s	.cacheDone
		add.w	d7,d7
		lea		(a3,d7.w),a1			; end of the entries
		tst.w	d0
		beq.s	.shiftY
		cmp.w	#1,d0					; one pixel sideways - by far the most
		beq.s	.shiftR					; common, and BLTCON0's top nibble is the
		cmp.w	#-1,d0					; start pixel, so an add of $1000 moves
		beq.s	.shiftL					; it and the carry says "next word"
		bra.s	.shiftX
.shiftR:
		tst.w	d2
		bne.s	.shiftRY
.sR:	add.w	#$1000,6(a3)
		bcc.s	.sR1
		addq.w	#2,2(a3)
.sR1:	lea		line_entry(a3),a3
		cmp.l	a1,a3
		blo.s	.sR
		move.l	a4,a3
		bra		.cacheEmit
.shiftRY:
		add.w	d2,2(a3)
		add.w	#$1000,6(a3)
		bcc.s	.sRY1
		addq.w	#2,2(a3)
.sRY1:	lea		line_entry(a3),a3
		cmp.l	a1,a3
		blo.s	.shiftRY
		move.l	a4,a3
		bra		.cacheEmit
.shiftL:
		add.w	d2,2(a3)
		sub.w	#$1000,6(a3)
		bcc.s	.sL1
		subq.w	#2,2(a3)
.sL1:	lea		line_entry(a3),a3
		cmp.l	a1,a3
		blo.s	.shiftL
		move.l	a4,a3
		bra		.cacheEmit
.shiftY:								; straight up or down: offsets only
		add.w	d2,2(a3)
		lea		line_entry(a3),a3
		cmp.l	a1,a3
		blo.s	.shiftY
		move.l	a4,a3
		bra.s	.cacheEmit
.shiftX:
		move.w	6(a3),d4				; BLTCON0
		move.w	d4,d5
		rol.w	#4,d5
		and.w	#$f,d5					; start pixel
		add.w	d0,d5					; + dx
		move.w	d5,d6
		asr.w	#4,d6					; words crossed ...
		add.w	d6,d6					; ... in bytes
		add.w	d2,d6
		add.w	d6,2(a3)				; offset
		and.w	#$f,d5
		ror.w	#4,d5
		and.w	#$0fff,d4
		or.w	d5,d4
		move.w	d4,6(a3)
		lea		line_entry(a3),a3
		cmp.l	a1,a3
		blo.s	.shiftX
		move.l	a4,a3
		bra.s	.cacheEmit

.cacheRefill:
		swap	d0						; back to xc:yc
.cacheFill:
		move.l	d0,obj_cachekey(a0)
		move.l	a6,-(a7)				; the draw table
		move.l	obj_cache(a0),a6		; build straight into the cache
		addq.l	#2,a6
		bsr.s	.norotBuild				; a1 still points at obj_coords
		move.l	obj_cache(a0),a3
		move.l	a6,d0
		sub.l	a3,d0
		subq.l	#2,d0
		lsr.w	#1,d0					; words written (0 if fully clipped)
		move.w	d0,(a3)
		move.l	(a7)+,a6
		bra.s	.cacheEmit

.norotBuild:
		move.w	obj_xc(a0),a3			; a3 survives set_line/drawline
		move.w	(a1)+,d7
		subq.w	#1,d7
.norotlines:	
		movem.w	(a1)+,d0-d3
		add.w	a3,d0
		add.w	a3,d2
		add.w	obj_yc(a0),d1
		add.w	obj_yc(a0),d3
		move.w	d7,-(a7)
		bsr		set_line
		move.w	(a7)+,d7
		dbf		d7,.norotlines
		rts
;---------------------------------------------
updateEnemies:
		clr.w	ai_zooming			; (letters spinning in, counted below)
		sf		ai_forming			; set again below by any letter that is
									; still waiting or still zooming in
		lea		collList,a4			; shootable enemies, rebuilt every frame
		move.l	enemy_con(pc),d0
		lea		enemy_structs(pc),a0
		moveq	#31,d7
.setenemys:	
		btst	d7,d0
		beq		.nenemy

		move.w	obj_wait(a0),d1
		tst.w	d1
		beq		.noWait
		subq.w	#1,d1
		move.w	d1,obj_wait(a0)
		st		ai_forming			; hasn't even started yet
		bra		.nenemy
.noWait:
		movem.l	d0/d7/a4,-(a7)
		bsr		obj_move			; move and setup draw
		movem.l	(a7)+,d0/d7/a4

		move.w	obj_appear(a0),d2
		tst.w	d2
		beq		.noAppear
		subq	#1,d2
		move.w	d2,obj_appear(a0)
		st		ai_forming			; still zooming in
		addq.w	#1,ai_zooming
		move.w	#appear_astep,d1
		bsr		obj_addangle

		move.w	obj_scale(a0),d1	; grow, clamped at full size
		cmp.w	#64,d1
		bge.s	.doneScale
		add.w	#appear_sstep,d1
		cmp.w	#64,d1
		blt.s	.storeScale
		move.w	#64,d1
.storeScale:
		move.w	d1,obj_scale(a0)
.doneScale:
		tst.w	d2					; animation finished?
		bne.s	.appearing
		; freeze here whatever the scale/angle steps happened to be, so the
		; timing constants can be retuned without the letter getting stuck
		; in the (expensive) rotating path
		move.w	#64,obj_scale(a0)
		move.w	#$8000,obj_angle(a0)

		; --- get random velocity
		; move.l	d0,d6				; store enemycon
		; jsr		getRandomNumber
		; and.l	#$1f,d0
		; sub.l	#$10,d0
		; move.w	d0,obj_xvelo(a0)
		; jsr		getRandomNumber
		; and.l	#$1f,d0
		; sub.l	#$10,d0
		; move.w	d0,obj_yvelo(a0)
		; move.l	d6,d0				; restore enemycon
.noAppear:
.appearing:
		move.w	obj_flag(a0),d6
		bne.s	.flagged

		; --- solid and fully arrived: shots can hit it this frame. the box
		;     goes into collList so shot_collision only walks the handful of
		;     live letters instead of all 32 slots for every shot.
		tst.w	obj_appear(a0)
		bne.s	.doneHit
		move.w	obj_collsize(a0),d1
		move.w	obj_xc(a0),d2
		move.w	d2,d3
		sub.w	d1,d2
		add.w	d1,d3
		move.w	d2,(a4)+			; x0
		move.w	d3,(a4)+			; x1
		move.w	obj_yc(a0),d2
		move.w	d2,d3
		sub.w	d1,d2
		add.w	d1,d3
		move.w	d2,(a4)+			; y0
		move.w	d3,(a4)+			; y1
		move.l	a0,(a4)+			; struct
		move.w	d7,(a4)+			; enemy_con bit
		addq.w	#2,a4				; pad to coll_len
		bra.s	.doneHit

.flagged:
		btst	#1,d6				; explode flag set?
		beq.s	.notExloding
		addq.w	#1,ai_zooming		; (bursting: as dear as spinning in)
		bsr		lineExplode
		bra.s	.doneHit
.notExloding:
		btst	#0,d6				; hit flag set?
		beq.s	.doneHit
		bsr		initLineExplode
.doneHit:

.nenemy:
		lea		obj_len(a0),a0
		dbf		d7,.setenemys

		move.l	a4,d1
		sub.l	#collList,d1
		lsr.w	#4,d1				; / coll_len
		move.w	d1,collCount
		rts
;---------------------------------------------
; a0: obj
; d0 -> dont change (enemycon)
; d6 -> obj_flag value
; d7 -> dont change (obj loop counter)
initLineExplode:
		bclr	#0,d6				; reset hit flag
		bset	#1,d6				; set explode flag
		move.w	d6,obj_flag(a0)		;

		move.w	#20,obj_timer(a0)	; hit "remove" time

		lea		obj_coords(a0),a1
		lea		obj_linespeed(a0),a2
		move.w	(a1)+,d2		; no. of lines
;		lsl.w	#2,d2			; * 4 for x1,y1,x2,y2
		sub.w	#1,d2
		ext.l	d2
		move.l	d2,d5
		move.l	d0,d6
; every endpoint flies off at (line centre * 4) + a random -16..15 per axis.
; that used to be four getRandomNumber calls per line, ~170 cycles each, and
; a burst can hit two or three letters in the same frame. now one call per
; line supplies all four offsets as 5 bit fields - bits 0-4, 16-20, 21-25
; and 26-30, which skips the weak low bits of the generator.
.lines:
		move.w	(a1)+,d3
		move.w	(a1)+,d4
		add.w	(a1)+,d3
		add.w	(a1)+,d4
		asr		#1,d3
		asl		#2,d3
		asr		#1,d4
		asl		#2,d4
		sub.w	#16,d3				; the -16 of every random offset, once
		sub.w	#16,d4

		move.w	rndPos(pc),d1		; a table of random longs instead of
		addq.w	#4,d1				; getRandomNumber - ~40 cycles, not ~170
		and.w	#(rndCount-1)*4,d1
		move.w	d1,rndPos
		lea		rndTab,a3
		move.l	(a3,d1.w),d0
		moveq	#$1f,d1
		and.w	d0,d1
		add.w	d3,d1
		move.w	d1,(a2)+			; p1 x speed
		swap	d0
		moveq	#$1f,d1
		and.w	d0,d1
		add.w	d4,d1
		move.w	d1,(a2)+			; p1 y speed
		lsr.w	#5,d0
		moveq	#$1f,d1
		and.w	d0,d1
		add.w	d3,d1
		move.w	d1,(a2)+			; p2 x speed
		lsr.w	#5,d0
		and.w	#$1f,d0
		add.w	d4,d0
		move.w	d0,(a2)+			; p2 y speed

		dbf		d2,.lines
		move.l	d6,d0

		lea		obj_coords+2(a0),a1
		lea		obj_linecoords(a0),a2
.copy:
		move.w	(a1)+,d3
		move.w	(a1)+,d4
		asl.w	#4,d3
		asl.w	#4,d4
		move.w	d3,(a2)+
		move.w	d4,(a2)+

		move.w	(a1)+,d3
		move.w	(a1)+,d4
		asl.w	#4,d3
		asl.w	#4,d4
		move.w	d3,(a2)+
		move.w	d4,(a2)+
		dbf		d5,.copy

		rts
; ------------------
lineExplode:
		; old effect -> 
		lea		obj_coords(a0),a1
		lea		obj_linecoords(a0),a3
		lea		obj_linespeed(a0),a2

		move.w	(a1)+,d2		; no. of lines
		lsl.w	#2,d2			; * 4 for x1,y1,x2,y2
		sub.w	#1,d2
		ext.l	d2
; each coordinate drifts by its speed, and the speed slows down by one
; towards zero. one tail per sign instead of a shared one saves the bra and
; the tst, and a coordinate that has stopped is simply skipped - its fixed
; point and integer values are already what they would be rewritten to.
.explode:
		move.w	(a2),d3			; speed
		bgt.s	.decSpeed
		beq.s	.still
		addq.w	#1,d3
		move.w	d3,(a2)+	; store speed
		add.w	(a3),d3
		move.w	d3,(a3)+	; store new coord (fixed point)
		asr.w	#4,d3		; convert to int
		move.w	d3,(a1)+	; store new coord (int)
		dbf		d2,.explode
		bra.s	.moved
.decSpeed:
		subq.w	#1,d3
		move.w	d3,(a2)+
		add.w	(a3),d3
		move.w	d3,(a3)+
		asr.w	#4,d3
		move.w	d3,(a1)+
		dbf		d2,.explode
		bra.s	.moved
.still:
		addq.w	#2,a2
		addq.w	#2,a3
		addq.w	#2,a1
		dbf		d2,.explode
.moved:

		sub.w	#1,obj_timer(a0)
		bne.s	.noRemove
		; free enemy object
		bclr	d7,d0
		move.l	d0,enemy_con
.noRemove
		rts

;---------------------------------------------
shot_init:				;<initialize a shot>
		move.l	a0,-(a7)
		move.w	shot_con(pc),d6
		lea		shot_structs(pc),a0
		lea		shot_times(pc),a1
		moveq	#15,d7
.findshot:	
		btst	d7,d6
		beq.s	.freeshot
		lea		obj_len(a0),a0
		addq.w	#2,a1
		dbf		d7,.findshot
		bra.s	.nofreeshot
.freeshot:
		move.w	#shot_frames,(a1)	;shot duration
		moveq	#shot,d5
		bsr		obj_init
		bset	d7,d6
		move.w	d6,shot_con
.nofreeshot:	
		move.l	(a7)+,a0
		rts

;---------------------------------------------
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
		bset	d7,d6
		move.w	#$8000,d2
		bsr		obj_init
		move.l	d6,enemy_con
.nofree:	
;		move.l	(a7)+,a0
		rts
;---------------------------------------------
shots_set:	
		move.w	shot_con(pc),d0

		cmp.w	#$c000,d0
		bne.s	.nodebug
		nop
.nodebug:

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
		; (the shots of the destruction sequence against the text: see
		;  seqShotScan, after the text of this frame is drawn)
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
; walks collList, which updateEnemies fills with the boxes of every enemy
; that is solid and fully arrived. that is at most the nine letters of a
; word, where this used to test all 32 slots for every shot in the air.
; out: d1 non zero if the shot hit something
shot_collision:
		move.w	obj_xc(a0),d0
		move.w	obj_yc(a0),d1
		move.w	collCount,d7
		subq.w	#1,d7
		bmi.s	.colldone
		lea		collList,a3
.shotcoll:
		cmp.w	(a3),d0				; x0 > x ?
		blt.s	.nocoll
		cmp.w	2(a3),d0			; x1 < x ?
		bgt.s	.nocoll
		cmp.w	4(a3),d1			; y0 > y ?
		blt.s	.nocoll
		cmp.w	6(a3),d1			; y1 < y ?
		bgt.s	.nocoll

		; collision occured
		move.l	8(a3),a4
		cmp.w	#letter,obj_name(a4)
		bne.s	.noLetter
		tst.w	obj_flag(a4)
		bne.s	.nocoll				; already hit by another shot this frame
		tst.b	word_scattered		; first hit on this word? then the rest
		bne.s	.letterHit			; of it breaks up, and the letter that
		bsr		word_scatter		; was hit goes as well - otherwise the
									; break up seems to come from nowhere
.letterHit:
		move.w	#1,obj_flag(a4)		; set "hit" flag
		moveq	#1,d1
		rts
.noLetter
		cmp.w	#small,obj_name(a4)
		bne.s	.nlast
.removeObj:
		move.w	10(a3),d6			; enemy_con bit
		move.l	enemy_con(pc),d7
		bclr	d6,d7
		move.l	d7,enemy_con
		moveq	#1,d1
		rts
.nlast:
		; split object into two (reusing self)
		move.w	#small,obj_name(a4)
		lea		coord_tabs(pc),a5
		move.l	small*4(a5),obj_coords(a4)
		move.l	#-1,obj_cachekey(a4)	; shape changed
		add.w	#32,obj_xvelo(a4)
		add.w	#32,obj_yvelo(a4)
		neg.w	obj_yvelo(a4)
		move.w	#8,obj_collsize(a4)
		moveq	#1,d1
		rts
.nocoll:
		lea		coll_len(a3),a3
		dbf		d7,.shotcoll
.colldone:
		moveq	#0,d1
		rts
;---------------------------------------------
; the first hit on a word: every letter of it flies off on its own course.
; see "the break up" in the constants.
; in:  a0 = the shot, a4 = the letter it hit
; keeps a0 and a6 (the draw table), uses d0-d7/a1
;---------------------------------------------
word_scatter:
		st		word_scattered
		move.l	enemy_con(pc),d4
		lea		enemy_structs(pc),a1
		moveq	#31,d7
.letter:
		btst	d7,d4
		beq.s	.next
		tst.w	obj_flag(a1)		; already blowing up
		bne.s	.next

		move.w	obj_xc(a1),d2		; away from the impact ...
		sub.w	obj_xc(a0),d2
		asr.w	#sc_awayshift,d2
		cmp.w	#sc_awaymax,d2
		ble.s	.notFast
		move.w	#sc_awaymax,d2
.notFast:
		cmp.w	#-sc_awaymax,d2
		bge.s	.notFastL
		move.w	#-sc_awaymax,d2
.notFastL:
		jsr		getRandomNumber		; ... plus a random part
		moveq	#sc_randx,d3
		and.w	d0,d3
		sub.w	#sc_randx/2,d3
		add.w	d3,d2
		; y: the sum of two random numbers, shifted so that most go down
		; or sideways and the few that go up go up slowly
		swap	d0
		moveq	#sc_randy1,d3
		and.w	d0,d3
		lsr.w	#8,d0
		and.w	#sc_randy2,d0
		add.w	d0,d3
		sub.w	#sc_upmax,d3		; -sc_upmax .. randy1+randy2-sc_upmax

		move.w	d2,d0				; never leave one sitting still
		bpl.s	.ax
		neg.w	d0
.ax:
		move.w	d3,d1
		bpl.s	.ay
		neg.w	d1
.ay:
		add.w	d1,d0
		cmp.w	#sc_minspeed,d0
		bhs.s	.fastEnough
		add.w	#sc_minspeed,d3		; too slow: a push up or down, the way
		tst.w	d3					; it was going anyway
		bpl.s	.fastEnough
		sub.w	#2*sc_minspeed,d3
.fastEnough:
		move.w	d2,d0				; + 1/4: a little quicker all round
		asr.w	#2,d0
		add.w	d0,d2
		move.w	d3,d0
		asr.w	#2,d0
		add.w	d0,d3
		move.w	d2,obj_xvelo(a1)
		move.w	d3,obj_yvelo(a1)
.next:
		lea		obj_len(a1),a1
		dbf		d7,.letter
		rts

word_scattered:	dc.b	0		; the word on screen has been broken up
				even
;---------------------------------------------
ship_explode:
		tst.b	ship_next
		beq.w	.noinit
		tst.b	ship_exploding
		bne.s	.noinit

		lea		ship_struct,a0
		move.w	obj_xc(a0),d5
		move.w	obj_yc(a0),d6
		move.w	obj_xvelo(a0),d3
		move.w	obj_yvelo(a0),d4
		moveq	#0,d3
		moveq	#0,d4
		move.w	obj_angle(a0),a4

		lea		ship_estruct,a0
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

		lea		ship_estruct,a0		
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

ai_enabled:		dc.b	1		; 0 hands the ship back to the keyboard
				even
ai_target:		dc.w	-1		; enemy_con BIT number, -1 = none
ai_retarget:	dc.w	0
ai_fireWait:	dc.w	0
ai_thrustLeft:	dc.w	0
ai_coastLeft:	dc.w	0
ai_dx:			dc.w	0		; wrapped vector to the target
ai_dy:			dc.w	0
ai_cross:		dc.l	0		; alignment against the target
ai_dot:			dc.l	0
ai_forming:		dc.b	0		; a letter of this word is still arriving
				even
ai_zooming:		dc.w	0		; letters spinning in or bursting (updateEnemies)
				even
ai_holdFire:	dc.w	ai_holdframes
ai_sidePicked:	dc.b	0		; side chosen for the word now on screen
				even			; <- without this ai_aimcross lands on an odd
							;    address and the first move.l to it bus errors
ai_aimcross:	dc.l	0		; cross/dot of whatever we are STEERING at,
ai_aimdot:		dc.l	0		; which is the station while repositioning and
							; the reverse velocity while braking or recovering.
							; ai_cross/ai_dot are always the target letter.
ai_state:		dc.b	ST_APPROACH
ai_over:		dc.b	0		; sailed past the station
ai_turning:		dc.b	1		; nose still swinging round
				even
ai_sdx:			dc.w	0		; vector to the station
ai_sdy:			dc.w	0
ai_sdist:		dc.w	0		; ... and its manhattan length
ai_hx:			dc.w	0		; hover point, absolute screen position
ai_hy:			dc.w	0
ai_hdist:		dc.w	0		; manhattan distance to the hover point
ai_coastTick:	dc.w	0
ai_burnLeft:	dc.w	0		; frames of shove still to go
ai_hstate:		dc.b	HS_ROTATE
ai_astate:		dc.b	AS_HOVER
				even
ai_settleTick:	dc.w	0
ai_regripTick:	dc.w	0
ai_attackTick:	dc.w	0
ai_edgeSide:	dc.w	0		; which end ai_target was picked for
ai_launched:	dc.b	0		; the launch shove has been spent
				even
ai_recover:		dc.b	0		; steering back onto the screen
				even
ai_side:		dc.w	-1		; which end of the word we attack from
ai_dry:			dc.w	0		; frames since the last shot
ai_burst:		dc.w	0		; shots left in the current burst
ai_enterTimer:	dc.w	ai_enterwait
ai_entered:		dc.b	0		; has the ship flown in yet?
ai_sidemode:	dc.b	0		; along-the-row attack for this word?
				even

;---------------------------------------------
ship_auto:
		lea		ship_struct,a0

		; --- wait off screen until the first word is actually up, then come
		;     in from the left under power
		tst.b	ai_entered
		bne.s	.flying
		move.l	enemy_con(pc),d0
		beq.s	.parkHold			; no word yet
		tst.w	ai_enterTimer		; word has spawned - hold for ai_enterwait
		beq.s	.launch				; frames, then go
		subq.w	#1,ai_enterTimer
		bra.s	.parked
.parkHold:
		move.w	#ai_enterwait,ai_enterTimer
		bra.s	.parked
.launch:
		st		ai_entered
		move.w	#ai_enterangle,obj_angle(a0)
		move.w	#ai_enterspeed,obj_xvelo(a0)
		clr.w	obj_yvelo(a0)
.parked:
		bsr		obj_move
		rts
.flying:
		tst.b	seq_on				; the logo destruction flies the ship now
		bne		seq_pilot
		IFNE	ai_hoveronly
		bsr		ai_pilot
		bsr		obj_move
		rts
		ENDC

		tst.w	ai_fireWait
		beq.s	.nfw
		subq.w	#1,ai_fireWait
.nfw:
		; hold fire until the whole word has finished arriving, then for a
		; further ai_holdframes so it can actually be read. the timer is
		; reloaded the whole time any letter is still waiting or zooming,
		; so it only starts running down once the word is complete.
		; --- which end do we attack from? Decided the moment a word
		;     appears, not when it has finished zooming in, so the ship can
		;     be on its way to that end while the letters are still arriving.
		move.l	enemy_con(pc),d0
		bne.s	.haveWord
		sf		ai_sidePicked		; no word - arm for the next one
		bra.s	.sideDone
.haveWord:
		tst.b	ai_sidePicked
		bne.s	.sideDone
		st		ai_sidePicked
		moveq	#-1,d0				; attack from whichever end we are nearer
		cmp.w	#ast_x_center,obj_xc(a0)
		blt.s	.sideSet
		moveq	#1,d0
.sideSet:
		move.w	d0,ai_side
		move.b	#ST_APPROACH,ai_state	; new word - fly clear of it first
.sideDone:
		tst.b	ai_forming
		beq.s	.formed
		move.w	#ai_holdframes,ai_holdFire
		bra.s	.holdDone
.formed:
		tst.w	ai_holdFire
		beq.s	.holdDone
		subq.w	#1,ai_holdFire
.holdDone:
		addq.w	#1,ai_dry
		bsr		ai_findTarget		; -> ai_target, ai_dx/dy, ai_cross/dot
		bsr		ai_checkBox			; -> ai_recover
		bsr		ai_station			; -> ai_sdx/sdy/sdist, ai_over
		bsr		ai_states			; -> ai_state

		; --- steer at whatever the current state says: the station while
		;     approaching, our own reverse velocity while braking, and the
		;     letter itself once we have settled.
		tst.b	ai_recover			; heading off the screen beats everything
		bne.s	.recoverAim
		cmp.b	#ST_APPROACH,ai_state
		beq.s	.stationAim
		cmp.b	#ST_ARRIVE,ai_state
		beq.s	.brakeAim
		move.l	ai_cross,d2			; ATTACK - nose on the letter
		move.l	ai_dot,d3
		bra		.aimSet

.stationAim:
		move.w	ai_sdx,d0
		move.w	ai_sdy,d1
		bsr		ai_crossdot
		bra		.aimSet

.brakeAim:
		move.w	obj_xvelo(a0),d0	; nose round to face backwards so the
		move.w	obj_yvelo(a0),d1	; thrust takes speed off
		neg.w	d0
		neg.w	d1
		asr.w	#4,d0
		asr.w	#4,d1
		bsr		ai_crossdot
		bra		.aimSet

.recoverAim:
		move.w	obj_xvelo(a0),d0	; how fast are we drifting?
		bpl.s	.rvx
		neg.w	d0
.rvx:
		move.w	obj_yvelo(a0),d1
		bpl.s	.rvy
		neg.w	d1
.rvy:
		add.w	d1,d0
		cmp.w	#ai_slowspeed,d0
		blt.s	.headHome			; slow enough - now aim for the middle
		move.w	obj_xvelo(a0),d0	; still quick - kill the drift first
		move.w	obj_yvelo(a0),d1
		neg.w	d0
		neg.w	d1
		asr.w	#4,d0				; keep the muls well inside a long
		asr.w	#4,d1
		bra.s	.recoverGo
.headHome:
		move.w	#ai_boxcx,d0
		sub.w	obj_xc(a0),d0
		move.w	#ai_boxcy,d1
		sub.w	obj_yc(a0),d1
		bsr		ai_wrap
.recoverGo:
		bsr		ai_crossdot
.aimSet:
		move.l	d2,ai_aimcross
		move.l	d3,ai_aimdot
		bsr		ai_turn
		bsr		ai_fire
		bsr		ai_move

		bsr		obj_move
		rts

;---------------------------------------------
; pick the nearest live letter, or fall back to loitering near the
; middle of the play area while a word is still appearing.
; out: ai_target, ai_dx/ai_dy, ai_cross/ai_dot
;---------------------------------------------
ai_findTarget:
		tst.w	ai_retarget
		beq.s	.repick
		subq.w	#1,ai_retarget
		move.w	ai_target,d7
		bmi.s	.repick
		bsr		ai_valid			; still worth shooting at?
		tst.w	d0
		bne		.have
.repick:
		move.w	#ai_retargetms,ai_retarget
		moveq	#-1,d3				; best bit so far
		move.w	#$7fff,d5			; best x (min end) or best distance
		tst.b	ai_sidemode
		beq.s	.wantLeft			; brawl mode -> nearest letter
		tst.w	ai_side
		bmi.s	.wantLeft
		move.w	#$8000,d5			; ... or max end
.wantLeft:
		move.l	enemy_con(pc),d4
		lea		enemy_structs(pc),a1
		moveq	#31,d7				; bit 31 is struct 0
.scan:
		btst	d7,d4
		beq.s	.next
		tst.w	obj_flag(a1)		; already hit and exploding
		bne.s	.next
		tst.b	ai_sidemode
		bne.s	.edgePick
		move.w	obj_xc(a1),d0		; brawl mode - just take the nearest
		sub.w	obj_xc(a0),d0
		move.w	obj_yc(a1),d1
		sub.w	obj_yc(a0),d1
		bsr		ai_wrap
		tst.w	d0
		bpl.s	.nx
		neg.w	d0
.nx:
		tst.w	d1
		bpl.s	.ny
		neg.w	d1
.ny:
		add.w	d1,d0
		cmp.w	d5,d0
		bge.s	.next
		bra.s	.take
.edgePick:
		move.w	obj_xc(a1),d0		; furthest letter towards our side
		tst.w	ai_side
		bmi.s	.leftEnd
		cmp.w	d5,d0
		ble.s	.next
		bra.s	.take
.leftEnd:
		cmp.w	d5,d0
		bge.s	.next
.take:
		move.w	d0,d5
		move.w	d7,d3
.next:
		lea		obj_len(a1),a1
		dbf		d7,.scan
		move.w	d3,ai_target
		move.w	d3,d7
		bmi.s	.loiter
.have:
		bsr		ai_ptr				; d7 = bit -> a1 = struct
		move.w	obj_xc(a1),d0
		sub.w	obj_xc(a0),d0
		move.w	obj_yc(a1),d1
		sub.w	obj_yc(a0),d1
		bra.s	.gotDelta
.loiter:
		clr.w	ai_burst			; do not carry a part fired burst across
		; nothing to shoot yet - drift back towards the middle instead,
		; so the ship keeps moving while the next word zooms in
		move.w	#ai_homex,d0
		sub.w	obj_xc(a0),d0
		move.w	#ai_homey,d1
		sub.w	obj_yc(a0),d1
.gotDelta:
		bsr		ai_wrap
		move.w	d0,ai_dx
		move.w	d1,ai_dy
		bsr		ai_crossdot
		move.l	d2,ai_cross
		move.l	d3,ai_dot
		rts

		IFNE	ai_debug
;---------------------------------------------
; DEBUG OVERLAY
;---------------------------------------------
; Appends a few lines to the draw table so the state machine can actually
; be watched. Must be called with a6 still pointing at the free end of
; linetab, i.e. after shots_set and before the terminating clr.w (a6).
; set_line needs a5 = yOffTab, the same contract obj_move sets up, so it
; is reloaded here.
;---------------------------------------------
ai_debugMarks:
		lea		ship_struct,a0
		lea		yOffTab(pc),a5

		IFEQ	ai_hoveronly
		move.w	ai_target,d7
		bmi.s	.noTarget
		ENDC

		; --- + on the point we are flying to
		IFNE	ai_hoveronly
		move.w	ai_hx,dbgx			; absolute, so the wrap cannot hide it
		move.w	ai_hy,dbgy
		ELSE
		move.w	obj_xc(a0),d0
		add.w	ai_sdx,d0
		move.w	d0,dbgx
		move.w	obj_yc(a0),d0
		add.w	ai_sdy,d0
		move.w	d0,dbgy
		ENDC
		bsr.s	ai_markPlus

		; --- X on the target letter
		move.w	ai_target,d7
		bmi.s	.noTarget
		bsr		ai_ptr
		move.w	obj_xc(a1),dbgx
		move.w	obj_yc(a1),dbgy
		bsr.s	ai_markCross
.noTarget:

		; --- state bar, bottom left. one segment per state, plus a fourth
		;     while the nose is still swinging round.
		moveq	#0,d6
		IFNE	ai_hoveronly
		move.b	ai_hstate,d6		; 1 rotate, 2 burn, 3 coast
		tst.b	ai_astate
		beq.s	.hoverBar
		addq.w	#4,d6				; 5..7 while attacking
.hoverBar:
		ELSE
		move.b	ai_state,d6
		ENDC
		addq.w	#1,d6				; 1 = APPROACH, 2 = ARRIVE, 3 = ATTACK
		mulu	#6,d6
		move.w	#ai_boxx0,d0
		move.w	#ai_boxy1,d1
		move.w	d0,d2
		add.w	d6,d2
		move.w	d1,d3
		bsr		set_line
		tst.b	ai_turning
		beq.s	.notTurning
		move.w	#ai_boxx0,d0		; second, shorter bar under it
		move.w	#ai_boxy1,d1
		addq.w	#3,d1
		move.w	d0,d2
		addq.w	#6,d2
		move.w	d1,d3
		bsr		set_line
.notTurning:
		rts

;---------------------------------------------
; dbgx/dbgy hold the centre, because set_line uses every data register
;---------------------------------------------
ai_markPlus:
		move.w	dbgx,d0
		sub.w	#ai_marksize,d0
		move.w	dbgy,d1
		move.w	dbgx,d2
		add.w	#ai_marksize,d2
		move.w	dbgy,d3
		bsr		set_line
		move.w	dbgx,d0
		move.w	dbgy,d1
		sub.w	#ai_marksize,d1
		move.w	dbgx,d2
		move.w	dbgy,d3
		add.w	#ai_marksize,d3
		bsr		set_line
		rts

ai_markCross:
		move.w	dbgx,d0
		sub.w	#ai_marksize,d0
		move.w	dbgy,d1
		sub.w	#ai_marksize,d1
		move.w	dbgx,d2
		add.w	#ai_marksize,d2
		move.w	dbgy,d3
		add.w	#ai_marksize,d3
		bsr		set_line
		move.w	dbgx,d0
		add.w	#ai_marksize,d0
		move.w	dbgy,d1
		sub.w	#ai_marksize,d1
		move.w	dbgx,d2
		sub.w	#ai_marksize,d2
		move.w	dbgy,d3
		add.w	#ai_marksize,d3
		bsr		set_line
		rts

dbgx:			dc.w	0
dbgy:			dc.w	0
		ENDC

		IFNE	ai_hoveronly
;---------------------------------------------
; Top level, see "autopilot - the hunt". The old hover beside the word and
; the pass along the row (ai_hover, ai_attack) are no longer called.
; a0 = ship. a6 is the draw table and must survive.
;---------------------------------------------
ai_pilot:
		tst.w	ai_fireWait
		beq.s	.nofw
		subq.w	#1,ai_fireWait
.nofw:
		; --- the read pause: nothing is fired until the whole word has
		;     been up for ai_holdframes
		tst.b	ai_forming
		beq.s	.formed
		move.w	#ai_holdframes,ai_holdFire
		tst.b	ai_styleSet			; a new word: how will we go in? decided
		bne.s	.holdDone			; now, so the ship can get into position
		st		ai_styleSet			; while the word forms (see .idle)
		bsr		ai_rushStart
		bra.s	.holdDone
.formed:
		tst.w	ai_holdFire
		beq.s	.holdDone
		subq.w	#1,ai_holdFire
		bne.s	.holdDone
		move.w	#ai_rushtime,ai_rush	; the word may be shot now: go for it
.holdDone:
		; --- the attack on a new word starts as a rush - faster, and
		;     closer in before it settles to shoot - until the first hit
		;     breaks the word up or ai_rushtime runs out
		tst.w	ai_rush
		beq.s	.noRush
		subq.w	#1,ai_rush
		tst.b	word_scattered
		beq.s	.noRush
		clr.w	ai_rush
.noRush:
		; --- the expensive looks round run on alternate frames: the scan of
		;     every letter on one, a new station or a chance shot on the
		;     other (ai_phase). a 25 Hz look is still quicker than any player
		not.b	ai_phase
		beq.s	.noScan
		cmp.w	#2,ai_zooming		; two letters or more spinning in or
		bhs.s	.noScan				; bursting (each one costs nearly as much
									; as the scan): the look round waits -
									; else the frame would run over
		bsr		ai_huntScan			; -> ai_target, ai_threat...
.noScan:
		; --- how long have we been in front of the logo or the scroller?
		;     a while is fine, but not for ever (see ai_busymax)
		move.w	obj_yc(a0),d4
		bsr		ai_signedCoord
		move.w	d4,d6
		bsr		ai_busyY
		beq.s	.notBusy
		cmp.w	#1000,ai_busyTime
		bhs.s	.busyDone
		addq.w	#1,ai_busyTime
		bra.s	.busyDone
.notBusy:
		clr.w	ai_busyTime
.busyDone:
		; --- a rush with a set way in goes for the letter at that end
		tst.w	ai_rush
		beq.s	.noRushTgt
		tst.w	ai_rushIdx
		bmi.s	.noRushTgt
		bsr		ai_rushTarget
.noRushTgt:

		; --- a threat that can be shot and is still a fair way off is the
		;     one to aim at. ai_wantVelo dodges every other one.
		move.w	ai_threat,d7
		bmi.s	.noThreat
		tst.b	ai_threatSolid
		beq.s	.noThreat
		cmp.w	#ai_shootthreat,ai_threatNow
		blo.s	.noThreat
		move.w	d7,ai_target
.noThreat:
		bsr		ai_aimTarget		; -> ai_aimcross/dot, ai_targetSolid
		bsr		ai_wantVelo			; -> ai_vdx/vdy, ai_evading

		; --- the word is broken up: hunt like a gunner. the nose goes from
		;     target to target and nowhere else - no turning away to steer.
		;     if the target is out of range the ship burns straight at it,
		;     along the way the nose points anyway. only dodging, and
		;     slowing down when far too fast, still use the steering below
		tst.b	word_scattered
		beq.s	.steerMode
		tst.b	ai_evading
		bne.s	.steerMode
		bsr		ai_speed
		cmp.w	#ai_gunnertop,d0
		bhs.s	.steerMode
		cmp.w	#ai_busymax,ai_busyTime	; too long in front of the logo or
		bhs.s	.steerMode			; the scroller: that moves it away
		sf		ai_mode
		tst.w	ai_target
		bmi		.fire
		move.l	ai_aimcross,d2
		move.l	ai_aimdot,d3
		bsr		ai_huntTurn
		tst.b	ai_turning			; on it, and it is out of range?
		bne		.fire
		cmp.w	#ai_gunnerfar,ai_aimDist
		blo		.fire
		move.w	obj_xvelo(a0),d0	; and not already closing fast enough
		move.w	obj_yvelo(a0),d1
		bsr		ai_crossdot			; d3 = our speed along the nose, Q15
		swap	d3
		add.w	d3,d3
		cmp.w	#ai_gunnerspeed,d3
		bge		.fire
		moveq	#ai_thrust,d2
		bsr		obj_thrust
		bra		.fire
.steerMode:

		; --- how far is our velocity off the one we want?
		move.w	ai_vdx,d0
		sub.w	obj_xvelo(a0),d0
		move.w	ai_vdy,d1
		sub.w	obj_yvelo(a0),d1
		bsr		ai_manhattan		; d5
		tst.b	ai_evading
		bne.s	.evade
		tst.w	ai_aimHold			; gave up on a correction a moment ago
		beq.s	.noHold
		subq.w	#1,ai_aimHold
		bra.s	.aim
.noHold:
		tst.b	ai_mode
		bne.s	.correcting
		cmp.w	#ai_corrstart,d5
		blo.s	.aim
		st		ai_mode
		st		ai_turning
		clr.w	ai_modeTick
.correcting:
		cmp.w	#ai_corrstop,d5
		blo.s	.toAim
		addq.w	#1,ai_modeTick
		cmp.w	#ai_corrmax,ai_modeTick
		blo.s	.steer
.toAim:
		; after EVERY manoeuvre the nose stays on the target for a while.
		; going straight back into the next correction is what swung the
		; nose to and fro like a drunk pilot
		move.w	#ai_aimhold,ai_aimHold
		sf		ai_mode
		st		ai_turning
		bra.s	.aim

; --- rotate, then burn: the nose into the velocity difference. once it
;     is within ai_burncone the ship just burns, it does not swing the
;     rest of the way round - the part of the thrust that goes sideways is
;     cheaper than the turn away from the target and back again
.steer:
		asr.w	#2,d0				; keep the muls well inside a long
		asr.w	#2,d1
		bsr		ai_crossdot
		tst.l	d3
		ble.s	.sTurn
		move.l	d2,d4
		bpl.s	.sPos
		neg.l	d4
.sPos:
		IFNE	ai_burncone-1
		lsl.l	#ai_burncone-1,d4	; |cross| * 2^(cone-1) < dot
		ENDC
		cmp.l	d3,d4
		bhs.s	.sTurn
		sf		ai_turning
		moveq	#ai_thrust,d2
		bsr		obj_thrust
		bra.s	.fire
.sTurn:
		bsr		ai_turn
		bra.s	.fire

; --- dodging can not wait for a tidy turn: burn as soon as the nose is
;     within 45 degrees of where it has to go
.evade:
		cmp.w	#ai_corrstop,d5
		blo.s	.aim
		st		ai_mode				; and once it is over carry on from here
		clr.w	ai_modeTick
		asr.w	#2,d0
		asr.w	#2,d1
		bsr		ai_crossdot
		bsr		ai_turn				; leaves d2/d3 alone
		tst.l	d3
		ble.s	.fire
		move.l	d2,d4
		bpl.s	.ePos
		neg.l	d4
.ePos:
		cmp.l	d3,d4				; |cross| < dot: inside 45 degrees
		bhs.s	.fire
		moveq	#ai_thrust,d2
		bsr		obj_thrust
		bra.s	.fire

.aim:
		; --- while aiming: if the nose happens to point the way we want to
		;     go anyway, give it a little thrust. that wears the velocity
		;     error down without a turn, so fewer big corrections are needed
		;     - each of those is a swing away from the target and back
		cmp.w	#ai_nudge,d5
		blo.s	.noNudge
		asr.w	#2,d0
		asr.w	#2,d1
		bsr		ai_crossdot
		tst.l	d3
		ble.s	.noNudge
		move.l	d2,d4
		bpl.s	.nPos
		neg.l	d4
.nPos:
		add.l	d4,d4				; |cross| * 2 < dot: inside ~26 degrees
		cmp.l	d3,d4
		bhs.s	.noNudge
		moveq	#ai_thrust,d2
		bsr		obj_thrust
.noNudge:
		tst.w	ai_holdFire			; patrolling (see ai_wantVelo): the nose
		bne.s	.fire				; stays the way we fly, no aiming about
		tst.w	ai_target
		bmi.s	.fire
		move.l	ai_aimcross,d2
		move.l	ai_aimdot,d3
		bsr		ai_huntTurn
.fire:
		bra		ai_huntFire

;---------------------------------------------
; the lead point of the target -> ai_aimcross/ai_aimdot, ai_aimDist, and
; ai_targetSolid if it can be shot (it has finished appearing)
;---------------------------------------------
ai_aimTarget:
		sf		ai_targetSolid
		move.w	ai_target,d7
		bmi.s	.none
		bsr		ai_ptr
		tst.w	obj_wait(a1)
		bne.s	.notSolid
		tst.w	obj_appear(a1)
		bne.s	.notSolid
		tst.w	obj_flag(a1)		; hit since the last scan
		bne.s	.notSolid
		st		ai_targetSolid
.notSolid:
		bsr		ai_leadAim			; d0/d1 = where to aim
		bsr		ai_crossdot
		move.l	d2,ai_aimcross
		move.l	d3,ai_aimdot
		rts
.none:
		clr.l	ai_aimcross
		clr.l	ai_aimdot			; dot 0 counts as behind us, never fires
		rts

;---------------------------------------------
; the rush on a new word: how does it go in? one of four, at random, so
; it never looks the same twice in a row for long:
;   along the row from the end nearer the ship
;   along the row from either end (maybe round the screen edge to get there)
;   diagonally down onto the end nearer the ship
;   no set way - the nearest letter, as in the hunt
; -> ai_rushIdx = the ai_offsets entry (byte offset), -1 for the last
;---------------------------------------------
ai_rushStart:
		jsr		getRandomNumber
		move.w	d0,d1
		and.w	#3,d1
		cmp.w	#3,d1
		bne.s	.set
		move.w	#-1,ai_rushIdx
		rts
.set:
		moveq	#0,d2				; 0 = the left end, 4 = the right one
		cmp.w	#1,d1
		bne.s	.near
		btst	#8,d0				; either end
		beq.s	.sideSet
		moveq	#4,d2
		bra.s	.sideSet
.near:
		cmp.w	#ast_x_center,obj_xc(a0)
		blt.s	.sideSet
		moveq	#4,d2
.sideSet:
		moveq	#32,d3				; along the row ...
		cmp.w	#2,d1
		bne.s	.way
		moveq	#40,d3				; ... or down onto the end
.way:
		add.w	d2,d3
		move.w	d3,ai_rushIdx
		rts

;---------------------------------------------
; where to wait while the word forms, for the way in ai_rushStart picked
; -> ai_wayx/ai_wayy. along the row: level with it, out beyond the end
; letter. from above: above that end. keeps d4.
;---------------------------------------------
ai_stagePoint:
		move.w	d4,-(a7)
		bsr		ai_endX				; d0 = x of the end letter
		move.w	(a7)+,d4
		move.w	ai_rushIdx,d2
		move.w	#ast_y_start,d1
		move.w	#ai_stagedx,d3
		cmp.w	#40,d2
		blo.s	.row
		sub.w	#ai_stagedy,d1		; from above
		move.w	#ai_stagedx2,d3
.row:
		btst	#2,d2				; the right end?
		bne.s	.right
		neg.w	d3
.right:
		add.w	d3,d0
		cmp.w	#ai_stagex0,d0		; on screen
		bge.s	.x0
		move.w	#ai_stagex0,d0
.x0:
		cmp.w	#ai_stagex1,d0
		ble.s	.x1
		move.w	#ai_stagex1,d0
.x1:
		move.w	d0,ai_wayx
		move.w	d1,ai_wayy
		rts

;---------------------------------------------
; -> d0 = x of the letter at the rush's end of the word (ai_rushIdx bit 2:
; the right end), letters still waiting included. uses d0-d7/a1
;---------------------------------------------
ai_endX:
		move.l	enemy_con(pc),d2
		lea		enemy_structs,a1
		moveq	#31,d7
		move.w	ai_rushIdx,d4
		and.w	#4,d4
		move.w	#ast_x_center,d3	; (no letters: the middle)
		move.w	#$7fff,d5
		tst.w	d4
		beq.s	.loop
		moveq	#-1,d5
.loop:
		btst	d7,d2
		beq.s	.next
		move.w	obj_xc(a1),d0
		tst.w	d4
		bne.s	.right
		cmp.w	d5,d0
		bge.s	.next
		bra.s	.take
.right:
		cmp.w	d5,d0
		ble.s	.next
.take:
		move.w	d0,d5
		move.w	d0,d3
.next:
		lea		obj_len(a1),a1
		dbf		d7,.loop
		move.w	d3,d0
		rts

;---------------------------------------------
; the rush goes for the letter at its end of the word -> ai_target
;---------------------------------------------
ai_rushTarget:
		move.l	enemy_con(pc),d2
		beq.s	.none
		lea		enemy_structs,a1
		moveq	#31,d7
		moveq	#-1,d3
		move.w	ai_rushIdx,d4
		and.w	#4,d4				; 0: smallest x wanted, else largest
		move.w	#$7fff,d5
		tst.w	d4
		beq.s	.loop
		moveq	#-1,d5
.loop:
		btst	d7,d2
		beq.s	.next
		tst.w	obj_flag(a1)
		bne.s	.next
		move.w	obj_xc(a1),d0
		tst.w	d4
		bne.s	.right
		cmp.w	d5,d0
		bge.s	.next
		bra.s	.take
.right:
		cmp.w	d5,d0
		ble.s	.next
.take:
		move.w	d0,d5
		move.w	d7,d3
.next:
		lea		obj_len(a1),a1
		dbf		d7,.loop
		tst.w	d3
		bmi.s	.none
		move.w	d3,ai_target
.none:
		rts

;---------------------------------------------
; the velocity we want -> ai_vdx/ai_vdy, ai_evading
;---------------------------------------------
ai_wantVelo:
		sf		ai_evading
		move.w	ai_threat,d7
		bmi.s	.calm
		tst.b	ai_threatSolid
		beq.s	.evade
		cmp.w	#ai_shootthreat,ai_threatNow
		blo.s	.evade
.calm:
		; a word still forming (and being read): keep patrolling. chasing
		; stations then meant a new nearest letter, a new station on the
		; other side and a half turn every time another letter popped up
		tst.w	ai_holdFire
		bne		.idle
		bsr		ai_pickStation		; d0 = 0 if there is no target
		tst.w	d0
		beq		.idle
		; --- in range already? then stay put relative to it and shoot from
		;     here. flying to a station after every kill meant a turn to
		;     burn and a turn back to aim each time - the drunk look
		move.w	ai_tdx,d0
		move.w	ai_tdy,d1
		AI_MANH
		move.w	#ai_engage,d6		; (hysteresis: once engaged it takes a
		tst.w	ai_rush				; good bit more to start flying again.
		beq.s	.engNorm			; in a rush, it closes in further first)
		move.w	#ai_rushengage,d6
.engNorm:
		tst.b	ai_engaged
		beq.s	.engTest
		add.w	#ai_engagehyst,d6
.engTest:
		sf		ai_engaged
		cmp.w	d6,d5
		bhs.s	.approach
		cmp.w	#ai_busymax,ai_busyTime	; parked in front of the logo or the
		bhs.s	.approach			; scroller for a while: move somewhere
		st		ai_engaged			; better (stations there count extra)
		; keep the drift we have (nothing to correct, so no turn), only
		; slow down if it is more than ai_drift
		move.w	obj_xvelo(a0),d0
		move.w	obj_yvelo(a0),d1
		AI_MANH
		cmp.w	#ai_drift,d5
		bls.s	.driftOk
		move.w	#ai_drift,d2
		bsr		ai_scaleTo
.driftOk:
		move.w	d0,ai_vdx
		move.w	d1,ai_vdy
		rts
.approach:
		move.w	ai_stx,d0
		move.w	ai_sty,d1
		move.w	ai_tvx,d2			; the station moves with the target
		move.w	ai_tvy,d3

; d0/d1 = vector to the point, d2/d3 = the point's own velocity
.toPoint:
		movem.w	d2/d3,-(a7)
		bsr		ai_manhattan
		cmp.w	#ai_stdead,d5
		bhs.s	.go
		moveq	#0,d0				; there - just move with it
		moveq	#0,d1
		bra.s	.ff
.go:
		add.w	d0,d0				; px -> 1/128 px a frame: get there in
		add.w	d1,d1				; about 64 frames ...
		add.w	d5,d5
		move.w	#ai_cruise,d2		; ... but never faster than cruise
		tst.w	ai_rush
		beq.s	.cruise
		move.w	#ai_rushcruise,d2
.cruise:
		cmp.w	d2,d5
		bls.s	.ff
		bsr		ai_scaleTo
.ff:
		movem.w	(a7)+,d2/d3
		add.w	d2,d0
		add.w	d3,d1
		move.w	d0,ai_vdx
		move.w	d1,ai_vdy
		rts

; --- no word (or one still forming): patrol from one waypoint to the
;     next - mostly where the ship can be seen well, sometimes over the
;     top, the short way round the screen edges. ai_home tells updateGame
;     the ship is out of the band the next word appears in and on screen,
;     so the word may come.
.idle:
		move.w	obj_xc(a0),d0
		move.w	obj_yc(a0),d4
		bsr		ai_signedCoord
		sf		ai_home
		sf		ai_clear
		cmp.w	#ai_homex0,d0		; on screen ...
		blt.s	.notHome
		cmp.w	#ai_homex1,d0
		bgt.s	.notHome
		tst.w	d4
		bmi.s	.notHome
		cmp.w	#game_height-16,d4
		bge.s	.notHome
		move.w	d4,d5				; ... and clear of the word row
		sub.w	#ast_y_start,d5
		bpl.s	.hAbs
		neg.w	d5
.hAbs:
		cmp.w	#ai_rowclear,d5
		blo.s	.notHome
		move.w	obj_yvelo(a0),d5	; ... and not heading for it
		cmp.w	#ast_y_start,d4
		bge.s	.below
		neg.w	d5
.below:
		st		ai_clear			; (out of the row band, see updateGame)
		cmp.w	#-16,d5				; (velocity away from the row, 1/128 px)
		blt.s	.notHome
		st		ai_home
.notHome:
		; --- pick a new waypoint when: a word was just cleared, the old one
		;     was reached or is taking too long, or we have hung about in
		;     front of the logo or the scroller long enough
		tst.w	ai_holdFire			; (a word is forming while this is set)
		beq.s	.noWord
		st		ai_hadWord
		bra.s	.wayCheck
.noWord:
		tst.b	ai_hadWord			; word just cleared
		beq.s	.wayCheck
		sf		ai_hadWord
		bra.s	.newWay
.wayCheck:
		subq.w	#1,ai_wayTick
		bmi.s	.newWay
		cmp.w	#ai_busymax,ai_busyTime
		bhs.s	.leaveBusy
		bsr		.wayDelta
		AI_MANH
		cmp.w	#ai_homedist,d5
		bhs.s	.toWay
		bra.s	.newWay				; reached
.leaveBusy:
		tst.b	ai_wayTop			; on the way to the logo anyway? then
		bne.s	.newWay				; somewhere else; else this one is fine
		bsr		.wayDelta			; (it is in the clear zone)
		bra.s	.toWay

; --- mostly the clear black area under the scroller, now and then a pass
;     over the top, anywhere across - and the way there may well be round
;     the edge of the screen
.newWay:
		move.w	#ai_waytime,ai_wayTick
		clr.w	ai_busyTime
		tst.w	ai_holdFire			; a word forming, and a set way in for
		beq.s	.wayRandom			; the attack? then wait where that starts
		tst.w	ai_rushIdx
		bmi.s	.wayRandom
		bsr		ai_stagePoint
		bsr		.wayDelta
		bra		.toWay
.wayRandom:
		jsr		getRandomNumber
		move.w	d0,d1
		and.w	#255,d0				; x 40..326
		add.w	#ai_homex0,d0
		lsr.w	#8,d1
		move.w	d1,d2
		and.w	#31,d2
		add.w	d2,d0
		move.w	d0,ai_wayx
		sf		ai_wayTop
		tst.w	ai_holdFire			; never the top while a word is forming
		bne.s	.wayBottom
		move.w	d1,d2
		and.w	#$e0,d2				; 1 in 8 goes over the top
		bne.s	.wayBottom
		st		ai_wayTop
		lsr.w	#3,d1
		and.w	#ai_waytoprange,d1
		add.w	#ai_waytop,d1
		bra.s	.waySet
.wayBottom:
		lsr.w	#3,d1
		and.w	#ai_waybotrange,d1
		add.w	#ai_waybottom,d1
.waySet:
		move.w	d1,ai_wayy
		bsr		.wayDelta
.toWay:
		moveq	#0,d2
		moveq	#0,d3
		bra		.toPoint

; d4 = ship y -> d0/d1 = vector to the waypoint, the short way round the
; screen. while a word is forming the way never crosses its row: if the
; waypoint is on the other side of it, we go round the top or bottom edge
.wayDelta:
		move.w	ai_wayx,d0
		sub.w	obj_xc(a0),d0
		move.w	ai_wayy,d1
		sub.w	d4,d1
		AI_WRAP
		tst.w	ai_holdFire
		beq.s	.wdDone
		cmp.w	#ast_y_start,d4		; above the row?
		bge.s	.wdBelow
		tst.w	d1					; then never down through it
		ble.s	.wdDone
		move.w	ai_wayy,d5
		cmp.w	#ast_y_start,d5
		blt.s	.wdDone				; (the waypoint is above it as well)
		sub.w	#ai_wrapy,d1		; up, round the top edge
		rts
.wdBelow:
		tst.w	d1					; below: never up through it
		bge.s	.wdDone
		move.w	ai_wayy,d5
		cmp.w	#ast_y_start,d5
		bge.s	.wdDone
		add.w	#ai_wrapy,d1		; down, round the bottom edge
.wdDone:
		rts

; --- dodge: off the threat's path, on the side we are already on - at
;     right angles to the way it is coming (relative to us) - plus away
;     from where it is going to be
.evade:
		st		ai_evading
		; a letter still appearing does not move - its "path" is just our
		; own, so stepping off it sideways only slides along the row into
		; the next one. straight away from it then
		tst.b	ai_threatSolid
		bne.s	.moving
		moveq	#0,d0
		moveq	#0,d1
		bra.s	.pDone
.moving:
		move.w	ai_threatRy,d0		; p = (-ry, rx)
		neg.w	d0
		move.w	ai_threatRx,d1
		movem.w	d0/d1,-(a7)			; the side the nose already points to:
		bsr		ai_crossdot			; a dodge that needs no half turn first
		movem.w	(a7)+,d0/d1			; gets going in time (the "away" part
		tst.l	d3					; added below keeps it off the letter)
		bpl.s	.sideOk
		neg.w	d0
		neg.w	d1
.sideOk:
		bsr		ai_manhattan
		cmp.w	#4,d5
		bhs.s	.pOk
		moveq	#0,d0				; hardly moving relative to us, no path
		moveq	#0,d1				; to step off - just away from it
		bra.s	.pDone
.pOk:
		moveq	#64,d2
		bsr		ai_scaleTo
.pDone:
		movem.w	d0/d1,-(a7)
		move.w	ai_threatPx,d0		; away from it
		move.w	ai_threatPy,d1
		neg.w	d0
		neg.w	d1
		moveq	#64,d2
		bsr		ai_scaleTo
		movem.w	(a7)+,d2/d3
		add.w	d2,d0
		add.w	d3,d1
		move.w	#ai_evadespeed,d2
		bsr		ai_scaleTo
		move.w	d0,ai_vdx
		move.w	d1,ai_vdy
		rts

;---------------------------------------------
; d0/d1 -> the same direction, |d0|+|d1| = d2 (about). a zero vector
; comes back as straight down. uses d5/d6.
;---------------------------------------------
ai_scaleTo:
		bsr		ai_manhattan
		tst.w	d5
		bne.s	.ok
		moveq	#0,d0
		move.w	d2,d1
		rts
.ok:
		muls	d2,d0
		divs	d5,d0
		muls	d2,d1
		divs	d5,d1
		rts

;---------------------------------------------
; the station for ai_target -> ai_stx/ai_sty (vector from the ship),
; ai_tvx/ai_tvy (the target's velocity), d0 = 0 if there is no target.
; The offset is chosen again when the target changes and every
; ai_offrepick frames: the one nearest the ship, unless another letter is
; within ai_stclear of it.
; uses d0-d7/a1/a2/a4
;---------------------------------------------
ai_offsets:
		dc.w	-ai_stdiag,-ai_stdiag
		dc.w	 ai_stdiag,-ai_stdiag
		dc.w	-ai_stdiag, ai_stdiag
		dc.w	 ai_stdiag, ai_stdiag
		dc.w	0,-ai_stvert
		dc.w	0, ai_stvert
		dc.w	-ai_sthorz,0
		dc.w	 ai_sthorz,0
ai_offcount		= 8
; only for the rush on a new word (see ai_rushStart), never picked otherwise
		dc.w	-ai_rushdx,0				; 32: in from the left, along the row
		dc.w	 ai_rushdx,0				; 36: in from the right
		dc.w	-ai_rushdg,-ai_rushdg		; 40: down onto the left end
		dc.w	 ai_rushdg,-ai_rushdg		; 44: down onto the right end

ai_pickStation:
		move.w	ai_target,d7
		bpl.s	.have
		moveq	#0,d0
		rts
.have:
		bsr		ai_ptr
		move.w	obj_xvelo(a1),ai_tvx
		move.w	obj_yvelo(a1),ai_tvy
		bsr		ai_deltaTo			; d0/d1 = target - ship
		move.w	d0,ai_tdx
		move.w	d1,ai_tdy
		tst.w	ai_rush				; a rush with a set way in?
		beq.s	.noRushWay
		move.w	ai_rushIdx,d3
		bmi.s	.noRushWay
		move.w	d3,ai_offIdx
		bra		.use
.noRushWay:
		tst.b	ai_phase			; not on a scan frame, see ai_pilot
		bne		.use
		cmp.w	ai_offTarget,d7
		bne.s	.repick
		subq.w	#2,ai_offTick		; (counts every other frame)
		bpl		.use
.repick:
		move.w	d7,ai_offTarget
		move.w	#ai_offrepick,ai_offTick
		; --- every candidate's vector from the ship and how far that is
		lea		ai_offsets(pc),a2
		lea		ai_cand,a4
		moveq	#ai_offcount-1,d3
.cand:
		move.w	ai_tdx(pc),d0
		add.w	(a2)+,d0
		move.w	ai_tdy(pc),d1
		add.w	(a2)+,d1
		AI_WRAP
		move.w	d0,(a4)+
		move.w	d1,(a4)+
		AI_MANH
		move.w	ai_shy(pc),d6		; a spot in front of the logo or the
		add.w	d1,d6				; scroller - where the ship is hard to
		bsr		ai_busyY			; see - counts as further away
		beq.s	.candFree
		add.w	#ai_busypen,d5
.candFree:
		move.w	d5,(a4)+
		addq.l	#2,a4
		dbf		d3,.cand
		; the side we are on already wins unless another is clearly nearer -
		; swapping sides for a few pixels is a needless trip and a turn
		lea		ai_cand,a4
		move.w	ai_offIdx(pc),d6
		add.w	d6,d6
		sub.w	#ai_stkeep,4(a4,d6.w)

		; --- then the nearest first, until one is free. usually the first
		;     or second is, so few get the letter check
		moveq	#ai_offcount-1,d3	; tries
.try:
		lea		ai_cand,a4
		move.w	#$7fff,d5
		moveq	#-1,d4				; nearest left, byte offset
		moveq	#0,d6
.min:
		cmp.w	4(a4,d6.w),d5
		ble.s	.notMin
		move.w	4(a4,d6.w),d5
		move.w	d6,d4
.notMin:
		addq.w	#8,d6
		cmp.w	#ai_offcount*8,d6
		blo.s	.min
		tst.w	d4
		bmi.s	.use				; all blocked - keep the one we had
		move.w	#$7fff,4(a4,d4.w)	; tried
		; --- blocked? the vectors to every letter are in ai_list already
		;     (ai_huntScan), so this is a few subtractions per letter
		move.w	(a4,d4.w),d2
		move.w	2(a4,d4.w),d7
		lea		ai_list,a1
		move.l	ai_listEnd(pc),a3
		bra.s	.chkTest
.chk:
		movem.w	(a1)+,d0/d1/d6		; dx, dy, bit
		addq.l	#6,a1				; rest of the entry
		cmp.w	ai_target(pc),d6
		beq.s	.chkTest			; the target itself
		sub.w	d2,d0				; letter - station
		sub.w	d7,d1
		AI_WRAP
		AI_MANH
		cmp.w	#ai_stclear,d5
		blo.s	.blocked			; something is in the way
.chkTest:
		cmp.l	a3,a1
		blo.s	.chk
		lsr.w	#1,d4				; free: ai_cand entry -> ai_offsets entry
		move.w	d4,ai_offIdx
		bra.s	.use
.blocked:
		dbf		d3,.try
.use:
		move.w	ai_offIdx,d3
		lea		ai_offsets(pc),a2
		move.w	ai_tdx,d0
		add.w	(a2,d3.w),d0
		move.w	ai_tdy,d1
		add.w	2(a2,d3.w),d1
		bsr		ai_wrap
		move.w	d0,ai_stx
		move.w	d1,ai_sty
		moveq	#1,d0
		rts

;---------------------------------------------
; d6 = y on the screen -> Z clear if that is in front of the logo or the
; scroller, where the ship is hard to make out. keeps d0-d5.
;---------------------------------------------
ai_busyY:
		cmp.w	#ai_logoy,d6
		blt.s	.busy
		cmp.w	#ai_scrolly0,d6
		blt.s	.free
		cmp.w	#ai_scrolly1,d6
		bge.s	.free
.busy:
		moveq	#1,d6
		rts
.free:
		moveq	#0,d6
		rts

;---------------------------------------------
; turn onto the lead point until a shot would actually hit. ai_turn's
; cones are angles - it stops anywhere inside about 7 degrees, which at
; 100 pixels is a 12 pixel miss, so the ship sat there lined up "enough"
; to stop turning and never well enough to fire. This one goes by the
; miss in pixels (cross >> 15, see the hunt notes) instead, and turns in
; single degrees once it is close, because 4 degree steps jump right over
; a letter at range.
; in: d2 = cross, d3 = dot
;---------------------------------------------
ai_huntTurn:
		tst.l	d3
		ble.s	.coarse				; behind us
		move.l	d2,d4
		bpl.s	.pos
		neg.l	d4
.pos:
		tst.b	ai_turning			; holding still: only start turning again
		bne.s	.wasTurning			; once a shot would miss - the lead point
		cmp.l	#ai_hitslack<<15,d4	; wanders a little all the time
		blo.s	.onTarget
.wasTurning:
		cmp.l	#(ai_hitslack/2)<<15,d4
		blo.s	.onTarget
		cmp.l	#(ai_hitslack*3)<<15,d4
		blo.s	.fine
.coarse:
		moveq	#ai_turnrate,d1
		bra.s	.turn
.fine:
		moveq	#1,d1
.turn:
		bra		ai_turnBy
.onTarget:
		sf		ai_turning
		rts

;---------------------------------------------
; turn d1 degrees towards cross d2 / dot d3. while the point is still
; behind us the direction we were already turning in is kept: deciding by
; the sign of cross every frame made the ship flip its turn - or spin on
; past a full circle - whenever the point wobbled across dead astern.
;---------------------------------------------
ai_turnBy:
		tst.b	ai_turning			; a new turn: count from 0
		bne.s	.going
		clr.w	ai_turnAcc
.going:
		tst.l	d3
		bgt.s	.free
		tst.b	ai_turning
		beq.s	.free
		cmp.w	#ai_spinmax,ai_turnAcc	; but never on past a half turn and a
		bhs.s	.free					; bit - that is a spin, not a turn
		tst.b	ai_turnDir
		bne.s	.sub
		bra.s	.add
.free:
		tst.l	d2
		bmi.s	.subSet
		tst.b	ai_turnDir			; same way as before?
		beq.s	.add
		clr.w	ai_turnAcc
		sf		ai_turnDir
.add:
		add.w	d1,ai_turnAcc
		st		ai_turning
		bra		obj_addangle
.subSet:
		tst.b	ai_turnDir
		bne.s	.sub
		clr.w	ai_turnAcc
		st		ai_turnDir
.sub:
		add.w	d1,ai_turnAcc
		st		ai_turning
		bra		obj_subangle

;---------------------------------------------
; nearest letter and the most dangerous one. letters still waiting or
; zooming in count for both - the ship lines up on them and keeps out of
; their way, it just can not shoot them yet (ai_targetSolid).
; out: ai_target  nearest, unless the current one is less than
;                 ai_huntsticky further away - then that stays
;      ai_threat  the letter that is, or in 16 or 32 frames will be,
;                 closest to us, if that is under ai_dangerdist. -1 if none
;      ai_threatNow  how far away that one is right now
;      ai_threatPx/Py  where it is then, relative to us
;      ai_threatRx/Ry  its velocity relative to ours, >> 3
;      ai_threatSolid  it can be shot
; uses d0-d7/a1-a4
;---------------------------------------------
ai_huntScan:
		move.w	#-1,ai_threat
		move.w	#ai_dangerdist,ai_threatDist
		move.w	#$7fff,ai_curDist
		moveq	#-1,d3				; nearest so far
		move.w	#$7fff,a2			; ... and how near
		lea		ai_list,a5			; every live letter's vector, for
		move.l	a5,ai_listEnd		; ai_pickStation
		move.l	enemy_con(pc),d2
		bne.s	.any
		move.w	#-1,ai_target
		rts
.any:
		; the ship, once - everything below is inlined, this runs for
		; every letter every frame
		move.w	obj_xc(a0),ai_shx
		move.w	obj_yc(a0),d0
		cmp.w	#480,d0				; see ai_signedCoord
		blo.s	.shyOk
		sub.w	#512,d0
.shyOk:
		move.w	d0,ai_shy
		move.w	obj_xvelo(a0),ai_shvx
		move.w	obj_yvelo(a0),ai_shvy
		move.w	obj_angle(a0),d6	; the nose, for picking the target
		sub.w	#90,d6
		bpl.s	.aOk
		add.w	#360,d6
.aOk:
		lsl.w	#2,d6
		lea		sctab(pc),a3
		move.w	2(a3,d6.w),ai_fx
		move.w	(a3,d6.w),ai_fy
		lea		enemy_structs(pc),a1
		moveq	#31,d7				; bit 31 is struct 0
.loop:
		btst	d7,d2
		beq		.next
		tst.w	obj_flag(a1)		; already blowing up
		bne		.next

		move.w	obj_xc(a1),d0		; ai_deltaTo, inlined
		sub.w	ai_shx(pc),d0
		move.w	obj_yc(a1),d1
		cmp.w	#480,d1
		blo.s	.lyOk
		sub.w	#512,d1
.lyOk:
		sub.w	ai_shy(pc),d1
		move.w	d0,ai_rawx			; the direct way, before the wrap
		move.w	d1,ai_rawy
		AI_WRAP
		; relative velocity * 16 frames, in pixels (velocity is 1/128 px)
		move.w	obj_xvelo(a1),d4
		sub.w	ai_shvx(pc),d4
		asr.w	#3,d4
		move.w	obj_yvelo(a1),d6
		sub.w	ai_shvy(pc),d6
		asr.w	#3,d6
		move.w	d6,a4
		move.w	d0,(a5)+			; into the list, see ai_list
		move.w	d1,(a5)+
		move.w	d7,(a5)+
		move.w	d4,(a5)+
		move.w	d6,(a5)+
		move.w	obj_wait(a1),d6		; 0 = can be shot
		or.w	obj_appear(a1),d6
		move.w	d6,(a5)+
		AI_MANH						; d5
		move.w	d5,a3				; kept for ai_threatNow
		; --- only reachable round the screen edge (the direct way is a lot
		;     longer)? then it counts as much further away as a target, and
		;     gets no chance shots: a direct attack on the visible screen
		;     comes first. the threat check below still uses the real
		;     distance, of course
		cmp.w	ai_rawx(pc),d0
		bne.s	.wrX
		cmp.w	ai_rawy(pc),d1
		beq.s	.direct
.wrX:
		movem.w	d0/d1,-(a7)
		move.w	ai_rawx(pc),d0
		move.w	ai_rawy(pc),d1
		AI_MANH
		sub.w	#ai_wrapslack,d5
		cmp.w	a3,d5
		movem.w	(a7)+,d0/d1			; (leaves the flags alone)
		ble.s	.direct				; hardly longer - fine, go direct
		or.w	#$100,-2(a5)		; no chance shots at it
		move.w	a3,d5
		add.w	#ai_wrappen,d5
		bra.s	.choose
.direct:
		move.w	a3,d5
.choose:
		; --- the target is the letter that can be shot SOONEST: turning
		;     the nose round takes time (6 degrees a frame), the shot takes
		;     time to get there (2 px a frame). score = degrees to turn +
		;     2 * distance - so the ship sweeps from one letter to the next
		;     one along, instead of swinging round to whatever is nearest
		tst.w	-2(a5)				; can it be shot? (0 = yes)
		beq.s	.solidT
		add.w	#1000,d5			; appearing, or only round the edge:
		bra.s	.scored				; only if there is nothing else
.solidT:
		add.w	d5,d5
		cmp.w	#ai_huntrange,a3
		blo.s	.inRange
		add.w	#ai_farpen*2+90,d5	; out of range: we would have to fly first
		bra.s	.scored				; (and the turn hardly matters then)
.inRange:
		movem.w	d0/d1/d4,-(a7)
		move.w	ai_fy(pc),d6
		muls	d0,d6				; fy*dx
		move.w	ai_fx(pc),d4
		muls	d1,d4				; fx*dy
		sub.l	d6,d4				; cross
		bpl.s	.cPos
		neg.l	d4
.cPos:
		move.w	ai_fx(pc),d6
		muls	d0,d6				; fx*dx
		muls	ai_fy(pc),d1		; fy*dy
		add.l	d1,d6				; dot
		moveq	#15,d0				; both in pixels
		asr.l	d0,d4
		asr.l	d0,d6
		move.w	d6,d1
		bpl.s	.dPos
		neg.w	d1
.dPos:
		add.w	d4,d1				; |cross| + |dot|
		beq.s	.angSet				; (d0 is 15 - near enough to "none")
		tst.w	d6
		bpl.s	.front
		move.w	d6,d0				; behind: 90 .. 180
		neg.w	d0
		mulu	#90,d0
		divu	d1,d0
		add.w	#90,d0
		bra.s	.angSet
.front:
		move.w	d4,d0				; in front: 0 .. 90
		mulu	#90,d0
		divu	d1,d0
.angSet:
		add.w	d0,d5
		add.w	d0,d5
		movem.w	(a7)+,d0/d1/d4
.scored:
		cmp.w	ai_target(pc),d7
		bne.s	.notCur
		move.w	d5,ai_curDist
.notCur:
		cmp.w	a2,d5
		bge.s	.notNearest
		move.w	d5,a2
		move.w	d7,d3
.notNearest:
		move.w	a3,d5				; the real distance again
		cmp.w	ai_threatDist(pc),d5	; too close right now?
		bhs.s	.in16
		bsr		.threat
.in16:
		add.w	d4,d0
		add.w	a4,d1
		AI_MANH
		cmp.w	ai_threatDist(pc),d5
		bhs.s	.in32
		bsr		.threat
.in32:
		add.w	d4,d0
		add.w	a4,d1
		AI_MANH
		cmp.w	ai_threatDist(pc),d5
		bhs.s	.next
		bsr		.threat
.next:
		lea		obj_len(a1),a1
		dbf		d7,.loop
		move.l	a5,ai_listEnd

		; --- keep the current target unless the new one is clearly nearer,
		;     or the nose swings back and forth between two of them
		move.w	ai_curDist,d5
		cmp.w	#$7fff,d5
		beq.s	.take				; current one gone
		sub.w	#ai_huntsticky,d5
		cmp.w	a2,d5
		ble.s	.done
.take:
		move.w	d3,ai_target
.done:
		rts

.threat:
		move.w	d5,ai_threatDist
		move.w	d7,ai_threat
		move.w	a3,ai_threatNow
		move.w	d0,ai_threatPx
		move.w	d1,ai_threatPy
		move.w	d4,ai_threatRx
		move.w	a4,ai_threatRy
		sf		ai_threatSolid
		tst.w	obj_wait(a1)
		bne.s	.notSolid
		tst.w	obj_appear(a1)
		bne.s	.notSolid
		st		ai_threatSolid
.notSolid:
		rts

;---------------------------------------------
; a1 = object -> d0/d1 = shortest vector from the ship (a0) to it. y can
; be just above the top (see ai_signedCoord), x never is. uses d4.
;---------------------------------------------
ai_deltaTo:
		move.w	obj_xc(a1),d0
		sub.w	obj_xc(a0),d0
		move.w	obj_yc(a1),d4
		bsr		ai_signedCoord
		move.w	d4,d1
		move.w	obj_yc(a0),d4
		bsr		ai_signedCoord
		sub.w	d4,d1
		; the way round the screen edge only if the direct one is a lot
		; longer: aiming (and the station next to the target) stay on the
		; visible screen whenever that is reasonable. uses d4-d6 too
		movem.w	d0/d1,-(a7)			; direct
		bsr		ai_wrap
		cmp.w	(a7),d0
		bne.s	.wrapped
		cmp.w	2(a7),d1
		beq.s	.direct
.wrapped:
		bsr		ai_manhattan		; round the edge
		move.w	d5,d4
		movem.w	(a7),d0/d1			; (still on the stack)
		bsr		ai_manhattan		; direct
		sub.w	#ai_wrapslack,d5
		cmp.w	d4,d5
		ble.s	.direct
		bsr		ai_wrap				; round the edge it is
		addq.l	#4,a7
		rts
.direct:
		movem.w	(a7)+,d0/d1
		rts

;---------------------------------------------
; d0/d1 -> d5 = |d0|+|d1|. uses d6.
;---------------------------------------------
ai_manhattan:
		move.w	d0,d5
		bpl.s	.x
		neg.w	d5
.x:
		move.w	d1,d6
		bpl.s	.y
		neg.w	d6
.y:
		add.w	d6,d5
		rts

;---------------------------------------------
; -> d0 = |xvelo|+|yvelo| of the ship. uses d1.
;---------------------------------------------
ai_speed:
		move.w	obj_xvelo(a0),d0
		bpl.s	.x
		neg.w	d0
.x:
		move.w	obj_yvelo(a0),d1
		bpl.s	.y
		neg.w	d1
.y:
		add.w	d1,d0
		rts

;---------------------------------------------
; a1 = target -> d0/d1 = where to aim so a shot meets it, ai_aimDist.
; a shot covers about 2 pixels a frame, so it takes distance/2 frames to
; get there; by then the target has moved on by its velocity relative to
; ours (the shot inherits our velocity) times that.
;---------------------------------------------
ai_leadAim:
		bsr		ai_deltaTo
		bsr		ai_manhattan
		lsr.w	#1,d5				; frames to get there
		cmp.w	#ai_leadmax,d5
		bls.s	.tOk
		moveq	#ai_leadmax,d5
.tOk:
		move.w	obj_xvelo(a1),d6
		sub.w	obj_xvelo(a0),d6
		muls	d5,d6
		asr.l	#7,d6
		add.w	d6,d0
		move.w	obj_yvelo(a1),d6
		sub.w	obj_yvelo(a0),d6
		muls	d5,d6
		asr.l	#7,d6
		add.w	d6,d1
		bsr		ai_manhattan
		move.w	d5,ai_aimDist
		rts

;---------------------------------------------
; fire when a shot would pass within ai_hitslack of the lead point
;---------------------------------------------
ai_huntFire:
		tst.w	ai_fireWait
		bne.s	.no
		; no more than ai_maxshots in the air - like the arcade game, and
		; every shot is a collision test per letter per frame
		move.w	shot_con,d0
		move.w	d0,d2
		and.w	#$ff,d0
		moveq	#0,d1
		lea		bitCount,a1
		move.b	(a1,d0.w),d1		; low byte ...
		lsr.w	#8,d2
		add.b	(a1,d2.w),d1		; ... + high byte
		cmp.w	#ai_maxshots,d1
		bhs.s	.no
		tst.w	ai_holdFire			; the read pause
		bne.s	.no
		tst.b	ai_targetSolid		; still appearing - a shot would go through
		beq.s	.snap
		cmp.w	#ai_huntrange,ai_aimDist
		bhs.s	.snap
		move.l	ai_aimdot,d3
		ble.s	.snap				; behind us
		move.l	ai_aimcross,d4
		bpl.s	.pos
		neg.l	d4
.pos:
		cmp.l	#ai_hitslack<<15,d4	; cross >> 15 is the miss in pixels
		bhs.s	.snap

.fire:
		; a shot fired while backing away crawls and never arrives - see
		; ai_fire. 256 of its own plus our speed along the nose.
		move.w	obj_xvelo(a0),d0
		move.w	obj_yvelo(a0),d1
		bsr		ai_crossdot
		add.l	d3,d3
		swap	d3
		add.w	#256,d3
		cmp.w	#ai_minclose,d3
		blt.s	.no

		bsr		ai_shoot
		jsr		getRandomNumber
		and.w	#3,d0
		add.w	#ai_huntgap,d0
		move.w	d0,ai_fireWait
.no:
		rts

; --- not lined up on the target - but maybe on another letter. a player
;     takes that shot too. every ai_snapevery frames, it is not cheap.
.snap:
		tst.b	ai_phase			; not on a scan frame, see ai_pilot
		bne.s	.no
		subq.w	#2,ai_snapTick		; (counts every other frame)
		bpl.s	.no
		move.w	#ai_snapevery-1,ai_snapTick
		bsr.s	ai_snapScan
		tst.w	d0
		bne.s	.fire
		rts

;---------------------------------------------
; any shootable letter within ai_snaprange that a shot fired now would hit
; (within ai_hitslack of its lead point)? -> d0 non zero
; uses d0-d7/a1/a3
;---------------------------------------------
ai_snapScan:
		move.w	obj_angle(a0),d6	; the nose, once
		sub.w	#90,d6
		bpl.s	.aOk
		add.w	#360,d6
.aOk:
		lsl.w	#2,d6
		lea		sctab(pc),a3
		move.w	2(a3,d6.w),ai_fx
		move.w	(a3,d6.w),ai_fy
		lea		ai_list,a1			; vectors and velocities from ai_huntScan
		move.l	ai_listEnd(pc),a3
		bra.s	.test
.loop:
		movem.w	(a1)+,d0-d5			; dx, dy, bit, rx, ry, not solid
		tst.w	d5
		bne.s	.test
		AI_MANH
		cmp.w	#ai_snaprange,d5
		bhs.s	.test
		lsr.w	#1,d5				; a shot's time to get there, as in
		cmp.w	#ai_leadmax,d5		; ai_leadAim
		bls.s	.tOk
		moveq	#ai_leadmax,d5
.tOk:
		muls	d5,d3				; rx is velocity >> 3, so * t >> 4
		asr.l	#4,d3
		add.w	d3,d0
		muls	d5,d4
		asr.l	#4,d4
		add.w	d4,d1
		move.w	ai_fx(pc),d3		; dot
		muls	d0,d3
		move.w	ai_fy(pc),d4
		muls	d1,d4
		add.l	d4,d3
		ble.s	.test				; behind us
		move.w	ai_fx(pc),d4		; cross
		muls	d1,d4
		move.w	ai_fy(pc),d5
		muls	d0,d5
		sub.l	d5,d4
		bpl.s	.cPos
		neg.l	d4
.cPos:
		cmp.l	#ai_hitslack<<15,d4
		bhs.s	.test
		moveq	#1,d0
		rts
.test:
		cmp.l	a3,a1
		blo.s	.loop
		moveq	#0,d0
		rts

ai_fx:			dc.w	0
ai_fy:			dc.w	0
ai_snapTick:	dc.w	0
ai_shx:			dc.w	0		; the ship for ai_huntScan, y signed
ai_shy:			dc.w	0
ai_shvx:		dc.w	0
ai_shvy:		dc.w	0
ai_rawx:		dc.w	0		; ai_huntScan: vector before the wrap
ai_rawy:		dc.w	0
ai_listEnd:		dc.l	ai_list
ai_cand:		ds.w	4*8		; ai_pickStation: x, y, distance, spare
; every live letter, rebuilt by ai_huntScan each frame: vector from the
; ship, enemy_con bit, velocity relative to the ship >> 3, and 0 if it can
; be shot
ai_le			= 6*2		; bytes per entry
ai_list:		ds.b	ai_le*32

ai_threat:		dc.w	-1		; see ai_huntScan
ai_threatDist:	dc.w	0
ai_threatNow:	dc.w	0
ai_curDist:		dc.w	0
ai_aimDist:		dc.w	0
ai_speedNow:	dc.w	0
ai_threatPx:	dc.w	0
ai_threatPy:	dc.w	0
ai_threatRx:	dc.w	0
ai_threatRy:	dc.w	0
ai_vdx:			dc.w	0		; the velocity we want
ai_vdy:			dc.w	0
ai_stx:			dc.w	0		; vector to the station
ai_sty:			dc.w	0
ai_tdx:			dc.w	0		; vector to the target
ai_tdy:			dc.w	0
ai_tvx:			dc.w	0		; the target's velocity
ai_tvy:			dc.w	0
ai_offIdx:		dc.w	0		; chosen ai_offsets entry, byte offset
ai_offTarget:	dc.w	-1		; target it was chosen for
ai_offTick:		dc.w	0
ai_modeTick:	dc.w	0
ai_aimHold:		dc.w	0
ai_braking:		dc.b	0
ai_threatSolid:	dc.b	0
ai_targetSolid:	dc.b	0
ai_evading:		dc.b	0
ai_mode:		dc.b	0		; 0 aim and shoot, else correcting the velocity
ai_phase:		dc.b	0		; flips every frame, see ai_pilot
ai_home:		dc.b	0		; no word, and the ship is out of its way
ai_clear:		dc.b	0		; ... at least out of the row band
ai_wayTop:		dc.b	0		; next waypoint in the top half?
ai_hadWord:		dc.b	0		; a word was up last time we patrolled
ai_engaged:		dc.b	0		; target in range, shooting from where we are
ai_turnDir:		dc.b	0		; 0 = turning by adding to the angle
				even
ai_turnAcc:		dc.w	0		; degrees turned the same way, this turn
ai_busyTime:	dc.w	0		; frames in front of the logo or the scroller
ai_rush:		dc.w	0		; frames of attack rush left, see ai_pilot
ai_rushIdx:		dc.w	-1		; its way in (ai_rushStart)
ai_styleSet:	dc.b	0		; ai_rushStart done for the word now up
				even
				even
ai_wayx:		dc.w	192		; patrol waypoint
ai_wayy:		dc.w	200
ai_wayTick:		dc.w	0
				even

;---------------------------------------------
; The letter at whichever end of the word we are attacking from. Picking
; the end rather than the nearest means they die in order along the row.
;
; The answer only changes when a letter dies, when one finishes arriving,
; or when we swap ends - perhaps a dozen times a word. Walking all 32
; slots to rediscover it every frame costs about 2000 cycles, four and a
; half raster lines; checking that the one we already have is still good
; costs about 210. So keep it and revalidate.
;---------------------------------------------
ai_pickEdge:
		tst.b	ai_forming			; letters still arriving - the end one can
		bne.s	.rescan				; change under us
		move.w	ai_target,d7
		bmi.s	.rescan
		move.w	ai_side,d6
		cmp.w	ai_edgeSide,d6		; swapped ends since we picked?
		bne.s	.rescan
		move.l	enemy_con(pc),d6
		btst	d7,d6
		beq.s	.rescan				; gone entirely
		bsr		ai_ptr
		tst.w	obj_appear(a1)
		bne.s	.rescan
		tst.w	obj_flag(a1)
		bne.s	.rescan
		rts						; still the right letter

.rescan:
		move.w	ai_side,d6
		move.w	d6,ai_edgeSide
		moveq	#-1,d3
		move.l	enemy_con(pc),d4
		beq		.store
		lea		enemy_structs(pc),a1
		moveq	#31,d7
		move.w	#$7fff,d5			; looking for the smallest x ...
		tst.w	d6
		bmi.s	.leftLoop
		move.w	#$8000,d5			; ... or the largest

; --- two loops rather than one, so the side test is not repeated inside
;     it. That was another 26 cycles per live letter.
.rightLoop:
		btst	d7,d4
		beq.s	.rnext
		tst.w	obj_appear(a1)		; not solid yet
		bne.s	.rnext
		tst.w	obj_flag(a1)		; already hit
		bne.s	.rnext
		move.w	obj_xc(a1),d0
		cmp.w	d5,d0
		ble.s	.rnext
		move.w	d0,d5
		move.w	d7,d3
.rnext:
		lea		obj_len(a1),a1
		dbf		d7,.rightLoop
		bra.s	.store

.leftLoop:
		btst	d7,d4
		beq.s	.lnext
		tst.w	obj_appear(a1)
		bne.s	.lnext
		tst.w	obj_flag(a1)
		bne.s	.lnext
		move.w	obj_xc(a1),d0
		cmp.w	d5,d0
		bge.s	.lnext
		move.w	d0,d5
		move.w	d7,d3
.lnext:
		lea		obj_len(a1),a1
		dbf		d7,.leftLoop
.store:
		move.w	d3,ai_target
		rts

;---------------------------------------------
; ATTACK - aim, one shove, then ride through the word shooting.
;---------------------------------------------
ai_attack:
		move.w	ai_target,d7
		bmi		.wordCleared

		addq.w	#1,ai_attackTick	; a pass that is going nowhere is better
		cmp.w	#ai_attackmax,ai_attackTick	; restarted from the hover point
		bhs		.giveUp

		bsr		ai_ptr
		move.w	obj_xc(a1),d0
		move.w	d0,ai_hx			; debug X sits here
		move.w	obj_xc(a0),d4
		bsr		ai_signedCoord
		sub.w	d4,d0
		move.w	obj_yc(a1),d1
		move.w	d1,ai_hy
		move.w	obj_yc(a0),d4
		bsr		ai_signedCoord
		sub.w	d4,d1

		bsr		ai_crossdot
		move.l	d2,ai_aimcross
		move.l	d3,ai_aimdot

		cmp.b	#HS_BURN,ai_hstate
		beq.s	.aburn
		cmp.b	#HS_COAST,ai_hstate
		beq.s	.arun

; --------------- AIM ---------------
		bsr		ai_turn
		bsr		ai_aligned
		tst.w	d0
		beq.s	.afire
		move.b	#HS_BURN,ai_hstate
		move.w	#ai_attackburn,d4	; one big shove to launch the run,
		tst.b	ai_launched			; nudges after that
		beq.s	.firstShove
		move.w	#ai_attackfix,d4
.firstShove:
		st		ai_launched
		move.w	d4,ai_burnLeft
		bra.s	.afire

; --------------- BURN ---------------
.aburn:
		moveq	#ai_thrust,d2
		bsr		obj_thrust
		subq.w	#1,ai_burnLeft
		bgt.s	.afire
		move.b	#HS_COAST,ai_hstate
		move.w	#ai_attackregrip,ai_regripTick
		bra.s	.afire

; --------------- RUN ---------------
; Hold the nose still and shoot. A player does not steer all the way down
; a row of rocks, so the aim is only re-checked every ai_attackregrip
; frames, and only a big error is worth turning for.
.arun:
		subq.w	#1,ai_regripTick
		bgt.s	.afire
		move.w	#ai_attackregrip,ai_regripTick
		move.l	ai_aimdot,d3
		ble.s	.regrip				; it is behind us now
		move.l	ai_aimcross,d4
		bpl.s	.apos
		neg.l	d4
.apos:
		add.l	d4,d4
		add.l	d4,d4				; |cross| * 4, about 14 degrees
		cmp.l	d3,d4
		blt.s	.afire				; near enough, carry on
.regrip:
		move.b	#HS_ROTATE,ai_hstate
		st		ai_turning
.afire:
		bsr		ai_attackFire
		rts

; --- nothing left to shoot: settle on the far side and wait for the
;     next word. The side flips because we have just flown across.
.wordCleared:
		move.b	#AS_HOVER,ai_astate
		move.w	ai_side,d0
		neg.w	d0
		move.w	d0,ai_side
		st		ai_sidePicked
		bra.s	.backToHover

; --- the pass ran out of time. Set up again from whichever side we are
;     nearer now, rather than flying back across the word.
.giveUp:
		move.b	#AS_HOVER,ai_astate
		moveq	#-1,d0
		cmp.w	#ast_x_center,obj_xc(a0)
		blt.s	.gaSide
		moveq	#1,d0
.gaSide:
		move.w	d0,ai_side
		st		ai_sidePicked
.backToHover:
		move.b	#HS_ROTATE,ai_hstate
		st		ai_turning
		clr.w	ai_settleTick
		rts

;---------------------------------------------
ai_attackFire:
		tst.w	ai_fireWait
		bne.s	.nofire
		move.l	ai_aimdot,d3
		ble.s	.nofire
		move.l	ai_aimcross,d4
		bpl.s	.fpos
		neg.l	d4
.fpos:
		add.l	d4,d4
		add.l	d4,d4				; |cross|*4, about 14 degrees
		cmp.l	d3,d4
		bge.s	.nofire

		tst.w	ai_burst
		bne.s	.shootIt
		jsr		getRandomNumber
		and.w	#ai_burstvar,d0
		add.w	#ai_burstlen,d0
		move.w	d0,ai_burst
.shootIt:
		subq.w	#1,ai_burst
		bsr		ai_shoot
		tst.w	ai_burst
		beq.s	.pause
		jsr		getRandomNumber
		and.w	#ai_gapvar,d0
		add.w	#ai_burstgap,d0
		move.w	d0,ai_fireWait
		rts
.pause:
		jsr		getRandomNumber
		and.w	#31,d0
		add.w	#ai_burstpause,d0
		move.w	d0,ai_fireWait
.nofire:
		rts

;---------------------------------------------
; obj_move keeps its position as a fixed point value and shifts it right
; with lsr - UNSIGNED. So an object that has drifted just above or just
; left of the play area does not report a small negative coordinate, it
; reports 496..511. Anything in that range is really -16..-1.
;
; Left uncorrected the vector to the hover point comes out around -480,
; ai_wrap (which only corrects by one period) turns that into -346, and
; the ship sits there pointing at a target that is nowhere near where the
; maths thinks it is - facing it, and never arriving.
;
; in/out: d4
;---------------------------------------------
ai_signedCoord:
		cmp.w	#480,d4				; no real coordinate ever reaches this
		blo.s	.positive
		sub.w	#512,d4
.positive:
		rts

;---------------------------------------------
; HOVER - the whole autopilot, for now.
; a0 must already point at ship_struct.
;---------------------------------------------
ai_hover:
		; --- which side? whichever half of the screen we are in, decided
		;     once and then left alone so the ship does not change its mind
		;     half way across.
		tst.b	ai_sidePicked
		bne.s	.gotSide
		st		ai_sidePicked
		moveq	#-1,d0
		cmp.w	#ast_x_center,obj_xc(a0)
		blt.s	.sideSet
		moveq	#1,d0
.sideSet:
		move.w	d0,ai_side
.gotSide:

		; --- vector to the hover point. The absolute position is kept too,
		;     because ai_wrap returns the SHORTEST way round the screen and
		;     ship+delta can then land outside the buffer entirely - which is
		;     why the debug marker kept vanishing.
		move.w	#ai_hoverleft,d0
		tst.w	ai_side
		bmi.s	.gotX
		move.w	#ai_hoverright,d0
.gotX:
		move.w	d0,ai_hx
		move.w	obj_xc(a0),d4
		bsr		ai_signedCoord
		sub.w	d4,d0
		move.w	#ai_hovery,d1
		move.w	d1,ai_hy
		move.w	obj_yc(a0),d4
		bsr		ai_signedCoord
		sub.w	d4,d1
		IFNE	ai_hoverwrap
		bsr		ai_wrap
		ENDC

		move.w	d0,ai_sdx			; kept so the debug + lands on it
		move.w	d1,ai_sdy

		move.w	d0,d4				; and the manhattan distance, which every
		bpl.s	.dx					; phase below needs
		neg.w	d4
.dx:
		move.w	d1,d5
		bpl.s	.dy
		neg.w	d5
.dy:
		add.w	d5,d4
		move.w	d4,ai_hdist

		; d0/d1 now hold the true vector to the hover point, and stay that
		; way - only the ROTATE phase below works on a modified copy.
		cmp.b	#HS_BURN,ai_hstate
		beq.s	.burning
		cmp.b	#HS_COAST,ai_hstate
		beq.s	.coasting

; --------------- ROTATE ---------------
		move.w	obj_xvelo(a0),d4	; aim at the point minus our own drift
		muls	#ai_hoverlead,d4
		asr.l	#7,d4				; velocity is 1/128 pixel per frame
		sub.w	d4,d0
		move.w	obj_yvelo(a0),d4
		muls	#ai_hoverlead,d4
		asr.l	#7,d4
		sub.w	d4,d1

		bsr		ai_crossdot
		move.l	d2,ai_aimcross
		move.l	d3,ai_aimdot
		bsr		ai_turn

		bsr		ai_aligned			; nose finally settled?
		tst.w	d0
		beq.s	.hdone
		move.b	#HS_BURN,ai_hstate

		move.w	ai_hdist,d4			; shove in proportion to how far it is
		lsr.w	#ai_hoverburnshift,d4
		cmp.w	#ai_hoverburnmin,d4
		bhs.s	.notTooShort
		move.w	#ai_hoverburnmin,d4
.notTooShort:
		cmp.w	#ai_hoverburnmax,d4
		bls.s	.notTooLong
		move.w	#ai_hoverburnmax,d4
.notTooLong:
		move.w	d4,ai_burnLeft
.hdone:
		rts

; --------------- BURN ---------------
; A fixed shove with the nose held still. Nothing is re-aimed here, which
; is the whole point - a thrust vector that rotates draws a circle.
.burning:
		moveq	#ai_thrust,d2
		bsr		obj_thrust
		subq.w	#1,ai_burnLeft
		bgt.s	.hdone2
		move.b	#HS_COAST,ai_hstate
		clr.w	ai_coastTick
.hdone2:
		rts

; --------------- COAST ---------------
; Drift until we are near the point, or until we have sailed past it.
; "Past it" is the dot product of the vector to the point with our own
; velocity going negative - the moment we stop closing.
.coasting:
		addq.w	#1,ai_coastTick		; do not drift for ever if the closing
		cmp.w	#ai_hovercoastmax,ai_coastTick	; test never trips
		bhs.s	.hagain
		cmp.w	#ai_hoverdead,ai_hdist
		blo.s	.hagain				; close enough

		; --- how many frames until we get there at this speed? if it is
		;     fewer than ai_hoverbrake, start turning round now.
		move.w	obj_xvelo(a0),d5
		bpl.s	.bvx
		neg.w	d5
.bvx:
		move.w	obj_yvelo(a0),d6
		bpl.s	.bvy
		neg.w	d6
.bvy:
		add.w	d6,d5
		beq.s	.notClosing			; not moving, no arrival to anticipate
		muls	#ai_hoverbrake,d5
		move.w	ai_hdist,d4
		ext.l	d4
		lsl.l	#7,d4				; into the same 1/128 pixel units
		cmp.l	d5,d4
		blt.s	.hagain
.notClosing:

		move.w	d0,d4
		muls	obj_xvelo(a0),d4
		move.w	d1,d5
		muls	obj_yvelo(a0),d5
		add.l	d5,d4
		bgt.s	.hdone3				; still closing - keep drifting
.hagain:
		move.b	#HS_ROTATE,ai_hstate
		st		ai_turning			; make the next turn start from scratch
.hdone3:
		rts
		ENDC

;---------------------------------------------
; Where we want to be: level with the target letter, ai_stationdx to the
; side of it. Also works out whether we have sailed past it, which is the
; other reason to stop flying and start shooting.
;---------------------------------------------
ai_station:
		sf		ai_over
		move.w	#$7fff,ai_sdist
		move.w	ai_target,d7
		bmi		.none

		tst.b	ai_forming
		beq.s	.letterStation

		; --- A word is still arriving. Sitting among letters that are about
		;     to materialise looks wrong - the ship is flying through solid
		;     objects and visibly not dying. So go and wait at the edge of
		;     the play box on our side until the word has finished, then
		;     come in from outside.
		move.w	#ai_boxx0,d0
		tst.w	ai_side
		bmi.s	.gotSafe
		move.w	#ai_boxx1,d0
.gotSafe:
		sub.w	obj_xc(a0),d0
		move.w	#ast_y_start,d1		; level with the row, ready to attack
		sub.w	obj_yc(a0),d1
		bsr		ai_wrap
		move.w	d0,ai_sdx
		move.w	d1,ai_sdy
		bra.s	.measure

.letterStation:
		bsr		ai_ptr
		move.w	#ai_stationdx,d6
		tst.w	ai_side
		bpl.s	.offPos
		neg.w	d6
.offPos:
		move.w	obj_xc(a1),d0
		add.w	d6,d0
		sub.w	obj_xc(a0),d0
		move.w	obj_yc(a1),d1
		add.w	#ai_stationdy,d1
		sub.w	obj_yc(a0),d1
		bsr		ai_wrap
		move.w	d0,ai_sdx
		move.w	d1,ai_sdy

		; overshot? on the way in the station is ahead of us, so ai_sdx has
		; the opposite sign to ai_side. once we are past it they match.
		muls	ai_side,d0
		ble.s	.measure
		st		ai_over
.measure:
		move.w	ai_sdx,d0
		bpl.s	.ax
		neg.w	d0
.ax:
		move.w	ai_sdy,d1
		bpl.s	.ay
		neg.w	d1
.ay:
		add.w	d1,d0
		move.w	d0,ai_sdist
.none:
		rts

;---------------------------------------------
; APPROACH -> ARRIVE -> ATTACK -> APPROACH
;---------------------------------------------
ai_states:
		move.w	obj_xvelo(a0),d0	; how fast are we going?
		bpl.s	.sx
		neg.w	d0
.sx:
		move.w	obj_yvelo(a0),d1
		bpl.s	.sy
		neg.w	d1
.sy:
		add.w	d1,d0

		tst.w	ai_target
		bmi.s	.toApproach			; nothing to aim at - just fly

		cmp.b	#ST_ARRIVE,ai_state
		beq.s	.inArrive
		cmp.b	#ST_ATTACK,ai_state
		beq.s	.inAttack

.inApproach:
		tst.b	ai_over				; sailed past the station?
		bne.s	.settle
		cmp.w	#ai_arrivedist,ai_sdist
		bhs.s	.done				; still a way to go
.settle:
		cmp.w	#ai_arrivespeed,d0
		bhi.s	.toArrive			; too quick to stop here - brake first
		bra.s	.toAttack

.inArrive:
		cmp.w	#ai_arrivespeed,d0
		bhi.s	.done				; still shedding speed
		bra.s	.toAttack

.inAttack:
		cmp.w	#ai_leavedist,ai_sdist
		bls.s	.done				; near enough - stay put and shoot
		moveq	#-1,d1				; drifted off. go round again, from
		cmp.w	#ast_x_center,obj_xc(a0)	; whichever end we are nearer now
		blt.s	.sideSet
		moveq	#1,d1
.sideSet:
		move.w	d1,ai_side
.toApproach:
		move.b	#ST_APPROACH,ai_state
		rts
.toArrive:
		move.b	#ST_ARRIVE,ai_state
		rts
.toAttack:
		move.b	#ST_ATTACK,ai_state
.done:
		rts

;---------------------------------------------
; project the ship ai_lookahead frames along its current velocity and set
; ai_recover if that would put it outside the box.
;---------------------------------------------
ai_checkBox:
		sf		ai_recover
		IFEQ	ai_keepbox
		rts
		ENDC
		move.w	obj_xvelo(a0),d1
		muls	#ai_lookahead,d1
		asr.l	#7,d1				; velocity is 1/128 pixel per frame
		add.w	obj_xc(a0),d1
		cmp.w	#ai_boxx0,d1
		blt.s	.out
		cmp.w	#ai_boxx1,d1
		bgt.s	.out
		move.w	obj_yvelo(a0),d1
		muls	#ai_lookahead,d1
		asr.l	#7,d1
		add.w	obj_yc(a0),d1
		cmp.w	#ai_boxy0,d1
		blt.s	.out
		cmp.w	#ai_boxy1,d1
		ble.s	.in
.out:
		st		ai_recover
.in:
		rts

;---------------------------------------------
; d7 = bit number -> a1 = enemy struct (bit 31 is struct 0)
;---------------------------------------------
ai_ptr:
		lea		enemy_structs(pc),a1
		moveq	#31,d6
		sub.w	d7,d6
		mulu	#obj_len,d6
		add.l	d6,a1
		rts

;---------------------------------------------
; d7 = bit number -> d0 non zero if still a valid target, a1 = struct
;---------------------------------------------
ai_valid:
		moveq	#0,d0
		move.l	enemy_con(pc),d6
		btst	d7,d6
		beq.s	.bad
		bsr.s	ai_ptr
		; a letter still zooming in counts as a target for POSITIONING - it
		; cannot be shot because the read pause is held up the whole time a
		; word is arriving, and shot_collision ignores it anyway.
		tst.w	obj_flag(a1)
		bne.s	.bad
		moveq	#1,d0
.bad:
		rts

;---------------------------------------------
; d0/d1 -> shortest delta the wrapped play area allows, so the ship will
; happily shoot across the border rather than fly the long way round
;---------------------------------------------
ai_wrap:
		cmp.w	#ai_wrapx/2,d0
		ble.s	.x1
		sub.w	#ai_wrapx,d0
.x1:
		cmp.w	#-ai_wrapx/2,d0
		bge.s	.x2
		add.w	#ai_wrapx,d0
.x2:
		cmp.w	#ai_wrapy/2,d1
		ble.s	.y1
		sub.w	#ai_wrapy,d1
.y1:
		cmp.w	#-ai_wrapy/2,d1
		bge.s	.y2
		add.w	#ai_wrapy,d1
.y2:
		rts

;---------------------------------------------
; in:  a0 = ship, d0 = dx, d1 = dy
; out: d2 = cross (long), d3 = dot (long)
;---------------------------------------------
ai_crossdot:
		move.w	obj_angle(a0),d6
		sub.w	#90,d6
		bpl.s	.ok
		add.w	#360,d6
.ok:
		lsl.w	#2,d6
		lea		sctab(pc),a3
		move.w	2(a3,d6.w),d4		; fx = cos(angle-90)
		move.w	(a3,d6.w),d5		; fy = sin(angle-90)

		move.w	d4,d2
		muls	d1,d2				; fx*dy
		move.w	d5,d6
		muls	d0,d6				; fy*dx
		sub.l	d6,d2				; cross

		move.w	d4,d3
		muls	d0,d3				; fx*dx
		move.w	d5,d6
		muls	d1,d6				; fy*dy
		add.l	d6,d3				; dot
		rts

;---------------------------------------------
; Are we lined up on what we are steering at closely enough to burn?
; -> d0 non zero if so. Uses d3/d4, leaves d2 alone for obj_thrust.
;---------------------------------------------
ai_aligned:
		moveq	#0,d0
		tst.b	ai_turning			; still swinging the nose round?
		bne.s	.no
		moveq	#1,d0
.no:
		rts

;---------------------------------------------
; in: d2 = cross, d3 = dot. turn towards it, with a deadzone so the ship
; does not jitter once it is lined up.
;---------------------------------------------
ai_turn:
		move.l	d2,d4
		bpl.s	.pos
		neg.l	d4					; d4 = |cross|
.pos:
		tst.l	d3
		ble.s	.turn				; behind us - always turn

		tst.b	ai_turning
		beq.s	.wasStill

		; --- turning: stop once inside the narrow cone (x8, about 7 deg)
		move.l	d4,d5
		add.l	d5,d5
		add.l	d5,d5
		add.l	d5,d5
		cmp.l	d3,d5
		bge.s	.turn				; not there yet
		sf		ai_turning			; lined up - hold the nose still
		rts

.wasStill:
		; --- lined up: only start again once outside the wider cone
		;     (x6, about 9.5 deg). The gap between the two is the deadband
		;     that stops the left-right jitter.
		move.l	d4,d5
		add.l	d5,d5
		move.l	d5,d6
		add.l	d5,d5
		add.l	d6,d5
		cmp.l	d3,d5
		blt.s	.done				; near enough - stay put

.turn:
		moveq	#ai_turnrate,d1
		bra		ai_turnBy
.done:
		rts

;---------------------------------------------
; fire when lined up on the TARGET (not on whatever we are steering
; towards), with a random cooldown so it does not machine gun
;---------------------------------------------
ai_fire:
		tst.w	ai_fireWait
		bne.w	.no

		IFNE	ai_pbholdfire
		tst.w	ai_holdFire			; the read pause silences everything,
		bne.w	.no					; point blank included
		ENDC

		; --- A shot inherits our velocity, so one fired while we are backing
		;     away crawls and never arrives. 256 of its own speed plus
		;     however much of ours points along the nose. This guards EVERY
		;     shot, point blank and mid burst included, because "flying into
		;     a letter" means closing on it, not drifting away from it.
		move.w	obj_xvelo(a0),d0
		move.w	obj_yvelo(a0),d1
		bsr		ai_crossdot			; d3 = our speed along the nose, Q15
		add.l	d3,d3
		swap	d3
		ext.l	d3					; -> 1/128 pixel units
		add.w	#256,d3				; the shot's own muzzle speed
		cmp.w	#ai_minclose,d3
		blt.w	.no					; would never catch up - hold fire

		; --- a letter right on top of us skips the fussy aiming tests, but
		;     it had to pass the two above to get here
		bsr		ai_pointblankNear
		tst.w	d0
		bne.w	.takeIt

		IFEQ	ai_pbholdfire
		tst.w	ai_holdFire			; pause only stops the ordinary shots
		bne.w	.no
		ENDC

		move.w	ai_target,d0
		bmi.w	.no					; nothing to shoot at
		cmp.b	#ST_ATTACK,ai_state	; only once we have arrived and settled
		bne.w	.no

		; once a burst is running the rest of it goes off regardless of aim.
		; the ship is still turning and drifting, so the tail of the burst
		; sprays and picks off whatever wanders into it
		tst.w	ai_burst
		bne.s	.takeIt
		move.l	ai_dot,d3
		bmi.w	.no					; target behind us
		move.l	ai_cross,d4
		bpl.s	.pos
		neg.l	d4
.pos:
		add.l	d4,d4
		add.l	d4,d4				; |cross|*4 vs dot -> about 14 degrees
		cmp.l	d3,d4
		bge.w	.no

		tst.b	ai_sidemode			; only side attacks care about the angle
		beq.s	.takeIt
		; hold out for a shot along the row, but not for ever
		cmp.w	#ai_patience,ai_dry
		bge.s	.takeIt
		move.w	ai_dy,d0
		bpl.s	.fy
		neg.w	d0
.fy:
		muls	#ai_fireflat,d0
		move.w	ai_dx,d1
		bpl.s	.fx
		neg.w	d1
.fx:
		ext.l	d1
		cmp.l	d1,d0
		bge.w	.no					; too steep, wait for a better angle
.takeIt:
		clr.w	ai_dry
		tst.w	ai_burst
		bne.s	.inBurst
		jsr		getRandomNumber		; start a new burst, 2..4 shots
		and.w	#ai_burstvar,d0
		add.w	#ai_burstlen,d0
		move.w	d0,ai_burst
.inBurst:
		subq.w	#1,ai_burst
		bsr		ai_shoot
		tst.w	ai_burst
		beq.s	.burstOver
		jsr		getRandomNumber		; 4..7 frames to the next one
		and.w	#ai_gapvar,d0
		add.w	#ai_burstgap,d0
		move.w	d0,ai_fireWait
		rts
.burstOver:
		jsr		getRandomNumber
		and.w	#31,d0
		add.w	#ai_burstpause,d0
		move.w	d0,ai_fireWait
.no:
		rts

;---------------------------------------------
; is ANY live letter within ai_pointblank of us? -> d0 non zero.
; checks every letter, not just the current target, because the one we
; happen to be flying through is often not the one we are aiming at.
; the wrap is folded into the compares instead of calling ai_wrap, and it
; stops at the first hit, so it usually costs far less than the full 32.
;---------------------------------------------
ai_pointblankNear:
		moveq	#0,d5
		move.l	enemy_con(pc),d4
		beq.s	.done
		lea		enemy_structs(pc),a1
		moveq	#31,d7
.loop:
		btst	d7,d4
		beq.s	.next
		tst.w	obj_appear(a1)		; not solid yet
		bne.s	.next
		tst.w	obj_flag(a1)		; already blowing up
		bne.s	.next

		move.w	obj_xc(a1),d0
		sub.w	obj_xc(a0),d0
		bpl.s	.ax
		neg.w	d0
.ax:
		cmp.w	#ai_pointblank,d0
		blt.s	.xok
		cmp.w	#ai_wrapx-ai_pointblank,d0
		blt.s	.next				; too far even going round the border
		sub.w	#ai_wrapx,d0		; wrapped - take the short way
		neg.w	d0
.xok:
		move.w	obj_yc(a1),d1
		sub.w	obj_yc(a0),d1
		bpl.s	.ay
		neg.w	d1
.ay:
		cmp.w	#ai_pointblank,d1
		blt.s	.yok
		cmp.w	#ai_wrapy-ai_pointblank,d1
		blt.s	.next
		sub.w	#ai_wrapy,d1
		neg.w	d1
.yok:
		add.w	d1,d0
		cmp.w	#ai_pointblank,d0
		bge.s	.next
		moveq	#1,d5				; got one - stop looking
		bra.s	.done
.next:
		lea		obj_len(a1),a1
		dbf		d7,.loop
.done:
		move.w	d5,d0
		rts

;---------------------------------------------
; same shot setup the keyboard fire path uses
;---------------------------------------------
ai_shoot:
		move.w	obj_xc(a0),d0
		move.w	obj_yc(a0),d1
		move.w	obj_angle(a0),d2
		sub.w	#90,d2
		bpl.s	.ok
		add.w	#360,d2
.ok:
		lsl.w	#2,d2
		lea		sctab(pc),a3
		move.w	#256,d3
		muls	2(a3,d2.w),d3
		lsl.l	#1,d3
		swap	d3
		move.w	#256,d4
		muls	(a3,d2.w),d4
		lsl.l	#1,d4
		swap	d4
		add.w	obj_xvelo(a0),d3
		add.w	obj_yvelo(a0),d4
		bsr		shot_init
		rts

;---------------------------------------------
; thrust bursts, coasting and counter-thrust braking
;---------------------------------------------
ai_move:
		tst.b	ai_recover
		beq.s	.notRecover
		; getting back on screen beats everything, but still only burn once
		; the nose has come round - otherwise the thrust sweeps in an arc
		bsr		ai_aligned
		tst.w	d0
		beq.s	.nothing
		moveq	#ai_thrust,d2
		bsr		obj_thrust
.nothing:
		rts

.notRecover:
		cmp.b	#ST_ARRIVE,ai_state
		bne.s	.notArrive
		; wait for the nose to come round to face backwards, then burn. This
		; used to thrust unconditionally, which meant ~45 frames of thrust
		; sweeping through every direction while it turned - a neat circle.
		bsr		ai_aligned
		tst.w	d0
		beq.s	.noBrake
		moveq	#ai_thrust,d2
		bsr		obj_thrust
.noBrake:
		rts

.notArrive:
		tst.w	ai_thrustLeft		; part way through a burn?
		beq.s	.notThrusting
		subq.w	#1,ai_thrustLeft
		moveq	#ai_thrust,d2
		bsr		obj_thrust
		rts
.notThrusting:
		tst.w	ai_coastLeft
		beq.s	.decide
		subq.w	#1,ai_coastLeft
		rts

.decide:
		cmp.b	#ST_APPROACH,ai_state
		bne.s	.attackBurn

		; --- flying to the station. Only burn when the nose is actually
		;     pointing at it; burning part way through the turn just shoves
		;     us sideways, which is what made the ship circle it. Short
		;     bursts, because a long one overshoots.
		bsr		ai_aligned			; lined up on the station yet?
		tst.w	d0
		beq.s	.stillTurning		; no - wait, and do NOT book a coast on
									; top of it. Falling through to .coast here
									; armed 8..39 idle frames every frame the
									; nose was still coming round, so the ship
									; finished its turn and then sat doing
									; nothing for most of a second.
		move.w	#ai_travelodds,d2
		moveq	#ai_travelburst,d3
		moveq	#1,d4
		bra.s	.odds

.attackBurn:
		; --- settled in and shooting. With ai_thrustodds at 0 this never
		;     burns at all, which is the point: hold the spot, let the shots
		;     do the work, and only move again when the state machine drops
		;     back to APPROACH.
		move.w	#ai_thrustodds,d2
		move.l	ai_dot,d1
		bmi.s	.attackLen			; nose away from it - safe to burn
		move.w	ai_dx,d0			; never burn straight at a close letter
		bpl.s	.kx
		neg.w	d0
.kx:
		move.w	ai_dy,d1
		bpl.s	.ky
		neg.w	d1
.ky:
		add.w	d1,d0
		cmp.w	#ai_keepaway,d0
		blt.s	.coast
.attackLen:
		moveq	#ai_thrustbase,d3
		moveq	#7,d4

.odds:
		jsr		getRandomNumber
		and.w	#255,d0
		cmp.w	d2,d0
		bcc.s	.coast
		jsr		getRandomNumber
		and.w	d4,d0
		add.w	d3,d0
		move.w	d0,ai_thrustLeft
		rts
.coast:
		jsr		getRandomNumber
		and.w	#31,d0
		add.w	#ai_coastbase,d0
		move.w	d0,ai_coastLeft
.stillTurning:
		rts

;======================================================================
; LOGO DESTRUCTION - the ship's side
;======================================================================
; once every name has been up (namesLooped) no new word comes, and the
; ship takes it badly:
;   SEARCH   it flies round from spot to spot looking for more, a look
;            left and right at each one
;   SPIN     gives up, a bored pirouette
;   A1MOVE   up over the bar, on the left
;   A1SHOOT  three aimed shots down at the running text, three letters
;            gone - and the scroller breaks (startGlitch in scroller.s:
;            a pause, glitch salad, stutter, the captain's message)
;   REPOS    dives under the bar and comes up again on the left, then
;            hangs about there, never quite still, until the message comes
;   SNIPE    shoots the message away before it reaches the twist, in a
;            run along the bar from left to right (seq_runAlong): over or
;            under it, aim with lead, a single shot or a short burst, a
;            letter each
;   CLEAN    waits, hovering, until what is left of the text has gone
;   LEAVE    out of the bar, and HOLD: nose up, then the TV switch off
seq_arrive		= 10		; px (manhattan) that count as "there"
seq_arrivev		= 24		; ... at under this speed
seq_corrstart	= 32		; velocity off by more than this: correct it ...
seq_corrstop	= 10		; ... until it is off by less than this
seq_wobx		= 14		; hovering: the spot it holds swings this far
seq_woby		= 8			; ... sideways and up and down
seq_wobstep		= 5			; degrees a frame, 72 frames a swing
seq_textY		= 184		; game y of the bottom text row (scroller.s
							; topLines + rightLine + 3)
seq_waypoints	= 3			; spots it searches
seq_searchv		= 150		; fastest it flies while searching
seq_lookrate	= 5			; degrees a frame, looking round
seq_spinrate	= 4			; the pirouette: 360/4 = 90 frames
seq_a1x			= 96		; first attack from here: over the bar, left
seq_a1y			= 132
seq_a1gap		= 12		; frames between the shots (5..8 of them)
seq_a1from		= 216		; letters from here ...
seq_a1to		= 334		; ... to here are shot at
seq_a1v			= 64		; edging about between shots, 1/128 px a frame
seq_a1watch		= 110		; frames after the last shot at most till the
							; scroller breaks (it breaks as the last one hits)
seq_roamv		= 120		; looking round while the scroller is mended
seq_facerate	= 4			; degrees a frame, turning the nose round
seq_rowY		= 183		; the bottom text row: game y 181..185 is
seq_wave		= 2			; scroller line 71..75 (the blast hits on 9)
seq_wavestep	= 4			; degrees a frame
; the attack (seq_run), speeds in 1/128 px a frame
seq_lapY		= 40		; the run up: this high over the screen ...
seq_lapv		= 300		; ... at this speed, or paced between these two
seq_lapvmin		= 160		; so it comes round just as the first letter
seq_lapvmax		= 448		; is at seq_lapfront
seq_wrapX		= 368		; (where it goes round: obj_move's wrap_x1)
seq_lapfront	= 340		; the lap is paced to have the ship on the left as
seq_appfront	= 385		; the first letter is here; down it goes from
							; there once the letter is in this far
seq_appx		= 60		; (at about here, x up to seq_appmaxx): down it
seq_appmaxx		= 110		; goes
seq_appv		= 384		; the approach: speed, and the point on the row
seq_lead		= 40		; it steers at, this far ahead - a steep dive first,
							; levelling out onto the row
seq_flyacc		= 11		; how hard it changes its velocity, a frame
seq_flymin		= 112		; never slower than this (1/128 px a frame)
seq_fireX		= 206		; the blast meets the first letter here, just
							; before the twist (scroller.s stutterHoldX 190)
seq_closest		= 64		; letters this close: fire at once
seq_torpclose	= 10		; px a frame blast and letter close at (7 + the
							; ship's 2 + the text's 1)
seq_recoil		= 64		; kick on firing (it slows, it does not stop)
seq_vcruise		= 192		; the run up at an Asteroids pace (1.5 px a frame) ...
seq_vmin		= 128		; ... paced between these two
seq_vfast		= 240
seq_finalX		= 64		; on the row by here, on the last crossing
msgHaltX0		= 188-30	; (scroller.s msgHaltX, less the slowing down)
seq_fireX0		= 32		; it fires with its nose in here, the first quarter
seq_fireX1		= 112
seq_breakdx		= 60		; the break: up to here (right of it) ...
seq_breakY		= 20
seq_breakv		= 420		; ... at this speed
seq_breakdone	= 110		; up past here: roaming
seq_roamfly		= 300		; roaming speed afterwards
seq_boredgap	= 30		; frames between bored shots, + 0..63
seq_rungap		= 5			; frames between the shots of a burst ...
seq_runpause	= 8			; ... and 8..15 after a burst
seq_targetx1	= 340		; letters further right than this are not
							; visible enough to shoot yet
seq_urgentx		= 236		; a letter left of this: no time to fly about
seq_holdx		= 214		; scroller.s stutterHoldX: it hangs for letters
							; left of this
seq_burstgap	= 6			; frames between the shots of a burst
seq_burstpause	= 12		; ... and after a burst
seq_glidev		= 150		; gliding about: top speed ...
seq_glidea		= 5			; ... and how hard it changes it, a frame
seq_range		= 108		; px (max + min/2): a shot lives 56 frames at 2 px,
							; so further away it is not even tried
seq_maxdrift	= 60		; drifting faster than this while aiming: back
							; to flying, to the firing spot
seq_aimmax		= 24		; frames of aiming before it fires anyway
seq_movemax		= 70		; frames to a firing spot before it fires
							; from wherever it is
seq_claimtime	= 45		; a letter shot at counts as gone this long
seq_textv		= 16		; text speed for the lead, 1/16 px a frame:
seq_textvs		= 7			; running, stuttering (about 0.45)
seq_cleanup		= 30		; frames after the text is gone
seq_x2			= 300		; where it goes then
seq_y2			= 232
seq_tvdelay		= 40		; frames from there to the TV off

SQ_SEARCH		= 0
SQ_SPIN			= 1
SQ_A1MOVE		= 2
SQ_A1SHOOT		= 3
SQ_REPOS		= 4
SQ_RUN			= 5
SQ_CLEAN		= 6
SQ_LEAVE		= 7
SQ_HOLD			= 8
SQ_DEFSHOOT		= 9			; the Defender ending (seq_defshoot ...)
SQ_DEFLAP		= 10
SQ_DEFGO		= 11
SQ_DEFTEST		= 12
SQ_DEFFIRE		= 13
SQ_AFTER		= 14

; a0 = ship_struct, from ship_auto
seq_pilot:
		addq.w	#1,seq_timer
		move.w	obj_yc(a0),d0		; for glitchFrame: never tear the ship
		add.w	#$20,d0				; (game line 0 is raster $20)
		move.w	d0,seq_shipY
		tst.w	seq_claimT			; a letter shot at is spoken for a while
		beq.s	.noClaim
		subq.w	#1,seq_claimT
.noClaim:
		moveq	#0,d0
		move.b	seq_state,d0
		add.w	d0,d0
		move.w	.states(pc,d0.w),d0
		movem.w	obj_xvelo(a0),d1/d2	; (the velocity before: did it burn?)
		movem.w	d1/d2,seq_v0
		jsr		.states(pc,d0.w)
		; the thrust sound: a change of speed like a burn's, a few frames on
		movem.w	obj_xvelo(a0),d1/d2
		sub.w	seq_v0,d1
		bpl.s	.tx
		neg.w	d1
.tx:
		sub.w	seq_v0+2,d2
		bpl.s	.ty
		neg.w	d2
.ty:
		add.w	d2,d1
		cmp.w	#seq_burnDv,d1
		blo.s	.noBurn
		move.w	#seq_burnT,seq_burnLeft
.noBurn:
seq_thrustSnd	= 0			; the thrust sound: 1 on (it is off - only shots
								; and booms)
		tst.w	seq_burnLeft
	ifne	seq_thrustSnd
		sne		sfxThrust			; (music.s)
	endc
		beq.s	.move
		subq.w	#1,seq_burnLeft
.move:
		bsr		obj_move
		rts
.states:
		dc.w	seq_search-.states
		dc.w	seq_spin-.states
		dc.w	seq_a1move-.states
		dc.w	seq_a1shoot-.states
		dc.w	seq_repos-.states
		dc.w	seq_run-.states
		dc.w	seq_clean-.states
		dc.w	seq_leave-.states
		dc.w	seq_hold-.states
		dc.w	seq_defshoot-.states
		dc.w	seq_deflap-.states
		dc.w	seq_defgo-.states
		dc.w	seq_deftest-.states
		dc.w	seq_deffire-.states
		dc.w	seq_after-.states

;--- SEARCH -----------------------------------
seq_search:
		tst.b	seq_sub
		bne.s	.look
		cmp.w	#1,seq_timer		; a new spot
		bne.s	.fly
		move.w	#seq_searchv,seq_vmax
		jsr		getRandomNumber
		moveq	#127,d1
		and.w	d0,d1
		add.w	#60,d1				; left half ...
		btst	#0,seq_wp+1
		beq.s	.xSet
		add.w	#130,d1				; ... or right half, in turn
.xSet:
		move.w	d1,seq_ax
		swap	d0
		moveq	#31,d1
		and.w	d0,d1
		move.w	seq_wp,d2
		add.w	d2,d2
		lea		.heights(pc),a1
		add.w	(a1,d2.w),d1
		move.w	d1,seq_ay
.fly:
		movem.w	seq_ax,d0/d1
		moveq	#seq_arrive*2,d2
		bsr		seq_steer
		tst.w	d0
		bne.s	.there
		cmp.w	#150,seq_timer
		blo.s	.done
.there:
		st		seq_sub				; look round
		clr.w	seq_timer
.done:
		rts
		; --- looking round: left, a moment, right, a moment
.look:
		move.w	seq_timer,d0
		moveq	#seq_lookrate,d1
		cmp.w	#12,d0
		bls		obj_subangle
		cmp.w	#20,d0
		bls.s	.done
		cmp.w	#44,d0
		bls		obj_addangle
		cmp.w	#54,d0
		bls.s	.done
		sf		seq_sub
		clr.w	seq_timer
		addq.w	#1,seq_wp
		cmp.w	#seq_waypoints,seq_wp
		bhs		seq_next
		rts
; y of the spots: over the logo, the black at the bottom, over the logo
; again (+ 0..31)
.heights:
		dc.w	36,212,60

;--- SPIN -------------------------------------
seq_spin:
		moveq	#seq_spinrate,d1
		bsr		obj_addangle
		cmp.w	#360/seq_spinrate,seq_timer
		bhs		seq_next
		rts

;--- FIRST ATTACK -----------------------------
seq_a1move:
		move.w	#112,seq_vmax
		move.w	#seq_a1x,d0
		move.w	#seq_a1y,d1
		moveq	#seq_arrive,d2
		bsr		seq_steer
		tst.w	d0
		bne.s	.there
		cmp.w	#300,seq_timer
		blo.s	.done
.there:
		st		seq_hits			; from now on the shots hit the text
		st		seq_shotsLive
		jsr		getRandomNumber		; 5..8 letters to shoot out
		and.w	#3,d0
		addq.w	#5,d0
		move.w	d0,seq_a1n
		sf		seq_dOn				; seq_drift starts afresh after it, with the
		st		seq_dWin			; pirouette for the hits
		sf		seq_defReady
		move.w	#seq_a1x,seq_ax
		move.w	#seq_a1y,seq_ay
		clr.w	seq_shots
		clr.w	seq_gap
		clr.w	seq_aimT
		bra		seq_next
.done:
		rts

seq_a1shoot:
		move.w	seq_a1n,d0
		cmp.w	seq_shots,d0
		bls		.watch
		movem.w	seq_ax,d0/d1		; edging about over the bar between
		move.w	#seq_a1v,seq_glidevNow	; shots
		bsr		seq_glide
		move.w	#seq_glidev,seq_glidevNow
		tst.w	seq_gap
		beq.s	.aim
		subq.w	#1,seq_gap
.aim:
		; a letter of the running text, the left part of the right block
		bsr		seq_claimX
		cmp.w	#seq_a1from,d0
		bge.s	.from
		move.w	#seq_a1from,d0
.from:
		move.w	#seq_a1to,d1
		jsr		findText
		tst.w	d0
		bmi.s	.done
		move.w	d0,d3
		move.w	#seq_textY,d1
		moveq	#seq_textv,d2
		bsr		seq_aim
		tst.w	seq_gap
		bne.s	.done
		tst.w	d0
		bne.s	.fire
		addq.w	#1,seq_aimT
		cmp.w	#seq_aimmax,seq_aimT
		blo.s	.done
.fire:
		bsr		seq_fireAt
		clr.w	seq_aimT
		addq.w	#1,seq_shots
		move.w	#seq_a1gap,seq_gap
		clr.w	seq_timer
		jsr		getRandomNumber		; and on to another spot, a little off
		move.w	d0,d1
		and.w	#31,d0
		sub.w	#16,d0
		add.w	#seq_a1x,d0
		move.w	d0,seq_ax
		lsr.w	#8,d1
		and.w	#15,d1
		subq.w	#8,d1
		add.w	#seq_a1y,d1
		move.w	d1,seq_ay
.done:
		rts
		; --- the shots are out: off it goes, pleased with itself (seq_drift,
		;     with a pirouette), and the scroller breaks the moment the last
		;     of them has hit (none left in the air)
.watch:
		bsr		seq_drift
		tst.w	shot_con
		beq.s	.broken
		cmp.w	#seq_a1watch,seq_timer	; (a shot that misses: not for ever)
		blo		.done
.broken:
		jsr		startGlitch			; the scroller breaks
		bra		seq_next

;--- REPOS ------------------------------------
; while the scroller is broken and gets mended the ship keeps looking
; round, lively, spot to spot - well away from the bar - until the
; captain's message starts to come in
seq_repos:
		sf		seq_shotsLive		; shots now are only for show
		tst.b	finalAttackOn		; (the old last attack: seq_run)
		bne.s	.attack
		tst.b	msgCue				; the glyph test's cue: the Defender ending
		bne.s	.defender
		bra		seq_drift			; till then it drifts about
.defender:
		move.b	#SQ_DEFSHOOT,seq_state
		clr.w	seq_timer
		sf		seq_sub
		rts
.attack:
		tst.b	msgCue				; the scroller is mended: the attack
		bne		.go					; begins, with its run up
		tst.b	seq_sub
		bne.s	.look
		cmp.w	#1,seq_timer		; a new spot
		bne.s	.fly
		move.w	#seq_roamv,seq_vmax
		jsr		getRandomNumber
		moveq	#127,d1
		and.w	d0,d1
		add.w	#60,d1				; left half ...
		addq.w	#1,seq_wp
		btst	#0,seq_wp+1
		beq.s	.xSet
		add.w	#130,d1				; ... or right half, in turn
.xSet:
		move.w	d1,seq_ax
		swap	d0
		moveq	#15,d1
		and.w	d0,d1
		lsr.w	#4,d0
		and.w	#3,d0
		add.w	d0,d0
		lea		.heights(pc),a1
		add.w	(a1,d0.w),d1
		move.w	d1,seq_ay
		tst.b	msgCue				; once the scroller is mended it keeps
		beq.s	.fly				; over the bar - all over it, the logo,
		jsr		getRandomNumber		; the space under it - so it is never
		moveq	#15,d1				; far from where the dive starts
		and.w	d0,d1
		lsr.w	#4,d0
		and.w	#3,d0
		add.w	d0,d0
		lea		.heightsUp(pc),a1
		add.w	(a1,d0.w),d1
		move.w	d1,seq_ay
.fly:
		movem.w	seq_ax,d0/d1
		moveq	#seq_arrive*2,d2
		bsr		seq_steer
		tst.w	d0
		bne.s	.there
		cmp.w	#200,seq_timer
		blo.s	.done
.there:
		st		seq_sub
		clr.w	seq_timer
.done:
		rts
.look:
		move.w	seq_timer,d0
		moveq	#seq_lookrate,d1
		cmp.w	#10,d0
		bls		obj_addangle
		cmp.w	#24,d0
		bls.s	.done
		cmp.w	#44,d0
		bls		obj_subangle
		cmp.w	#56,d0
		bls.s	.done
		sf		seq_sub
		clr.w	seq_timer
		rts
.go:
		bra		seq_next			; the message is coming: the attack
; well clear of the bar: over the logo, under the bar, between them
; (+ 0..15)
.heights:
		dc.w	40,232,72,96
; once the scroller is mended: over the logo, either side of its bottom,
; between it and the bar (+ 0..15)
.heightsUp:
		dc.w	36,64,100,124

; bored: now and then a shot into the air, wherever the nose points - but
; only when it points upwards, away from the bar (and the shots of this
; time do not count against the text anyway, see seq_shotsLive)
seq_bored:
		subq.w	#1,seq_boredT
		bpl.s	.no
		jsr		getRandomNumber
		and.w	#63,d0
		add.w	#seq_boredgap,d0
		move.w	d0,seq_boredT
		move.w	obj_angle(a0),d0	; the nose up-ish: angle 300..360, 0..60
		cmp.w	#60,d0
		blo.s	.shoot
		cmp.w	#300,d0
		bls.s	.no
.shoot:
		jsr		getRandomNumber		; one, sometimes two
		btst	#5,d0
		beq.s	.one
		move.w	#4,seq_boredT2
.one:
		bra		ai_shoot
.no:
		tst.w	seq_boredT2			; the second of a pair
		beq.s	.out
		subq.w	#1,seq_boredT2
		bne.s	.out
		bra		ai_shoot
.out:
		rts

;--- DRIFT ------------------------------------
; from the last shot of the first attack on, and again once the words are
; gone: weightless, the Asteroids way. the nose turns, the engine burns
; (only along the nose), the ship coasts - spot to spot, and it never
; brakes to a halt: the velocity it is after points at the spot at
; seq_dvmin..seq_vmax, and as it gets near it is off to the next one.
; coasting, it turns its nose about and has a look round. right after the
; hits it is off, fast, and spins round once as it glides away - a
; pirouette for the hits.
; the spots: the gap between logo and bar and the black under the bar -
; the logo and the bar it only flies across or brushes in a turn
seq_dvmin		= 72		; never slower than this on the way (|vx|+|vy|)
seq_dthere		= 24		; px (manhattan) that count as "there"
seq_dlegT		= 400		; frames to a spot at most
seq_dspinr		= 8			; the pirouette: degrees a frame
seq_dlookr		= 3			; looking round: degrees a frame
seq_wmidY0		= 116		; the gap between logo and bar: y 116..131
seq_wlowY0		= 224		; the black under the bar: y 224..239
seq_dcrossv		= 230		; over to the other band: this fast at most
seq_wbarY0		= 152		; the bar is below this (ship included)

seq_drift:
		tst.b	seq_dOn
		bne.s	.on
		st		seq_dOn
		clr.w	seq_lookT
		sf		seq_corr
		bsr		seq_dnext
		tst.b	seq_dFast			; (off the row after the laser: briskly)
		beq.s	.slow
		sf		seq_dFast
		move.w	#seq_dcrossv,seq_vmax
.slow:
		tst.b	seq_dWin			; right after the hits: away, fast, and a
		beq.s	.on					; pirouette on the way
		sf		seq_dWin
		move.w	#360,seq_dspin
		move.w	#210,seq_vmax
		move.w	obj_xc(a0),d0
		add.w	#110,d0
		move.w	d0,seq_ax
		move.w	#seq_wmidY0+8,seq_ay
.on:
		addq.w	#1,seq_wT
		movem.w	seq_ax,d0/d1
		bsr		seq_wdelta
		movem.w	d0/d1,seq_dx
		bsr		ai_manhattan		; d5 = how far
		cmp.w	#seq_dthere,d5
		blo.s	.next
		cmp.w	#seq_dlegT,seq_wT
		blo.s	.go
.next:
		bra		seq_dnext
.go:
		; the velocity it is after: 2/128 px a frame per px off, in
		; seq_dvmin..seq_vmax (|vx|+|vy|, as ai_speed measures it)
		move.w	d5,d4
		add.w	d4,d4
		cmp.w	#seq_dvmin,d4
		bge.s	.v0
		move.w	#seq_dvmin,d4
.v0:
		cmp.w	seq_vmax,d4
		ble.s	.v1
		move.w	seq_vmax,d4
.v1:
		movem.w	seq_dx,d0/d1
		muls	d4,d0
		divs	d5,d0
		muls	d4,d1
		divs	d5,d1
		sub.w	obj_xvelo(a0),d0	; how far off the velocity is
		sub.w	obj_yvelo(a0),d1
		movem.w	d0/d1,seq_dx
		bsr		ai_manhattan
		tst.b	seq_corr
		bne.s	.corr
		cmp.w	#seq_corrstart,d5
		blo.s	.coast
		st		seq_corr
		st		ai_turning
.corr:
		cmp.w	#seq_corrstop,d5
		bhs.s	.steer
		sf		seq_corr
		bra.s	.coast
.steer:
		movem.w	seq_dx,d0/d1		; round to the burn, then burn
		asr.w	#2,d0
		asr.w	#2,d1
		bsr		ai_crossdot
		tst.l	d3
		ble.s	.turn
		move.l	d2,d4
		bpl.s	.cPos
		neg.l	d4
.cPos:
		lsl.l	#2,d4				; inside ~14 degrees: burn
		cmp.l	d3,d4
		bhs.s	.turn
		sf		ai_turning
		moveq	#ai_thrust,d2
		bra		obj_thrust
.turn:
		bra		ai_turn
		; --- coasting: the pirouette, or a look round
.coast:
		move.w	seq_dspin,d1
		beq.s	.look
		moveq	#seq_dspinr,d0
		cmp.w	d0,d1
		bhs.s	.spin
		move.w	d1,d0
.spin:
		sub.w	d0,seq_dspin
		move.w	d0,d1
		bra		obj_addangle
.look:
		subq.w	#1,seq_lookT
		bpl.s	.looking
		jsr		getRandomNumber		; somewhere else to look: 30..93 degrees
		move.w	d0,d1				; this way or that, for 30..93 frames
		and.w	#63,d1
		add.w	#30,d1
		btst	#8,d0
		beq.s	.lw
		neg.w	d1
.lw:
		add.w	obj_angle(a0),d1
		bpl.s	.l0
		add.w	#360,d1
.l0:
		cmp.w	#360,d1
		blo.s	.l1
		sub.w	#360,d1
.l1:
		move.w	d1,seq_lookA
		lsr.w	#8,d0
		and.w	#63,d0
		add.w	#30,d0
		move.w	d0,seq_lookT
.looking:
		move.w	seq_lookA,d0
		moveq	#seq_dlookr,d1
		bra		seq_turnTo

; the next spot: the gap, the black under the bar, or (not twice running,
; 1 in 4) up on the logo; anywhere across; a top speed of its own
seq_dnext:
		clr.w	seq_wT
		jsr		getRandomNumber
		moveq	#0,d1				; x 40..330
		move.b	d0,d1
		move.w	d0,d2
		lsr.w	#8,d2
		and.w	#31,d2
		add.w	d2,d1
		add.w	#40,d1
		cmp.w	#330,d1
		bls.s	.x
		move.w	#330,d1
.x:
		move.w	d1,seq_ax
		swap	d0
		move.w	d0,d1				; the top speed: 0.9 .. 1.6 px a frame
		lsr.w	#8,d1
		and.w	#63,d1
		add.w	#120,d1
		move.w	d1,seq_vmax
		moveq	#15,d1				; where in the band
		and.w	d0,d1
		btst	#5,d0				; 1 in 4 over to the other band - across
		beq.s	.same				; the bar, briskly
		btst	#6,d0
		beq.s	.same
		not.b	seq_dLow
.same:
		add.w	#seq_wmidY0,d1		; between logo and bar ...
		tst.b	seq_dLow
		beq.s	.y
		add.w	#seq_wlowY0-seq_wmidY0,d1	; ... or under it
.y:
		move.w	d1,seq_ay
		; across the bar from where it is: briskly
		move.w	obj_yc(a0),d0
		cmp.w	#seq_wbarY0,d0
		blo.s	.above
		cmp.w	#seq_wbarY0,d1
		bhs.s	.out
		bra.s	.cross
.above:
		cmp.w	#seq_wbarY0,d1
		blo.s	.out
.cross:
		move.w	#seq_dcrossv,seq_vmax
.out:
		rts

; d0/d1 = a spot -> d0/d1 = the way there from the ship, x the short way
; round (the play area wraps)
seq_wdelta:
		sub.w	obj_xc(a0),d0
		sub.w	obj_yc(a0),d1
		cmp.w	#(wrap_x1-wrap_x0)/2,d0
		blt.s	.x0
		sub.w	#wrap_x1-wrap_x0,d0
.x0:
		cmp.w	#-(wrap_x1-wrap_x0)/2,d0
		bge.s	.x1
		add.w	#wrap_x1-wrap_x0,d0
.x1:
		rts

;--- THE DEFENDER ENDING ----------------------
; the scroller is mended and runs its glyph test (scroller.s feedScript).
; at its cue (msgCue) the end is set up:
;   DEFSHOOT over to a spot over the bar, the Asteroids way, and from there
;            5..6 glyphs of the test shot out (as in the first attack)
;   DEFLAP   the last one gone: the bar starts to flicker (scroller.s
;            barFlicker), the stars slow down to a stand and then go the
;            other way, half as fast again (updateStars, starTurn) - and the
;            ship does a lap of honour, Asteroids style, with a pirouette
;   DEFGO    on towards the Defender spot: on the way two more glyphs shot
;            out, the second one gone and the monitor goes off (the TV, with
;            the text running on: tvKeepText). at the spot the nose goes
;            right, and it hangs there the Defender way till the TV is off
;            and the world runs past from right to left at full speed
;   DEFTEST  a Defender ship now: up and down at once, along with weight,
;            the reverse - it tries it out for a few seconds. the message
;            is let in now (seq_defReady), and in time it gets onto the row
;   DEFFIRE  the laser (scroller.s launchLaser), a word a shot, each one
;            just before it gets to the twist
;   AFTER    the words are gone: the stars run down to a stand, the ship
;            is an Asteroids ship again (seq_drift)
seq_defX		= 56		; the Defender spot
seq_defY		= 136
seq_defStar		= -768		; the stars then: 3 px a frame to the left
seq_starAcc		= 2			; how fast they slow down, 8.8 a frame ...
seq_starAccD	= 4			; ... and speed up the other way (and run down
							; at the end)
seq_defvmax		= 120		; the drift over, top speed
seq_tshotX		= 150		; DEFSHOOT: the spot it shoots the test from ...
seq_tshotY		= 140		; (close: a shot only gets ~110 px far)
seq_tshot2X		= 160		; ... and DEFGO's, on the way
seq_tshot2Y		= 136
seq_tgap		= 14		; frames between those shots
seq_t1from		= 214		; glyphs from here ...
seq_t1to		= 246		; ... to here are shot at: in reach, and hit
							; before they get to the twist
seq_lapT		= 180		; the lap of honour
seq_dreverse	= 15		; the reverse: degrees a frame
seq_dfireX		= 198		; a word is shot once it is in this far (the twist
seq_dlastX		= 190		; is at 184) - and here at the latest
seq_dcool		= 6			; frames between a word gone and the next shot
seq_burnDv		= 6			; a change of speed this big (|dvx|+|dvy|) is a
seq_burnT		= 6			; burn: the thrust sounds this many frames on
								; (if seq_thrustSnd, see seq_pilot)
seq_dswayX		= 16		; firing: the ship moves about this far to and
seq_dswayY		= 3			; fro, and up and down

seq_defshoot:
		cmp.w	#1,seq_timer
		bne.s	.on
		jsr		getRandomNumber		; 5..6 glyphs
		and.w	#1,d0
		addq.w	#5,d0
		move.w	#seq_tshotX,d1
		move.w	#seq_tshotY,d2
		bsr		seq_tshootInit
.on:
		bsr		seq_tshoot
		move.w	d0,-(a7)
		move.w	hitTotal,d0			; the first glyph gone: the scroller starts
		cmp.w	seq_tHit0,d0		; to jerk a little (scroller.s stutterStep)
		beq.s	.noJerk
		tst.w	glitchLevel
		bne.s	.noJerk
		move.w	#1,glitchLevel
		move.w	#1,glitchTarget
.noJerk:
		tst.w	seq_shots			; the first shot out: somebody on the bridge
		beq.s	.noCry				; cries out (scroller.s whatHellReq)
		st		whatHellReq
.noCry:
		move.w	(a7)+,d0
		bne		seq_next			; -> DEFLAP
		cmp.w	#1500,seq_timer		; (never for ever)
		bhs		seq_next
		rts

seq_deflap:
		cmp.w	#1,seq_timer
		bne.s	.on
		st		barFlickOn			; (scroller.s)
		clr.w	starTarget			; the stars slow down, then turn round
		move.w	#seq_starAcc,starAcc
		st		starTurn
		sf		seq_shotsLive
		sf		seq_dOn				; the lap: off and away, a pirouette
		st		seq_dWin
.on:
		bsr		seq_drift
		cmp.w	#seq_lapT,seq_timer
		bhs		seq_next			; -> DEFGO
		rts

seq_defgo:
		cmp.w	#1,seq_timer
		bne.s	.on
		moveq	#2,d0				; two more glyphs on the way
		move.w	#seq_tshot2X,d1
		move.w	#seq_tshot2Y,d2
		bsr		seq_tshootInit
		sf		seq_dThere
.on:
		tst.b	tvGo
		bne.s	.toSpot
		bsr		seq_tshoot
		tst.w	d0
		bne.s	.monitorOff
		cmp.w	#900,seq_timer
		blo.s	.out
.monitorOff:
		st		tvKeepText			; the monitor goes off - the text runs on
		st		tvGo
		sf		seq_shotsLive
		move.w	#seq_defvmax,seq_vmax
		sf		seq_corr
.out:
		rts
		; --- on to the Defender spot
.toSpot:
		tst.b	seq_dThere
		bne.s	.there
		move.w	#seq_defX,d0
		move.w	#seq_defY,d1
		moveq	#seq_arrive,d2
		bsr		seq_steer
		tst.w	d0
		beq.s	.out
		sf		seq_corr
		st		seq_dThere
		; --- there: nose to the right, and it hangs there the Defender way
		;     till the TV is off and the world runs past at full speed
.there:
		move.w	#90,seq_dface
		moveq	#14,d2				; a slow figure of eight
		moveq	#8,d3
		bsr		seq_dfloat
		bsr		seq_dmove
		cmp.w	#90,obj_angle(a0)
		bne.s	.out
		cmp.b	#5,tvState			; (scroller.s: the TV is off)
		bne.s	.out
		cmp.w	#seq_defStar+48,starV
		bgt.s	.out
		bra		seq_next			; -> DEFTEST

; shooting glyphs of the test out: d0 = how many, d1/d2 the spot to shoot
; from. there the Asteroids way first, then edging about it between the
; shots and aiming as in the first attack
seq_tshootInit:
		move.w	d0,seq_a1n
		move.w	d1,seq_tsx
		move.w	d2,seq_tsy
		move.w	d1,seq_ax
		move.w	d2,seq_ay
		move.w	hitTotal,seq_tHit0	; (scroller.s) letters gone so far
		st		seq_aimFine			; aimed finely: the glyphs are few
		st		seq_shotsLive
		clr.w	seq_shots
		clr.w	seq_gap
		clr.w	seq_aimT
		sf		seq_tThere
		move.w	#seq_defvmax,seq_vmax
		rts

; -> d0 non zero once seq_a1n glyphs are gone
seq_tshoot:
		move.w	hitTotal,d0
		sub.w	seq_tHit0,d0
		cmp.w	seq_a1n,d0
		bhs		.done
		tst.b	seq_tThere
		bne.s	.there
		movem.w	seq_ax,d0/d1
		moveq	#seq_arrive*2,d2
		bsr		seq_steer
		tst.w	d0
		beq		.no
		sf		seq_corr
		st		seq_tThere
.there:
		movem.w	seq_ax,d0/d1		; edging about between the shots
		move.w	#seq_a1v,seq_glidevNow
		bsr		seq_glide
		move.w	#seq_glidev,seq_glidevNow
		tst.w	seq_gap
		beq.s	.aim
		subq.w	#1,seq_gap
.aim:
		bsr		seq_claimX
		cmp.w	#seq_t1from,d0
		bge.s	.from
		move.w	#seq_t1from,d0
.from:
		move.w	#seq_t1to,d1		; (glyphs with some body: the specks of
		jsr		findSolid			; a dot or a colon a shot would miss)
		tst.w	d0
		bmi.s	.no
		move.w	d0,d3
		move.w	#seq_textY,d1
		moveq	#seq_textv,d2
		bsr		seq_aim
		tst.w	seq_gap
		bne.s	.no
		tst.w	d0
		bne.s	.fire
		addq.w	#1,seq_aimT
		cmp.w	#seq_aimmax,seq_aimT
		blo.s	.no
.fire:
		bsr		seq_fireAt
		clr.w	seq_aimT
		addq.w	#1,seq_shots
		move.w	#seq_tgap,seq_gap
		jsr		getRandomNumber		; and to another spot, a little off
		move.w	d0,d1
		and.w	#31,d0
		sub.w	#16,d0
		add.w	seq_tsx,d0
		move.w	d0,seq_ax
		lsr.w	#8,d1
		and.w	#15,d1
		subq.w	#8,d1
		add.w	seq_tsy,d1
		move.w	d1,seq_ay
.no:
		moveq	#0,d0
		rts
.done:
		moveq	#1,d0
		rts


; a few seconds of trying the Defender ship out: up, down under the bar,
; the reverse and round again - then onto the row, nose right, and the
; first shot once the first word is far enough in
seq_deftest:
		cmp.w	#1,seq_timer
		bne.s	.on
		st		seq_defReady		; the message may come now (scroller.s)
.on:
		move.w	seq_timer,d2
		lea		.steps(pc),a1
.find:
		move.w	(a1)+,d3			; the step's last frame, 0: the row
		beq.s	.row
		cmp.w	d3,d2
		blo.s	.this
		addq.l	#6,a1
		bra.s	.find
.this:
		movem.w	(a1),d0/d1/d3
		move.w	d3,seq_dface
		bra		seq_dmove
.row:
		move.w	#90,seq_dface
		moveq	#seq_dswayX,d2		; on the row, never quite still
		moveq	#seq_dswayY,d3
		bsr		seq_dfloat
		add.w	#seq_rowY-seq_defY,d1
		bsr		seq_dmove
		jsr		msgLeftX			; the first word
		tst.w	d0
		bmi.s	.out
		cmp.w	#seq_dlastX,d0		; (not a frame later than this)
		bls.s	.fire
		cmp.w	#seq_dfireX,d0
		bhi.s	.out
		move.w	obj_yc(a0),d0		; on the row, nose right?
		sub.w	#seq_rowY,d0
		bpl.s	.ay
		neg.w	d0
.ay:
		cmp.w	#seq_dswayY+1,d0
		bhi.s	.out
		cmp.w	#90,obj_angle(a0)
		bne.s	.out
.fire:
		clr.w	seq_gap
		bra		seq_next			; -> DEFFIRE
.out:
		rts
; frame it ends, x, y, which way the nose
.steps:
		dc.w	30,	84,118,90		; up and forward
		dc.w	60,	70,232,90		; down, across the bar, under it
		dc.w	84,	46,206,270		; the reverse: round to the left, back
		dc.w	106, 62,166,90		; and round again
		dc.w	140, 98,128,90		; forward and up
		dc.w	172, 64,228,90		; down again
		dc.w	196, 42,196,270		; the reverse once more
		dc.w	220, 70,150,90		; round again
		dc.w	250, 86,122,90		; up
		dc.w	0

; on the row: the laser, a word a shot, each one just before the twist
seq_deffire:
		move.w	#90,seq_dface
		moveq	#seq_dswayX,d2		; to and fro, up and down a little, on
		moveq	#seq_dswayY,d3		; the row: the laser goes off where the
										; nose is (scroller.s keeps it on the text)
		bsr		seq_dfloat
		add.w	#seq_rowY-seq_defY,d1
		bsr		seq_dmove
		tst.b	laserOn				; (scroller.s) a shot in the air
		bne.s	.out
		tst.w	seq_gap
		beq.s	.ready
		subq.w	#1,seq_gap
		rts
.ready:
		jsr		msgLeftX			; the next word in sight?
		tst.w	d0
		bmi.s	.none
		cmp.w	#seq_dfireX,d0		; (just before the twist)
		bhi.s	.out
		move.w	obj_xc(a0),d0		; fire, from the nose
		addq.w	#7,d0
		move.w	obj_yc(a0),d1
		jsr		launchLaser
		addq.w	#1,seq_lasers
		move.w	#seq_dcool,seq_gap
		rts
.none:
		tst.b	msgEnded			; nothing on the row: all gone, if all of
		beq.s	.out				; the message has come in
		clr.w	starTarget			; the stars run down to a stand
		move.w	#seq_starAccD,starAcc
		sf		seq_shotsLive
		sf		seq_dOn				; an Asteroids ship again - up off the row
		sf		seq_dLow			; into the gap, briskly
		st		seq_dFast
		bra		seq_next			; -> AFTER
.out:
		rts

; the words are gone: Asteroids again
seq_after:
		bsr		seq_drift
		bra		seq_endCheck

; -> d0/d1 = the Defender spot on a slow figure of eight, d2 px to and fro
; and d3 up and down (seq_timer: 4 seconds a round)
seq_dfloat:
		move.w	seq_timer,d0
		mulu	#3,d0
		lsr.w	#1,d0				; 1.5 degrees a frame
		divu	#360,d0
		swap	d0
		lea		sctab(pc),a3
		move.w	d0,d1
		lsl.w	#2,d1
		move.w	(a3,d1.w),d1		; sin a
		muls	d2,d1
		add.l	d1,d1
		swap	d1
		add.w	d0,d0				; sin 2a
		cmp.w	#360,d0
		blo.s	.a
		sub.w	#360,d0
.a:
		lsl.w	#2,d0
		move.w	(a3,d0.w),d0
		muls	d3,d0
		add.l	d0,d0
		swap	d0
		exg		d0,d1
		add.w	#seq_defX,d0
		add.w	#seq_defY,d1
		rts

; Defender flying to d0/d1: up and down snappily (the velocity eases a
; quarter of the way a frame to 12/128 px a frame per px off), along with
; weight (an eighth, 6/128 per px); the nose to seq_dface, turned round
; quickly (the reverse)
seq_dmove:
		sub.w	obj_xc(a0),d0
		sub.w	obj_yc(a0),d1
		muls	#12,d1
		cmp.l	#300,d1
		ble.s	.y0
		move.l	#300,d1
.y0:
		cmp.l	#-300,d1
		bge.s	.y1
		move.l	#-300,d1
.y1:
		sub.w	obj_yvelo(a0),d1
		asr.w	#2,d1
		add.w	d1,obj_yvelo(a0)
		muls	#6,d0
		cmp.l	#220,d0
		ble.s	.x0
		move.l	#220,d0
.x0:
		cmp.l	#-220,d0
		bge.s	.x1
		move.l	#-220,d0
.x1:
		sub.w	obj_xvelo(a0),d0
		asr.w	#3,d0
		add.w	d0,obj_xvelo(a0)
		move.w	seq_dface,d0
		moveq	#seq_dreverse,d1
		bra		seq_turnTo

; the end of it all: the message gone, the text all gone, then the TV
; goes off
seq_endCheck:
		tst.b	tvGo
		bne.s	.done
		tst.b	msgEnded
		beq.s	.done
		jsr		msgLeftX
		tst.w	d0
		bpl.s	.done
		jsr		glitchStop
		tst.b	scrollGone
		beq.s	.wait
		addq.w	#1,seq_tvT
		cmp.w	#seq_tvdelay,seq_tvT
		blo.s	.done
		st		tvGo				; switch the TV off
		bra.s	.done
.wait:
		clr.w	seq_tvT
.done:
		rts

;--- RUN --------------------------------------
; the last attack (only with finalAttackOn), flown like a fighter's - the ship never stops, the
; nose always along the way it flies (seq_fly):
;   lap       from the cue on (the scroller is mended) it takes a run up:
;             high over the screen to the right, out of it, and in again
;             from the left (the play area wraps). the speed of the lap is
;             set so it comes round just as the last words are far enough
;             in - and if they are not, it goes round again
;   approach  from the left, down out of the height in a curve onto the
;             bottom text row, straight at the letters
;   fire      the power blast (launchTorpedo, with its muzzle flash and a
;             kick), once the first letter will be at seq_fireX by the
;             time the blast is there - or at once if the letters are too
;             near
;   break     straight away it pulls up and away out of the blast's way,
;             up and to the right
;   roam      and then it flies about over the bar, the logo, the screen,
;             spot to spot - all through the scroller going off and the TV
SR_LAP			= 0
SR_APPROACH		= 1
SR_BREAK		= 2
SR_ROAM			= 3

seq_run:
		move.w	seq_phase,d0
		beq.s	.lap
		cmp.w	#SR_APPROACH,d0
		beq		.approach
		cmp.w	#SR_BREAK,d0
		beq		.break
		bra		.roam

		; --- the run up: once or twice across the screen and round (the
		;     play area wraps), at an Asteroids pace, coming down a little
		;     all the way - a long, flat glide from where it was to the
		;     bottom text row, which it reaches early on the last crossing
.lap:
		tst.b	seq_runInit
		bne.s	.lapGo
		st		seq_runInit
		move.w	obj_yc(a0),seq_y0
		; how far to fly: round once at least, and once or twice more if the
		; message is that far off - at the cruising speed
		bsr		seq_frontEst
		move.w	#seq_wrapX,d1
		sub.w	obj_xc(a0),d1
		add.w	#seq_finalX-16,d1		; the way round once (d1)
		moveq	#0,d2					; extra laps
		tst.w	d0
		bmi.s	.laps
		sub.w	#msgHaltX0,d0			; frames to go
		ble.s	.laps
		mulu	#seq_vcruise,d0
		lsr.l	#7,d0					; the way at the cruising speed
		sub.w	d1,d0
		ble.s	.laps
		add.w	#176,d0
		ext.l	d0
		divu	#seq_wrapX-16,d0		; laps, rounded
		move.w	d0,d2
		cmp.w	#2,d2
		bls.s	.laps
		moveq	#2,d2
.laps:
		move.w	d2,seq_lapsLeft
		mulu	#seq_wrapX-16,d2
		add.w	d2,d1
		move.w	d1,seq_dTotal
		move.w	obj_xc(a0),seq_lastX
.lapGo:
		; round from the right?
		move.w	obj_xc(a0),d0
		move.w	seq_lastX,d1
		move.w	d0,seq_lastX
		sub.w	d0,d1
		cmp.w	#200,d1
		ble.s	.noWrap
		subq.w	#1,seq_lapsLeft
		bpl.s	.noWrap
		move.w	#SR_APPROACH,seq_phase	; that was the last time round
		bra		.approach
.noWrap:
		; the way still to go, to seq_finalX on the last crossing
		move.w	#seq_wrapX,d3
		sub.w	obj_xc(a0),d3
		add.w	#seq_finalX-16,d3
		move.w	seq_lapsLeft,d0
		mulu	#seq_wrapX-16,d0
		add.w	d0,d3					; d3 = the way to go
		; the height there, 48 px on: straight down the line from where it
		; started to the row
		move.w	d3,d1
		sub.w	#48,d1
		bpl.s	.dr
		moveq	#0,d1
.dr:
		move.w	#seq_rowY,d0
		sub.w	seq_y0,d0				; how far it comes down in all
		muls	d1,d0
		move.w	seq_dTotal,d2
		bne.s	.dt
		moveq	#1,d2
.dt:
		divs	d2,d0
		move.w	#seq_rowY,d1
		sub.w	d0,d1					; the height to steer at
		; the pace: there just as the message stops on screen
		move.w	#seq_vcruise,d2
		bsr		seq_frontEst
		tst.w	d0
		bmi.s	.go
		sub.w	#msgHaltX0,d0			; frames until it stands
		ble.s	.fastest
		mulu	#128,d3
		divu	d0,d3
		bvs.s	.fastest
		move.w	d3,d2
		cmp.w	#seq_vmin,d2
		bge.s	.v0
		move.w	#seq_vmin,d2
.v0:
		cmp.w	#seq_vfast,d2
		ble.s	.go
.fastest:
		move.w	#seq_vfast,d2
.go:
		move.w	obj_xc(a0),d0
		add.w	#48,d0
		bra		seq_fly

		; --- the last crossing: on the row from the left, at the words
.approach:
		move.w	seq_wob,d0
		addq.w	#seq_wavestep,d0
		cmp.w	#360,d0
		blo.s	.wOk
		sub.w	#360,d0
.wOk:
		move.w	d0,seq_wob
		lsl.w	#2,d0
		lea		sctab(pc),a3
		move.w	(a3,d0.w),d1
		muls	#seq_wave,d1
		swap	d1
		add.w	d1,d1
		add.w	#seq_rowY,d1
		move.w	obj_xc(a0),d0
		add.w	#48,d0
		move.w	#seq_vcruise,d2		; (a little slower while it waits for
		tst.b	msgHalted			; the message to stand)
		bne.s	.appV
		move.w	#seq_vmin,d2
.appV:
		bsr		seq_fly
		; --- fire? the message standing, all of it on show, the ship in
		;     the first quarter of the screen, on the row, nose to the right
		jsr		msgLeftX
		tst.w	d0
		bmi		.noFire
		move.w	obj_xc(a0),d0
		cmp.w	#seq_fireX1,d0
		bhi.s	.lateFire			; (the last chance)
		cmp.w	#seq_fireX0,d0
		blo		.noFire
		tst.b	msgHalted
		beq		.noFire
		move.w	obj_yc(a0),d0
		sub.w	#seq_rowY,d0
		bpl.s	.ay
		neg.w	d0
.ay:
		cmp.w	#seq_wave+1,d0
		bhi		.noFire
		move.w	obj_angle(a0),d0
		sub.w	#ai_enterangle,d0
		bpl.s	.aa
		neg.w	d0
.aa:
		cmp.w	#8,d0
		bhi		.noFire
		bra.s	.fire
.lateFire:
		addq.w	#1,seq_lateFires	; (testing: should stay 0)
.fire:
		move.w	obj_xc(a0),d0
		addq.w	#6,d0
		move.w	d0,seq_fireAtX		; (testing)
		jsr		msgLeftX
		move.w	d0,seq_fireMsgX
		move.w	obj_xc(a0),d0
		addq.w	#6,d0
		move.w	obj_yc(a0),d1
		move.w	obj_xvelo(a0),d2
		jsr		launchTorpedo
		sub.w	#seq_recoil,obj_xvelo(a0)	; the kick
		move.w	#SR_BREAK,seq_phase
.noFire:
		rts
		; --- the break: up and away from where it all goes off
.break:
		move.w	obj_xc(a0),d0
		add.w	#seq_breakdx,d0
		moveq	#seq_breakY,d1
		move.w	#seq_breakv,d2
		bsr		seq_fly
		cmp.w	#seq_breakdone,obj_yc(a0)
		bgt.s	.bDone
		move.w	#SR_ROAM,seq_phase
		bsr		seq_newWay
.bDone:
		rts

		; --- roaming about, never still
.roam:
		movem.w	seq_ax,d0/d1
		move.w	#seq_roamfly,d2
		bsr		seq_fly
		movem.w	seq_ax,d0/d1		; there? the next spot
		sub.w	obj_xc(a0),d0
		bpl.s	.rx
		neg.w	d0
.rx:
		sub.w	obj_yc(a0),d1
		bpl.s	.ry
		neg.w	d1
.ry:
		add.w	d1,d0
		cmp.w	#seq_arrive*3,d0
		bhi.s	.rOn
		bsr		seq_newWay
.rOn:
		; the end of it all: the text gone, then the TV goes off
		tst.b	tvGo
		bne.s	.rDone
		tst.b	torpOn
		bne.s	.rDone
		tst.b	wakeOn
		bne.s	.rDone
		tst.w	detN
		bne.s	.rDone
		tst.b	msgEnded
		beq.s	.rDone
		jsr		msgLeftX
		tst.w	d0
		bpl.s	.rDone
		jsr		glitchStop
		tst.b	scrollGone
		beq.s	.rWait
		addq.w	#1,seq_tvT
		cmp.w	#seq_tvdelay,seq_tvT
		blo.s	.rDone
		st		tvGo				; switch the TV off
		bra.s	.rDone
.rWait:
		clr.w	seq_tvT
.rDone:
		rts

; a new spot to roam to: over the bar, left half and right half in turn
seq_newWay:
		jsr		getRandomNumber
		moveq	#127,d1
		and.w	d0,d1
		add.w	#48,d1
		addq.w	#1,seq_wp
		btst	#0,seq_wp+1
		beq.s	.x
		add.w	#140,d1
.x:
		move.w	d1,seq_ax
		swap	d0
		and.w	#63,d0
		add.w	#36,d0				; y 36..99: over the logo, its bottom
		move.w	d0,seq_ay
		rts

; -> d0 = where the first letter of the message is (screen x), on screen
; or still to come in; -1 if it has not started yet
seq_frontEst:
		jsr		msgLeftX			; on the row?
		tst.w	d0
		bpl.s	.out
		tst.b	msgEnded			; (all of it gone already: none)
		bne.s	.none
		move.w	msgStartAbs,d0		; still coming in: where it was put ...
		tst.b	msgStarted
		bne.s	.est
		tst.b	msgCue				; ... or where it will be (from the cue
		beq.s	.none				; on, scroller.s knows that)
		move.w	msgPredAbs,d0
.est:
		sub.w	scrollSteps,d0
		rts
.none:
		moveq	#-1,d0
.out:
		rts

; fly towards d0/d1 at speed d2 (1/128 px a frame) the way a craft flies:
; the velocity swings round towards the target at seq_flyacc a frame at
; most, so it curves rather than turns, and it never stops; the nose along
; the way it goes
seq_fly:
		sub.w	obj_xc(a0),d0
		sub.w	obj_yc(a0),d1
		move.w	d0,d4
		bpl.s	.ax
		neg.w	d4
.ax:
		move.w	d1,d5
		bpl.s	.ay
		neg.w	d5
.ay:
		cmp.w	d5,d4
		bhs.s	.big
		exg		d4,d5
.big:
		lsr.w	#1,d5
		add.w	d5,d4				; length, ~ max + min/2
		bne.s	.len
		moveq	#1,d4
.len:
		muls	d2,d0				; the velocity wanted
		divs	d4,d0
		muls	d2,d1
		divs	d4,d1
		sub.w	obj_xvelo(a0),d0
		move.w	#seq_flyacc,d6
		bsr.s	.clamp
		add.w	d0,obj_xvelo(a0)
		move.w	d1,d0
		sub.w	obj_yvelo(a0),d0
		bsr.s	.clamp
		add.w	d0,obj_yvelo(a0)
		; never slower than seq_flymin: turning back it swings round in an
		; arc at that speed instead of braking through a standstill
		move.w	obj_xvelo(a0),d0
		move.w	obj_yvelo(a0),d1
		move.w	d0,d4
		bpl.s	.mx
		neg.w	d4
.mx:
		move.w	d1,d5
		bpl.s	.my
		neg.w	d5
.my:
		cmp.w	d5,d4
		bhs.s	.mbig
		exg		d4,d5
.mbig:
		lsr.w	#1,d5
		add.w	d5,d4				; ~ its speed
		cmp.w	#seq_flymin,d4
		bhs.s	.fast
		tst.w	d4
		bne.s	.scale
		move.w	#seq_flymin,obj_xvelo(a0)	; (dead still: off to the right)
		bra.s	.fast
.scale:
		muls	#seq_flymin,d0
		divs	d4,d0
		move.w	d0,obj_xvelo(a0)
		muls	#seq_flymin,d1
		divs	d4,d1
		move.w	d1,obj_yvelo(a0)
.fast:
		move.w	obj_xvelo(a0),d0	; the nose along the way it flies
		move.w	obj_yvelo(a0),d1
		move.w	d0,d2
		or.w	d1,d2
		beq.s	.out
		bra		seq_faceMove
.clamp:
		cmp.w	d6,d0
		ble.s	.c0
		move.w	d6,d0
.c0:
		neg.w	d6
		cmp.w	d6,d0
		bge.s	.c1
		move.w	d6,d0
.c1:
		neg.w	d6
.out:
		rts

; turn the nose towards the way d0/d1 (the velocity): up to 10 degrees a
; frame, 2 when nearly there
seq_faceMove:
		bsr		ai_crossdot			; d2 cross, d3 dot
		moveq	#10,d1
		tst.l	d3
		ble.s	.turn
		move.l	d2,d4
		bpl.s	.p
		neg.l	d4
.p:
		move.l	d4,d5
		lsl.l	#2,d5				; off by more than ~14 degrees: fast
		cmp.l	d3,d5
		bhs.s	.turn
		moveq	#2,d1
		lsl.l	#4,d4				; within ~4 degrees: done
		cmp.l	d3,d4
		bhs.s	.turn
		rts
.turn:
		tst.l	d2
		bmi		obj_subangle
		bra		obj_addangle

; every frame, from updateScroller once this frame's text is drawn: every
; shot in the air against the text as it is shown (textShot). a shot that
; hits is gone at once
seqShotScan::
		movem.l	d0-d7/a0-a6,-(a7)
		jsr		textFrame			; held over hits, the power blast
		tst.b	seq_shotsLive		; (the bored shots go nowhere)
		beq		.done
		lea		shot_structs(pc),a0
		moveq	#15,d7
.shot:
		move.w	shot_con(pc),d6
		btst	d7,d6
		beq.s	.next
		move.w	obj_xfloat(a0),d0
		sub.w	obj_xvelo(a0),d0
		lsr.w	#7,d0				; where it was last frame
		move.w	obj_yfloat(a0),d1
		sub.w	obj_yvelo(a0),d1
		asr.w	#7,d1
		move.w	obj_xc(a0),d2		; and where it is now
		move.w	obj_yc(a0),d3
		move.w	d2,d4
		sub.w	d0,d4
		bpl.s	.adx
		neg.w	d4
.adx:
		cmp.w	#16,d4				; wrapped round the edge: not near any
		bhi.s	.next				; text
		move.w	obj_xvelo(a0),d4
		move.w	obj_yvelo(a0),d5
		move.w	d7,-(a7)
		jsr		textShot
		move.w	(a7)+,d7
		tst.w	d0
		beq.s	.next
		move.w	shot_con(pc),d6		; a hit: the shot is gone
		bclr	d7,d6
		move.w	d6,shot_con
.next:
		lea		obj_len(a0),a0
		dbf		d7,.shot
.done:
		movem.l	(a7)+,d0-d7/a0-a6
		rts
;--- CLEAN, LEAVE, HOLD -----------------------
seq_clean:
		bsr		seq_hover
		tst.b	scrollGone
		bne.s	.gone
		clr.w	seq_timer			; counts from the moment it is all gone
		rts
.gone:
		cmp.w	#seq_cleanup,seq_timer
		bhs		seq_next
		rts

seq_leave:
		move.w	#112,seq_vmax
		move.w	#seq_x2,d0
		move.w	#seq_y2,d1
		moveq	#seq_arrive,d2
		bsr		seq_steer
		tst.w	d0
		bne.s	.there
		cmp.w	#400,seq_timer
		blo.s	.done
.there:
		clr.w	obj_xvelo(a0)		; under 1/5 pixel a frame: nobody sees it
		clr.w	obj_yvelo(a0)		; stop dead
		bra		seq_next
.done:
		rts

seq_hold:
		moveq	#0,d0				; nose up again, and wait
		moveq	#3,d1
		bsr		seq_turnTo
		cmp.w	#seq_tvdelay,seq_timer
		blo.s	.done
		st		tvGo				; switch the TV off
.done:
		rts

seq_next:
		addq.b	#1,seq_state
		clr.w	seq_timer
		sf		seq_sub
		rts

;--- helpers ----------------------------------
; -> d0 = screen x from which letters are still free to shoot at (the one
; shot at last is spoken for while its shot is in the air), -32768 if all
seq_claimX:
		move.w	#-32768,d0
		tst.w	seq_claimT
		beq.s	.free
		move.w	seq_claim,d0
		sub.w	scrollSteps,d0
.free:
		rts

; fire at the letter at screen x d3 (seq_aim has the nose on it)
seq_fireAt:
		moveq	#1,d0				; its sound (music.s sfxPlay, SFX_SHOT)
		jsr		sfxPlay
		addq.w	#1,seq_fired
		move.w	d3,-(a7)			; (ai_shoot uses d0-d4)
		bsr		ai_shoot
		move.w	(a7)+,d3
		move.w	d3,d0
		add.w	#12,d0
		add.w	scrollSteps,d0		; the claim moves with the text
		move.w	d0,seq_claim
		move.w	#seq_claimtime,seq_claimT
		rts

; hold the spot seq_ax/seq_ay, swinging round it a little so the ship is
; never still. -> d7 non zero when close to it
seq_hover:
		move.w	seq_wob,d0
		addq.w	#seq_wobstep,d0
		cmp.w	#360,d0
		blo.s	.wOk
		sub.w	#360,d0
.wOk:
		move.w	d0,seq_wob
		lea		sctab(pc),a3
		lsl.w	#2,d0
		move.w	(a3,d0.w),d2		; sin(w)
		muls	#seq_wobx,d2
		swap	d2
		add.w	d2,d2				; * wobx / 32768
		add.w	seq_ax,d2
		move.w	seq_wob,d0
		add.w	d0,d0				; twice as fast up and down
		cmp.w	#360,d0
		blo.s	.w2
		sub.w	#360,d0
.w2:
		lsl.w	#2,d0
		move.w	(a3,d0.w),d1
		muls	#seq_woby,d1
		swap	d1
		add.w	d1,d1
		add.w	seq_ay,d1
		move.w	d2,d0
; glide to d0/d1: the velocity eases towards twice the distance (up to
; seq_glidevNow), an 8th of the difference and at most seq_glidea a
; frame - smooth, no jerks. no turning to thrust, the nose
; stays free for aiming. -> d7 non zero when close
seq_glide:
		sub.w	obj_xc(a0),d0
		sub.w	obj_yc(a0),d1
		move.w	d0,d7
		bpl.s	.ax
		neg.w	d7
.ax:
		move.w	d1,d6
		bpl.s	.ay
		neg.w	d6
.ay:
		add.w	d6,d7
		cmp.w	#seq_arrive*2,d7
		shs		d7					; (0 = there)
		not.b	d7
		ext.w	d7
		add.w	d0,d0
		add.w	d1,d1
		move.w	seq_glidevNow,d6
		bsr.s	.clamp
		sub.w	obj_xvelo(a0),d0
		bsr.s	.ease
		add.w	d0,obj_xvelo(a0)
		move.w	d1,d0
		move.w	seq_glidevNow,d6
		bsr.s	.clamp
		sub.w	obj_yvelo(a0),d0
		bsr.s	.ease
		add.w	d0,obj_yvelo(a0)
		rts
; d0 = how far the velocity is off -> the change this frame: an 8th of it
; (no jerks), at least 1 so the last bit gets there too, seq_glidea at most
.ease:
		move.w	d0,d6
		asr.w	#3,d0
		bne.s	.eased
		tst.w	d6
		beq.s	.eased
		moveq	#1,d0
		tst.w	d6
		bpl.s	.eased
		moveq	#-1,d0
.eased:
		move.w	#seq_glidea,d6
.clamp:
		cmp.w	d6,d0
		ble.s	.c0
		move.w	d6,d0
.c0:
		neg.w	d6
		cmp.w	d6,d0
		bge.s	.c1
		move.w	d6,d0
.c1:
		rts

; d0/d1 = the way to where the shot is to meet the letter -> d0/d1 = the
; way to aim (from seq_aimDx/Dy): the shot's flight time is that distance
; / 2 px a frame (max + 3/8 min of |dx|, |dy|); meanwhile the text moves on
; seq_aimV/16 px a frame, and the shot carries the ship's own drift
seq_aimLead:
		move.w	d0,d4
		bpl.s	.ax
		neg.w	d4
.ax:
		move.w	d1,d5
		bpl.s	.ay
		neg.w	d5
.ay:
		cmp.w	d5,d4
		bhs.s	.big
		exg		d4,d5
.big:
		move.w	d5,d0				; 3/8 min
		add.w	d5,d5
		add.w	d0,d5
		lsr.w	#3,d5
		add.w	d5,d4
		lsr.w	#1,d4				; t
		cmp.w	#63,d4
		bls.s	.tOk
		moveq	#63,d4
.tOk:
		tst.w	seq_aimFt			; halfway from the last guess
		beq.s	.first
		add.w	seq_aimFt,d4
		lsr.w	#1,d4
.first:
		move.w	d4,seq_aimFt
		movem.w	seq_aimDx,d0/d1
		move.w	seq_aimV,d2
		mulu	d4,d2				; the text moves on meanwhile
		lsr.w	#4,d2
		sub.w	d2,d0
		move.w	obj_xvelo(a0),d5	; and the shot carries our drift
		muls	d4,d5
		asr.l	#7,d5
		sub.w	d5,d0
		move.w	obj_yvelo(a0),d5
		muls	d4,d5
		asr.l	#7,d5
		sub.w	d5,d1
		rts

; nose onto the letter at screen x d3 the text
; moves left d2/16 px a frame, and the shot carries the ship's own drift.
; -> d0 non zero when a shot fired now would pass within ~3 px of it.
; keeps d3
seq_aim:
		move.w	d3,-(a7)
		move.w	d2,seq_aimV
		move.w	d3,d0
		sub.w	obj_xc(a0),d0		; dx
		sub.w	obj_yc(a0),d1		; dy
		movem.w	d0/d1,seq_aimDx
		; the lead, from the shot's flight time - first from where the
		; letter is now, then three times more from where the guess before
		; says the shot meets it, each time halfway from the last flight
		; time to the new one (far off, the first guess is well out, and
		; going all the way it swings to and fro)
		clr.w	seq_aimFt
		bsr		seq_aimLead
		tst.b	seq_aimFine			; (the first attack: one guess, as ever)
		beq.s	.led
		bsr		seq_aimLead
		bsr		seq_aimLead
		bsr		seq_aimLead
.led:
		bsr		ai_crossdot			; d2 cross, d3 dot
		tst.l	d3
		ble.s	.coarse				; behind us
		move.l	d2,d4
		bpl.s	.cPos
		neg.l	d4
.cPos:
		cmp.l	#3<<15,d4			; cross >> 15 is the miss in pixels
		blo.s	.on
		tst.b	seq_onTarget		; lined up a moment ago: the nose stays
		beq.s	.notOn				; put until it is 6 px off, so it does
		cmp.l	#6<<15,d4			; not twitch with every step the text
		blo.s	.on					; makes
.notOn:
		sf		seq_onTarget
		cmp.l	#12<<15,d4
		blo.s	.fine
.coarse:
		sf		seq_onTarget
		moveq	#ai_turnrate,d1
		bra.s	.turn
.fine:
		moveq	#1,d1
.turn:
		tst.l	d2
		bmi.s	.sub
		bsr		obj_addangle
		bra.s	.off
.sub:
		bsr		obj_subangle
.off:
		moveq	#0,d0
		bra.s	.out
.on:
		st		seq_onTarget
		moveq	#1,d0
.out:
		move.w	(a7)+,d3
		rts

;---------------------------------------------
seq_turnTo:
		move.w	d0,d2
		sub.w	obj_angle(a0),d2	; -359..359
		bpl.s	.pos
		add.w	#360,d2				; 0..359
.pos:
		cmp.w	#180,d2
		blt.s	.signed
		sub.w	#360,d2				; -180..179
.signed:
		move.w	d2,d3
		bpl.s	.abs
		neg.w	d3
.abs:
		cmp.w	d1,d3
		bgt.s	.step
		move.w	d0,obj_angle(a0)
		moveq	#1,d0
		rts
.step:
		tst.w	d2
		bmi.s	.sub
		bsr		obj_addangle
		moveq	#0,d0
		rts
.sub:
		bsr		obj_subangle
		moveq	#0,d0
		rts

;---------------------------------------------
; fly to d0/d1 and stop there: rotate, burn, coast like ai_pilot. the
; velocity wanted is twice the distance (1/128 pixel a frame per pixel),
; up to seq_vmax. d2 = how close is close enough. -> d0 non zero once there
;---------------------------------------------
seq_steer:
		sub.w	obj_xc(a0),d0
		sub.w	obj_yc(a0),d1
		movem.w	d0/d1,seq_dx
		bsr		ai_manhattan
		cmp.w	d2,d5
		bhs.s	.go
		bsr		ai_speed
		cmp.w	#seq_arrivev,d0
		bhs.s	.go
		moveq	#1,d0
		rts
.go:
		movem.w	seq_dx,d0/d1
		move.w	seq_vmax,d4
		move.w	d4,d5
		neg.w	d5
		add.w	d0,d0
		cmp.w	d4,d0
		ble.s	.x0
		move.w	d4,d0
.x0:
		cmp.w	d5,d0
		bge.s	.x1
		move.w	d5,d0
.x1:
		add.w	d1,d1
		cmp.w	d4,d1
		ble.s	.y0
		move.w	d4,d1
.y0:
		cmp.w	d5,d1
		bge.s	.y1
		move.w	d5,d1
.y1:
		sub.w	obj_xvelo(a0),d0	; how far off the velocity is
		sub.w	obj_yvelo(a0),d1
		bsr		ai_manhattan
		tst.b	seq_corr
		bne.s	.corr
		cmp.w	#seq_corrstart,d5
		blo.s	.coast
		st		seq_corr
		st		ai_turning
.corr:
		cmp.w	#seq_corrstop,d5
		bhs.s	.steer
		sf		seq_corr
		bra.s	.coast
.steer:
		asr.w	#2,d0				; keep the muls well inside a long
		asr.w	#2,d1
		bsr		ai_crossdot
		tst.l	d3
		ble.s	.turn
		move.l	d2,d4
		bpl.s	.cPos
		neg.l	d4
.cPos:
		lsl.l	#2,d4				; inside ~14 degrees: burn
		cmp.l	d3,d4
		bhs.s	.turn
		sf		ai_turning
		moveq	#ai_thrust,d2
		bsr		obj_thrust
		bra.s	.coast
.turn:
		bsr		ai_turn
.coast:
		moveq	#0,d0
		rts

seq_on:			dc.b	0		; the sequence has the ship
seq_hits::		dc.b	0		; shots go for the scroll text
namesLooped::	dc.b	0		; every name has been up once (or F10)
seq_state:		dc.b	SQ_SEARCH
seq_sub:		dc.b	0		; a state's own step
seq_corr:		dc.b	0		; seq_steer is correcting the velocity
				even
seq_timer:		dc.w	0		; frames in the current state (or step)
seq_vmax:		dc.w	112		; seq_steer's top speed
seq_dx:			dc.w	0
seq_dy:			dc.w	0
seq_ax:			dc.w	0		; the spot it is flying to or holding
seq_ay:			dc.w	0
seq_wp:			dc.w	0		; search spots done
seq_wob:		dc.w	0		; hovering swing, degrees
seq_shots:		dc.w	0
seq_a1n:		dc.w	0		; letters to shoot out in the first attack
seq_gap:		dc.w	0		; frames to the next shot
seq_aimT:		dc.w	0		; frames spent aiming
seq_burst:		dc.w	1		; shots left in the burst
seq_claim:		dc.w	0		; letter shot at, screen x + scrollSteps
seq_claimT:		dc.w	0		; ... for this many more frames
seq_glidevNow:	dc.w	seq_glidev	; seq_glide's top speed
seq_ahead:		dc.w	0		; x of the first text ahead of the ship
seq_phase:		dc.w	0		; seq_run: SR_LAP, SR_APPROACH, SR_BREAK, SR_ROAM
seq_lastX:		dc.w	0
seq_tvT:		dc.w	0
seq_y0:			dc.w	0		; the height the run up started at
seq_dTotal:		dc.w	0		; ... and its length
seq_lapsLeft:	dc.w	0
seq_lateFires:	dc.w	0		; (testing)
seq_fireAtX:	dc.w	0
seq_fireMsgX:	dc.w	0
seq_runInit:	dc.b	0
finalAttackOn::	dc.b	0		; the last attack on the message (seq_run) - off
							; for now: the message runs through, see seq_repos
seq_dOn:		dc.b	0		; seq_drift has started
seq_dWin:		dc.b	0		; ... right after the hits (the pirouette)
seq_dLow:		dc.b	0		; ... its spots are under the bar now
seq_dFast:		dc.b	0		; ... the first spot briskly
seq_dThere:		dc.b	0		; DEFGO: at the Defender spot
seq_defReady::	dc.b	0		; DEFTEST: the message may come (scroller.s)
seq_tThere:		dc.b	0		; seq_tshoot: at its spot
seq_aimFine:	dc.b	0		; seq_aim: the lead guessed four times
				even
seq_wT:			dc.w	0		; seq_drift: frames on the way to a spot
seq_dspin:		dc.w	0		; ... degrees of the pirouette still to go
seq_lookT:		dc.w	0		; ... frames left of the look round
seq_lookA:		dc.w	0		; ... and where the nose looks
seq_dface:		dc.w	90		; Defender: which way the nose is
seq_lasers:		dc.w	0		; (testing) laser shots
seq_v0:			dc.w	0,0		; the velocity before this frame's steering
seq_burnLeft:	dc.w	0		; frames of thrust sound still to go
seq_tsx:		dc.w	0		; seq_tshoot: the spot it shoots from ...
seq_tsy:		dc.w	0
seq_tHit0:		dc.w	0		; ... and hitTotal when it began
seq_aimDx:		dc.w	0		; seq_aim: the way to the letter ...
seq_aimDy:		dc.w	0
seq_aimV:		dc.w	0		; ... and the text's speed
seq_aimFt:		dc.w	0		; ... and the flight time guessed
seq_diveT:		dc.w	0
seq_p0x:		dc.w	0		; the dive's curve: start ...
seq_p0y:		dc.w	0
seq_cx:			dc.w	0		; ... control point (on the row) ...
seq_p2x:		dc.w	0		; ... and end (on the row)
seq_torp:		dc.b	0		; the torpedo has gone
seq_shotsLive:	dc.b	0		; shots count against the text
				even
seq_boredT:		dc.w	0
seq_boredT2:	dc.w	0
				even
seq_onTarget:	dc.b	0		; seq_aim: lined up last frame
				even
seq_shipY::		dc.w	0		; the ship's raster line, for glitchFrame
seq_fired:		dc.w	0		; shots fired (for testing)
seq_jx:			dc.w	0		; ... and the spot's offset from it
;---------------------------------------------
ship_set:				;<set ship, keyboard control>
		lea		ship_struct,a0

		move.b	jkcode,d0
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
scaleLetters:
		tst.b	lettersScaled		; the coord tables are scaled in place, so a
		bne.s	.done				; second call would shrink them again
		st		lettersScaled
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
.done:
		rts

lettersScaled:
		dc.b	0
		even

scaleOffset:
		muls.w	#3,d0
		asr.w	#2,d0
		rts

; ast_x_start		= 80			; for big
; ast_x_offset 	= 32

; ast_x_start		= 70+((8*16)/2)			; for small
; ast_x_offset 	= 16

; --- word centring
; the game area copperlist uses DDFSTRT $28, which is 16 colour clocks
; earlier than the standard $38, so bitplane pixel 0 lands at hpos 97
; while DIWSTRT is still at $81 (129). the leftmost 32 pixels of the
; buffer are therefore behind the left border and the visible range is
; x = 32..351 - hence game_width 352, and hence a visible centre of 192.
; nudge this if you ever change DDFSTRT or the display window.

; d6 (byte) = character  ->  d6 (word) = how far x moves on to the next
; letter. anything that is not a..z gets the space width.
;---------------------------------------------
advanceOf:
		and.w	#$00ff,d6
		cmp.w	#' ',d6
		beq.s	.space
		sub.w	#'a',d6
		cmp.w	#26,d6
		blo.s	.lookup
.space:
		moveq	#26,d6				; last entry is the space
.lookup:
		add.w	d6,d6
		lea		letterAdvance(pc),a2
		move.w	(a2,d6.w),d6
		rts

;---------------------------------------------
; per letter spacing. the glyphs themselves are nearly all 24 pixels wide
; after scaleLetters takes its 3/4, so a flat 24 advance looks right for
; almost everything. the exceptions are the ones that used to look loose:
;
;     i  13 px wide      j  20      v  23      e, l  25      rest  24
;
; the slot was always 24, so a narrow letter simply sat in a gap. entries
; are written relative to ast_x_offset so the whole word still scales.
;---------------------------------------------
letterAdvance:
		dc.w	ast_x_offset		; a
		dc.w	ast_x_offset		; b
		dc.w	ast_x_offset		; c
		dc.w	ast_x_offset		; d
		dc.w	ast_x_offset		; e
		dc.w	ast_x_offset		; f
		dc.w	ast_x_offset		; g
		dc.w	ast_x_offset		; h
		dc.w	ast_x_offset-8		; i   narrow glyph, 13 px
		dc.w	ast_x_offset-3		; j   narrow glyph, 20 px
		dc.w	ast_x_offset		; k
		dc.w	ast_x_offset		; l
		dc.w	ast_x_offset		; m
		dc.w	ast_x_offset		; n
		dc.w	ast_x_offset		; o
		dc.w	ast_x_offset		; p
		dc.w	ast_x_offset		; q
		dc.w	ast_x_offset		; r
		dc.w	ast_x_offset		; s
		dc.w	ast_x_offset		; t
		dc.w	ast_x_offset		; u
		dc.w	ast_x_offset		; v
		dc.w	ast_x_offset		; w
		dc.w	ast_x_offset		; x
		dc.w	ast_x_offset		; y
		dc.w	ast_x_offset		; z
		dc.w	ast_x_offset+4		; space - word gaps want to be wider

		; init letter asteroids from names table
asteroids_init:
		; --- a fresh word is whole again, and the autopilot goes back to
		;     hovering beside it and lining up a pass along the row
		sf		word_scattered
		sf		ai_braking
		move.b	#AS_HOVER,ai_astate
		move.b	#HS_ROTATE,ai_hstate
		st		ai_turning
		sf		ai_sidePicked
		clr.w	ai_settleTick
		clr.w	ai_burst
		move.w	#-1,ai_target
		move.w	#-1,ai_offTarget
		sf		ai_mode
		sf		ai_home
		sf		ai_clear
		clr.w	ai_rush
		sf		ai_styleSet
		clr.w	ai_aimHold

		lea		names,a3
		add.l	nameOffset,a3
		move.l	(a3)+,a4
		tst.l	(a3)
		bne.s	.noEnd
		move.l	#0,nameOffset
		st		namesLooped			; the last name - the sequence comes next
		bra.s	.end
.noEnd:
		add.l	#4,nameOffset
.end:
		; --- centre the word. the distance from the first letter's centre
		;     to the last one's is the sum of every character's advance
		;     except the last, so walk the string and add them up.
		moveq	#0,d1				; running span
		move.l	a4,a3
		tst.b	(a3)
		beq.s	.spandone			; empty name
.spanloop:
		move.b	(a3)+,d6
		tst.b	(a3)
		beq.s	.spandone			; that was the last one - no advance after it
		bsr		advanceOf			; d6 char -> d6 advance
		add.w	d6,d1
		bra.s	.spanloop
.spandone:
		lsr.w	#1,d1
		move.w	#ast_x_center,d0	; x
		sub.w	d1,d0
.centred:
		move.w	#0,d2				; angle
		move.w	#0,d3				; x velo
		move.w	#0,d4				; y velo
		moveq	#0,d7				; wait

		; --- get random velocity
		move.l	d0,d6
		jsr		getRandomNumber
		and.l	#$1f,d0
		sub.l	#$10,d0
;		moveq	#0,d0		; test
		move.l	d0,d3
		jsr		getRandomNumber
		and.l	#$3,d0
		add.l	#$1,d0
		; moveq	#0,d0		; zero out test
		move.l	d0,d4
		move.l	d6,d0

.loop:
		move.w	#ast_y_start,d1		; y

		move.b	(a4)+,d6
		cmp.b	#' ',d6
		beq.s	.skip
		sub.b	#'a',d6
		ext.w	d6

		; obj_init copies the shape of type d5 out of coord_tabs, and the
		; letters follow 'letter' in there - so it copies the right letter
		; straight away. obj_name has to be 'letter' for all of them.
		moveq	#letter,d5
		add.w	d6,d5
		movem.l	d0-d7/a1-a6,-(a7)
		bsr		enemy_init
		movem.l	(a7)+,d0-d7/a1-a6
		move.w	#letter,obj_name(a0)

		move.w	#12,obj_collsize(a0)
		; move.w	d7,d6
		; lsl.w	#2,d6
		; move.w	d6,obj_angle(a0)
		move.w	#appear_frames,obj_appear(a0)
		move.w	#0,obj_angle(a0)
		move.w	#appear_scale0,obj_scale(a0)
		move.w	d7,obj_wait(a0)

		add.w	#appear_stagger,d7		; next wait
.skip:		
		move.b	-1(a4),d6			; the character we just placed
		bsr		advanceOf
		add.w	d6,d0

		tst.b	(a4)
		bne		.loop
		; dbf		d7,.loop

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
clearShipScratch:			;<wipe the 32x32 scan corner of the buffer>
		move.l	screenloc,a0
		moveq	#32-1,d0
.line:
		clr.l	(a0)
		lea		game_lineBytes(a0),a0
		dbf		d0,.line
		rts
;---------------------------------------------
ship_pcoords:				;<get point coords from ship lines>
		lea		ship_struct,a0
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
		mulu	#game_lineBytes,d1
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

; ship_pcoords renders the ship at (16,16) and reads it back out of the
; buffer, so the top left 32x32 corner has to be clean before and after.
; standalone mode got that from the double "clear" in initGame; when the
; scroller owns the buffer we have to do it ourselves.
		bsr	clearShipScratch
		bsr	ship_pcoords
		bsr	clearShipScratch

		lea	ship_struct,a0
		move.w	#ship_start_x,d0	;x
		move.w	#ship_start_y,d1	;y
		move.w	#0,d2			;angle
		move.w	#0,d3			;x velo
		move.w	#0,d4			;y velo
		moveq	#ship,d5
		bsr		obj_init
		rts
;---------------------------------------------
clear:					;<switch screens and clear>
		lea		$dff000,a6
		not.b	screenToggle
		bne.s	.s0
		move.w	#0,bp0+2
		move.w	#0,bp1+2
		move.l	#$78000,screenloc
		bra.s	.s1
.s0:		
		move.w	#$8000,bp0+2
		move.w	#$8000,bp1+2
		move.l	#$70000,screenloc
.s1:
		jsr		bbusy
		move.l	screenloc,$54(a6)
		move.l	#-1,$44(a6)
		move.l	#0,$64(a6)
		move.l	#$01000000,$40(a6)
		move.w	#(game_height<<6)+(game_lineBytes/2),$58(a6)
		rts
;---------------------------------------------
screenToggle:		
		dc.w	0
screenloc::		
		dc.l	$70000
;---------------------------------------------
; y -> y*game_lineBytes. built once, used by drawline and set_point.
		even
yOffTab:	ds.w	game_height

; raw p2 (2 words) + rotated p2 (2 words) of the previous line
lineCache:	ds.w	6		; raw p2, rotated p2, then sin and cos

buildYOffTab:
		lea		yOffTab,a0
		moveq	#0,d0
		move.w	#game_height-1,d1
.loop:
		move.w	d0,(a0)+
		add.w	#game_lineBytes,d0
		dbf		d1,.loop
		rts
;---------------------------------------------
;-------------------------------------
; set_line / drawline layout notes:
;   the four exits from the fast path are the only branches that cost
;   anything, so the dispatch blocks they jump to sit immediately in
;   front of set_line and stay reachable with short branches. the fast
;   path then falls straight through into drawline instead of branching
;   to it. everything on the clipping path is placed after drawline and
;   uses explicit .w branches, so nothing there can go out of range no
;   matter how much the routine grows.
;-------------------------------------
sl_cy1:
		tst.w	d1
		bmi.w	sl_y11			; below zero
		move.w	#game_height-1,d6	; past the limit
		bra.w	sl_y21
sl_cy2:
		tst.w	d3
		bmi.w	sl_y12			; below zero
		move.w	#game_height-1,d6	; past the limit
		bra.w	sl_y22
sl_cx1:
		tst.w	d0
		bmi.w	sl_x11			; below zero
		move.w	#game_width-1,d6	; past the limit
		bra.w	sl_x21
sl_cx2:
		tst.w	d2
		bmi.w	sl_x12			; below zero
		move.w	#game_width-1,d6	; past the limit
		bra.w	sl_x22
;-------------------------------------
set_line:
sl_again:
		; one unsigned compare per coordinate catches both "< 0" and
		; "> limit". a fully visible line costs four compares and four
		; untaken branches, then falls through into drawline.
		cmp.w	#game_height,d1
		bhs.s	sl_cy1
		cmp.w	#game_height,d3
		bhs.s	sl_cy2
		cmp.w	#game_width,d0
		bhs.s	sl_cx1
		cmp.w	#game_width,d2
		bhs.s	sl_cx2
		; --- falls through
;-------------------------------------
drawline:
		; output, 7 words per line (line_entry):
		;   BLTSIZE, buffer offset, BLTAPTL, BLTCON0, BLTCON1, BLTBMOD, BLTAMOD
		; BLTSIZE leads because it is never 0 or negative, so it doubles as
		; the entry type for objects_draw (0 = end of table, -1 = a point).
		; the offset is relative to the buffer, objects_draw adds screenloc.
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
		exg		d1,d0
		bra.s	.l4
.l2:		
		neg.w	d1
		cmp.w	d0,d1
		bge.s	.l5
		moveq	#$19,d7
		bra.s	.l4
.l5:		
		moveq	#$5,d7
		exg		d1,d0
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
		exg		d1,d0
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
						; BltStart nach d6
.l4:
		add.w	d3,d3
		and.w	#$fff0,d2
		lsr.w	#3,d2
		add.w	(a5,d3.w),d2			; + y*game_lineBytes -> buffer offset
						; Bltsize nach d5
		move.w	d0,d5
		addq	#1,d5
 		lsl.w	#6,d5
		addq	#2,d5
						; 2*y-x nach a3 und 4*y nach d1
		add.w	d1,d1
		move.w	d1,d3
		sub.w	d0,d3
		bpl.s	notneg
		bset	#6,d7
notneg:
		add.w	d1,d1
						; 4*y-4*x nach a5
		move.w	d1,d6
		lsl.w	#2,d0
		sub.w	d0,d6

		move.w	d5,(a6)+				; BLTSIZE
		move.w	d2,(a6)+				; offset
		move.w	d3,(a6)+				; BLTAPTL
		move.w	d4,(a6)+				; BLTCON0
		move.w	d7,(a6)+				; BLTCON1
		move.w	d1,(a6)+				; BLTBMOD
		move.w	d6,(a6)+				; BLTAMOD
		rts
;-------------------------------------
; clipping - off the fast path, all branches explicitly .w
sl_y11:
		moveq	#0,d6
		tst.w	d3			; y2 below zero as well ?
		bmi.w	sl_clpend	; then nothing to draw
		bsr.w	clipy
		move.w	d4,d0		; new x1
		moveq	#0,d1		; y1 = 0
		bra.w	sl_again
sl_y12:
		moveq	#0,d6
		bsr.w	clipy
		move.w	d4,d2		; new x2
		moveq	#0,d3		; y2 = 0
		bra.w	sl_again
sl_y21:
		cmp.w	d6,d3
		bgt.w	sl_clpend
		bsr.w	clipy
		move.w	d4,d0
		move.w	d6,d1
		bra.w	sl_again
sl_y22:
		bsr.w	clipy
		move.w	d4,d2
		move.w	d6,d3
		bra.w	sl_again
sl_x11:
		moveq	#0,d6
		tst.w	d2
		bmi.w	sl_clpend
		bsr.w	clipx
		move.w	d4,d1
		moveq	#0,d0
		bra.w	sl_again
sl_x12:
		moveq	#0,d6
		bsr.w	clipx
		move.w	d4,d3
		moveq	#0,d2
		bra.w	sl_again
sl_x21:
		cmp.w	d6,d2
		bgt.w	sl_clpend
		bsr.w	clipx
		move.w	d4,d1
		move.w	d6,d0
		bra.w	sl_again
sl_x22:
		bsr.w	clipx
		move.w	d4,d3
		move.w	d6,d2
		bra.w	sl_again
sl_clpend:				; line invisible
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
		beq.s	.flat				; (a line already clipped down to a
		divs	d5,d4				; point: a divide by zero, a guru)
		add.w	d2,d4
		rts
.flat:
		move.w	d2,d4
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
		beq.s	.flat
		divs	d5,d4
		add.w	d3,d4
		rts
.flat:
		move.w	d3,d4
		rts
;-------------------------------------------------------
set_point:
		cmp.w	#game_width-1,d0
		bhi.s	.npoint
		cmp.w	#game_height-1,d1
		bhi.s	.npoint

		; point entry: -1, buffer offset, bit number (3 words)
		move.w	#-1,(a6)+		;set flag for point (not line)
		add.w	d1,d1
		move.w	d0,d2
		not.w	d2				; bit, msb = leftmost (bset uses the low 3 bits)
		lsr.w	#3,d0
		add.w	(a5,d1.w),d0	; + y*game_lineBytes, yOffTab preloaded by obj_move
		move.w	d0,(a6)+
		move.w	d2,(a6)+
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
		add.l	d6,d6
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
		add.l	d6,d6
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
		add.l	d6,d6
		swap	d6				;new y
		move.w	d6,d3
		rts
;-------------------------------------------------------
shipcoll:
		lea		$dff000,a6
		jsr		bbusy
		move.l	screenloc(pc),a0
		lea		ship_struct,a1
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
		mulu	#game_lineBytes,d1
		add.w	d0,d1
		add.w	d1,a0

		move.l	a0,$4c(a6)
;		move.l	a0,$54(a6)
		move.l	#$04c00000,$40(a6)		;$5fc for or!
		move.l	#$f0000000,d4			; src mask
		lsr.l	d3,d4
		move.l	d4,$44(a6)
		move.w	#game_lineBytes-4,$62(a6)			; modulo
; 		move.w	#$0024,$62(a6)
;		move.w	#$0024,$66(a6)
		move.w	#-1,$74(a6)
		move.w	#5*64+2,$58(a6)

		jsr		bbusy

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
		move.l	screenloc,d6			; the entries hold buffer offsets

		lea		$dff000,a6
		; blitter nasty stays set for the whole batch and the wait is inlined.
		; bbusy cost a jsr/rts plus two DMACON writes on every single line.
		move.w	#$8400,$96(a6)
.wait0:	btst	#6,2(a6)
		bne.s	.wait0
		move.w	#game_lineBytes,$60(a6)
		move.w	#game_lineBytes,$66(a6)
		; move.w	#$28,$60(a6)
		; move.w	#$28,$66(a6)
		move.l  #$ffff0000,$44(a6)
		move.w	#$8000,$74(a6)
		move.w	#-1,$72(a6)
.objects:
		move.w	(a0)+,d5		; BLTSIZE, -1 for a point, -2 for a letter's
		beq.s	.end			; cached lines, 0 = end of table
		bpl.s	.line			;point or line?
		addq.w	#1,d5
		bne.s	.cached
					;<draw point>
		move.w	(a0)+,a4
		add.l	d6,a4
		move.w	(a0)+,d3
		bset	d3,(a4)
		bra.s	.objects
.line:
					;<draw line>
		move.w	(a0)+,a4		; offset (sign extended, always < $8000)
		add.l	d6,a4
		movem.w	(a0)+,d1-d4/a5	; BLTAPTL, BLTCON0, BLTCON1, BLTBMOD, BLTAMOD

.wait1:	btst	#6,2(a6)
		bne.s	.wait1
		move.l	a4,$48(a6)
		move.l	a4,$54(a6)
		move.w	d1,$52(a6)
		movem.w	d2/d3,$40(a6)
		movem.w	d4/a5,$62(a6)
		move.w	d5,$58(a6)		;zeinchen der linie
		bra.s	.objects

; --- start and end of a run of line entries in a letter's cache
.cached:
		move.l	(a0)+,a1
		move.l	(a0)+,a3
.cline:
		move.w	(a1)+,d5
		move.w	(a1)+,a4
		add.l	d6,a4
		movem.w	(a1)+,d1-d4/a5
.wait2:	btst	#6,2(a6)
		bne.s	.wait2
		move.l	a4,$48(a6)
		move.l	a4,$54(a6)
		move.w	d1,$52(a6)
		movem.w	d2/d3,$40(a6)
		movem.w	d4/a5,$62(a6)
		move.w	d5,$58(a6)
		cmp.l	a3,a1
		blo.s	.cline
		bra.s	.objects
.end:
		move.w	#$0400,$96(a6)	; blitter nasty off
		rts
;----------------------------------------
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
linetab:	ds.b	340*line_entry	; letters, explosions, ship and shots all in
							; one table now (updateGameLogic)

; a5: pointer to copperlist 
setupStarfield::
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

		bsr		setupStarfieldPointers
		rts

setupStarfieldPointers::
		move.l	#slst0,d0
;		lea		spoint+2,a0
		addq	#2,a5
		move.w	d0,4(a5)
		swap	d0
		move.w	d0,(a5)
		addq	#8,a5
		move.l	#slst1,d0
		move.w	d0,4(a5)
		swap	d0
		move.w	d0,(a5)
		addq	#8,a5
		move.l	#slst2,d0
		move.w	d0,4(a5)
		swap	d0
		move.w	d0,(a5)
		addq	#8,a5
		move.l	#slst3,d0
		move.w	d0,4(a5)
		swap	d0
		move.w	d0,(a5)
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
		jsr		getRandomNumber
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
; 		cmp.w	#$cc,d0			; scrollerbar = cf - e0
; 		ble		.noScrollerBar
; 		cmp.w	#$e0,d0
; 		bhi		.noScrollerBar
; 		add.w	#$22,d0
; 		add.w	#$22,d2
; .noScrollerBar

		addq	#2,d0		; next v start
		addq	#2,d2		; next v stop
		dbf		d7,.loop

		move.l	#0,(a0)+	; end of sprite list
		rts
;---------------------------------------------
; the stars: four layers, the front one at starV (8.8 px a frame, + is to
; the right), each one behind it at half the speed of the one in front.
; starV eases to starTarget by starAcc a frame. a call of starsFwd moves
; the front layer a pixel right and the ones behind it a half, a quarter
; and an eighth (each star's fraction rides in its SH0 bit), starsBack the
; same to the left; this frame's share of starV says how many calls.
; the dots (scroller.s accelX) go with them: their wind turns round with
; the stars, and while the stars change speed the dots get the same push,
; as if it were the ship that sped up or slowed down

updateStars::
		move.w	starV,d1
		move.w	starTarget,d0
		sub.w	d1,d0				; how far off
		move.w	starAcc,d2
		cmp.w	d2,d0
		ble.s	.s0
		move.w	d2,d0
.s0:
		neg.w	d2
		cmp.w	d2,d0
		bge.s	.s1
		move.w	d2,d0
.s1:
		add.w	d0,d1				; d0: the change this frame
		move.w	d1,starV
		bne.s	.going				; stood still, and to turn round: the
		tst.b	starTurn			; other way now, at seq_defStar
		beq.s	.going
		sf		starTurn
		move.w	#seq_defStar,starTarget
		move.w	#seq_starAccD,starAcc
.going:
		; the dots' wind, in units of 1<<9 (drawPoints keeps each dot's glow
		; step in the low bits of its x speed, so the low 9 bits of accelX
		; must stay clear): 3 at starV 256; the other way round only one a
		; pixel of starV (they go with the stars, but glow out first),
		; and the change this frame on top
		move.w	d1,d2
		bmi.s	.wBack
		muls	#3,d2
		asr.w	#8,d2
		bra.s	.w
.wBack:
		asr.w	#8,d2
.w:
		move.w	d0,d3
		asr.w	#1,d3
		add.w	d3,d2
		ext.l	d2
		moveq	#9,d3
		asl.l	d3,d2
		move.l	d2,accelX
		add.w	starFrac,d1			; whole pixels this frame
		move.w	d1,d0
		asr.w	#8,d0
		move.w	d0,d2
		lsl.w	#8,d2
		sub.w	d2,d1
		move.w	d1,starFrac
		tst.w	d0
		beq.s	.out
		bmi.s	.back
.fwd:
		cmp.w	#3,d0				; three: four now, two next frame (four or
		bne.s	.f4					; two in one go are as cheap as one)
		moveq	#4,d0
		sub.w	#256,starFrac
.f4:
		cmp.w	#4,d0
		blt.s	.f2
		subq.w	#4,d0
		move.w	d0,-(a7)
		bsr		starsFwd4
		move.w	(a7)+,d0
		bne.s	.fwd
		rts
.f2:
		cmp.w	#2,d0
		blt.s	.f1
		bra		starsFwd2
.f1:
		bra		starsFwd
.back:
		cmp.w	#-3,d0
		bne.s	.b4
		moveq	#-4,d0
		add.w	#256,starFrac
.b4:
		cmp.w	#-4,d0
		bgt.s	.b2
		addq.w	#4,d0
		move.w	d0,-(a7)
		bsr		starsBack4
		move.w	(a7)+,d0
		bne.s	.back
		rts
.b2:
		cmp.w	#-2,d0
		bgt.s	.b1
		bra		starsBack2
.b1:
		bra		starsBack
.out:
		rts

starV::			dc.w	256
starTarget::	dc.w	256
starAcc::		dc.w	0
starFrac:		dc.w	0
starTurn::		dc.b	0		; once they stand: round the other way
				even

; the star lists are walked four entries at a time. bchg tests and toggles
; the SH0 bit in one instruction (Z comes from the ORIGINAL bit), which
; replaces an eor.b plus a btst on the same byte - 20 cycles instead of
; 32, per layer, per star. a star of the layer behind is only moved when
; the one in front carried over (forwards: its SH0 bit went 1 -> 0; back:
; 0 -> 1, a borrow). stars_count must stay a multiple of 4.
STARS	macro					; \1 beq (forwards) or bne (back), \2 add/sub
		moveq	#1,d0
		move.w	#(stars_count/4)-1,d7
		lea		slst0+1,a0
.loop\@:
		bchg	#0,2(a0)
		\1.s	.n0\@
		\2.b	d0,(a0)
		bchg	#0,stars_count*8+0+2+4(a0)
		\1.s	.n0\@
		\2.b	d0,stars_count*8+0+4(a0)
		bchg	#0,stars_count*16+0+2+8(a0)
		\1.s	.n0\@
		\2.b	d0,stars_count*16+0+8(a0)
		bchg	#0,stars_count*24+0+2+12(a0)
		\1.s	.n0\@
		\2.b	d0,stars_count*24+0+12(a0)
.n0\@:
		bchg	#0,8+2(a0)
		\1.s	.n8\@
		\2.b	d0,8(a0)
		bchg	#0,stars_count*8+8+2+4(a0)
		\1.s	.n8\@
		\2.b	d0,stars_count*8+8+4(a0)
		bchg	#0,stars_count*16+8+2+8(a0)
		\1.s	.n8\@
		\2.b	d0,stars_count*16+8+8(a0)
		bchg	#0,stars_count*24+8+2+12(a0)
		\1.s	.n8\@
		\2.b	d0,stars_count*24+8+12(a0)
.n8\@:
		bchg	#0,16+2(a0)
		\1.s	.n16\@
		\2.b	d0,16(a0)
		bchg	#0,stars_count*8+16+2+4(a0)
		\1.s	.n16\@
		\2.b	d0,stars_count*8+16+4(a0)
		bchg	#0,stars_count*16+16+2+8(a0)
		\1.s	.n16\@
		\2.b	d0,stars_count*16+16+8(a0)
		bchg	#0,stars_count*24+16+2+12(a0)
		\1.s	.n16\@
		\2.b	d0,stars_count*24+16+12(a0)
.n16\@:
		bchg	#0,24+2(a0)
		\1.s	.n24\@
		\2.b	d0,24(a0)
		bchg	#0,stars_count*8+24+2+4(a0)
		\1.s	.n24\@
		\2.b	d0,stars_count*8+24+4(a0)
		bchg	#0,stars_count*16+24+2+8(a0)
		\1.s	.n24\@
		\2.b	d0,stars_count*16+24+8(a0)
		bchg	#0,stars_count*24+24+2+12(a0)
		\1.s	.n24\@
		\2.b	d0,stars_count*24+24+12(a0)
.n24\@:
		lea		32(a0),a0
		dbf		d7,.loop\@
		rts
		endm

starsFwd:
		STARS	beq,add
starsBack:
		STARS	bne,sub

; two pixels in one go: the front layer straight on by a whole HSTART
; step (its SH0 bit stays as it is), the ones behind it as one call would
; move the layer in front of them
STARS2	macro					; \1 beq (forwards) or bne (back), \2 add/sub
		moveq	#1,d0
		move.w	#stars_count-1,d7
		lea		slst0+1,a0
.loop\@:
		\2.b	d0,(a0)
		bchg	#0,stars_count*8+0+2+4(a0)
		\1.s	.n\@
		\2.b	d0,stars_count*8+0+4(a0)
		bchg	#0,stars_count*16+0+2+8(a0)
		\1.s	.n\@
		\2.b	d0,stars_count*16+0+8(a0)
		bchg	#0,stars_count*24+0+2+12(a0)
		\1.s	.n\@
		\2.b	d0,stars_count*24+0+12(a0)
.n\@:
		addq.l	#8,a0
		dbf		d7,.loop\@
		rts
		endm

starsFwd2:
		STARS2	beq,add
starsBack2:
		STARS2	bne,sub

; four pixels in one go: the front layer two HSTART steps, the one behind
; it one, the next one pixel (its SH0 bit) - and the last a half: on when
; that one carried
STARS4	macro					; \1 beq (forwards) or bne (back), \2 add/sub
		moveq	#1,d0
		moveq	#2,d1
		move.w	#stars_count-1,d7
		lea		slst0+1,a0
.loop\@:
		\2.b	d1,(a0)
		\2.b	d0,stars_count*8+0+4(a0)
		bchg	#0,stars_count*16+0+2+8(a0)
		\1.s	.n\@
		\2.b	d0,stars_count*16+0+8(a0)
		bchg	#0,stars_count*24+0+2+12(a0)
		\1.s	.n\@
		\2.b	d0,stars_count*24+0+12(a0)
.n\@:
		addq.l	#8,a0
		dbf		d7,.loop\@
		rts
		endm

starsFwd4:
		STARS4	beq,add
starsBack4:
		STARS4	bne,sub
		
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

; ---------------

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
wordGapTimer:	dc.w	wordGap
shot_times:		ds.w	16
shot_structs:	ds.b	obj_len*16
enemy_con:		dc.l	0
collCount:		dc.w	0		; entries in collList this frame
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
		dc.w -7-8,-16,10-8,-13
		dc.w 10-8,-13,3-8,17
		dc.w 3-8,17,-7-8,-16

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
		dc.w 1,-7,15,-16
		dc.w 15,-16,9,-2
		dc.w 9,-2,16,17
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
		dc.w 12,-16,6,5
		dc.w 6,5,17,10
		dc.w 17,10,-12,17
		dc.w -12,17,-3,-3
		dc.w -3,-3,-12,3
		dc.w -12,3,-16,-8

;---------------------------------------------
; only the CPU touches these, so they need not be in chip memory, and as
; bss they cost nothing in the executable
		section	"gamebss",bss
enemy_cache:	ds.b	cache_len*32	; one line cache per enemy slot
collList:		ds.b	coll_len*32		; shootable boxes, see updateEnemies
