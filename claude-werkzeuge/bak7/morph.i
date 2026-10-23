;======================================================================
; morph.i - the Elite ending: "Elite Attack". included at the end of
; asteroids.s, switched by switches.i elite3.
;
; the world changes from Asteroids (a tiny ship seen from above, very far
; off) to Elite (endless space, mighty sizes), and the scale is told by
; speeds: the stars, which are endlessly far, rush by faster and faster,
; while the fighter - huge - moves through the same space as we do.
;
;   UNFOLD  (live) the Defender ship, small and far off, unfolds into the
;           Quadlite Thrust fighter in 3D lines (16 points, from the flat
;           arrow; part by part with a smoothstep, new lines glow; towards
;           the end the back lines go - backface culling)
;   HOLD    (live) it settles and waits for the next bar of the music
;   PLAY    the flight, worked out beforehand frame by frame (the "sim"
;           below) and only played here: the points on the screen, which
;           faces are seen, the glow, the torpedoes, the sounds. so the
;           ship is drawn in every frame, at 50 Hz
;
; the flight (all of it on the beat grid of the music: 24 frames a beat,
; the high points on beats):
;   OPEN    Zeronine wakes up: the system check (the wings rock twice), a
;           sag, the engine fires (the glow flares, the sound comes in, the
;           stars go into depth), a feint left - and hard round to the
;           right until it faces us, a little overshoot, then it sits
;   PASS    we pick up speed and come up to it, it comes on slowly; then it
;           sees us: the afterburner, a dip, and hard up into a loop - we
;           catch up with it as it climbs: out at the top over our heads
;   LOOP    it is behind us, flying a loop (unseen, heard)
;   ENTRY   it comes down from the upper right corner, faster than we are,
;           and settles ahead of us; we speed up with it (top speed)
;   ESCORT  it drops its torpedoes (they fall, then their engines fire)
;           and flies ahead of us: the maneuvers of morphEscList
;   BREAK   3 s before the first hit: like a fighter it turns hard to the
;           right, down and round, and thunders past us on the lower right
;   (the torpedoes reach the logo 15 s after their drop; the hits: later)
;
; the ship is a body in the world: its middle (morphSX/SY/SZ, 1/16 units,
; ahead of the eye), turned by roll/pitch/yaw/tilt/heading; a point on the
; screen is the stars' middle + (S + p) * lens / (SZ - z) - the same
; perspective as the stars'. flying, its nose goes along its way through
; the world (our speed added), and it banks by how hard it turns.
;
; the sim runs in the VBL's time left over (morphSimRun, at the end of
; updateScroller, until raster line morphSimLine), from the rest after the
; last words on, in small steps; the play waits for it if it ever had to
;======================================================================

		section "code",data,chip

morphLen	= 168		; frames from the flat arrow to the fighter
morphCull	= 134		; frames: from here on the back lines are hidden
morphGlow	= 6			; frames a part's lines glow either side of its end
morphRoll	= 46		; degrees the ship rolls over (its right wing up)
morphPitch	= 13		; degrees its nose dips
morphZ0		= 1024*16	; the ship's depth (1/16 units) - far off
morphF		= 288		; the lens: 0.28 px a unit at morphZ0 (the fighter
						; 72 units long: 20 px, twice the Asteroids ship)
morphG0		= 131		; 8.8: the arrow at the start (the game's size)
morphVX		= 177		; the stars' middle (warp.i warpCx/warpCy, on the game's
						; plane 17 px further right): where
morphVY		= 134		; we fly to
morphNP		= 16		; points
morphNE		= 23		; edges
morphNF		= 9			; faces

; --- the music's grid (CopperCabana: a row every 2 frames, 12 rows a beat,
;     the kick on beats 1 and 3 of a bar of 4 - the patterns are bars)
morphBeat	= 24		; frames a beat
morphBar	= 4*morphBeat
morphCueTicks = $300	; (music.s musicPalTicks: its tick counter's round)
morphHoldMin = 20		; frames the fighter holds still at least
morphHoldMax = morphHoldMin+3*morphBar	; ... at most (no music: on anyway)
	ifeq	escortMux
morphSimLine = 222		; the sim works on till this raster line (a step is
						; 6k cycles at most: the frame stays below 117k)
	else
morphSimLine = 218		; (escortMux: its steps a little longer - the
	endc				; torpedoes' rows; it is through long before the play)

; --- the pass
morphPassT	= 400		; frames: the stars from slow to top speed (u^3)
morphVzPass	= 20		; the stars at the end of it: this many times the start's
morphClose0	= 16		; we gain on it (1/16 units a frame): at first ...
morphClose1	= 62		; ... and at the end (it flies our way, a little slower)
morphPassBehind = 150*16	; ... heard on until it is this far behind us
morphJkZ	= 780		; units: this near (on a beat) it sees us - two heavy
morphJk1	= 3*morphBeat	; swerves: left (frames) ...
morphJkL	= -60*16	; ... this far (1/16 units)
morphLrX	= 30*16		; ... then right and down to here (1/16 units:
morphLrY	= 20*16		; low on the right), where it waits
morphJkT	= 8*morphBeat	; frames from the swerves to the afterburner
morphJk2	= morphJkT-morphBeat	; (the swerve right: frames)
morphEvA	= 2*morphBeat	; (simEvade) frames it takes to get faster than we
morphEvB	= 24		; are, by this (1/16 units a frame)
morphEvD	= 32		; frames: then the dip, the nose down to
morphEvDip	= -5*16		; ... this (1/16 degrees)
morphEvG	= 48		; frames: then up, the turn building up to
morphEvW	= 40		; ... this (1/16 degrees a frame: 2.5)
morphEvLean	= 40*16		; the loop leans over to the left this far (1/16
						; degrees: rolling into it from the dip on)
morphEvThMax = 200*16	; (the nose no further round: it is gone by then)
morphEvLoss	= 179		; going up it loses (1/512 units a frame, a frame:
						; heavy - a loop costs speed)
morphFlyMin	= 2*4096	; (simFly) its way ahead never slower than this
						; (1/4096 units a frame): its nose stays ahead
; --- the loop and the attack run
morphLoopT	= 144		; frames it is behind us, at least (then: on a beat)
morphVzLoop	= 6			; ... we ease off to this speed meanwhile,
morphVzDown	= 24		; ... this much a frame
morphAtkRoll = -60		; degrees: it comes out of the loop banked (left)
morphEntryT	= 5*morphBeat	; frames: in from the upper right corner (x, y, z
morphEX0	= 75*16			; 1/16 units) ...
morphEY0	= -52*16
morphEZ0	= 30*16
morphEX1	= -12*16		; ... to its place ahead of us
morphEY1	= 10*16
morphEZ1	= 230*16
	ifeq	escortMux
morphBreakLead = 6*morphBeat	; frames from the break to the first hit
morphBreakAt = morphTorpHitAge-morphBreakLead	; (frames into the escort)
	else
morphBreakLead = 16*morphBeat	; frames from the break to the first hit (7.7 s)
morphBreakAt = morphTorpHitAge-morphEntryT+morphMxDrop0-morphBreakLead
	endc
morphBreakT	= 4*morphBeat	; frames of the turn (eased in and out: heavy)
morphBreakA	= 180		; degrees it turns: round, back at us
morphBreakV	= 4*16		; its speed in the turn (1/16 units a frame; ours: 7)
morphBreakXY = 90		; ... its turn tilted: this much (%) to the right,
morphBreakDn = 40		; ... this much down
morphBreakRoll = 75		; degrees banked (right), then
morphBreakOut = 25		; ... this much as it comes round
morphBreakTilt = -18	; the nose down
morphNear	= 25*16		; nearer than this it is past us: not drawn
morphClipZ	= 240		; a point nearer the eye than this (1/16): not drawn
; --- the torpedoes
morphTorpN	= 3			; torpedoes
morphTorpGap = 3*morphBeat/2	; frames from one drop to the next (on the grid)
morphTorpBelow = 8*16	; dropped this far below the ship's middle
morphTorpDropT0 = morphBeat	; frames they fall at least before their engines fire
morphTorpDropV = 77		; ... falling (1/256 units a frame) ...
morphTorpDropG = 8		; ... faster and faster (a frame)
morphTorpDropT1 = 2*morphBeat	; ... at most (else: once this far from the ship -
morphTorpFireD = 45		; |dx| + |dy| + |dz|, units: it maneuvers)
morphTorpAcc = 6		; then they speed up (1/256 units a frame, a frame)
	ifeq	escortMux
morphTorpHitAge = 31*morphBeat	; frames from the drop to the hit (14.9 s)
	else
; (switches.i escortMux) the torpedoes go in the entry already, half a beat
; apart, while the fighter is still high: they fall a little, cold, and their
; engines fire once it is safely below them (their glows and the
; afterburner's share the sprites, one above the other). the hits as they
; were: the first drop's hit later by what it is earlier, each next one
; 1.25 beats later than that (they were 1.5 beats apart, the drops are a
; quarter beat now: all of them out before the fighter is down)
morphMxDrop0 = morphBeat/2	; frames into the entry: the first drop
morphMxDropGap = morphBeat/4	; ... the next ones
morphTorpHitAge = 31*morphBeat+morphEntryT-morphMxDrop0	; (the first's)
morphMxHitStep = morphTorpGap-morphMxDropGap	; ... each next one's: longer
morphMxDropV = 20		; their fall (1/256 units a frame) ...
morphMxDropG = 1		; ... faster and faster (a frame)
morphMxFireT1 = 4*morphBeat	; their engines fire at the latest (simMxLate)
morphMxGap	= 2			; lines between a torpedo's glow and the afterburner's
						; rows at least (besides the one the sprite needs)
TF_NOSPR	= 4			; (flags) its glow would touch the afterburner's: none
	endc
morphTorpR	= 8*16		; their size (radius, 1/16 units)
morphTorpHissT = 40		; frames their hiss is heard after the whoosh
	ifeq	escortMux
MSPR_LEN	= 4+15*4+4	; (morphSprFrame) a sprite: control, 15 rows, the end
	else
MSPR_LEN	= 2*(4+15*4)+4	; (morphSprFrame) a sprite: two glows, the end
	endc
MSPR_RMAX	= 7			; ... a glow's R at most (the torpedoes, the small flame)
AB_TM		= 16		; (morphSprFrame) frames from the afterburner's chain
						; (a power of 2: shifts for it)
						; to the small flame (the torpedoes), and back
AB_FLICK	= 1			; the chain's glows flicker (a 4 frame round): 0 off
AB_DEBUG	= 0			; 1: the line from the plate's middle to the
						; flame's tip, drawn in the playfield
; --- the flight
morphKV		= 11		; our speed (1/16 units a frame) = the stars' (8.8) * this
						; >> 8: 7 units a frame at top speed
morphVzMax	= 10		; the stars at top speed: this many times the start's
morphSpK	= 4			; the spring its place follows: pull, damping (1/1024) -
morphSpD	= 80		; heavy: it takes its time, overshoots a little, sits
morphSpK2	= 3			; ... from the pass on heavier still (as damped)
morphSpD2	= 70
morphTurnK	= 4			; (MV_TURNTO) the heading's spring
morphTurnD	= 42
morphTurnBank = 5		; ... its bank by the turn's speed
morphClimbTilt = 22		; (MV_CLIMB) degrees the nose comes up
morphClimbBank = 30		; ... and it banks into the turn
morphKBank	= 34		; the bank from how hard it turns (1/64 of 1/16 degrees
						; per 1/4096 units a frame^2 across)
morphBankMax = 70*16	; (1/16 degrees)
; --- the sound
morphSndShip = 9000		; the engine's loudness (volume times units away)
morphSnd2V	= 32		; ... this loud on: on channel 3 as well
morphPerShip = 400		; ... its pitch (period, standing still)
morphSndTorp = 6000		; the torpedoes' loudness
morphPerTorp = 170		; ... their pitch
morphParkZ	= 170		; new stars this much further off for each step of speed
morphPark0	= 400		; ... and from the pass on this much anyway
morphParkMax = 1930		; ... at most (as it was at the old top speed)

SFX_DROP	= 7			; (music.s: a torpedo drops out - a clunk)
SFX_IGNITE	= 8			; (music.s: its engine fires - a whoosh)
SFX_SHIPIGN	= 9			; (music.s: the fighter's engine fires)
SFX_BIGBOOM	= 6			; (music.s: the Defender's big boom)

MP_UNFOLD	= 0
MP_HOLD		= 1
MP_PLAY		= 2
MP_GONE		= 3

; --- the maneuvers: a list of blocks, each: type, frames, p1, p2, thrust
;     (0..256: the engine's sound and glow). reorder them as you like
MV_WIGGLE	= 0			; the wings rock: p1 degrees, p2 times
MV_SAG		= 1			; sags p1 units and catches itself, rolls onto its
						; side, the nose p2 degrees away (to the side view)
MV_IGNITE	= 2			; the engine fires: a lurch of p1 units
MV_FEINT	= 3			; banks p1 degrees left, nose p2 degrees (- left)
MV_TURNTO	= 4			; hard round to heading p1 (180: facing us)
MV_FISH		= 5			; fishtail: p1 units across, p2 frames a swing (about)
MV_BARREL	= 6			; barrel roll round its way: p1 units, p2 1 right,
						; -1 left
MV_BACK		= 7			; falls back p1 units, then pulls away p2
MV_KNIFE	= 8			; knife edge: p1 degrees (+ left)
MV_HOLD		= 9			; steady
MV_VROLL	= 10		; a quick roll: p2 1 right, -1 left
MV_SALUTE	= 11		; the wings rock: p1 degrees, p2 times
MV_MOVE		= 12		; its place in the escort: p1 units across, p2 ahead
MV_CLIMB	= 13		; pulls up and turns to heading p1, climbing p2 units
MV_WEAVE	= 14		; a slow weave: p1 units across, p2 rounds
mv_len		= 10
MV		macro
		dc.w	\1,\2,\3,\4,\5
		endm

; Zeronine wakes up (from the fighter as it unfolded, still, seen from
; above: 16 beats; the sum of these is where the pass starts)
morphOpenList:
		MV		MV_WIGGLE,2*morphBeat,28,2,0		; the system check
		MV		MV_SAG,2*morphBeat,16,-25,0			; it sags, onto its side
		MV		MV_IGNITE,2*morphBeat,12,0,256		; the engine fires (bar 2)
		MV		MV_FEINT,2*morphBeat,30,-24,96		; a feint left ...
		MV		MV_CLIMB,8*morphBeat,0,22,192		; ... then it pulls up and turns
		dc.w	-1									; away into our way, slowly
; the escort, from the first drop on (the break comes after morphBreakAt
; frames, whatever is left: a list too short holds on the last place)
morphEscList:
	ifne	escortMux					; (the torpedoes gone already, the break
		MV		MV_WEAVE,3*morphBeat,24,1,96		; 15 beats on: 7.7 s before the
		MV		MV_BARREL,4*morphBeat,18,1,256		; first hit)
		MV		MV_KNIFE,3*morphBeat,90,0,128
		MV		MV_MOVE,3*morphBeat,-50,160,160
		MV		MV_VROLL,2*morphBeat,0,1,192
		dc.w	-1
	else
		MV		MV_WEAVE,4*morphBeat,24,1,96		; (the drops on its beats)
		MV		MV_BARREL,4*morphBeat,18,1,256
		MV		MV_BACK,4*morphBeat,90,40,128
		MV		MV_KNIFE,4*morphBeat,90,0,128
		MV		MV_BARREL,4*morphBeat,18,-1,256
		MV		MV_MOVE,3*morphBeat,-50,160,160		; (up left, away: room for
		MV		MV_VROLL,2*morphBeat,0,1,192		; the victory roll; the break)
		dc.w	-1
	endc

; the parts: start frame, frames to unfold
morphParts:	dc.w	0,46			; 0 the arrow grows
			dc.w	36,46			; 1 the hull opens, the ship rolls
			dc.w	76,46			; 2 the wing guns
			dc.w	99,46			; 3 the canopy
			dc.w	122,46			; 4 the engine plate

; a point: start (on the arrow), end (the fighter) - x forward, y towards
; the right wing (down on the screen), z up - and its part
MPT		macro
		dc.w	\1,\2,\3,(\4)-(\1),(\5)-(\2),(\6)-(\3),\7
		endm
morphPts:
		MPT		28,0,0,40,0,0,0				; 0 nose
		MPT		-14,0,0,-24,-12,9,1			; 1 back, top left
		MPT		-14,0,0,-24,12,9,1			; 2 back, top right
		MPT		-14,0,0,-24,-12,-6,1		; 3 back, bottom left
		MPT		-14,0,0,-24,12,-6,1			; 4 back, bottom right
		MPT		-35,-28,0,-32,-38,0,0		; 5 wing tip left
		MPT		-35,28,0,-32,38,0,0			; 6 wing tip right
		MPT		-14,0,0,-24,-7,5,4			; 7 engine plate
		MPT		-14,0,0,-24,7,5,4			; 8
		MPT		-14,0,0,-24,7,-2,4			; 9
		MPT		-14,0,0,-24,-7,-2,4			; 10
		MPT		8,0,0,16,0,3,3				; 11 canopy front (the canopy lies
		MPT		-6,0,0,-6,-6,6,3			; 12 canopy back left  on the top face,
		MPT		-6,0,0,-6,6,6,3				; 13 canopy back right a window in it)
		MPT		-35,-28,0,-6,-38,0,2		; 14 gun left
		MPT		-35,28,0,-6,38,0,2			; 15 gun right
mp_len	= 14

; an edge: two points (as offsets into morphXY), the two faces it is on
; (-1 none), its part, and whether it is one of the arrow's own lines
MED		macro
		dc.b	(\1)*4,(\2)*4,\3,\4,\5,\6
		endm
morphEdges:
		MED		0,1,0,1,1,0
		MED		0,2,0,2,1,0
		MED		0,3,3,4,1,0
		MED		0,4,3,5,1,0
		MED		0,5,1,4,0,1
		MED		0,6,2,5,0,1
		MED		1,2,0,6,1,0
		MED		3,4,3,6,1,0
		MED		1,3,6,7,1,0
		MED		2,4,6,8,1,0
		MED		1,5,1,7,1,1
		MED		3,5,4,7,1,0
		MED		2,6,2,8,1,1
		MED		4,6,5,8,1,0
		MED		7,8,6,-1,4,0
		MED		8,9,6,-1,4,0
		MED		9,10,6,-1,4,0
		MED		10,7,6,-1,4,0
		MED		11,12,0,-1,3,0
		MED		11,13,0,-1,3,0
		MED		12,13,0,-1,3,0
		MED		5,14,1,4,2,0
		MED		6,15,2,5,2,0
me_len	= 6
; the same edges: their faces as bits (all of them: on no face, always)
morphEM:
		dc.w	$0003,$0005,$0018,$0028,$0012,$0024,$0041,$0048
		dc.w	$00c0,$0140,$0082,$0090,$0104,$0120
		dc.w	$0040,$0040,$0040,$0040,$0001,$0001,$0001	; (the canopy: on the top)
		dc.w	$0012,$0024		; (the guns: with their wing's faces)

; a face: three of its corners; (b-a) x (c-a) points out of the hull
morphFaces:
		dc.b	0*4,2*4,1*4			; 0 top
		dc.b	0*4,1*4,5*4			; 1 top left
		dc.b	0*4,6*4,2*4			; 2 top right
		dc.b	0*4,3*4,4*4			; 3 bottom
		dc.b	0*4,5*4,3*4			; 4 bottom left
		dc.b	0*4,4*4,6*4			; 5 bottom right
		dc.b	1*4,2*4,4*4			; 6 back (the engine plate's)
		dc.b	1*4,3*4,5*4			; 7 back left
		dc.b	2*4,6*4,4*4			; 8 back right
		even

; smoothstep, 0..64 -> 0..256
morphSmooth:
MSI		set		0
		rept	65
		dc.w	(MSI*MSI*(192-2*MSI)*256)/(64*64*64)
MSI		set		MSI+1
		endr

; atan(i/64), i = 0..64, in 1/16 degrees
morphAtanTab:
		dc.w	0,14,29,43,57,71,86,100,114,128,142,156,170
		dc.w	184,197,211,225,238,251,265,278,291,304,316,329,341
		dc.w	354,366,378,390,402,414,425,436,448,459,470,481,491
		dc.w	502,512,522,532,542,552,562,571,581,590,599,608,617
		dc.w	626,634,642,651,659,667,675,683,690,698,705,713,720

morphOn::		dc.b	0		; seq_after: the ship is drawn from here
morphKept::		dc.b	0		; the unfolding is over
morphPhase::	dc.b	MP_UNFOLD
morphDirty:		dc.b	-1		; the picture has to be built again
morphClip:		dc.b	0		; (morphPoints) a point too near the eye
morphPShip:		dc.b	0		; (the play) the ship is drawn this frame
morphPGlow:		dc.b	0		; ... and its engine plate is seen
morphPark:		dc.b	0		; ... the stars thinned out anyway
				even
morphT::		dc.w	0		; frames into the unfolding (< 0: the arrow)
morphPT:		dc.w	0		; frames in the phase
morphU:			ds.w	5		; each part's 0..256 this frame
morphFG:		dc.w	0		; the lens times the arrow's growth
morphRollD:		dc.w	0		; (the unfolding) roll, pitch, degrees
morphPitchD:	dc.w	0
morphCX:		dc.w	0		; (the unfolding) its middle on the screen
morphCY:		dc.w	0
morphVz:		dc.w	256		; the stars' speed, 8.8 times warpVz
morphBarLast:	dc.w	0		; (the hold) ticks into the bar, last frame
morphGlowE:		dc.w	0		; (morphLine) glow: the edge again, a line down
morphKey:		dc.l	-1		; xc:yc the cache was built for
morphCacheEnd:	dc.l	morphCache
morphCache:		ds.b	2*morphNE*line_entry
; what the play shows this frame
morphPMask:		dc.w	0		; the faces seen
morphPGP:		dc.w	0		; the glow: radius (px) << 8 | thrust
morphPTorpN:	dc.w	0		; torpedoes
morphSprB:		dc.b	0		; (morphSprFrame) the sprite buffer built now
morphFlash:		dc.b	0		; ... the afterburner's flash: frames on
morphFlPh:		dc.b	0		; ... the flame's phase (0..3)
morphFlPC:		dc.b	0		; ... frames till the next
				even
morphFlJ:		dc.w	0		; ... its size up or down a little (R)
morphFlTX:		dc.w	0		; ... the tongues flicker about (px)
morphFlTY:		dc.w	0
morphFlX:		dc.w	0		; ... the plate's middle (screen)
morphFlY:		dc.w	0
morphFlVX:		dc.w	0		; ... the way out behind it (the nose to the
morphFlVY:		dc.w	0		; plate)
morphFlR16:		dc.w	0		; ... its R * 16 (softly), R (0: none)
morphFlR:		dc.w	0
morphTm:		dc.w	0		; ... the chain over to the small flame (0..AB_TM)
morphFlBoost:	dc.w	0		; ... the ignition's overshoot (* 256 of f)
morphChP:		ds.w	4*4		; ... the chain's glows: x, y, R*16, (b) off
morphChR16:		ds.w	4		; ... their R * 16, softly
morphChTip:		ds.w	4		; ... the plate's middle, the way to the tip
morphFrame:		dc.b	0		; ... frames (the flicker's round)
morphChDbg:		dc.b	0		; ... (AB_DEBUG) the line drawn
				even
morphPXY:		ds.w	2*morphNP	; the points
morphPTorps:	ds.b	8*morphTorpN	; x, y, radius, flags, flare x, flare y
TF_BURN		= 0			; (flags) its engine burns: it glows
TF_FLARE	= 1			; ... its flare is shown
TF_DOT		= 2			; ... far: a dot
TF_FLASH	= 3			; ... its engine fires this frame: a flash

; --- the turn and the points: the live ship's (the unfolding, the hold)
;     and the sim's both - swapped (morphSwap) while both are about
				cnop	0,4
morphSwapA:
morphR16:		dc.w	0		; the turn, 1/16 degrees: roll (about its length),
morphP16:		dc.w	0		; pitch (about its wings), yaw (in the screen's
morphY16:		dc.w	0		; plane), tilt (its nose up or down, seen from us),
morphT16:		dc.w	0		; heading (+: its nose to the right while it flies
morphH16:		dc.w	0		; away)
morphCR:		dc.w	0		; roll cos, sin
morphSR:		dc.w	0
morphCP:		dc.w	0		; pitch cos, sin
morphSP:		dc.w	0
morphSX:		dc.w	0		; the ship's middle, 1/16 units: across,
morphSY:		dc.w	0		; down,
morphSZ:		dc.l	morphZ0	; ahead
morphSh:		dc.w	0		; far off: everything this much smaller (>>)
morphSXs:		dc.w	0		; ... the middle so
morphSYs:		dc.w	0
morphSZs:		dc.w	0
morphM:			ds.w	9		; (unfolded) the turn as a matrix, Q15
morphXY:		ds.w	2*morphNP	; the points on the screen
morphFV:		ds.b	morphNF+1	; faces seen
morphFMask:		dc.w	0		; faces seen, a bit each
				cnop	0,4
morphSwapE:
morphSimSwap:	ds.b	morphSwapE-morphSwapA	; the other one's

; a torpedo: frames since it was dropped (0: none, -1: there), x, y, z and
; its speed ahead (1/256 units), the slope of its way (x, y per z, 4.12),
; its aim on the screen
				rsreset
tp_age:			rs.w	1
tp_x:			rs.l	1
tp_y:			rs.l	1
tp_z:			rs.l	1
tp_vz:			rs.l	1
tp_kx:			rs.w	1
tp_ky:			rs.w	1
tp_ax:			rs.w	1
tp_ay:			rs.w	1
tp_fv:			rs.w	1		; its fall (1/256 units a frame), dying away once
						; it burns
tp_burn:		rs.w	1		; frames its engine has burnt (0: falling still)
	ifne	escortMux
tp_hit:			rs.w	1		; its age at the hit
	endc
tp_len:			rs.b	0
morphTorps:		ds.b	morphTorpN*tp_len
morphTorpNext:	dc.w	0		; the next one to go
morphTorpLeft::	dc.w	0		; on their way
	ifne	escortMux
simMxTop::		dc.w	$7fff	; the afterburner's rows (about: simMxRange) -
simMxBot::		dc.w	$8000	; none
simMxHold:		dc.w	0		; ... frames they are kept on
simMxR:			dcb.l	4,$7fff8000	; ... each glow's (top, bottom): the
										; sprite a torpedo shares with it
simMxSkip::		dc.w	0		; (the harness) frames a torpedo's glow was left out
simMxLate::		dc.w	0		; ... torpedoes fired late (not safely above)
morphMxSkip::	dc.w	0		; ... glows the play still had to leave out
morphMxTwo::	dc.w	0		; ... sprites with two glows (frames)
	endc
; where they hit (the logo, screen x/y)
morphTorpAim:	dc.w	135,44, 177,54, 220,44

;---------------------------------------------
; d0 = degrees (any) -> d0 = sin, d1 = cos (Q15). uses a1
morphSinCos:
		tst.w	d0
		bpl.s	.p
.n:		add.w	#360,d0
		bmi.s	.n
.p:		cmp.w	#360,d0
		blo.s	.ok
		sub.w	#360,d0
		bra.s	.p
.ok:	lsl.w	#2,d0
		lea		sctab,a1
		move.w	2(a1,d0.w),d1
		move.w	(a1,d0.w),d0
		rts

; d0 = 1/16 degrees (any word) -> d0 = sin, d1 = cos (Q15), in a straight
; line between the table's degrees. uses d2/a1
morphSinCos16:
		tst.w	d0
		bpl.s	.p
.m:		add.w	#360*16,d0
		bmi.s	.m
.p:		cmp.w	#360*16,d0
		blo.s	.ok
		sub.w	#360*16,d0
		bra.s	.p
.ok:	moveq	#15,d2
		and.w	d0,d2				; the sixteenths
		lsr.w	#4,d0
		lsl.w	#2,d0
		lea		sctab,a1
		move.w	d0,d1
		addq.w	#4,d1
		cmp.w	#360*4,d1
		bne.s	.n
		moveq	#0,d1
.n:		movem.l	d3/d4,-(a7)
		move.w	(a1,d0.w),d3		; sin, cos of the degree
		move.w	2(a1,d0.w),d4
		move.w	(a1,d1.w),d0		; ... and of the next
		move.w	2(a1,d1.w),d1
		sub.w	d3,d0
		muls	d2,d0
		asr.l	#4,d0
		add.w	d3,d0
		sub.w	d4,d1
		muls	d2,d1
		asr.l	#4,d1
		add.w	d4,d1
		movem.l	(a7)+,d3/d4
		rts

; d0 = y, d1 = x (words) -> d0 = atan2(y, x), 1/16 degrees (-180..180):
; the angle of the way (x ahead, y across). uses d1-d3/a1
morphAtan2:
		moveq	#0,d3				; (bit 0: y < 0, bit 1: x < 0)
		tst.w	d0
		bpl.s	.a0
		neg.w	d0
		addq.w	#1,d3
.a0:	tst.w	d1
		bpl.s	.a1
		neg.w	d1
		addq.w	#2,d3
.a1:	cmp.w	d1,d0
		bhi.s	.steep
		tst.w	d1
		beq.s	.zero
		moveq	#0,d2
		move.w	d0,d2
		lsl.l	#8,d2
		lsl.l	#4,d2
		divu	d1,d2				; y/x, 4.12
		bsr.s	.tab
		bra.s	.quad
.steep:	moveq	#0,d2
		move.w	d1,d2
		lsl.l	#8,d2
		lsl.l	#4,d2
		divu	d0,d2				; x/y
		bsr.s	.tab
		neg.w	d0
		add.w	#90*16,d0
.quad:	btst	#1,d3
		beq.s	.q0
		neg.w	d0
		add.w	#180*16,d0
.q0:	btst	#0,d3
		beq.s	.q1
		neg.w	d0
.q1:	rts
.zero:	moveq	#0,d0
		rts
; d2 = 0..4096 -> d0 = atan of it, 1/16 degrees (between the table's steps)
.tab:	move.w	d2,d1
		lsr.w	#6,d1				; 0..64
		and.w	#63,d2
		add.w	d1,d1
		lea		morphAtanTab,a1
		move.w	(a1,d1.w),d0
		tst.w	d2
		beq.s	.t0
		move.w	2(a1,d1.w),d1
		sub.w	d0,d1
		mulu	d2,d1
		lsr.w	#6,d1
		add.w	d1,d0
.t0:	rts

; the same for longs (both made smaller till they fit a word)
morphAtan2L:
.f:		move.l	d0,d2
		bpl.s	.f0
		neg.l	d2
.f0:	move.l	d1,d3
		bpl.s	.f1
		neg.l	d3
.f1:	or.l	d3,d2
		cmp.l	#32767,d2
		bls		morphAtan2
		asr.l	#1,d0
		asr.l	#1,d1
		bra.s	.f

; d0 = frames, d1 = frames in all -> d0 = 0..256 (clamped), d1 the
; smoothstep of it
morphUnit:
		cmp.w	d1,d0
		blo.s	.u0
		move.w	d1,d0
.u0:	tst.w	d0
		bpl.s	.u1
		moveq	#0,d0
.u1:	ext.l	d0
		lsl.l	#6,d0
		divu	d1,d0				; 0..64
		move.w	d0,d1
		add.w	d1,d1
		lea		morphSmooth(pc),a1
		move.w	(a1,d1.w),d1
		lsl.w	#2,d0				; 0..256
		rts

; -> d0 = music ticks into the bar (0..95)
morphBarPos:
		move.w	#morphCueTicks,d0
		sub.w	musicPalCountdown,d0
		and.l	#$ffff,d0
		divu	#morphBar,d0
		swap	d0
		rts

;---------------------------------------------
; once a frame from seq_morph (asteroids.s), before the ship moves and is
; drawn: the timeline. a0 the ship, kept. d0 = 0: the ship is not still yet
morphTick::
		move.w	d0,-(a7)
		addq.w	#1,morphT
		addq.w	#1,morphPT
		moveq	#0,d1
		move.b	morphPhase,d1
		add.w	d1,d1
		move.w	.tab(pc,d1.w),d1
		jsr		.tab(pc,d1.w)
		addq.l	#2,a7
		; the stars' speed, and fewer of them while they rush
		move.w	morphVz,d0
		mulu	#warpVz,d0
		lsr.l	#8,d0
		move.w	d0,warpVzNow
		; new stars from further off the faster they come (the same wait for
		; each: the faster, the fewer of them in sight - a rush of stars
		; costs; the parked ones next to nothing)
		move.w	morphVz,d0
		sub.w	#256,d0
		bcc.s	.pk0
		moveq	#0,d0
.pk0:	mulu	#morphParkZ,d0
		lsr.l	#8,d0
		tst.b	morphPark				; (from the pass on a few always: the
		beq.s	.pk						; ship costs its share)
		add.w	#morphPark0,d0
.pk:	cmp.w	#morphParkMax,d0		; (no further than the field takes)
		bls.s	.pk1
		move.w	#morphParkMax,d0
.pk1:	move.w	d0,warpPark
		rts
.tab:	dc.w	.unfold-.tab,.hold-.tab,.play-.tab,.gone-.tab

.unfold:
		st		morphDirty
		cmp.w	#morphLen+morphGlow,morphT
		blt.s	.out
		st		morphKept
		move.b	#MP_HOLD,morphPhase
		clr.w	morphPT
.out:	rts

.hold:	; still, then on the next bar of the music: the play
		tst.w	4(a7)				; (d0: still?)
		bne.s	.h0
		clr.w	morphPT				; not yet
		rts
.h0:	tst.b	warpState			; still: the stars start to go into depth
		bne.s	.h2					; (their costly frames come while the ship
		jsr		warpStart			; is only shown, before the play)
.h2:	cmp.w	#morphHoldMin,morphPT
		blo.s	.out
		tst.b	morphSimEnd			; the whole flight worked out?
		beq.s	.out
	cmp.w	#morphHoldMax,morphPT	; (no music: on anyway)
		bhs.s	.go
		bsr		morphBarPos
		move.w	morphBarLast,d1
		move.w	d0,morphBarLast
		cmp.w	d1,d0				; a new bar since the last frame?
		bhs.s	.out
.go:	move.b	#MP_PLAY,morphPhase
		clr.w	morphPT
		rts

.play:	move.l	a0,-(a7)
	ifne	showdownLean
		tst.b	morphLean			; (the ship gone: the torpedoes alone)
		beq.s	.p0
		bsr		morphLnFrame
		bra.s	.p1
.p0:	bsr		morphPlayFrame
		bsr		morphLnCheck
.p1:
	else
		bsr		morphPlayFrame
	endc
		move.l	(a7)+,a0
		rts

.gone:	; (the hits come here)
		lea		sfxDroneOn,a1
		clr.l	(a1)
		rts

;---------------------------------------------
; the play: the next frame of the flight as the sim wrote it
;
; a frame: a word of flags, then what they say is there - the faces seen
; (a word), the stars' speed (a word, bit 15: thinned out anyway), the
; engine's sound (volume, period), the torpedo's (so), the glow (radius <<
; 8 | thrust), the points (as nibbles or bytes: the change since the last
; frame, or as words), the torpedoes (8 bytes each)
RF_MODE		= 3			; bits 0-1: the points (0 none, 1 nibbles, 2 bytes,
						; 3 words)
RB_MASK		= 2
RB_GLOW		= 3			; the engine plate is seen (its glow)
RB_VZ		= 4
RB_SND1		= 5			; the engine's drone (channel 1)
RB_SND3		= 6			; a torpedo's hiss (channel 3)
RB_DROP		= 7			; a torpedo drops (the clunk)
RB_IGN		= 8			; its engine fires (the whoosh)
RB_SIGN		= 9			; the fighter's engine fires
RB_WARP		= 10		; the stars go into depth
RB_TORPS	= 11		; bits 11-12: torpedoes
RB_GLOWP	= 13
RB_END		= 14		; the last frame
RB_BOOM		= 15		; the break: the afterburner kicks in (a boom)

morphPlayFrame:
		move.w	morphSimN,d0
		sub.w	morphPlayN,d0
		bhi.s	.go
		addq.w	#1,morphStalls		; not worked out yet: the last one again
		rts
.go:	tst.b	morphSimEnd			; (the least lead while the sim works)
		bne.s	.l0
		cmp.w	morphLeadLow,d0
		bhs.s	.l0
		move.w	d0,morphLeadLow
.l0:	move.l	morphPlayR,a0
		move.w	(a0)+,d7
		lea		sfxDroneOn,a2
		sf		1(a2)
		sf		3(a2)
		sf		morphPGlow
		btst	#RB_MASK,d7
		beq.s	.f0
		move.w	(a0)+,morphPMask
.f0:	btst	#RB_VZ,d7
		beq.s	.f1
		move.w	(a0)+,d0
		smi		morphPark
		and.w	#$7fff,d0
		move.w	d0,morphVz
.f1:	btst	#RB_SND1,d7
		beq.s	.f2
		move.w	(a0)+,sfxDroneVol+2
		move.w	(a0)+,sfxDronePer+2
		st		1(a2)
.f2:	btst	#RB_SND3,d7
		beq.s	.f2e
		move.w	(a0)+,sfxDroneVol+6
		move.w	(a0)+,sfxDronePer+6
		st		3(a2)
		sf		sfxEng3				; (its hiss: music.s)
		bra.s	.f3
.f2e:	tst.b	1(a2)				; no hiss, the engine near: on 3 as well,
		beq.s	.f3					; a little lower - the other side, a
		moveq	#morphSnd2V,d0			; slow beat between them: big
		tst.b	sfxEng3				; (on already: till it is a quarter
		beq.s	.f2v					; quieter)
		moveq	#morphSnd2V*3/4,d0
.f2v:	cmp.w	sfxDroneVol+2,d0
		bls.s	.f2o
		sf		sfxEng3
		bra.s	.f3
.f2o:		move.w	sfxDroneVol+2,sfxDroneVol+6
		move.w	sfxDronePer+2,d0
		move.w	d0,d1
		lsr.w	#6,d1
		add.w	d1,d0
		move.w	d0,sfxDronePer+6
		st		sfxEng3
		st		3(a2)
.f3:	btst	#RB_GLOWP,d7
		beq.s	.f4
		move.w	(a0)+,morphPGP
.f4:	; the points
		moveq	#RF_MODE,d0
		and.w	d7,d0
		sne		morphPShip
		beq.s	.pts9
		lea		morphPXY,a1
		subq.w	#2,d0
		bmi.s	.nib
		beq.s	.byt
		moveq	#morphNP-1,d6		; words: as they are
.wd:	move.l	(a0)+,(a1)+
		dbf		d6,.wd
		bra.s	.pts8
.byt:	moveq	#2*morphNP-1,d6		; bytes: the change
.by:	move.b	(a0)+,d0
		ext.w	d0
		add.w	d0,(a1)+
		dbf		d6,.by
		bra.s	.pts8
.nib:	moveq	#morphNP-1,d6		; nibbles: the change, x and y in a byte
.nb:	move.b	(a0)+,d0
		move.b	d0,d1
		asr.b	#4,d0
		ext.w	d0
		add.w	d0,(a1)+
		lsl.b	#4,d1
		asr.b	#4,d1
		ext.w	d1
		add.w	d1,(a1)+
		dbf		d6,.nb
.pts8:	btst	#RB_GLOW,d7
		sne		morphPGlow
.pts9:	; the torpedoes
		move.w	d7,d0
		moveq	#RB_TORPS,d1
		lsr.w	d1,d0
		and.w	#3,d0
		move.w	d0,morphPTorpN
		lea		morphPTorps,a1
		subq.w	#1,d0
		bmi.s	.tp9
.tp:	move.l	(a0)+,(a1)+
		move.l	(a0)+,(a1)+
		dbf		d0,.tp
.tp9:	move.l	a0,morphPlayR
		addq.w	#1,morphPlayN
		; what happens this frame
		btst	#RB_DROP,d7
		beq.s	.e0
		moveq	#SFX_DROP,d0
		jsr		sfxPlay
.e0:	btst	#RB_IGN,d7
		beq.s	.e1
		moveq	#SFX_IGNITE,d0
		jsr		sfxPlay
.e1:	btst	#RB_SIGN,d7			; (and with the break: the whoosh on 1,
		bne.s	.ig					; a big boom on 3 - left and right)
		tst.w	d7
		bpl.s	.e2
	ifne	drumSeq
		move.w	morphPhT+2*SP_BREAK,d1	; (the break's boom - not the pass's:
		beq.s	.ig					; music.s, the music ends - its voices
		move.w	morphPlayN,d0		; fade, the drums go on)
		subq.w	#1,d0
		cmp.w	d1,d0
		blo.s	.ig
		move.w	#morphBreakLead-1,musHitIn
		st		musFadeGo
	endc
.ig:	move.b	#2,morphFlash		; (the afterburner: its flash, the flame
		move.w	#128,morphFlBoost	; longer for a while)
		moveq	#SFX_SHIPIGN,d0
		jsr		sfxPlay
		moveq	#SFX_BIGBOOM,d0
		jsr		sfxPlay
.e2:	btst	#RB_WARP,d7
		beq.s	.e3
		move.l	d7,-(a7)
		jsr		warpStart
		move.l	(a7)+,d7
.e3:	btst	#RB_END,d7
		beq.s	.e4
		move.b	#MP_GONE,morphPhase
		clr.w	morphPT
		sf		morphPShip
		clr.w	morphPTorpN
.e4:	rts

	ifne	showdownLean
	ifeq	escortMux
	fail	"showdownLean needs escortMux (the torpedoes' glows: morphMxTGeo)"
	endc
; --- (switches.i showdownLean) once the fighter has gone (past us, the
;     wait begun, its afterburner died away: morphLnAfter frames on, not
;     drawn) the flight's work stops: no record read any more, no flame -
;     the torpedoes fly on by themselves, each straight from where it is to
;     its point on the logo (morphTorpAim), there with its hit as before
;     (the first one morphBreakLead-1 frames after the break, each next one
;     morphTorpGap later), as blobs: sprites (morphSprFrame), no lines. the
;     record and the sim's table are free from then on (morphRecFree: the
;     overlay sdOvl, sdOvlLen bytes)
morphLnAfter = 24		; frames into the wait at least
sdOvl		= morphRcp	; (the sim's table and the record, one after the other)
sdOvlLen	= morphRecEnd-morphRcp

; after a frame of the record: the switch over?
morphLnCheck:
		cmp.b	#MP_PLAY,morphPhase
		bne.s	.no
		move.w	morphPhT+2*SP_WAIT,d0
		beq.s	.no
		add.w	#morphLnAfter,d0
		cmp.w	morphPlayN,d0
		bhi.s	.no
		tst.b	morphPShip
		bne.s	.no
		move.w	morphPTorpN,d7
		beq.s	.no
		move.w	d7,morphLnN
		moveq	#morphTorpN,d6		; (those gone already: the first ones)
		sub.w	d7,d6
		move.w	morphPhT+2*SP_BREAK,d5	; this one's hit (frame)
		add.w	#morphBreakLead-1,d5
		move.w	d6,d0
		mulu	#morphTorpGap,d0
		add.w	d0,d5
		lsl.w	#2,d6
		lea		morphTorpAim,a2
		add.w	d6,a2
		lea		morphPTorps,a0
		lea		morphLnT,a1
		subq.w	#1,d7
.t:		move.l	(a0),(a1)+			; where it is now, where it goes, when
		move.l	(a2)+,(a1)+
		move.w	d5,(a1)+
		moveq	#2,d0				; (its blob: R 1, 2 if it was bigger)
		cmp.b	#2,4(a0)
		blo.s	.r
		moveq	#3,d0
.r:		move.w	d0,(a1)+
		add.w	#morphTorpGap,d5
		addq.l	#8,a0
		dbf		d7,.t
		move.w	morphPlayN,morphLnS
		clr.w	morphLnV			; its engine, as it is heard now (it
		tst.b	sfxDroneOn+1		; dies away as it flies on: morphLnFrame)
		beq.s	.e
		move.w	sfxDroneVol+2,morphLnV
		move.w	sfxDronePer+2,morphLnP
.e:		st		morphLean
.no:	rts

; a frame of the torpedoes alone: on their straight ways (morphPTorps, as
; the record had them: a gone one's place kept, not burning - no blob);
; the fighter's engine far behind us dies away (its volume * 512 / (512 +
; frames), as the record had it: further and further off), on 3 as well
; while it is loud enough (as morphPlayFrame)
morphLnFrame:
		lea		sfxDroneOn,a2
		sf		1(a2)
		sf		3(a2)
		move.w	morphPlayN,d0
		sub.w	morphLnS,d0
		add.w	#512,d0
		move.w	morphLnV,d1
		mulu	#512,d1
		divu	d0,d1
		cmp.w	#2,d1
		blo.s	.q
		move.w	d1,sfxDroneVol+2
		move.w	morphLnP,d0
		move.w	d0,sfxDronePer+2
		st		1(a2)
		tst.b	sfxEng3
		beq.s	.s9
		cmp.w	#morphSnd2V*3/4,d1
		blo.s	.q
		move.w	d1,sfxDroneVol+6
		move.w	d0,d1
		lsr.w	#6,d1
		add.w	d1,d0
		move.w	d0,sfxDronePer+6
		st		3(a2)
		bra.s	.s9
.q:		sf		sfxEng3
.s9:	sf		morphPGlow
		sf		morphPShip
		move.w	morphPlayN,d4		; (this frame)
		addq.w	#1,morphPlayN
		lea		morphLnT,a1
		lea		morphPTorps,a0
		moveq	#0,d7				; (on their way still)
		move.w	morphLnN,d6
		subq.w	#1,d6
.t:		move.w	8(a1),d3			; there: gone
		cmp.w	d3,d4
		bhs.s	.gone
		move.w	d4,d0				; t / T of its way
		sub.w	morphLnS,d0
		sub.w	morphLnS,d3
		move.w	4(a1),d1
		sub.w	(a1),d1
		muls	d0,d1
		divs	d3,d1
		add.w	(a1),d1
		move.w	d1,(a0)+
		move.w	6(a1),d1
		sub.w	2(a1),d1
		muls	d0,d1
		divs	d3,d1
		add.w	2(a1),d1
		move.w	d1,(a0)+
		move.b	11(a1),(a0)+
		move.b	#1<<TF_BURN,(a0)+
		clr.w	(a0)+
		addq.w	#1,d7
		bra.s	.n
.gone:	clr.l	4(a0)
		addq.l	#8,a0
.n:		lea		12(a1),a1
		dbf		d6,.t
		tst.w	d7
		bne.s	.on
		move.b	#MP_GONE,morphPhase	; all there: as the record's end
		clr.w	morphPT
		clr.w	morphPTorpN
		st		morphRecFree
.on:	rts
	endc

;---------------------------------------------
; obj_move comes here for the ship while morphOn is set: a0 the ship, a5
; yOffTab, a6 the draw table. the ship's lines go into morphCache and the
; table gets a pointer to them
morphDraw:
		cmp.b	#MP_PLAY,morphPhase
		blo.s	.live
		bsr		morphPlayDraw
		rts
.live:	; the unfolding and the hold: worked out here, when it has changed
		tst.b	morphDirty
		bne.s	.build
		move.l	obj_xc(a0),d0		; the same picture: and the ship on the
		cmp.l	morphKey,d0			; same pixel?
		beq		.emit
.build:
		move.l	obj_xc(a0),morphKey
		sf		morphDirty
		bsr		morphPose
		moveq	#0,d6
		moveq	#morphNP-1,d7
		bsr		morphPoints
		; which faces we see
		cmp.w	#morphCull,morphT
		blt.s	.allFaces
		bsr		morphFaceVis
		bra.s	.lines
.allFaces:
		lea		morphFV,a1
		moveq	#morphNF-1,d0
.af:	st		(a1)+
		dbf		d0,.af
.lines:
		move.l	a6,-(a7)
		lea		morphCache,a6
		lea		morphEdges,a4
		moveq	#morphNE-1,d7
		tst.b	morphKept
		beq.s	.edge
		; unfolded: an edge is drawn if one of its faces is seen (morphEM
		; against morphFaceVis's bits), no glow
		move.w	morphFMask,d5
		lea		morphEM,a3
		lea		morphXY,a1
		bsr		morphEdgeLines
		bra.s	.lend
.edge:	move.w	d7,-(a7)
		clr.w	morphGlowE
		moveq	#0,d0
		move.b	4(a4),d0			; its part
		lsl.w	#2,d0
		lea		morphParts,a1
		move.w	morphT,d1
		sub.w	(a1,d0.w),d1		; frames since its part started
		bgt.s	.out
		tst.b	5(a4)				; not out yet: only the arrow's own lines
		beq.s	.skip
.out:	sub.w	2(a1,d0.w),d1		; glow: near the end of its part
		bpl.s	.g0
		neg.w	d1
.g0:	cmp.w	#morphGlow,d1
		bhi.s	.seen
		move.w	#1,morphGlowE
.seen:	bsr		morphSeen
		beq.s	.skip
		bsr		morphLine
.skip:	lea		me_len(a4),a4
		move.w	(a7)+,d7
		dbf		d7,.edge
.lend:	move.l	a6,morphCacheEnd
		move.l	(a7)+,a6
.emit:
		move.l	morphCacheEnd,d0
		cmp.l	#morphCache,d0
		beq.s	.none
		move.w	#-2,(a6)+
		move.l	#morphCache,(a6)+
		move.l	d0,(a6)+
.none:	rts

; the edges whose faces are seen (d5 the faces' bits) into the table at a6:
; a1 the points, a3 morphEM, a4 morphEdges, d7 edges-1
morphEdgeLines:
.k:		move.w	(a3)+,d0
		and.w	d5,d0
		beq.s	.kn
		moveq	#0,d0
		move.b	(a4),d0
		moveq	#0,d2
		move.b	1(a4),d2
		movem.w	(a1,d0.w),d0/d1
		movem.w	(a1,d2.w),d2/d3
		movem.w	d5/d7,-(a7)
		jsr		set_line			; (keeps a1-a4)
		movem.w	(a7)+,d5/d7
.kn:	addq.l	#me_len,a4
		dbf		d7,.k
		rts

; the play's picture: the torpedoes, the glow, the ship
morphPlayDraw:
		bsr		morphSprFrame		; (the glows: sprites)
	ifne	showdownLean
		tst.b	morphLean			; (the torpedoes alone: blobs, no lines)
		bne.s	.none
	endc
		bsr		morphPTorpDraw
		tst.b	morphPShip
		beq.s	.none
		move.l	a6,-(a7)
		lea		morphCache,a6
		lea		morphEdges,a4
		lea		morphEM,a3
		lea		morphPXY,a1
		move.w	morphPMask,d5
		moveq	#morphNE-1,d7
		bsr		morphEdgeLines
	ifne	AB_DEBUG
		tst.b	morphChDbg			; (the thrust axis: the plate's middle to
		beq.s	.nd					; the flame's tip)
		movem.w	morphChTip,d0-d3
		add.w	d0,d2
		add.w	d1,d3
		jsr		set_line
.nd:
	endc
		move.l	a6,d0
		move.l	(a7)+,a6
		cmp.l	#morphCache,d0
		beq.s	.none
		move.w	#-2,(a6)+
		move.l	#morphCache,(a6)+
		move.l	d0,(a6)+
.none:	rts

;---------------------------------------------
; the sprites: every glow (the star planes are the stars' alone), from
; morphPlayDraw every frame. built in one of two buffers: the copper takes
; their pointers (clistElite elSpr) and colours (elSprCol) at the top of
; the next frame. sprites 0..3 only - the wide fetch (DDFSTRT $28) takes
; the higher ones' DMA slots:
;   no torpedoes about: the afterburner - four round glows on the thrust
;     axis on the screen, from the plate's middle out to the flame's tip
;     (the plate's middle and more of the nose-to-plate way): seen from
;     behind they fall together into one glow, from the side they make a
;     stream - no special cases (morphChain)
;   torpedoes about: 0, 1, 2 their glows (once they burn), 3 the ship's
;     small flame - over morphTm frames the chain fades out of 0..2 into
;     that (and the colours go over), and back once they are gone
;   (switches.i escortMux) the chain stays all the time, and a torpedo's
;     glow (abImg as well, the chain's flicker, its colours) goes into a
;     sprite of it above or below the chain's glow there - multiplexed: the
;     sim (simTorps) keeps them clear of each other (morphMxSpr)
; keeps all
	ifne	escortMux
morphSprFrame:
	ifne	sprTest
		rts
	endc
		movem.l	d0-d7/a0-a6,-(a7)
		addq.b	#1,morphFrame
		not.b	morphSprB
		lea		morphSprBuf,a2
		tst.b	morphSprB
		beq.s	.b0
		lea		4*MSPR_LEN(a2),a2
.b0:
	ifne	showdownLean
		tst.b	morphLean			; (the ship gone: the torpedoes' blobs
		bne		.lean				; alone)
	endc
		bsr		morphFlRand			; (the flicker's numbers)
		bsr		morphFlGeo
		move.w	morphFlBoost,d0		; the ignition's overshoot dies away
		move.w	d0,d1
		lsr.w	#3,d1
		addq.w	#1,d1
		sub.w	d1,d0
		bpl.s	.bo
		moveq	#0,d0
.bo:	move.w	d0,morphFlBoost
		bsr		morphChain
		lea		elSpr,a3			; 0..3: the chain's glows, 0..2 a
		lea		morphPTorps,a4		; torpedo's as well
		moveq	#0,d7
.s:		bsr		morphMxSpr
		bsr		morphSprPtr
		lea		MSPR_LEN(a2),a2
		addq.l	#8,a4
		addq.w	#1,d7
		cmp.w	#4,d7
		blo.s	.s
		lea		morphColAb,a0		; the colours 17-19, 21-23: the
		lea		elSprCol+2,a4		; afterburner's
		moveq	#7-1,d7
.ca:	move.w	(a0)+,(a4)
		addq.l	#4,a4
		dbf		d7,.ca
		tst.b	morphFlash			; (it fires: white hot, a frame or two)
		beq.s	.out
		subq.b	#1,morphFlash
		lea		elSprCol+2,a4
		move.w	#$0fff,4(a4)
		move.w	#$0fff,8(a4)
.out:	movem.l	(a7)+,d0-d7/a0-a6
		rts
	ifne	showdownLean
.lean:	lea		elSpr,a3			; 0..2: a torpedo's blob, nothing else
		lea		morphPTorps,a4
		moveq	#0,d7
.ls:	bsr		morphMxTGeo
		tst.w	d5
		beq.s	.ln
		moveq	#4,d4
		moveq	#0,d3
		bsr		morphSprPut
		bra.s	.lp
.ln:	move.l	#s3Null,d0
.lp:	bsr		morphSprPtr
		lea		MSPR_LEN(a2),a2
		addq.l	#8,a4
		addq.w	#1,d7
		cmp.w	#4,d7
		blo.s	.ls
		bra.s	.out
	endc

; sprite d7 (a2 its buffer, a4 the torpedo with it): the chain's glow and
; the torpedo's, the higher one first, a line between them at least (the
; sprite fetches the next one's control words there) - else the torpedo's
; is left out (morphMxSkip: the sim keeps it 0) -> d0 = its pointer.
; uses d0-d6/a0/a1
morphMxSpr:
		bsr		morphMxTGeo			; the torpedo's: d0/d1, a1, d5
		movem.w	d0/d1/d5,morphMxT
		move.l	a1,morphMxT+6
		bsr		morphChGeo			; the chain's
		tst.w	morphMxT+4
		beq.s	.one				; (no torpedo's: the chain's alone)
		tst.w	d5
		bne.s	.two
		movem.w	morphMxT,d0/d1/d5	; (no chain's: the torpedo's alone)
		move.l	morphMxT+6,a1
.one:	tst.w	d5
		beq.s	.null
		moveq	#4,d4
		moveq	#0,d3
		bra		morphSprPut
.null:	move.l	#s3Null,d0
		rts
.two:	movem.w	d0/d1/d5,morphMxC	; both: the higher one first
		move.l	a1,morphMxC+6
		lea		morphMxC,a0
		lea		morphMxT,a1
		move.w	2(a1),d2
		cmp.w	d1,d2
		bge.s	.ord
		exg		a0,a1
.ord:	move.w	2(a0),d2			; the lower one a line below the higher
		add.w	4(a0),d2			; one's end at least
		cmp.w	2(a1),d2
		blt.s	.fit
		addq.w	#1,morphMxSkip		; (touching: the chain's alone)
		movem.w	morphMxC,d0/d1/d5
		move.l	morphMxC+6,a1
		bra.s	.one
.fit:	addq.w	#1,morphMxTwo
		move.l	a1,-(a7)
		movem.w	(a0),d0/d1/d5
		move.l	6(a0),a1
		moveq	#4,d4
		moveq	#0,d3
		bsr		morphSprPut			; (a0: its end now)
		move.l	(a7)+,a1
		cmp.l	#s3Null,d0
		beq.s	.lo					; (the higher one off the screen)
		move.l	d0,-(a7)
		move.l	a2,-(a7)
		move.l	a0,a2				; the lower one after it
		movem.w	(a1),d0/d1/d5
		move.l	6(a1),a1
		bsr		morphSprPut
		move.l	(a7)+,a2
		move.l	(a7)+,d0
		rts
.lo:	movem.w	(a1),d0/d1/d5
		move.l	6(a1),a1
		bra		morphSprPut
morphMxT:	ds.w	5			; (morphMxSpr) the torpedo's: left, top, rows,
morphMxC:	ds.w	5			; its first row; the chain's

; a4 = the torpedo with sprite d7 (morphPTorps) -> its glow: d0/d1 = its
; left, top, a1 = its first row (abImg: the nozzle's kind, the chain's frame
; and flicker for that glow), d5 = rows (0: none - not burning, left out by
; the sim, flickered off). uses d2/d6/a1
morphMxTGeo:
		moveq	#0,d5
		cmp.w	morphPTorpN,d7
		bhs.s	.no
		move.b	5(a4),d2
		btst	#TF_BURN,d2
		beq.s	.no
		btst	#TF_NOSPR,d2
		bne.s	.no
	ifne	AB_FLICK
		moveq	#3,d6				; (the chain's flicker: its next glow's)
		and.b	morphFrame,d6
		lea		morphChFlk+1,a1
		btst	d6,(a1,d7.w)
		beq.s	.no
	endc
		moveq	#0,d6				; R: inside its diamond (the flash: bigger)
		move.b	4(a4),d6
		subq.w	#1,d6
		btst	#TF_FLASH,d2
		beq.s	.r0
		addq.w	#4,d6
.r0:	cmp.w	#1,d6
		bge.s	.r1
		moveq	#1,d6
.r1:	cmp.w	#MSPR_RMAX,d6
		ble.s	.r2
		moveq	#MSPR_RMAX,d6
.r2:	lea		morphChF,a1			; its rows: the nozzle's kind (0), the
		moveq	#0,d2				; chain's frame for that glow, R
		move.b	(a1,d7.w),d2
		add.w	d2,d2
		lea		morphChKf(pc),a1
		move.w	(a1,d2.w),d2
		move.w	d6,d5
		add.w	d5,d5
		lea		morphChRr-2(pc),a1
		add.w	(a1,d5.w),d2
		lea		abImg,a1
		add.w	d2,a1
		movem.w	(a4),d0/d1			; its middle -> its left, top
		subq.w	#7,d0
		sub.w	d6,d1
		move.w	d6,d5
		add.w	d5,d5
		addq.w	#1,d5
.no:	rts

	else
morphSprFrame:
	ifne	sprTest
		rts
	endc
		movem.l	d0-d7/a0-a6,-(a7)
		addq.b	#1,morphFrame
		not.b	morphSprB
		lea		morphSprBuf,a2
		tst.b	morphSprB
		beq.s	.b0
		lea		4*MSPR_LEN(a2),a2
.b0:	bsr		morphFlRand			; (the flicker's numbers)
		bsr		morphFlGeo
		move.w	morphTm,d0			; torpedoes about: over to the small
		tst.w	morphPTorpN			; flame, none: back to the chain
		beq.s	.t0
		cmp.w	#AB_TM,d0
		bhs.s	.t1
		addq.w	#1,d0
		bra.s	.t1
.t0:	tst.w	d0
		beq.s	.t1
		subq.w	#1,d0
.t1:	move.w	d0,morphTm
		move.w	morphFlBoost,d0		; the ignition's overshoot dies away
		move.w	d0,d1
		lsr.w	#3,d1
		addq.w	#1,d1
		sub.w	d1,d0
		bpl.s	.bo
		moveq	#0,d0
.bo:	move.w	d0,morphFlBoost
		bsr		morphChain
		lea		elSpr,a3			; 0..2: a torpedo's glow (burning) or
		lea		morphPTorps,a4		; the chain's
		lea		morphChP,a5
		moveq	#0,d7
.s:		cmp.w	morphPTorpN,d7
		bhs.s	.ch
		btst	#TF_BURN,5(a4)
		beq.s	.ch
		moveq	#0,d6				; (its glow: inside its diamond, the
		move.b	4(a4),d6			; flash bigger)
		subq.w	#1,d6
		btst	#TF_FLASH,5(a4)
		beq.s	.s0
		addq.w	#4,d6
.s0:	movem.w	(a4),d0/d1
		bsr		morphGlowPut
		bra.s	.ptr
.ch:	bsr		morphChPut
.ptr:	bsr		morphSprPtr
		lea		MSPR_LEN(a2),a2
		addq.l	#8,a4
		addq.l	#8,a5
		addq.w	#1,d7
		cmp.w	#3,d7
		blo.s	.s
		cmp.w	#AB_TM/2,morphTm	; 3: the chain's tip, or the small flame
		bhs.s	.sm
		bsr		morphChPut
		bra.s	.p3
.sm:	move.w	morphFlR16,d6		; (the small flame: as big as the plate,
		mulu	morphTm,d6			; growing in as the chain goes)
		lsr.l	#4,d6				; (/ AB_TM)
		addq.w	#8,d6
		lsr.w	#4,d6
		beq.s	.n3
		add.w	morphFlJ,d6
		movem.w	morphFlX,d0/d1
		bsr		morphGlowPut
		bra.s	.p3
.n3:	move.l	#s3Null,d0
.p3:	bsr		morphSprPtr
		; the colours 17-19, 21-23: the afterburner's, the torpedoes' (the
		; same in both pairs), in between as it goes over
		lea		morphColAb,a0
		lea		morphColTorp,a1
		lea		elSprCol+2,a4
		move.w	morphTm,d5
		moveq	#7-1,d7
		tst.w	d5					; (all the one or the other: no mixing)
		beq.s	.ca
		cmp.w	#AB_TM,d5
		bne.s	.c
		move.l	a1,a0
.ca:	move.w	(a0)+,(a4)
		addq.l	#4,a4
		dbf		d7,.ca
		bra.s	.cd
.c:		move.w	(a0)+,d0
		move.w	(a1)+,d1
		bsr		morphColMix
		move.w	d0,(a4)
		addq.l	#4,a4
		dbf		d7,.c
.cd:
		tst.b	morphFlash			; (it fires: white hot, a frame or two)
		beq.s	.out
		subq.b	#1,morphFlash
		cmp.w	#AB_TM/2,morphTm
		bhs.s	.out
		lea		elSprCol+2,a4
		move.w	#$0fff,4(a4)
		move.w	#$0fff,8(a4)
.out:
	ifne	AB_DEBUG
		st		morphChDbg
	endc
		movem.l	(a7)+,d0-d7/a0-a6
		rts

; d0 = a colour (the afterburner's), d1 = another (the torpedoes'), d5 =
; 0..AB_TM -> d0 = between them. uses d2-d4
morphColMix:
		moveq	#0,d4
		move.w	#$f00,d3
.n:		move.w	d0,d2				; each of r, g, b
		and.w	d3,d2
		move.w	d1,-(a7)
		and.w	d3,d1
		sub.w	d2,d1
		muls	d5,d1
		asr.l	#4,d1				; (/ AB_TM)
		add.w	d1,d2
		and.w	d3,d2
		or.w	d2,d4
		move.w	(a7)+,d1
		lsr.w	#4,d3
		bne.s	.n
		move.w	d4,d0
		rts
	endc

; the chain (no special cases): the tip = the plate's middle + its way out
; behind it (morphFlVX/VY: the nose to the plate on the screen) * f - f
; 0.3 .. 0.5 with the thrust (the nose-to-plate way is most of the ship's
; length), longer the frame it fires (morphFlBoost), +-15 % a frame. the
; four glows at 12, 38, 66, 100 % of the way: their middles, their R (* 16,
; softly: the plate's size, more for the further ones and the longer the
; flame; less as the torpedoes take over), their frames (0 and 2 every 2
; frames, 1 and 3 every 3, 1 or 2 on), their flicker -> morphChP
morphChain:
		cmp.w	#8,morphFlR16		; (no flame, and none dying away: nothing
		bhs.s	.on					; to work out)
		move.l	morphChR16,d0
		or.l	morphChR16+4,d0
		bne.s	.on
		lea		morphChP+4,a0
		moveq	#4-1,d0
.no:	clr.w	(a0)
		addq.l	#8,a0
		dbf		d0,.no
		rts
.on:	moveq	#0,d0				; f (* 256)
		move.b	morphPGP+1,d0
		mulu	#51,d0
		lsr.w	#8,d0
		add.w	#77,d0
		add.w	morphFlBoost,d0
		move.w	morphFlRn+2,d1		; (+-15 %: * 77 >> 14 ~ / 213)
		and.w	#63,d1
		sub.w	#32,d1
		muls	d0,d1
		muls	#77,d1
		asr.l	#8,d1
		asr.l	#6,d1
		add.w	d1,d0
		move.w	morphFlVX,d2		; the way to the tip
		muls	d0,d2
		asr.l	#8,d2
		move.w	morphFlVY,d3
		muls	d0,d3
		asr.l	#8,d3
		move.w	d2,d4				; its length (about: max + min/2)
		bpl.s	.l0
		neg.w	d4
.l0:	move.w	d3,d5
		bpl.s	.l1
		neg.w	d5
.l1:	cmp.w	d5,d4
		bhs.s	.l2
		exg		d4,d5
.l2:	lsr.w	#1,d5
		add.w	d5,d4				; (px)
		movem.w	morphFlX,d0/d1
		movem.w	d0-d3,morphChTip	; (the debug line: the middle, the way)
		lea		morphChP,a0			; the four glows' middles: 1/8, 3/8,
		move.w	d2,d5				; 11/16 and all of the way (shifts: no
		asr.w	#3,d5				; multiplies)
		move.w	d3,d6
		asr.w	#3,d6
		add.w	d0,d5
		add.w	d1,d6
		movem.w	d5/d6,(a0)
		move.w	d2,d5
		asr.w	#1,d5
		move.w	d2,d6
		asr.w	#3,d6
		sub.w	d6,d5
		add.w	d0,d5
		move.w	d5,8(a0)
		move.w	d3,d5
		asr.w	#1,d5
		move.w	d3,d6
		asr.w	#3,d6
		sub.w	d6,d5
		add.w	d1,d5
		move.w	d5,10(a0)
		move.w	d2,d5
		asr.w	#1,d5
		move.w	d2,d6
		asr.w	#3,d6
		add.w	d6,d5
		asr.w	#1,d6
		add.w	d6,d5
		add.w	d0,d5
		move.w	d5,16(a0)
		move.w	d3,d5
		asr.w	#1,d5
		move.w	d3,d6
		asr.w	#3,d6
		add.w	d6,d5
		asr.w	#1,d6
		add.w	d6,d5
		add.w	d1,d5
		move.w	d5,18(a0)
		add.w	d0,d2
		add.w	d1,d3
		movem.w	d2/d3,24(a0)
		; their R * 16 wanted: the plate's * 9/16, 11/16, 7/8, 1, + the
		; flame's length * 0, 1, 2, 3 (none if the plate's none: it fades
		; with RB_GLOW)
		lea		.want(pc),a1
		move.w	morphFlR16,d0
		cmp.w	#8,d0
		bhs.s	.w0
		clr.l	(a1)
		clr.l	4(a1)
		bra.s	.w1
.w0:	move.w	d0,d1
		lsr.w	#1,d1
		move.w	d0,d2
		lsr.w	#4,d2
		add.w	d2,d1
		move.w	d1,(a1)
		move.w	d0,d2
		lsr.w	#3,d2
		add.w	d2,d1
		add.w	d4,d1
		move.w	d1,2(a1)
		move.w	d0,d1
		sub.w	d2,d1
		add.w	d4,d1
		add.w	d4,d1
		move.w	d1,4(a1)
		add.w	d4,d0
		add.w	d4,d0
		add.w	d4,d0
		move.w	d0,6(a1)
.w1:	lea		morphChR16,a1
		lea		.want(pc),a4
		lea		.max(pc),a3
		lea		morphChC,a5
		lea		morphChF,a6
		moveq	#0,d7				; the glow
.g:		move.w	(a4)+,d5			; at most its own: they grow from the
		cmp.w	(a3)+,d5			; nozzle to the tip
		bls.s	.g1
		move.w	-2(a3),d5
.g1:	move.w	morphTm,d6			; (0..2: less as the torpedoes take
		beq.s	.g3					; over; 3: as it goes over to the small
		cmp.w	#3,d7				; flame)
		beq.s	.g2
		neg.w	d6
		add.w	#AB_TM,d6
		mulu	d6,d5
		lsr.l	#4,d5				; (/ AB_TM)
		bra.s	.g3
.g2:	neg.w	d6
		add.w	#AB_TM/2,d6
		bpl.s	.g4
		moveq	#0,d6
.g4:	mulu	d6,d5
		lsr.l	#3,d5				; (/ AB_TM/2)
.g3:	move.w	(a1),d6				; softly there
		sub.w	d6,d5
		asr.w	#2,d5
		add.w	d6,d5
		move.w	d5,(a1)+
		move.w	d5,4(a0)
		subq.b	#1,(a5,d7.w)		; its frame: on now and then
		bpl.s	.f9
		moveq	#1,d6				; (0 and 2: every 2 frames, 1 and 3:
		btst	#0,d7				; every 3)
		beq.s	.f0
		moveq	#2,d6
.f0:	move.b	d6,(a5,d7.w)
		move.b	(a6,d7.w),d6
		addq.b	#1,d6
		btst	d7,morphFlRn+1		; (1 or 2 on)
		beq.s	.f1
		addq.b	#1,d6
.f1:	and.b	#abFrames-1,d6
		move.b	d6,(a6,d7.w)
.f9:	moveq	#0,d6				; its flicker: on, off (4 frames round)
	ifne	AB_FLICK
		move.b	morphFrame,d6
		and.w	#3,d6
	ifeq	escortMux
		lea		.flk(pc),a3
	else
		lea		morphChFlk(pc),a3
	endc
		move.b	(a3,d7.w),d5
		btst	d6,d5
		seq		d6
		lea		.max+2(pc),a3		; (back on the caps)
		add.w	d7,a3
		add.w	d7,a3
	endc
		move.b	d6,6(a0)			; (0: shown)
		addq.l	#8,a0
		addq.w	#1,d7
		cmp.w	#4,d7
		blo		.g
		rts
.want:	ds.w	4
.max:	dc.w	4*16,5*16,6*16,7*16	; (R * 16 at most: 4, 5, 6, 7)
	ifeq	escortMux
.flk:	dc.b	%1111,%0101,%0110,%1001	; (frame & 3 -> bit: shown)
	else
morphChFlk:	dc.b	%1111,%0101,%0110,%1001	; (frame & 3 -> bit: shown; the
	endc								; torpedoes' glows too: morphMxTGeo)
morphChC:	dc.b	0,1,0,2			; frames till a glow's next frame ...
morphChF:	dc.b	0,1,2,3			; ... its frame now
		even

	ifeq	escortMux
; d7 = a glow of the chain (0..3): into the sprite at a2 -> d0 = its
; pointer (s3Null: none - too small, flickered off, off the screen)
morphChPut:
	else
; d7 = a glow of the chain (0..3) -> d0/d1 = its left, top, a1 = its first
; row, d5 = rows (0: none - too small, flickered off). uses d2/d3/d6/a0
morphChGeo:
	endc
		move.w	d7,d0
		lsl.w	#3,d0
		lea		morphChP,a0
		add.w	d0,a0
		tst.b	6(a0)				; (flickered off)
		bne.s	.null
		move.w	4(a0),d6			; R
		addq.w	#8,d6
		lsr.w	#4,d6
		beq.s	.null
		add.w	morphFlJ,d6
		cmp.w	#1,d6
		bge.s	.r0
		moveq	#1,d6
.r0:	cmp.w	#MSPR_RMAX,d6
		ble.s	.r1
		moveq	#MSPR_RMAX,d6
.r1:	move.w	d7,d2				; its rows: its kind, its frame, R
		lsl.w	#2,d2				; (abFrames 4: kind * 4 + frame)
		lea		morphChF,a1
		add.b	(a1,d7.w),d2
		add.w	d2,d2
	ifeq	escortMux
		lea		.kf(pc),a1
	else
		lea		morphChKf(pc),a1
	endc
		move.w	(a1,d2.w),d2
		move.w	d6,d3
		add.w	d3,d3
	ifeq	escortMux
		lea		.rr-2(pc),a1
	else
		lea		morphChRr-2(pc),a1
	endc
		add.w	(a1,d3.w),d2
		lea		abImg,a1
		add.w	d2,a1
		movem.w	(a0),d0/d1			; its middle -> its left, top
		subq.w	#7,d0
		sub.w	d6,d1
		move.w	d6,d5
		add.w	d5,d5
		addq.w	#1,d5
	ifeq	escortMux
		moveq	#4,d4
		moveq	#0,d3
		bra		morphSprPut
.null:	move.l	#s3Null,d0
		rts
	else
		rts
.null:	moveq	#0,d5
		rts
	endc
	ifeq	escortMux
.kf:
	else
morphChKf:							; (the torpedoes' glows too)
	endc
MCHI	set		0
	rept	4*4					; (a kind's frame: its first byte; abFrames 4)
		dc.w	MCHI*63*4
MCHI	set		MCHI+1
	endr
	ifeq	escortMux
.rr:
	else
morphChRr:
	endc
MCHI	set		1
	rept	MSPR_RMAX				; (R: its first row's byte)
		dc.w	(MCHI*MCHI-1)*4
MCHI	set		MCHI+1
	endr
	ifeq	escortMux
; d0/d1 = the middle, d6 = R (clamped to 1..MSPR_RMAX): a glow (morphSprImg)
; into the sprite at a2 -> d0 = its pointer
morphGlowPut:
		cmp.w	#1,d6
		bge.s	.r0
		moveq	#1,d6
.r0:	cmp.w	#MSPR_RMAX,d6
		ble.s	.r1
		moveq	#MSPR_RMAX,d6
.r1:	move.w	d6,d2				; its rows: from (R^2 - 1) on
		mulu	d2,d2
		subq.w	#1,d2
		lsl.w	#2,d2
		lea		morphSprImg,a1
		add.w	d2,a1
		moveq	#4,d4
		moveq	#0,d3
		sub.w	d6,d1
		subq.w	#7,d0
		move.w	d6,d5
		add.w	d5,d5
		addq.w	#1,d5
		bra		morphSprPut
	endc

; d0 = a sprite's pointer -> into elSpr at a3, a3 on to the next
morphSprPtr:
		move.w	d0,6(a3)
		swap	d0
		move.w	d0,2(a3)
		addq.l	#8,a3
		rts

; d0/d1 = the image's left, top (game plane), a1 = its first row (plane A,
; B), d4 = from one row to the next (bytes), d5 = rows, d3 = $80 attached
; (the odd sprite of a pair), a2 = the sprite's buffer -> d0 = the sprite's
; pointer (s3Null: not on the screen). cut at the top and the bottom.
; uses d0-d2/d5/a1
morphSprPut:
		add.w	#96,d0				; HSTART
		bmi.s	.null
		cmp.w	#$1c0,d0
		bhs.s	.null
		tst.w	d1					; (rows above the plane: off)
		bpl.s	.y0
		add.w	d1,d5
		neg.w	d1
		mulu	d4,d1
		add.w	d1,a1
		moveq	#0,d1
.y0:	move.w	d1,d2				; (and below it)
		add.w	d5,d2
		sub.w	#game_height,d2
		ble.s	.y1
		sub.w	d2,d5
.y1:	tst.w	d5
		ble.s	.null
		add.w	#$20,d1				; VSTART, VSTOP: the control words
		move.w	d1,d2
		lsl.w	#8,d2
		move.b	d0,d2				; (HSTART >> 1)
		lsr.b	#1,d2
		btst	#8,d0
		beq.s	.h8
		bset	#7,d2
.h8:	move.w	d2,(a2)
		move.w	d1,d2
		add.w	d5,d2				; VSTOP
		lsl.w	#8,d2
		or.b	d3,d2				; (attached)
		btst	#8,d1
		beq.s	.c0
		bset	#2,d2
.c0:	move.w	d1,-(a7)
		add.w	d5,d1
		btst	#8,d1
		beq.s	.c1
		bset	#1,d2
.c1:	move.w	(a7)+,d1
		btst	#0,d0
		beq.s	.c2
		bset	#0,d2
.c2:	move.w	d2,2(a2)
		lea		4(a2),a0
	ifeq	escortMux
		subq.w	#1,d5
.r:		move.l	(a1),(a0)+
		add.w	d4,a1
		dbf		d5,.r
	else
		neg.w	d5					; (rows one after the other, 15 at most:
		add.w	d5,d5				; into the run)
		jmp		.r9(pc,d5.w)
	rept	15
		move.l	(a1)+,(a0)+
	endr
.r9:
	endc
		clr.l	(a0)
		move.l	a2,d0
		rts
.null:	move.l	#s3Null,d0
		rts

; the flame (both sizes): where the plate is, how big - its area (seen edge
; on: small) times the thrust, softly (morphFlR16), the way out behind it;
; the flicker: a new phase every 2..5 frames, the size a little up or down
morphFlGeo:
		subq.b	#1,morphFlPC
		bpl.s	.ph
		move.w	morphFlRn,d0
		moveq	#3,d1
		and.w	d0,d1
		cmp.b	morphFlPh,d1
		bne.s	.p0
		addq.w	#1,d1
		and.w	#3,d1
.p0:	move.b	d1,morphFlPh
		lsr.w	#2,d0
		moveq	#3,d1
		and.w	d0,d1
		addq.w	#2,d1
		move.b	d1,morphFlPC
		lsr.w	#2,d0
		moveq	#3,d1
		and.w	d0,d1
		subq.w	#1,d1				; -1 .. 2: (2 -> 0)
		cmp.w	#2,d1
		bne.s	.p1
		moveq	#0,d1
.p1:	move.w	d1,morphFlJ
		move.w	morphFlRn+2,d0
		moveq	#7,d1
		and.w	d0,d1
		subq.w	#4,d1
		move.w	d1,morphFlTX
		lsr.w	#3,d0
		moveq	#7,d1
		and.w	d0,d1
		subq.w	#4,d1
		move.w	d1,morphFlTY
.ph:	moveq	#0,d6				; the size wanted (R * 16): none ...
		tst.b	morphPShip
		beq		.sz
		tst.b	morphPGlow
		beq		.sz
		lea		morphPXY+7*4,a0		; ... or the plate's: its middle
		move.w	(a0),d0
		add.w	4(a0),d0
		add.w	8(a0),d0
		add.w	12(a0),d0
		asr.w	#2,d0
		move.w	d0,morphFlX
		move.w	2(a0),d1
		add.w	6(a0),d1
		add.w	10(a0),d1
		add.w	14(a0),d1
		asr.w	#2,d1
		move.w	d1,morphFlY
		sub.w	morphPXY,d0			; the way out behind it: from the nose
		move.w	d0,morphFlVX
		sub.w	morphPXY+2,d1
		move.w	d1,morphFlVY
		move.w	8(a0),d2			; its area: the diagonals' cross product
		sub.w	(a0),d2
		move.w	10(a0),d3
		sub.w	2(a0),d3
		move.w	12(a0),d4
		sub.w	4(a0),d4
		move.w	14(a0),d5
		sub.w	6(a0),d5
		muls	d5,d2
		muls	d4,d3
		sub.l	d3,d2
		bpl.s	.a0
		neg.l	d2
.a0:	moveq	#0,d6				; ... its root (the plate's size)
		move.w	#128,d1
.q:		move.w	d6,d3
		add.w	d1,d3
		move.w	d3,d4
		mulu	d4,d4
		cmp.l	d2,d4
		bhi.s	.q1
		move.w	d3,d6
.q1:	lsr.w	#1,d1
		bne.s	.q
		moveq	#0,d1				; the fireball: the plate, up to half as
		move.b	morphPGP+1,d1		; big again with the thrust (R * 16 =
		lsr.w	#1,d1				; root/2 * (256 + thrust/2) / 16)
		add.w	#256,d1
		mulu	d1,d6
		lsr.l	#5,d6
.sz:	move.w	morphFlR16,d0		; softly there
		sub.w	d0,d6
		asr.w	#2,d6
		add.w	d6,d0
		move.w	d0,morphFlR16
		addq.w	#8,d0
		lsr.w	#4,d0
		move.w	d0,morphFlR			; (0: none)
		rts

; -> morphFlRn (two words): the next random numbers (xorshift). uses d0/d1
morphFlRand:
		move.l	morphFlRn,d0
		move.l	d0,d1
		lsl.l	#8,d1
		lsl.l	#5,d1
		eor.l	d1,d0
		move.l	d0,d1
		clr.w	d1
		swap	d1
		lsr.l	#1,d1
		eor.l	d1,d0
		move.l	d0,d1
		lsl.l	#5,d1
		eor.l	d1,d0
		move.l	d0,morphFlRn
		rts
morphFlRn:	dc.l	$6c8e9cf5

	ifeq	escortMux
; the sprite colours 17..31: the torpedoes' (17-19, 21-23: rim, middle,
; core) ...
morphColTorp:	dc.w	$0a20,$0f60,$0ffe,0,$0a20,$0f60,$0ffe,0,0,0,0,0,0,0,0
	endc
; ... the afterburner's (17-19: white, light yellow, yellow - glows 0, 1;
; 21-23: orange, red, dark red - glows 2, 3)
morphColAb:		dc.w	$0fff,$0ffb,$0fe4,0,$0f80,$0e30,$0810

	ifeq	escortMux				; (escortMux: none - the torpedoes' glows
									; are abImg's, no small flame)
; once (morphInit): the glows' rows - the torpedoes' and the small flame's
; (rim, middle, core: 1, 2, 3) by the distance from the middle. (the
; afterburner's: abgen.py -> abflame.i)
morphSprMake:
		movem.l	d0-d7/a0,-(a7)
		lea		morphSprImg,a0		; the glows
		moveq	#1,d6				; R
		moveq	#MSPR_RMAX-1,d7
.sz:	move.w	d6,d5
		mulu	d5,d5				; R^2: the bounds (* 100) of the core,
		move.l	d5,d0				; the middle, the rim (R^2 + R/2: rounder)
		mulu	#16,d0
		move.l	d0,.thC
		move.l	d5,d0
		mulu	#49,d0
		move.l	d0,.thM
		mulu	#100,d5
		move.w	d6,d0
		mulu	#50,d0
		add.l	d0,d5
		move.l	d5,.thR
		move.w	d6,d4
		neg.w	d4					; dy
.row:	moveq	#0,d0				; plane A, B
		moveq	#0,d1
		moveq	#-7,d3				; dx
.px:	add.l	d0,d0				; (the next pixel)
		add.l	d1,d1
		bsr		morphSqD
		mulu	#100,d2				; d^2 * 100
		cmp.l	.thC(pc),d2
		bhi.s	.p1
		addq.l	#1,d0				; core: 3
		addq.l	#1,d1
		bra.s	.pn
.p1:	cmp.l	.thM(pc),d2
		bhi.s	.p2
		addq.l	#1,d1				; middle: 2
		bra.s	.pn
.p2:	cmp.l	.thR(pc),d2
		bhi.s	.pn
		addq.l	#1,d0				; rim: 1
.pn:	addq.w	#1,d3
		cmp.w	#9,d3
		blt.s	.px
		move.w	d0,(a0)+
		move.w	d1,(a0)+
		addq.w	#1,d4
		cmp.w	d6,d4
		ble.s	.row
		addq.w	#1,d6
		dbf		d7,.sz
		movem.l	(a7)+,d0-d7/a0
		rts
.thC:	dc.l	0
.thM:	dc.l	0
.thR:	dc.l	0

; d3 = dx, d4 = dy -> d2 = dx^2 + dy^2. keeps the rest
morphSqD:
		move.w	d3,d2
		muls	d2,d2
		move.w	d4,-(a7)
		muls	d4,d4
		add.l	d4,d2
		move.w	(a7)+,d4
		rts
	endc

; the torpedoes into the draw table: a plasma ball - a diamond that
; twinkles, its size by its distance - then a spark, then a dot; and its
; engine's flare behind it once it burns
morphPTorpDraw:
		move.w	morphPTorpN,d7
		subq.w	#1,d7
		bmi.s	.out
		lea		morphPTorps,a4
.t:		movem.l	d7/a4,-(a7)
		movem.w	(a4),d3/d4			; x, y
		moveq	#0,d0
		move.b	4(a4),d0			; radius
		btst	#TF_DOT,5(a4)
		beq.s	.ball
		move.w	d3,d0
		move.w	d4,d1
		jsr		set_point
		bra.s	.nx
.ball:	movem.w	d3/d4,-(a7)			; (its glow: a sprite, morphTorpSpr)
		cmp.w	#4,d0
		bhs.s	.dia
		bsr		.cross				; (small: a cross, two lines)
		bra.s	.dd
.dia:	bsr		.line4
.dd:	movem.w	(a7)+,d3/d4
		move.l	4(a7),a4
		btst	#TF_FLARE,5(a4)		; its engine's flare: a line out behind it
		beq.s	.nx
		move.b	6(a4),d2
		ext.w	d2
		move.b	7(a4),d5
		ext.w	d5
		move.w	d3,d0
		move.w	d4,d1
		add.w	d0,d2
		add.w	d1,d5
		move.w	d5,d3
		jsr		set_line
.nx:	movem.l	(a7)+,d7/a4
		addq.l	#8,a4
		dbf		d7,.t
.out:	rts
; two lines: a cross of radius d0 round d3/d4
.cross:
		move.w	d0,d5
		move.w	d3,d0
		sub.w	d5,d0
		move.w	d4,d1
		move.w	d3,d2
		add.w	d5,d2
		movem.w	d3-d5,-(a7)
		move.w	d1,d3
		jsr		set_line
		movem.w	(a7)+,d3-d5
		move.w	d3,d0
		move.w	d4,d1
		sub.w	d5,d1
		move.w	d3,d2
		add.w	d5,d4
		move.w	d4,d3
		jmp		set_line
; four lines: the diamond of radius d0 round d3/d4
.line4:
		move.w	d0,d5
		move.w	d3,d0				; left -> top
		sub.w	d5,d0
		move.w	d4,d1
		move.w	d3,d2
		move.w	d4,d3
		sub.w	d5,d3
		movem.w	d0-d5,-(a7)
		jsr		set_line
		movem.w	(a7)+,d0-d5
		move.w	d2,d0				; top -> right
		move.w	d3,d1
		add.w	d5,d2
		add.w	d5,d3
		movem.w	d0-d5,-(a7)
		jsr		set_line
		movem.w	(a7)+,d0-d5
		move.w	d2,d0				; right -> bottom
		move.w	d3,d1
		sub.w	d5,d2
		add.w	d5,d3
		movem.w	d0-d5,-(a7)
		jsr		set_line
		movem.w	(a7)+,d0-d5
		move.w	d2,d0				; bottom -> left
		move.w	d3,d1
		sub.w	d5,d2
		sub.w	d5,d3
		jmp		set_line

;---------------------------------------------
; the live ship's turn, growth and place (the unfolding, the hold)
morphPose:
		tst.b	morphKept
		bne		.done
		; the unfolding: the parts' smoothsteps
		move.w	morphT,d6
		bpl.s	.t0
		moveq	#0,d6
.t0:	lea		morphParts,a1
		lea		morphU,a2
		lea		morphSmooth,a3
		moveq	#5-1,d7
.part:	moveq	#0,d0
		move.w	d6,d0
		sub.w	(a1)+,d0
		bpl.s	.p0
		moveq	#0,d0
.p0:	move.w	(a1)+,d1
		cmp.w	d1,d0
		blo.s	.p1
		move.w	d1,d0
.p1:	lsl.w	#6,d0				; 0..64
		divu	d1,d0
		add.w	d0,d0
		move.w	(a3,d0.w),(a2)+
		dbf		d7,.part
		; the arrow grows a little (from the game's size)
		move.w	morphU,d0
		mulu	#256-morphG0,d0
		lsr.l	#8,d0
		add.w	#morphG0,d0
		mulu	#morphF,d0
		lsr.l	#8,d0
		move.w	d0,morphFG
		; roll and pitch come in with the hull
		move.w	morphU+2,d1
		move.w	d1,d0
		mulu	#morphRoll,d0
		lsr.l	#8,d0
		move.w	d0,morphRollD
		mulu	#morphPitch,d1
		lsr.l	#8,d1
		move.w	d1,morphPitchD
		move.w	obj_xc(a0),morphCX
		move.w	obj_yc(a0),morphCY
		move.w	morphRollD,d0
		bsr		morphSinCos
		move.w	d1,morphCR
		move.w	d0,morphSR
		move.w	morphPitchD,d0
		bsr		morphSinCos
		move.w	d1,morphCP
		move.w	d0,morphSP
		rts
.done:	; unfolded, holding: a body in the world, its place from the ship
		; (obj_xc/yc, at morphZ0), turned as it unfolded
		move.w	obj_xc(a0),d0
		sub.w	#morphVX,d0
		muls	#morphZ0,d0
		divs	#morphF,d0
		move.w	d0,morphSX
		move.w	obj_yc(a0),d0
		sub.w	#morphVY,d0
		muls	#morphZ0,d0
		divs	#morphF,d0
		move.w	d0,morphSY
		move.l	#morphZ0,morphSZ
		move.w	morphRollD,d0
		lsl.w	#4,d0
		move.w	d0,morphR16
		move.w	morphPitchD,d0
		lsl.w	#4,d0
		move.w	d0,morphP16
		clr.w	morphY16
		clr.w	morphT16
		clr.w	morphH16
		; (falls through)

; the turn (morphR16..morphH16) as a matrix and the place (morphSX/SY/SZ),
; for morphPointsK - the hold's and the sim's
morphPoseW:
		; far off: all of it smaller by a shift, so the depth fits the table
		move.l	morphSZ,d2
		move.w	morphSX,d0
		move.w	morphSY,d1
		moveq	#0,d3
.sh:	cmp.l	#16000,d2
		ble.s	.sh0
		asr.l	#1,d2
		asr.w	#1,d0
		asr.w	#1,d1
		addq.w	#1,d3
		bra.s	.sh
.sh0:	move.w	d2,morphSZs
		move.w	d0,morphSXs
		move.w	d1,morphSYs
		move.w	d3,morphSh
		; the turn as one matrix, Q15: roll, pitch, yaw, then the tilt
		move.w	morphR16,d0
		bsr		morphSinCos16
		move.w	d1,morphCR
		move.w	d0,morphSR
		move.w	morphP16,d0
		bsr		morphSinCos16
		move.w	d1,morphCP
		move.w	d0,morphSP
		move.w	morphY16,d0
		bsr		morphSinCos16
		move.w	d0,d6				; syw
		move.w	d1,d7				; cyw
		lea		morphM,a2
		move.w	morphSP,d4
		move.w	morphSR,d0
		muls	d4,d0
		add.l	d0,d0
		swap	d0					; t1 = sr sp
		move.w	morphCR,d1
		muls	d4,d1
		add.l	d1,d1
		swap	d1					; t2 = cr sp
		move.w	morphCP,d5
		; m00 = cp cyw
		move.w	d5,d2
		muls	d7,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; m01 = -t1 cyw - cr syw
		move.w	d0,d2
		muls	d7,d2
		move.w	morphCR,d3
		muls	d6,d3
		add.l	d3,d2
		neg.l	d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; m02 = -t2 cyw + sr syw
		move.w	d1,d2
		muls	d7,d2
		move.w	morphSR,d3
		muls	d6,d3
		sub.l	d2,d3
		add.l	d3,d3
		swap	d3
		move.w	d3,(a2)+
		; m10 = cp syw
		move.w	d5,d2
		muls	d6,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; m11 = -t1 syw + cr cyw
		move.w	morphCR,d2
		muls	d7,d2
		move.w	d0,d3
		muls	d6,d3
		sub.l	d3,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; m12 = -t2 syw - sr cyw
		move.w	d1,d2
		muls	d6,d2
		move.w	morphSR,d3
		muls	d7,d3
		add.l	d3,d2
		neg.l	d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; m20 = sp, m21 = sr cp, m22 = cr cp
		move.w	d4,(a2)+
		move.w	morphSR,d2
		muls	d5,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		move.w	morphCR,d2
		muls	d5,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,(a2)+
		; the tilt (about the screen's x, + its nose up): y' = c y + s z,
		; z' = -s y + c z, column by column
		move.w	morphT16,d0
		beq.s	.noTilt
		bsr		morphSinCos16		; d0 s, d1 c
		lea		morphM+6,a2			; row y
		moveq	#3-1,d7
.tc:	move.w	(a2),d2				; y
		move.w	6(a2),d3			; z
		move.w	d2,d4
		muls	d1,d4
		move.w	d3,d5
		muls	d0,d5
		add.l	d5,d4
		add.l	d4,d4
		swap	d4
		move.w	d4,(a2)
		muls	d1,d3
		muls	d0,d2
		sub.l	d2,d3
		add.l	d3,d3
		swap	d3
		move.w	d3,6(a2)
		addq.l	#2,a2
		dbf		d7,.tc
.noTilt:
		; the heading (about the screen's up: + its nose to the right while
		; it flies away): x' = c x - s z, z' = s x + c z
		move.w	morphH16,d0
		beq.s	.out
		bsr		morphSinCos16
		lea		morphM,a2			; rows x (0) and z (12)
		moveq	#3-1,d7
.hc:	move.w	(a2),d2
		move.w	12(a2),d3
		move.w	d2,d4
		muls	d1,d4
		move.w	d3,d5
		muls	d0,d5
		sub.l	d5,d4
		add.l	d4,d4
		swap	d4
		move.w	d4,(a2)
		muls	d0,d2
		muls	d1,d3
		add.l	d2,d3
		add.l	d3,d3
		swap	d3
		move.w	d3,12(a2)
		addq.l	#2,a2
		dbf		d7,.hc
.out:	rts

; the points d6.. (d7+1 of them): unfolded as far as their part is,
; turned, onto the screen
morphPoints:
		move.w	d6,d0
		mulu	#mp_len,d0
		lea		morphPts,a1
		add.w	d0,a1
		move.w	d6,d0
		lsl.w	#2,d0
		lea		morphXY,a2
		add.w	d0,a2
		tst.b	morphKept
		beq		morphPtsU
		bra.s	morphKm
; the same, unfolded always (the sim)
morphPointsK:
		move.w	d6,d0
		mulu	#mp_len,d0
		lea		morphPts,a1
		add.w	d0,a1
		move.w	d6,d0
		lsl.w	#2,d0
		lea		morphXY,a2
		add.w	d0,a2
		; unfolded: the end points through the matrix (morphPoseW), and
		; onto the screen from where the ship is in the world
morphKm:
.km:	movem.w	(a1),d0-d2
		add.w	6(a1),d0
		add.w	8(a1),d1
		add.w	10(a1),d2
		lsl.w	#4,d0
		lsl.w	#4,d1
		lsl.w	#4,d2
		lea		morphM,a3
		move.w	(a3)+,d4
		muls	d0,d4
		move.w	(a3)+,d5
		muls	d1,d5
		add.l	d5,d4
		move.w	(a3)+,d5
		muls	d2,d5
		add.l	d5,d4
		add.l	d4,d4
		swap	d4					; x (across)
		move.w	(a3)+,d3
		muls	d0,d3
		move.w	(a3)+,d5
		muls	d1,d5
		add.l	d5,d3
		move.w	(a3)+,d5
		muls	d2,d5
		add.l	d5,d3
		add.l	d3,d3
		swap	d3					; y (down)
		move.w	(a3)+,d5
		muls	d0,d5
		move.w	(a3)+,d6
		muls	d1,d6
		add.l	d6,d5
		move.w	(a3)+,d6
		muls	d2,d6
		add.l	d6,d5
		add.l	d5,d5
		swap	d5					; z (+: towards the eye)
		move.w	morphSh,d1
		asr.w	d1,d4
		asr.w	d1,d3
		asr.w	d1,d5
		move.w	morphSZs,d1
		sub.w	d5,d1
		cmp.w	#morphClipZ,d1		; (too near the eye: not drawn)
		bge.s	.kc
		st		morphClip
.kc:	cmp.w	#64,d1				; (never at or behind the eye)
		bge.s	.kz
		moveq	#64,d1
.kz:	lsr.w	#3,d1				; the lens over the depth: the table
		add.w	d1,d1				; (morphInit)
		lea		morphRcp,a3
		move.w	(a3,d1.w),d0
		add.w	morphSXs,d4
		muls	d0,d4
		asr.l	#8,d4
		asr.l	#4,d4
		add.w	#morphVX,d4
		add.w	morphSYs,d3
		muls	d0,d3
		asr.l	#8,d3
		asr.l	#4,d3
		add.w	#morphVY,d3
		move.w	d4,(a2)+
		move.w	d3,(a2)+
		lea		mp_len(a1),a1
		dbf		d7,.km
		rts
morphPtsU:
		movem.w	(a1),d0-d2			; start
		movem.w	6(a1),d3-d5			; the way to the end
		move.w	12(a1),d6			; its part's smoothstep
		add.w	d6,d6
		lea		morphU,a3
		move.w	(a3,d6.w),d6
		lsl.w	#4,d0				; 1/16 units: x*16 + d*u/16
		lsl.w	#4,d1
		lsl.w	#4,d2
		muls	d6,d3
		asr.l	#4,d3
		add.w	d3,d0
		muls	d6,d4
		asr.l	#4,d4
		add.w	d4,d1
		muls	d6,d5
		asr.l	#4,d5
		add.w	d5,d2
		; roll about x: y' = y cr - z sr, z' = y sr + z cr
		move.w	d1,d3
		muls	morphCR,d3
		move.w	d2,d4
		muls	morphSR,d4
		sub.l	d4,d3
		add.l	d3,d3
		swap	d3					; y'
		muls	morphSR,d1
		muls	morphCR,d2
		add.l	d1,d2
		add.l	d2,d2
		swap	d2					; z'
		; pitch about y: x'' = x cp - z' sp, z'' = x sp + z' cp
		move.w	d0,d4
		muls	morphCP,d4
		move.w	d2,d5
		muls	morphSP,d5
		sub.l	d5,d4
		add.l	d4,d4
		swap	d4					; x''
		muls	morphSP,d0
		muls	morphCP,d2
		add.l	d0,d2
		add.l	d2,d2
		swap	d2					; z'' (+: towards the eye)
		; onto the screen round the ship: * lens*growth / (depth - z'')
		move.w	#morphZ0,d1
		sub.w	d2,d1
		moveq	#0,d0				; (4.12)
		move.w	morphFG,d0
		lsl.l	#8,d0
		lsl.l	#4,d0
		divu	d1,d0
		muls	d0,d4
		asr.l	#8,d4
		asr.l	#4,d4
		muls	d0,d3
		asr.l	#8,d3
		asr.l	#4,d3
		add.w	morphCX,d4
		add.w	morphCY,d3
		move.w	d4,(a2)+
		move.w	d3,(a2)+
		lea		mp_len(a1),a1
		dbf		d7,morphPtsU
		rts

; the faces seen, from the projected corners: (b-a) x (c-a) of a face's
; corners points out of the hull (morphFaces), and the screen keeps the
; turn's hand (x right, y down, z to the eye like the model's x forward, y
; right, z up) - so a face towards us comes out positive
morphFaceVis:
		lea		morphFaces,a1
		lea		morphXY,a2
		lea		morphFV,a3
		moveq	#0,d6
		moveq	#morphNF-1,d7
.f:		moveq	#0,d0
		move.b	(a1)+,d0
		movem.w	(a2,d0.w),d0/d1		; a
		moveq	#0,d2
		move.b	(a1)+,d2
		movem.w	(a2,d2.w),d2/d3		; b
		moveq	#0,d4
		move.b	(a1)+,d4
		movem.w	(a2,d4.w),d4/d5		; c
		sub.w	d0,d2				; b-a
		sub.w	d1,d3
		sub.w	d0,d4				; c-a
		sub.w	d1,d5
		muls	d2,d5				; (bx-ax)(cy-ay)
		muls	d3,d4				; (by-ay)(cx-ax)
		sub.l	d4,d5
		sgt		(a3)+
		ble.s	.nv
		moveq	#8,d0				; (and a bit for each face seen: the
		sub.w	d7,d0				; unfolded ship's quick line loop)
		bset	d0,d6
.nv:	dbf		d7,.f
		move.w	d6,morphFMask

		rts
; a4 = an edge -> NE if one of its faces is seen (or it is on none)
morphSeen:
		move.b	2(a4),d2
		bmi.s	.yes
		ext.w	d2
		lea		morphFV,a1
		tst.b	(a1,d2.w)
		bne.s	.yes
		move.b	3(a4),d2
		bmi.s	.no
		ext.w	d2
		tst.b	(a1,d2.w)
		rts
.yes:	moveq	#1,d2
		rts
.no:	moveq	#0,d2
		rts

; a4 = an edge: its line into the table at a6 (the cache) (and once more a
; line lower while it glows). keeps a4
morphLine:
		lea		morphXY,a1
		moveq	#0,d0
		move.b	(a4),d0
		moveq	#0,d2
		move.b	1(a4),d2
		movem.w	(a1,d0.w),d0/d1
		movem.w	(a1,d2.w),d2/d3
		movem.w	d0-d3,-(a7)
		jsr		set_line
		movem.w	(a7)+,d0-d3
		tst.w	morphGlowE
		beq.s	.out
		addq.w	#1,d1
		addq.w	#1,d3
		jsr		set_line
.out:	rts

;---------------------------------------------
; once, at the start (warp.i warpInit): the lens over the depth, an eighth
; of a unit apart (4.12) - no division a point once the ship is unfolded
morphInit:
		jsr		s3Init				; (stars3d.i: its tables)
	ifeq	escortMux
		bsr		morphSprMake		; (the torpedoes' glows)
	endc
		lea		morphRcp,a0
		moveq	#0,d1
.r:		move.w	d1,d2
		lsl.w	#3,d2
		cmp.w	#64,d2
		bhs.s	.r0
		moveq	#64,d2
.r0:	move.l	#morphF<<12,d0
		divu	d2,d0
		move.w	d0,(a0)+
		addq.w	#1,d1
		cmp.w	#morphRcpN,d1
		bne.s	.r
		bra		morphSimInit		; the flight is worked out from now on

morphRcpN	= 2200		; up to a depth of 17600 (1/16 units)

;======================================================================
; THE SIM: the flight worked out beforehand, frame by frame, into
; morphRec (the play reads it). its own state; the pose variables it
; shares with the live ship (morphSwapA..E) are swapped in while the live
; ship is still about (the unfolding, the hold)
;======================================================================
SP_OPEN		= 0
SP_PASS		= 1
SP_LOOP		= 2
SP_ENTRY	= 3
SP_ESCORT	= 4
SP_BREAK	= 5
SP_WAIT		= 6
SP_END		= 7

morphSimOn::	dc.b	0		; the sim runs
morphSimEnd::	dc.b	0		; ... and is through (the last frame written)
simResident:	dc.b	0		; its pose variables are in place (no swap)
simHidden:		dc.b	0		; (this frame) the ship is not drawn
simGone:		dc.b	0		; it has gone past: not drawn (till the attack)
simPrevHid:		dc.b	-1		; the last frame written had no ship
simEngine:		dc.b	0		; its engine burns (the drone)
simFlyOn:		dc.b	0		; (this frame) the nose along its way
simFlyNew:		dc.b	0		; ... the first frame of it (no bank yet)
				even
morphSimN::		dc.w	0		; frames written
morphPlayN::	dc.w	0		; frames played
morphStalls::	dc.w	0		; frames the play had to wait (stays 0)
morphLeadLow::	dc.w	$7fff	; the least lead the play had
morphSimStepN:	dc.w	0		; the step of the frame next
morphSimLine0:	dc.w	0		; (morphSimRun) the line it started on
morphSimW::		dc.l	morphRec
morphPlayR:		dc.l	morphRec
simT:			dc.w	0		; the frame being worked out (from the play's start)
simPhase::		dc.w	0
simPT:			dc.w	0		; frames in the phase
simList:		dc.l	0		; the maneuver now (a block)
simBT:			dc.w	0		; frames into it
simEv:			dc.w	0		; this frame's events (RB_ bits)
; its middle and speed (springs: place, speed), 1/4096 units: across, down,
; ahead
simX:			dc.l	0
simVX:			dc.l	0
simY:			dc.l	0
simVY:			dc.l	0
simZ:			dc.l	0
simVZ:			dc.l	0
simHS:			dc.l	0		; (MV_TURNTO) the heading's spring, 1/4096 deg
simHV:			dc.l	0
simX0:			dc.w	0		; where it set off (1/16 units)
simY0:			dc.w	0
simXo:			dc.l	0		; last frame's place
simYo:			dc.l	0
simZo:			dc.l	0
simWX:			dc.l	0		; its way this frame (1/4096 units)
simWY:			dc.l	0
simWZ:			dc.l	0
simWXo:			dc.l	0		; ... across, last frame
simVz:			dc.w	256		; the stars' speed (8.8 times warpVz)
simVc:			dc.w	11		; ours, 1/16 units a frame
simRoll:		dc.w	0		; its turn, 1/16 degrees (-> morphR16..)
simPitch:		dc.w	0
simYaw:			dc.w	0
simTilt:		dc.w	0
simHead:		dc.w	0
simBank:		dc.w	0		; the bank from its turns
simA0:			dc.w	0		; a block's start values
simA1:			dc.w	0
simA2:			dc.w	0
simMX:			dc.w	0		; a block's offset (1/16 units): across, down,
simMY:			dc.w	0		; ahead
simMZ:			dc.w	0
simMR:			dc.w	0		; ... its own roll, heading (1/16 degrees)
simBX:			dc.w	0		; (MV_MOVE) the escort's place moved: across,
simBZ:			dc.w	0		; ahead (1/16 units)
simMH:			dc.w	0
simFishS:		dc.w	0		; (MV_FISH) the side, frames till the swing,
simFishT:		dc.w	0		; the yaw kick
simFishH:		dc.w	0
simThrust:		dc.w	0		; 0..256
simThrT:		dc.w	0		; ... where it goes
simJit:			dc.w	0		; (the pilot) frames till the next correction
simDodgeT:		dc.w	0		; (the pass) frames into its evade, + 1
simEvV:			dc.w	0		; ... its speed in the world (1/256 units a frame)
simEvTh:		dc.w	0		; ... its nose (1/16 degrees: 0 ahead, 90 up)
simEvG:			dc.w	0		; ... its way (following the nose)
simEvB:			dc.w	0		; ... its loop's lean (1/16 degrees, + left)
simEvH:			dc.w	0		; ... its heading, roll in the loop (simEvPose)
simEvR:			dc.w	0
simEvHr:		dc.w	0		; ... what it had of a heading (dying away)
simJkT:			dc.w	0		; (the pass) frames into its swerves, + 1
simSpK:			dc.w	morphSpK	; the spring its place follows (simSpringP)
simSpD:			dc.w	morphSpD
simJX:			dc.w	0		; ... its offset (1/16 units)
simJY:			dc.w	0
simRnd:			dc.l	$2545f491	; its own random numbers: the same flight always
simSnd1V:		dc.w	0		; this frame's engine sound: volume, period
simSnd1P:		dc.w	0
simSnd3V:		dc.w	0		; ... a torpedo's
simSnd3P:		dc.w	0
simZOld:		dc.l	0		; (the Doppler)
simPrevMask:	dc.w	-1
simPrevVz:		dc.w	-1
simPrevGlow:	dc.w	-1
simPrev:		ds.w	2*morphNP	; the points last written
simPhLast:		dc.w	-1
morphPhT::		ds.w	8		; (the harness) the frame each phase began

;---------------------------------------------
; from seq_deftest (the Defender ship comes in for the last words) - or
; seq_deffire, seq_morph: the sim starts (once). keeps every register
morphSimInit::
		tst.b	morphSimOn
		bne.s	.out
		movem.l	d0-d1/a0,-(a7)
		sf		morphSimEnd
		sf		simResident
		st		simPrevHid
		sf		simEngine
		sf		simGone
		sf		simFlyNew
		clr.w	morphSimN
		clr.w	morphPlayN
		clr.w	morphStalls
		move.w	#$7fff,morphLeadLow
		clr.w	morphSimStepN
		move.l	#morphRec,morphSimW
		move.l	#morphRec,morphPlayR
		clr.w	simT
		clr.w	simPhase
		move.w	#-1,simPhLast
		clr.w	simPT
		move.l	#morphOpenList,simList
		clr.w	simBT
		; where it unfolds (as morphPose has it: seq_mX/seq_mY at morphZ0)
		move.w	#seq_mX-morphVX,d0
		muls	#morphZ0,d0
		divs	#morphF,d0
		move.w	d0,simX0
		ext.l	d0
		asl.l	#8,d0
		move.l	d0,simX
		move.l	d0,simXo
		move.w	#seq_mY-morphVY,d0
		muls	#morphZ0,d0
		divs	#morphF,d0
		move.w	d0,simY0
		ext.l	d0
		asl.l	#8,d0
		move.l	d0,simY
		move.l	d0,simYo
		move.l	#morphZ0<<8,simZ
		move.l	#morphZ0<<8,simZo
		clr.l	simVX
		clr.l	simVY
		clr.l	simVZ
		clr.l	simWXo
		; turned as it unfolded, seen from above
		move.w	#morphRoll*16,simRoll
		move.w	#morphPitch*16,simPitch
		clr.w	simYaw
		clr.w	simTilt
		clr.w	simHead
		clr.w	simBank
		move.w	#256,simVz
		move.w	#11,simVc
		clr.w	simThrust
		clr.w	simThrT
		clr.w	simJit
		clr.w	simDodgeT
		clr.w	simJkT
		move.w	#morphSpK,simSpK
		move.w	#morphSpD,simSpD
		clr.w	simJX
		clr.w	simJY
		move.l	#$2545f491,simRnd
		move.w	#-1,simPrevMask
		move.w	#-1,simPrevVz
		move.w	#-1,simPrevGlow
		clr.l	simZOld
		clr.w	simSnd1V
		move.w	#morphPerShip,simSnd1P
		lea		morphTorps,a0
		moveq	#morphTorpN*tp_len/2-1,d0
.c:		clr.w	(a0)+
		dbf		d0,.c
		clr.w	morphTorpNext
		clr.w	morphTorpLeft
		clr.w	morphPTorpN
		sf		morphPShip
		sf		morphPark
		move.w	#256,morphVz
		st		morphSimOn
		movem.l	(a7)+,d0-d1/a0
.out:	rts

;---------------------------------------------
; the end of updateScroller: the sim works on in what is left of the
; frame, a step at a time, till raster line morphSimLine
morphSimRun::
		tst.b	morphSimOn
		beq.s	.out
		tst.b	morphSimEnd
		bne.s	.out
		movem.l	d0-d7/a0-a6,-(a7)
		bsr.s	.line
		move.w	d0,morphSimLine0
		cmp.w	#morphSimLine,d0
		bhs.s	.done
		tst.b	simResident			; its pose variables in
		bne.s	.loop
		bsr		morphSwap
.loop:	bsr		morphSimStep
		tst.b	morphSimEnd
		bne.s	.stop
		bsr.s	.line
		cmp.w	morphSimLine0,d0	; (round into the next frame: stop)
		blo.s	.stop
		cmp.w	#morphSimLine,d0
		blo.s	.loop
.stop:	cmp.b	#MP_PLAY,morphPhase	; the live ship about: its variables back
		bhs.s	.res
		bsr		morphSwap
		bra.s	.done
.res:	st		simResident
.done:	movem.l	(a7)+,d0-d7/a0-a6
.out:	rts
.line:	move.l	$dff004,d0			; -> d0 = the raster line
		lsr.l	#8,d0
		and.w	#$1ff,d0
		rts

; the shared pose variables against their other copy
morphSwap:
		lea		morphSwapA,a0
		lea		morphSimSwap,a1
		moveq	#(morphSwapE-morphSwapA)/4-1,d0
.x:		move.l	(a0),d1
		move.l	(a1),(a0)+
		move.l	d1,(a1)+
		dbf		d0,.x
		rts

; one step of a frame (none more than 3k cycles)
morphSimStep:
		move.w	morphSimStepN,d0
		addq.w	#1,morphSimStepN
		add.w	d0,d0
		move.w	.tab(pc,d0.w),d0
		jmp		.tab(pc,d0.w)
.tab:	dc.w	.s0-.tab,.s1-.tab,.s2-.tab,.s3-.tab,.s4-.tab,.s5-.tab
		dc.w	.s6-.tab
.s0:	bsr		morphSimTick
		rts
.s1:	tst.b	simHidden
		bne.s	.skip
		bsr		morphPoseW
		rts
.s2:	moveq	#0,d6
		bra.s	.pts
.s3:	moveq	#3,d6
		bra.s	.pts
.s4:	moveq	#6,d6
.pts:	tst.b	simHidden
		bne.s	.skip
		moveq	#3-1,d7
		bsr		morphPtsF
		rts
.s5:	tst.b	simHidden
		bne.s	.skip
		bsr		morphFaceVis
		rts
.s6:	clr.w	morphSimStepN
		bsr		simEncode
		rts
.skip:	rts

; the points, quicker (the sim): the fighter is the same left and right,
; so a pair of points is one turned half (x, z) and the other (y) added or
; taken away. d6 = the first pair (morphPF), d7 = pairs-1. on the way the
; sides of the screen all of them are off (morphOutAnd) and the points
; kept within a line's reach (+-8000). uses all registers
morphPtsF:
		mulu	#10,d6
		lea		morphPF,a1
		add.w	d6,a1
.e:		movem.w	(a1)+,d0-d2			; x, y, z (1/16 units)
		lea		morphM,a3
		move.w	(a3),d3				; A = x col0 + z col2
		muls	d0,d3
		move.w	4(a3),d6
		muls	d2,d6
		add.l	d6,d3
		move.w	6(a3),d4
		muls	d0,d4
		move.w	10(a3),d6
		muls	d2,d6
		add.l	d6,d4
		move.w	12(a3),d5
		muls	d0,d5
		move.w	16(a3),d6
		muls	d2,d6
		add.l	d6,d5
		move.l	d3,a4
		move.l	d4,a5
		move.l	d5,a6
		move.w	(a1)+,a2			; (the point with +y)
		tst.w	d1					; B = y col1
		beq.s	.single
		move.w	2(a3),d0
		muls	d1,d0
		move.w	8(a3),d2
		muls	d1,d2
		move.w	14(a3),d6
		muls	d1,d6
		add.l	d0,d3				; A + B
		add.l	d2,d4
		add.l	d6,d5
		bsr.s	.one
		move.l	a4,d3				; A - B
		sub.l	d0,d3
		move.l	a5,d4
		sub.l	d2,d4
		move.l	a6,d5
		sub.l	d6,d5
		move.w	(a1)+,a2
		bsr.s	.one
		dbf		d7,.e
		rts
.single:
		bsr.s	.one
		addq.l	#2,a1
		dbf		d7,.e
		rts
; d3/d4/d5 = x, y, z turned (Q15 sums), a2 = its place in morphXY: onto
; the screen (as morphKm). uses d1/d3-d5/a3
.one:	add.l	d3,d3
		swap	d3
		add.l	d4,d4
		swap	d4
		add.l	d5,d5
		swap	d5
		move.w	morphSh,d1
		beq.s	.n0
		asr.w	d1,d3
		asr.w	d1,d4
		asr.w	d1,d5
.n0:	move.w	morphSZs,d1
		sub.w	d5,d1
		cmp.w	#morphClipZ,d1
		bge.s	.kc
		st		morphClip
.kc:	cmp.w	#64,d1
		bge.s	.kz
		moveq	#64,d1
.kz:	lsr.w	#3,d1
		add.w	d1,d1
		lea		morphRcp,a3
		move.w	(a3,d1.w),d1
		add.w	morphSXs,d3
		muls	d1,d3
		asr.l	#8,d3
		asr.l	#4,d3
		add.w	#morphVX,d3
		add.w	morphSYs,d4
		muls	d1,d4
		asr.l	#8,d4
		asr.l	#4,d4
		add.w	#morphVY,d4
		; (within a line's reach)
		cmp.w	#8000,d3
		ble.s	.c0
		move.w	#8000,d3
.c0:	cmp.w	#-8000,d3
		bge.s	.c1
		move.w	#-8000,d3
.c1:	cmp.w	#8000,d4
		ble.s	.c2
		move.w	#8000,d4
.c2:	cmp.w	#-8000,d4
		bge.s	.c3
		move.w	#-8000,d4
.c3:	; the sides it is off
		moveq	#0,d1
		tst.w	d3
		bpl.s	.o0
		moveq	#1,d1
.o0:	cmp.w	#game_width,d3
		blt.s	.o1
		addq.w	#2,d1
.o1:	tst.w	d4
		bpl.s	.o2
		addq.w	#4,d1
.o2:	cmp.w	#game_height,d4
		blt.s	.o3
		addq.w	#8,d1
.o3:	and.b	d1,morphOutAnd
		lea		morphXY,a3
		move.w	d3,(a3,a2.w)
		move.w	d4,2(a3,a2.w)
		rts
morphOutAnd:	dc.b	0		; (morphPtsF) the sides all points are off
				even
; the pairs: x, y, z (1/16 units: the fighter's end points), the point
; with +y, the one with -y (as offsets into morphXY)
MPF		macro
		dc.w	(\1)*16,(\2)*16,(\3)*16,(\4)*4,(\5)*4
		endm
morphPF:
		MPF		40,0,0,0,0			; the nose
		MPF		16,0,3,11,11		; the canopy's front
		MPF		-24,12,9,2,1		; the back corners
		MPF		-24,12,-6,4,3
		MPF		-32,38,0,6,5		; the wing tips
		MPF		-24,7,5,8,7			; the engine plate
		MPF		-24,7,-2,9,10
		MPF		-6,6,6,13,12		; the canopy's back
		MPF		-6,38,0,15,14		; the guns

;---------------------------------------------
; a frame of the flight: where it is, how it is turned, what it does
morphSimTick:
		move.w	simPhase,d0			; (a new phase: its first frame noted)
		cmp.w	simPhLast,d0
		beq.s	.ph
		move.w	d0,simPhLast
		add.w	d0,d0
		lea		morphPhT,a1
		move.w	simT,(a1,d0.w)
.ph:	clr.w	simEv
		sf		simHidden
		sf		simFlyOn
		sf		morphClip
		move.b	#$f,morphOutAnd
		clr.w	simMX
		clr.w	simMY
		clr.w	simMZ
		clr.w	simMR
		clr.w	simMH
		move.w	simPhase,d0
		add.w	d0,d0
		lea		.tab(pc),a1
		move.w	(a1,d0.w),d0
		jsr		(a1,d0.w)
		addq.w	#1,simPT
		addq.w	#1,simT
		; its way this frame (for the nose and the Doppler)
		move.l	simX,d0
		move.l	d0,d1
		sub.l	simXo,d0
		move.l	d0,simWX
		move.l	d1,simXo
		move.l	simY,d0
		move.l	d0,d1
		sub.l	simYo,d0
		move.l	d0,simWY
		move.l	d1,simYo
		move.l	simZ,d0
		move.l	d0,d1
		sub.l	simZo,d0
		move.l	d0,simWZ
		move.l	d1,simZo
		tst.b	simFlyOn
		beq.s	.nf
		bsr		simFly
.nf:	bsr		morphTorpMove
		move.w	simThrT,d0			; the thrust follows the maneuver's
		sub.w	simThrust,d0
		asr.w	#3,d0
		add.w	d0,simThrust
		bsr		simSound
		; the pose for morphPoseW
		move.w	simRoll,morphR16
		move.w	simPitch,morphP16
		move.w	simYaw,morphY16
		move.w	simTilt,morphT16
		move.w	simHead,morphH16
		move.l	simX,d0
		asr.l	#8,d0
		move.w	d0,morphSX
		move.l	simY,d0
		asr.l	#8,d0
		move.w	d0,morphSY
		move.l	simZ,d0
		asr.l	#8,d0
		move.l	d0,morphSZ
		cmp.l	#morphNear,d0		; past us, behind us: not drawn
		bge.s	.n
		st		simHidden
.n:		tst.b	simGone
		beq.s	.g
		st		simHidden
.g:		rts
.tab:	dc.w	simOpen-.tab,simPass-.tab,simLoop-.tab,simEntry-.tab
		dc.w	simEscort-.tab,simBreak-.tab,simWait-.tab,simEndP-.tab

; --- the start: Zeronine wakes up (morphOpenList)
simOpen:
		bsr		simBlock
		tst.w	d0
		bne.s	.sp
		move.w	#SP_PASS,simPhase	; through: the pass
		move.w	#-1,simPT
.sp:	; its place: where it unfolded, a block's offset, the spring
		move.w	simX0,d0
		move.w	simY0,d1
		move.w	#morphZ0>>4,d2		; (>>4: the spring's z in 1/16 units <<4)
		bra		simTargets

; --- the pass: it flies off ahead of us, the same way as we do; we pick
;     up speed - the stars faster and faster - and catch up with it only
;     slowly (it is fast too, and big, and far): it grows and grows. near
;     us it dodges - a quick roll and a jink - and we go past it on its
;     right
simPass:
		tst.w	simPT
		bne.s	.p
		st		simFlyNew			; (the nose along its way from here)
		move.w	#morphSpK2,simSpK	; (heavier from here on)
		move.w	#morphSpD2,simSpD
.p:		; the stars faster and faster (u^3): we fly
		move.w	simPT,d0
		move.w	#morphPassT,d1
		bsr		morphUnit			; d0 u 0..256
		move.w	d0,d4
		move.w	d0,d1
		mulu	d0,d1
		lsr.l	#8,d1
		mulu	d0,d1
		lsr.l	#8,d1				; u^3
		mulu	#morphVzPass-1,d1
		add.w	#256,d1
		move.w	d1,simVz
		bsr		simOurSpeed
		; the depth: we are only a little faster than it is
		moveq	#morphClose0,d0
		move.w	d4,d1
		mulu	#morphClose1-morphClose0,d1
		lsr.l	#8,d1
		add.w	d1,d0
		tst.w	simDodgeT			; (in its evade: its own way)
		beq.s	.c0
		bsr		simEvade
		bra.s	.c9
.c0:	move.w	d0,d5
		asl.l	#8,d0
		sub.l	d0,simZ
		move.w	#128,simThrT
		; on a beat, coming near: it sees us ("I'm being followed") - two
		; heavy swerves, left, then right and down: there it waits, low on
		; the right; six beats on (a beat): the afterburner (from the next
		; frame on: simEvade)
		moveq	#0,d0
		move.w	simT,d0
		addq.w	#1,d0				; (the next frame)
		divu	#morphBeat,d0
		swap	d0					; (0: on a beat)
		move.w	simJkT,d1
		bne.s	.j1
		tst.w	d0
		bne.s	.ne
		cmp.l	#(morphJkZ*16)<<8,simZ
		bgt.s	.ne
		move.w	#1,simJkT			; (the swerves from the next frame on)
		bra.s	.ne
.j1:	addq.w	#1,simJkT
		cmp.w	#morphJkT,d1
		blo.s	.ne
		tst.w	d0
		bne.s	.ne
		neg.w	d5
		move.w	d5,simEvV			; (coming nearer: its speed from us < 0)
		move.w	#1,simDodgeT
.ne:	; across and up/down: where it is held (the swerves), a correction
		; now and then
		bsr		simJitter
		move.w	simX0,d0
		move.w	simY0,d1
		move.w	simJkT,d2
		beq.s	.h
		subq.w	#2,d2				; (frames in)
		cmp.w	#morphJk1,d2
		bhs.s	.h1
		move.w	d2,d0				; left (eased) ...
		move.w	#morphJk1,d1
		bsr		simSmooth
		move.w	simX0,d2
		move.w	d2,d3
		add.w	#morphJkL,d3
		bsr		simLerpF
		move.w	d2,d0
		move.w	simY0,d1
		bra.s	.h
.h1:	sub.w	#morphJk1,d2		; ... then right, and down (eased)
		move.w	d2,d0
		move.w	#morphJk2-morphJk1,d1
		bsr		simSmooth
		move.w	d0,-(a7)
		move.w	simX0,d2
		add.w	#morphJkL,d2
		move.w	#morphLrX,d3
		bsr		simLerpF
		move.w	(a7)+,d0
		move.w	d2,-(a7)
		move.w	simY0,d2
		move.w	#morphLrY,d3
		bsr		simLerpF
		move.w	d2,d1
		move.w	(a7)+,d0
.h:		move.w	d1,-(a7)
		add.w	simJX,d0
		ext.l	d0
		asl.l	#8,d0
		lea		simX,a1
		bsr		simSpringP
		move.w	(a7)+,d0
		add.w	simJY,d0
		ext.l	d0
		asl.l	#8,d0
		lea		simY,a1
		bsr		simSpringP
		st		simFlyOn			; the nose along its way, banked into turns
.c9:	tst.b	simGone
		bne.s	.gone
		rts
.gone:	; past us: on behind us (heard), then its loop
		cmp.l	#-morphPassBehind<<8,simZ
		bgt.s	.out
		move.w	#SP_LOOP,simPhase
		move.w	#-1,simPT
.out:	rts

; --- the evade (the pass, simDodgeT from 1 on): it has seen us, and we
;     cannot turn - we rush on straight ahead. a fighter's loop, in the
;     world: the afterburner (a boom), a little faster than we are; a dip
;     (it gathers speed, its way follows the nose late); then it pulls up,
;     the turn building up slowly (the G), rolling left into it - the loop
;     leans over to the upper left; going up it loses speed. less and less
;     of its speed goes ahead: we catch up with it - it sweeps from low on
;     the right up across the screen, bigger and bigger, and out at the top
;     left close by us, its nose up, still in its loop (the rest unseen: the
;     loop). its speed in the world simEvV, its nose simEvTh in the loop
;     (0 ahead, 90 up), its way simEvG, the loop's lean simEvB
simEvade:
		move.w	simDodgeT,d7
		subq.w	#1,d7				; frames into it
		addq.w	#1,simDodgeT
		tst.w	d7
		bne.s	.e0
		or.w	#1<<RB_BOOM,simEv
		move.w	#256,simThrust
		move.w	simEvV,d0			; (from us: its speed in the world, 1/256)
		add.w	simVc,d0
		lsl.w	#4,d0
		move.w	d0,simA1
		clr.w	simEvTh
		clr.w	simEvG
		clr.w	simEvB
		move.w	simHead,simEvHr		; (what it had of a heading: dies away)
.e0:	move.w	#256,simThrT		; (it howls)
		cmp.w	#morphEvA,d7
		bhs.s	.e1
		move.w	d7,d0				; the afterburner: a little faster than
		move.w	#morphEvA,d1		; we are
		bsr		simSmooth
		move.w	simA1,d2
		move.w	simVc,d3
		add.w	#morphEvB,d3
		lsl.w	#4,d3
		bsr		simLerpF
		move.w	d2,simEvV
		bra		.go
.e1:	sub.w	#morphEvA,d7
		move.w	d7,d0				; the lean: rolling into it, from the dip
		move.w	#morphEvD+morphEvG,d1	; on
		bsr		simSmooth
		mulu	#morphEvLean,d0
		lsr.l	#8,d0
		lsr.l	#4,d0
		move.w	d0,simEvB
		cmp.w	#morphEvD,d7
		bhs.s	.e2
		move.w	d7,d0				; the dip: the nose down, slowly
		move.w	#morphEvD,d1
		bsr		simSmooth
		moveq	#0,d2
		move.w	#morphEvDip,d3
		bsr		simLerpF
		move.w	d2,simEvTh
		bra.s	.go
.e2:	sub.w	#morphEvD,d7		; up: the turn builds up, slowly
		move.w	d7,d0
		move.w	#morphEvG,d1
		bsr		simSmooth
		mulu	#morphEvW,d0
		lsr.l	#8,d0
		lsr.l	#4,d0
		add.w	simEvTh,d0
		cmp.w	#morphEvThMax,d0
		ble.s	.e3
		move.w	#morphEvThMax,d0
.e3:	move.w	d0,simEvTh
		bsr		morphSinCos16		; going up it loses speed
		tst.w	d0
		ble.s	.go
		muls	#morphEvLoss,d0
		swap	d0
		sub.w	d0,simEvV
.go:	move.w	simEvTh,d0			; its way follows the nose, late
		sub.w	simEvG,d0
		asr.w	#2,d0
		add.w	d0,simEvG
		move.w	simEvB,d0			; the lean: sin, cos (d4, d5)
		bsr		morphSinCos16
		move.w	d0,d4
		move.w	d1,d5
		move.w	simEvG,d0			; its way this frame, in the world, less
		bsr		morphSinCos16		; ours: ahead S cos - us; S sin up,
		move.w	simEvV,d2			; leaning over to the left
		muls	d2,d1
		asr.l	#8,d1
		asr.l	#3,d1				; (1/256 units * Q15 -> 1/4096)
		moveq	#0,d3
		move.w	simVc,d3
		lsl.l	#8,d3
		sub.l	d3,d1
		add.l	d1,simZ
		muls	d2,d0				; S sin (1/256 units)
		add.l	d0,d0
		swap	d0
		move.w	d0,d1
		muls	d5,d0				; up: * cos lean
		asr.l	#8,d0
		asr.l	#3,d0
		sub.l	d0,simY
		muls	d4,d1				; left: * sin lean
		asr.l	#8,d1
		asr.l	#3,d1
		sub.l	d1,simX
		bsr		simEvPose			; the nose, the top to the loop's middle
		move.w	simEvHr,d0			; what it had of a heading and a bank
		asr.w	#3,d0				; dies away
		sub.w	d0,simEvHr
		move.w	simBank,d0
		asr.w	#3,d0
		sub.w	d0,simBank
		move.w	simEvH,d0
		add.w	simEvHr,d0
		move.w	d0,simHead
		move.w	simEvR,d0
		sub.w	simBank,d0
		move.w	d0,simRoll
		rts

; the nose (simEvTh, in the loop) and the loop's lean (simEvB) as the
; pose's heading, tilt and roll (as morphPoseW turns: the roll about its
; length, then the tilt, then the heading). the nose n = (-sl st, cl st,
; ct) (right, up, ahead), its top u = (-sl ct, cl ct, -st) (towards the
; loop's middle) -> simEvH, simTilt, simEvR
simEvPose:
		move.w	simEvB,d0
		bsr		morphSinCos16
		move.w	d0,evSL
		move.w	d1,evCL
		move.w	simEvTh,d0
		bsr		morphSinCos16
		move.w	d0,evST
		move.w	d1,evCT
		move.w	evSL,d2				; n across
		muls	evST,d2
		add.l	d2,d2
		swap	d2
		neg.w	d2
		move.w	d2,evNX
		move.w	evCL,d2				; ... up
		muls	evST,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,evNU
		move.w	evNX,d0				; the heading: atan2(across, ahead)
		move.w	evCT,d1
		bsr		morphAtan2
		move.w	d0,simEvH
		bsr		morphSinCos16
		move.w	d0,evSH
		move.w	d1,evCH
		move.w	evNX,d2				; the tilt: atan2(up, along the ground)
		muls	evSH,d2
		move.w	evCT,d3
		muls	evCH,d3
		add.l	d3,d2
		add.l	d2,d2
		swap	d2
		move.w	evNU,d0
		move.w	d2,d1
		bsr		morphAtan2
		move.w	d0,simTilt
		bsr		morphSinCos16
		move.w	d0,evS2
		move.w	d1,evC2
		move.w	evSL,d2				; u across: -sl ct
		muls	evCT,d2
		add.l	d2,d2
		swap	d2
		neg.w	d2
		move.w	d2,d4
		muls	evCH,d2				; x1 = ux ch - uz sh = ux ch + st sh
		move.w	evST,d3
		muls	evSH,d3
		add.l	d3,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,evX1
		muls	evSH,d4				; z1 = ux sh + uz ch = ux sh - st ch
		move.w	evST,d3
		muls	evCH,d3
		sub.l	d3,d4
		add.l	d4,d4
		swap	d4
		move.w	evCL,d2				; uy = cl ct
		muls	evCT,d2
		add.l	d2,d2
		swap	d2
		muls	evC2,d2				; y2 = uy c2 - z1 s2
		muls	evS2,d4
		sub.l	d4,d2
		add.l	d2,d2
		swap	d2
		move.w	d2,d1
		move.w	evX1,d0				; the roll: atan2(-x2, y2) (+: its left
		neg.w	d0					; wing down)
		bsr		morphAtan2
		move.w	d0,simEvR
		rts
evSL:	dc.w	0
evCL:	dc.w	0
evST:	dc.w	0
evCT:	dc.w	0
evNX:	dc.w	0
evNU:	dc.w	0
evSH:	dc.w	0
evCH:	dc.w	0
evS2:	dc.w	0
evC2:	dc.w	0
evX1:	dc.w	0

; d0 = frames in, d1 = frames -> d0 = the smoothstep of (d0+1)/d1, fine:
; 0..4096 (clamped). uses d1
simSmooth:
		bsr.s	simUQ
; d0 = u (0..4096, clamped) -> d0 = its smoothstep (0..4096). uses d1
simSS:
		cmp.w	#4096,d0
		blo.s	.s0
		move.w	#4096,d0
		rts
.s0:	move.w	d0,d1
		mulu	d1,d1
		lsr.l	#8,d1
		lsr.l	#4,d1				; u^2
		add.w	d0,d0
		neg.w	d0
		add.w	#3*4096,d0			; 3 - 2u
		mulu	d1,d0
		lsr.l	#8,d0
		lsr.l	#4,d0
		rts

; d0 = frames in, d1 = frames -> d0 = (d0+1)/d1, 0..4096 (clamped)
simUQ:
		addq.w	#1,d0
		cmp.w	d1,d0
		blo.s	.u0
		move.w	#4096,d0
		rts
.u0:	tst.w	d0
		bgt.s	.u1
		moveq	#0,d0
		rts
.u1:	ext.l	d0
		lsl.l	#8,d0
		lsl.l	#4,d0
		divu	d1,d0
		rts

; d2 = from, d3 = to, d0 = 0..4096 -> d2
simLerpF:
		sub.w	d2,d3
		muls	d0,d3
		asr.l	#8,d3
		asr.l	#4,d3
		add.w	d3,d2
		rts

; --- the loop: unseen; we ease off. on a beat: the attack
simLoop:
		st		simGone
		move.w	#160,simThrT
		move.w	simVz,d0
		cmp.w	#morphVzLoop*256,d0
		bls.s	.l0
		sub.w	#morphVzDown,d0
		move.w	d0,simVz
.l0:	bsr		simOurSpeed
		cmp.w	#morphLoopT,simPT
		blo.s	.out
		moveq	#0,d0
		move.w	simT,d0
		addq.w	#1,d0				; (the next frame)
		divu	#morphBeat,d0
		swap	d0
		tst.w	d0
		bne.s	.out
		move.w	#SP_ENTRY,simPhase
		move.w	#-1,simPT
		sf		simGone
		st		simFlyNew
		move.l	#morphEX0<<8,simX
		move.l	#morphEX0<<8,simXo
		move.l	#morphEY0<<8,simY
		move.l	#morphEY0<<8,simYo
		move.l	#morphEZ0<<8,simZ
		move.l	#morphEZ0<<8,simZo
		clr.w	simBank
		clr.w	simHead
		clr.w	simTilt
		clr.w	simRoll
		move.w	#-90*16,simPitch	; (from behind, upright)
		move.w	#-90*16,simYaw
.out:	rts

; --- the entry: down from the upper right corner (out of its loop),
;     faster than we are,
;     slowing down to our speed ahead of us; we speed up with it
simEntry:
		move.w	simPT,d0
		addq.w	#1,d0
		move.w	#morphEntryT,d1
		bsr		morphUnit			; d0 u, d1 its smoothstep
		move.w	d1,d6
		; e = 1 - (1-u)^2, fine (Q15): no steps in its way, so no jitter in
		; its nose (which follows the way)
		moveq	#0,d0
		move.w	simPT,d0
		addq.w	#1,d0
		swap	d0
		lsr.l	#1,d0
		divu	#morphEntryT,d0		; u, Q15
		move.w	#32768,d5
		sub.w	d0,d5				; 1-u
		mulu	d5,d5
		lsr.l	#8,d5
		lsr.l	#7,d5				; (1-u)^2
		neg.w	d5
		add.w	#32768,d5			; e
		bpl.s	.e0					; (1 is one too many for a word: 32767)
		move.w	#32767,d5
.e0:	move.w	#morphEX1-morphEX0,d2
		bsr.s	.mul
		add.l	#morphEX0<<8,d2
		move.l	d2,simX
		move.w	#morphEY1-morphEY0,d2
		bsr.s	.mul
		add.l	#morphEY0<<8,d2
		move.l	d2,simY
		move.w	#morphEZ1-morphEZ0,d2
		bsr.s	.mul
		add.l	#morphEZ0<<8,d2
		move.l	d2,simZ
	ifne	escortMux
		move.w	morphTorpNext,d0	; the torpedoes go, still high up
		cmp.w	#morphTorpN,d0
		bhs.s	.nt
		mulu	#morphMxDropGap,d0
		add.w	#morphMxDrop0,d0
		cmp.w	simPT,d0
		bne.s	.nt
		bsr		morphTorpFire
.nt:
	endc
		; rolling out of its loop
		move.w	#-morphAtkRoll*16,d0
		move.w	#256,d1
		sub.w	d6,d1
		muls	d1,d0
		asr.l	#8,d0
		move.w	d0,simMR
		move.w	#224,simThrT
		move.w	simVz,d0			; we speed up with it: top speed
		cmp.w	#morphVzMax*256,d0
		beq.s	.v
		bhi.s	.v1
		add.w	#16,d0
		cmp.w	#morphVzMax*256,d0
		bls.s	.v2
.v1:	move.w	#morphVzMax*256,d0
.v2:	move.w	d0,simVz
.v:		bsr		simOurSpeed
		st		simFlyOn
		cmp.w	#morphEntryT-1,simPT
		blo.s	.out
		; there: the escort - the spring takes over from here, on its way
		move.w	#SP_ESCORT,simPhase
		move.w	#-1,simPT
		move.l	#morphEscList,simList
		clr.w	simBT
		clr.w	simBX
		clr.w	simBZ
		move.l	simX,d0
		sub.l	simXo,d0
		move.l	d0,simVX
		move.l	simY,d0
		sub.l	simYo,d0
		move.l	d0,simVY
		move.l	simZ,d0
		sub.l	simZo,d0
		move.l	d0,simVZ
.out:	rts
; d2 = a way (1/16 units), d5 = e (Q15) -> d2.l = way * e (1/4096 units)
.mul:	muls	d5,d2
		asr.l	#7,d2
		rts

; --- the escort: the torpedoes go, it flies ahead of us (morphEscList)
simEscort:
	ifeq	escortMux				; (escortMux: they went in the entry)
		move.w	morphTorpNext,d0	; a torpedo every morphTorpGap frames
		cmp.w	#morphTorpN,d0
		bhs.s	.t
		mulu	#morphTorpGap,d0
		cmp.w	simPT,d0
		bne.s	.t
		bsr		morphTorpFire
	endc
.t:		bsr		simBlock
		move.w	#morphEX1,d0
		move.w	#morphEY1,d1
		move.w	#morphEZ1>>4,d2
		bsr		simTargets
		st		simFlyOn
		bsr		simOurSpeed
		cmp.w	#morphBreakAt-1,simPT	; time to go (from the next frame)
		blo.s	.out
		move.w	#SP_BREAK,simPhase
		move.w	#-1,simPT
		move.l	simWX,simVX			; (on its way as it was, dying away)
		move.l	simWY,simVY
		move.l	simWZ,simVZ
.out:	rts

; --- the break: like a fighter it turns hard to the right, down and
;     round - past us on the lower right and away behind us
simBreak:
		tst.w	simPT
		bne.s	.b
		or.w	#1<<RB_BOOM,simEv
		move.w	simHead,simA0
		move.w	simRoll,simA1
		move.w	simTilt,simA2
.b:		move.w	simPT,d0
		move.w	#morphBreakT,d1
		bsr		simUQ				; d0 u 0..4096 (fine)
		move.w	d0,d6
		bsr		simSS
		move.w	d0,d5				; (eased in and out)
		move.w	simA0,d2			; the nose round
		move.w	#morphBreakA*16,d3
		bsr		simLerp
		move.w	d2,simHead
		move.w	simA2,d2			; the nose down
		move.w	#morphBreakTilt*16,d3
		bsr		simLerp
		move.w	d2,simTilt
		move.w	d6,-(a7)
		move.w	simHead,d0
		bsr		morphSinCos16		; d0 sin, d1 cos
		; its way, less ours: v (sin right, sin down, cos) - ours
		move.w	d0,d2
		muls	#morphBreakV*morphBreakXY/100,d2
		add.l	d2,d2
		swap	d2
		ext.l	d2
		asl.l	#8,d2
		add.l	d2,simX
		move.w	d0,d2
		muls	#morphBreakV*morphBreakDn/100,d2
		add.l	d2,d2
		swap	d2
		ext.l	d2
		asl.l	#8,d2
		add.l	d2,simY
		muls	#morphBreakV,d1
		add.l	d1,d1
		swap	d1
		sub.w	simVc,d1
		ext.l	d1
		asl.l	#8,d1
		add.l	d1,simZ
		; ... and what it still had of its own (dying away)
		move.l	simVX,d0
		add.l	d0,simX
		asr.l	#3,d0
		sub.l	d0,simVX
		move.l	simVY,d0
		add.l	d0,simY
		asr.l	#3,d0
		sub.l	d0,simVY
		move.l	simVZ,d0
		add.l	d0,simZ
		asr.l	#3,d0
		sub.l	d0,simVZ
		; banked hard over to the right at once, then less as it comes round
		move.w	(a7)+,d0			; (u)
		cmp.w	#86*16,d0
		bhs.s	.r1
		mulu	#3,d0
		bsr		simSS
		move.w	d0,d5
		move.w	simA1,d2
		move.w	#-morphBreakRoll*16,d3
		bsr		simLerp
		bra.s	.r2
.r1:	sub.w	#86*16,d0
		mulu	#4096,d0
		divu	#4096-86*16,d0
		bsr		simSS
		move.w	d0,d5
		move.w	#-morphBreakRoll*16,d2
		move.w	#-morphBreakOut*16,d3
		bsr		simLerp
.r2:	move.w	d2,simRoll
		move.w	#256,simThrT		; (it howls)
		cmp.w	#morphBreakT-1,simPT
		blo.s	.out
		move.w	#SP_WAIT,simPhase
		move.w	#-1,simPT
.out:	rts

; --- gone past us: on behind us (heard) till the torpedoes are there
simWait:
		move.l	simWX,d0
		add.l	d0,simX
		move.l	simWY,d0
		add.l	d0,simY
		move.l	simWZ,d0
		add.l	d0,simZ
		cmp.w	#morphTorpN,morphTorpNext
		bne.s	.out
		tst.w	morphTorpLeft
		bne.s	.out
		move.w	#SP_END,simPhase
		move.w	#-1,simPT
.out:	rts

simEndP:
		st		simGone
		rts

; d0/d1 = the place (1/16 units, across, down), d2 = ahead (1/256 units):
; the springs pull it there, plus a block's offset and the pilot's
; corrections
simTargets:
		movem.w	d0-d2,-(a7)
		bsr		simJitter
		movem.w	(a7)+,d0-d2
		add.w	simMX,d0
		add.w	simJX,d0
		add.w	simBX,d0
		add.w	simMY,d1
		add.w	simJY,d1
		move.w	d1,-(a7)
		move.w	d2,-(a7)
		ext.l	d0
		asl.l	#8,d0
		lea		simX,a1
		bsr		simSpringP
		move.w	(a7)+,d0			; ahead: <<4, and the block's offset
		ext.l	d0
		asl.l	#4,d0
		move.w	simMZ,d1
		add.w	simBZ,d1
		ext.l	d1
		add.l	d1,d0
		asl.l	#8,d0
		lea		simZ,a1
		bsr		simSpringP
		move.w	(a7)+,d0
		ext.l	d0
		asl.l	#8,d0
		lea		simY,a1
		bra		simSpringP

; a1 = a spring (place, speed: longs, 1/4096 units), d0.l = where it is
; pulled: one frame of it (simSpK, simSpD: 1/1024)
simSpringP:
		move.w	simSpK,d2
		move.w	simSpD,d3
		move.l	d0,d1
		moveq	#4,d4
		bra.s	simSpr
; (d1 = where, d2 = pull, d3 = damping, both 1/256)
simSpring:
		moveq	#2,d4
simSpr:	sub.l	(a1),d1				; off by
		asr.l	#6,d1
		bsr.s	.clamp
		muls	d2,d1
		asr.l	d4,d1
		move.l	4(a1),d0
		asr.l	#6,d0
		exg		d0,d1
		bsr.s	.clamp
		muls	d3,d1
		asr.l	d4,d1
		sub.l	d1,d0				; the push this frame
		add.l	d0,4(a1)
		move.l	4(a1),d0
		add.l	d0,(a1)
		rts
.clamp:	cmp.l	#32767,d1
		ble.s	.c0
		move.l	#32767,d1
.c0:	cmp.l	#-32767,d1
		bge.s	.c1
		move.l	#-32767,d1
.c1:	rts

; d2 = from, d3 = to, d5 = 0..4096 -> d2
simLerp:
		sub.w	d2,d3
		muls	d5,d3
		asr.l	#8,d3
		asr.l	#4,d3
		add.w	d3,d2
		rts

; our speed from the stars'
simOurSpeed:
		move.w	simVz,d0
		mulu	#morphKV,d0
		lsr.l	#8,d0
		move.w	d0,simVc
		rts

; -> d0 = a random word (its own: the flight is the same every time)
simRandom:
		move.l	simRnd,d0
		move.l	d0,d1
		lsl.l	#8,d1
		lsl.l	#5,d1
		eor.l	d1,d0
		move.l	d0,d1
		clr.w	d1
		swap	d1
		lsr.l	#1,d1
		eor.l	d1,d0
		move.l	d0,d1
		lsl.l	#5,d1
		eor.l	d1,d0
		move.l	d0,simRnd
		rts

; the pilot is a human: now and then a small correction of where he holds
; it (the spring overshoots it a little and catches itself)
simJitter:
		subq.w	#1,simJit
		bpl.s	.out
		bsr.s	simRandom
		move.w	d0,d1
		and.w	#31,d1
		add.w	#30,d1
		add.w	d1,d1
		move.w	d1,simJit			; 60..122 frames to the next
		move.w	d0,d1
		lsr.w	#5,d1
		and.w	#63,d1
		sub.w	#32,d1
		move.w	d1,simJX			; +-2 units across
		swap	d0
		and.w	#31,d0
		sub.w	#16,d0
		move.w	d0,simJY			; +-1 up and down
.out:	rts

; the nose along its way through the world (ours added: its way ahead is
; its own and ours), banked by how hard it turns
simFly:
		move.l	simWX,d0			; (in 1/1024 units: words)
		asr.l	#2,d0
		move.l	simWZ,d1
		moveq	#0,d2
		move.w	simVc,d2
		asl.l	#8,d2
		add.l	d2,d1				; ahead, in the world
		cmp.l	#morphFlyMin,d1		; (never a crawl: else as it hangs still
		bge.s	.fm					; in the world its nose would swing round
		move.l	#morphFlyMin,d1		; to any small way it has)
.fm:	asr.l	#2,d1
		move.l	d1,-(a7)
		bsr		morphAtan2L
		add.w	simMH,d0
		move.w	d0,simHead
		move.l	simWY,d0
		asr.l	#2,d0
		neg.l	d0					; (up: the nose up)
		move.l	(a7)+,d1
		bsr		morphAtan2L
		move.w	d0,simTilt
		; the bank: how fast its way across changes (right: right wing down)
		move.l	simWX,d0
		move.l	d0,d1
		sub.l	simWXo,d0
		move.l	d1,simWXo
		tst.b	simFlyNew
		beq.s	.b0
		sf		simFlyNew
		moveq	#0,d0
.b0:	cmp.l	#900,d0
		ble.s	.b1
		move.l	#900,d0
.b1:	cmp.l	#-900,d0
		bge.s	.b2
		move.l	#-900,d0
.b2:	muls	#morphKBank,d0
		asr.l	#6,d0
		cmp.w	#morphBankMax,d0
		ble.s	.b3
		move.w	#morphBankMax,d0
.b3:	cmp.w	#-morphBankMax,d0
		bge.s	.b4
		move.w	#-morphBankMax,d0
.b4:	sub.w	simBank,d0			; (slowly: a heavy ship)
		muls	#3,d0
		asr.l	#6,d0
		add.w	d0,simBank
		; the bank (right: - , the right wing down) and the block's own
		move.w	simMR,d0
		sub.w	simBank,d0
		move.w	d0,simRoll
		rts

;---------------------------------------------
; the maneuver list: the block at simList, simBT frames into it. -> d0 = 0
; if the list is through
simBlock:
		move.l	simList,a2
		tst.w	(a2)
		bmi.s	.end
		move.w	simBT,d0
		move.w	2(a2),d1
		cmp.w	d1,d0
		blo.s	.do
		lea		mv_len(a2),a2		; the next
		move.l	a2,simList
		clr.w	simBT
		moveq	#0,d0
		tst.w	(a2)
		bmi.s	.end
		move.w	2(a2),d1
.do:	move.w	8(a2),simThrT
		move.w	(a2),d2
		add.w	d2,d2
		move.w	.tab(pc,d2.w),d2
		jsr		.tab(pc,d2.w)		; d0 frames in, d1 frames, a2 the block
		move.l	simList,a2
		addq.w	#1,simBT
		moveq	#1,d0
		move.w	simBT,d1			; its last frame, and no block after it:
		cmp.w	2(a2),d1			; through with this frame
		blo.s	.on
		tst.w	mv_len(a2)
		bpl.s	.on
		moveq	#0,d0
.on:	rts
.end:	moveq	#0,d0
		rts
.tab:	dc.w	mvWiggle-.tab,mvSag-.tab,mvIgnite-.tab,mvFeint-.tab
		dc.w	mvTurnTo-.tab,mvFish-.tab,mvBarrel-.tab,mvBack-.tab
		dc.w	mvKnife-.tab,mvHold-.tab,mvVRoll-.tab,mvSalute-.tab
		dc.w	mvMove-.tab,mvClimb-.tab,mvWeave-.tab

; d0 = frames in, d1 = frames -> d5 = the smoothstep of (d0+1)/d1 (0..4096,
; fine: no steps from a table). keeps d0/d1
simU:	movem.w	d0/d1,-(a7)
		bsr		simSmooth
		move.w	d0,d5
		movem.w	(a7)+,d0/d1
		rts

; d0 = frames in, d1 = frames, d2 = times -> d0 = sin(times*360*u) *
; sin(180*u) (Q15): a wave, in and out softly. keeps d1
simWave:
		movem.l	d1/d4,-(a7)
		move.w	d0,d4
		addq.w	#1,d4
		mulu	#180*16,d4
		divu	d1,d4				; 180 u
		addq.w	#1,d0
		mulu	d2,d0
		mulu	#360*16,d0
		divu	d1,d0				; times * 360 u
		bsr		morphSinCos16
		move.w	d0,-(a7)
		move.w	d4,d0
		bsr		morphSinCos16
		muls	(a7)+,d0
		add.l	d0,d0
		swap	d0
		movem.l	(a7)+,d1/d4
		rts

; d0 = a wave (Q15), d1 = degrees -> d0 = 1/16 degrees
simDeg:	muls	d1,d0
		asr.l	#8,d0
		asr.l	#3,d0
		rts

; --- the wings rock (seen from above: its roll)
mvWiggle:
		tst.w	d0
		bne.s	.w
		move.w	simRoll,simA0
.w:		move.w	6(a2),d2
		bsr		simWave
		move.w	4(a2),d1
		bsr		simDeg
		add.w	simA0,d0
		move.w	d0,simRoll
		rts

; --- it sags and catches itself; it rolls onto its side (90), the nose
;     level and a little away from us: then seen from behind, the same turn
mvSag:
		tst.w	d0
		bne.s	.s
		move.w	simRoll,simA0
		move.w	simPitch,simA1
		move.w	simHead,simA2
.s:		cmp.w	#12,d0				; down, then up again (the spring)
		bhs.s	.s1
		move.w	4(a2),d2
		lsl.w	#4,d2
		move.w	d2,simMY
.s1:	bsr		simU
		move.w	simA0,d2
		move.w	#90*16,d3
		bsr		simLerp
		move.w	d2,simRoll
		move.w	simA1,d2
		moveq	#0,d3
		bsr		simLerp
		move.w	d2,simPitch
		move.w	simA2,d2
		move.w	6(a2),d3
		lsl.w	#4,d3
		bsr		simLerp
		move.w	d2,simHead
		addq.w	#1,d0				; the last frame: from behind from here
		cmp.w	d1,d0				; on - (90, 0, 0, 0, h) is (0, -90, -90,
		bne.s	.out				; 0, 90+h): the roll there is its bank
		clr.w	simRoll
		move.w	#-90*16,simPitch
		move.w	#-90*16,simYaw
		add.w	#90*16,simHead
.out:	rts

; --- the engine fires: the sound, the glow flares; a lurch forward
mvIgnite:
		tst.w	d0
		bne.s	.i
		or.w	#1<<RB_SIGN,simEv
		st		simEngine
		move.w	#256,simThrust
.i:		cmp.w	#8,d0
		bhs.s	.out
		move.w	4(a2),d2
		lsl.w	#4,d2
		move.w	d2,simMX
.out:	rts

; --- a feint left: banks in and out again, the nose a little left
mvFeint:
		tst.w	d0
		bne.s	.f
		move.w	simHead,simA2
.f:		bsr		simU
		move.w	simA2,d2
		move.w	6(a2),d3
		lsl.w	#4,d3
		add.w	d2,d3
		bsr		simLerp
		move.w	d2,simHead
		; once in and out: sin(180 u)
		movem.w	d0/d1,-(a7)
		addq.w	#1,d0
		mulu	#180*16,d0
		divu	d1,d0
		bsr		morphSinCos16
		move.w	4(a2),d1
		bsr		simDeg
		move.w	d0,d2
		movem.w	(a7)+,d0/d1
		move.w	d2,simRoll			; (+: left wing down)
		rts

; --- hard round to a heading: a spring (it overshoots a little, then it
;     sits), banked into the turn by how fast it turns
mvTurnTo:
	ifne	fixQmarks				; (not in the lists: room for asteroids.s
		rts							; seq_qfire - the total must not grow)
	else
		tst.w	d0
		bne.s	.t
		move.w	simHead,d2
		ext.l	d2
		asl.l	#8,d2
		move.l	d2,simHS
		clr.l	simHV
.t:		lea		simHS,a1
		move.w	4(a2),d1
		muls	#16*256,d1
		moveq	#morphTurnK,d2
		moveq	#morphTurnD,d3
		bsr		simSpring
		move.l	simHS,d0
		asr.l	#8,d0
		move.w	d0,simHead
		move.l	simHV,d0			; the bank (turning right: right wing down)
		asr.l	#4,d0
		muls	#morphTurnBank,d0
		asr.l	#2,d0
		cmp.l	#morphBankMax,d0
		ble.s	.b0
		move.w	#morphBankMax,d0
.b0:	cmp.l	#-morphBankMax,d0
		bge.s	.b1
		move.w	#-morphBankMax,d0
.b1:	neg.w	d0
		move.w	d0,simRoll
		rts
	endc

; --- fishtail: it swings from side to side, a human hand on it - the
;     swings not quite even, the yaw kicked in with each, the spring's
;     overshoot and catch
mvFish:
	ifne	fixQmarks				; (not in the lists either)
		rts
	else
		tst.w	d0
		bne.s	.f
		move.w	#1,simFishS
		move.w	6(a2),d2
		lsr.w	#1,d2
		move.w	d2,simFishT
.f:		subq.w	#1,simFishT
		bpl.s	.f1
		neg.w	simFishS			; the swing over
		bsr		simRandom
		move.w	d0,d2
		and.w	#15,d2
		subq.w	#8,d2
		add.w	6(a2),d2
		move.w	d2,simFishT			; its frames: p2 -8..+7
		swap	d0
		and.w	#7,d0				; its width: p1 * (12..19)/16
		add.w	#12,d0
		mulu	4(a2),d0
		move.w	d0,simA0			; (1/16 units)
.f1:	move.w	simA0,d0
		tst.w	simFishS
		bpl.s	.f2
		neg.w	d0
.f2:	move.w	d0,simMX
		move.w	simFishS,d0			; the yaw kick (5 degrees), eased
		muls	#5*16,d0
		sub.w	simFishH,d0
		asr.w	#3,d0
		add.w	d0,simFishH
		move.w	simFishH,simMH
		rts
	endc

; --- barrel roll: a full roll and a circle round its way
mvBarrel:
		bsr		simU
		move.w	d5,d0
		mulu	#360*16,d0
		lsr.l	#8,d0
		lsr.l	#4,d0				; the roll so far
		move.w	d0,d4
		muls	6(a2),d4
		neg.w	d4					; (p2 1: right - right wing down first)
		move.w	d4,simMR
		bsr		morphSinCos16		; d0 sin, d1 cos
		move.w	4(a2),d2
		lsl.w	#4,d2				; R (1/16 units)
		muls	d2,d0
		add.l	d0,d0
		swap	d0
		muls	6(a2),d0
		move.w	d0,simMX			; across: R sin
		sub.w	#32767,d1
		muls	d2,d1
		add.l	d1,d1
		swap	d1
		move.w	d1,simMY			; up: R (1 - cos)
		rts

; --- it falls back (nearer us), then pulls away again
mvBack:
		move.w	d1,d2
		lsr.w	#1,d2
		cmp.w	d2,d0
		bhs.s	.away
		move.w	#48,simThrT			; (off the throttle)
		move.w	d2,d1
		bsr		simU
		move.w	4(a2),d3
		lsl.w	#4,d3
		neg.w	d3
		moveq	#0,d2
		bsr		simLerp
		move.w	d2,simMZ
		rts
.away:	sub.w	d2,d0
		sub.w	d2,d1
		bsr		simU
		move.w	#224,simThrT		; (full throttle)
		move.w	4(a2),d2
		lsl.w	#4,d2
		neg.w	d2
		move.w	6(a2),d3
		lsl.w	#4,d3
		bsr		simLerp
		move.w	d2,simMZ
		rts

; --- knife edge: rolled onto its side, held, back; it slips a little
;     towards the low wing
mvKnife:
		move.w	d1,d2
		lsr.w	#2,d2				; a quarter in, half held, a quarter out
		cmp.w	d2,d0
		bhs.s	.k0
		move.w	d0,d3
		addq.w	#1,d3
		bra.s	.k2
.k0:	move.w	d1,d3
		sub.w	d0,d3
		subq.w	#1,d3
		cmp.w	d2,d3
		blo.s	.k2
		move.w	d2,d3
.k2:	movem.w	d0/d1,-(a7)
		move.w	d3,d0
		subq.w	#1,d0
		move.w	d2,d1
		bsr		simSmooth
		move.w	d0,d5
		movem.w	(a7)+,d0/d1
		move.w	4(a2),d3
		lsl.w	#4,d3
		moveq	#0,d2
		bsr		simLerp
		move.w	d2,simMR
		move.w	#-10*16,d3			; (left down: it slips left)
		tst.w	4(a2)
		bpl.s	.k3
		neg.w	d3
.k3:	moveq	#0,d2
		bsr		simLerp
		move.w	d2,simMX
		rts

mvHold:	rts

; --- a quick full roll
mvVRoll:
		bsr		simU
		move.w	d5,d0
		mulu	#360*16,d0
		lsr.l	#8,d0
		lsr.l	#4,d0
		muls	6(a2),d0
		neg.w	d0
		move.w	d0,simMR
		rts

; --- it pulls up and turns away into our way: slowly, a heavy glider -
;     the nose round to heading p1 (eased), up and level again, banked into
;     the turn and out of it, climbing p2 units
mvClimb:
		tst.w	d0
		bne.s	.c
		move.w	simHead,simA0
		move.w	simY0,simA1
.c:		bsr		simU				; d5 eased 0..4096
		move.w	simA0,d2
		move.w	4(a2),d3
		lsl.w	#4,d3
		bsr		simLerp
		move.w	d2,simHead
		move.w	6(a2),d3			; the climb: its place up (the spring)
		lsl.w	#4,d3
		muls	d5,d3
		asr.l	#8,d3
		asr.l	#4,d3
		move.w	simA1,d2
		sub.w	d3,d2
		move.w	d2,simY0
		movem.w	d0/d1,-(a7)			; the hump: sin(180 u)
		addq.w	#1,d0
		mulu	#180*16,d0
		divu	d1,d0
		bsr		morphSinCos16
		move.w	d0,d4
		movem.w	(a7)+,d0/d1
		move.w	d4,d0				; the nose up, and level again
		move.w	#morphClimbTilt,d1
		bsr		simDeg
		move.w	d0,simTilt
		move.w	d4,d0				; banked into the turn (left: +)
		move.w	#morphClimbBank,d1
		bsr		simDeg
		move.w	simA0,d2			; (which way it turns)
		cmp.w	4(a2),d2
		bge.s	.b0
		neg.w	d0
.b0:	move.w	d0,simRoll
		rts

; --- a slow weave from side to side (the nose and the bank follow by
;     themselves): p1 units, p2 rounds
mvWeave:
		move.w	6(a2),d2
		bsr		simWave2
		move.w	4(a2),d1
		lsl.w	#4,d1
		muls	d1,d0
		add.l	d0,d0
		swap	d0
		move.w	d0,simMX
		rts
; d0 = frames in, d1 = frames, d2 = rounds -> d0 = sin(rounds*360*u) (Q15).
; keeps d1
simWave2:
		move.l	d1,-(a7)
		addq.w	#1,d0
		mulu	d2,d0
		mulu	#360*16,d0
		divu	d1,d0
		bsr		morphSinCos16
		move.l	(a7)+,d1
		rts

; --- its place in the escort from here on (the springs follow)
mvMove:
		tst.w	d0
		bne.s	.m
		move.w	simBX,simA0
		move.w	simBZ,simA1
.m:		bsr		simU
		move.w	simA0,d2
		move.w	4(a2),d3
		lsl.w	#4,d3
		bsr		simLerp
		move.w	d2,simBX
		move.w	simA1,d2
		move.w	6(a2),d3
		lsl.w	#4,d3
		bsr		simLerp
		move.w	d2,simBZ
		rts

; --- the wings rock (a wave to us)
mvSalute:
		move.w	6(a2),d2
		bsr		simWave
		move.w	4(a2),d1
		bsr		simDeg
		move.w	d0,simMR
		rts

;---------------------------------------------
; a torpedo is dropped from the ship: it falls out below it, keeping our
; speed, then its engine fires and it speeds away, along the line that ends
; on its point of the logo
morphTorpFire:
		move.w	morphTorpNext,d0
		addq.w	#1,morphTorpNext
		addq.w	#1,morphTorpLeft
		move.w	d0,d2
		mulu	#tp_len,d0
		lea		morphTorps,a1
		add.w	d0,a1
		move.w	#1,tp_age(a1)
		clr.w	tp_burn(a1)
	ifne	escortMux
		move.w	d2,d0				; its hit: where it was (each a beat later)
		mulu	#morphMxHitStep,d0
		add.w	#morphTorpHitAge,d0
		move.w	d0,tp_hit(a1)
	endc
		move.l	simX,d0				; (1/4096 -> 1/256 units)
		asr.l	#4,d0
		move.l	d0,tp_x(a1)
		move.l	simY,d0
		add.l	#morphTorpBelow<<8,d0
		asr.l	#4,d0
		move.l	d0,tp_y(a1)
		move.l	simZ,d0
		asr.l	#4,d0
		move.l	d0,tp_z(a1)
		clr.l	tp_vz(a1)
		lsl.w	#2,d2				; its point on the logo: the slope there
		lea		morphTorpAim,a2
		move.w	(a2,d2.w),d0		; x on the screen
		sub.w	#morphVX,d0
		muls	#4096,d0
		divs	#morphF,d0
		move.w	d0,tp_kx(a1)
		move.w	2(a2,d2.w),d0		; y
		sub.w	#morphVY,d0
		muls	#4096,d0
		divs	#morphF,d0
		move.w	d0,tp_ky(a1)
		move.l	(a2,d2.w),tp_ax(a1)	; (its aim on the screen too)
	ifeq	escortMux
		move.w	#morphTorpDropV,tp_fv(a1)
	else
		move.w	#morphMxDropV,tp_fv(a1)
	endc
		or.w	#1<<RB_DROP,simEv
		rts

; the torpedoes on (x, y, z in 1/256 units)
morphTorpMove:
		lea		morphTorps,a1
		moveq	#morphTorpN-1,d7
.t:		move.w	tp_age(a1),d0
		ble.s	.n
		addq.w	#1,tp_age(a1)
		move.w	tp_fv(a1),d1		; falling out (once it burns: its fall
		ext.l	d1					; dies away)
		add.l	d1,tp_y(a1)
		tst.w	tp_burn(a1)
		bne.s	.burn
	ifne	escortMux
		addq.w	#morphMxDropG,tp_fv(a1)
		cmp.w	#morphMxFireT1,d0	; its engine fires: the fighter (its
		bhs.s	.late				; afterburner) safely below it, or late
		cmp.w	#morphTorpDropT0,d0	; anyway
		blo.s	.n
		bsr		simMxTorpLo
		cmp.w	simMxTop,d3
		bgt.s	.n
		bra.s	.fire
.late:	bsr		simMxTorpLo
		cmp.w	simMxTop,d3
		ble.s	.fire
		addq.w	#1,simMxLate
		bra.s	.fire
	else
		addq.w	#morphTorpDropG,tp_fv(a1)
		cmp.w	#morphTorpDropT1,d0	; its engine fires: far enough from the
		bhs.s	.fire				; ship (it maneuvers), or late anyway
		cmp.w	#morphTorpDropT0,d0
		blo.s	.n
		move.l	tp_x(a1),d2			; (|dx| + |dy| + |dz|, 1/256 units)
		move.l	simX,d3
		bsr.s	.d
		move.l	d2,d4
		move.l	tp_y(a1),d2
		move.l	simY,d3
		bsr.s	.d
		add.l	d2,d4
		move.l	tp_z(a1),d2
		move.l	simZ,d3
		bsr.s	.d
		add.l	d2,d4
		cmp.l	#morphTorpFireD<<8,d4
		blo.s	.n
	endc
.fire:	or.w	#1<<RB_IGN,simEv
.burn:	addq.w	#1,tp_burn(a1)
		asr.w	#3,d1
		sub.w	d1,tp_fv(a1)
		add.l	#morphTorpAcc,tp_vz(a1)
		move.l	tp_vz(a1),d0
		add.l	d0,tp_z(a1)
		move.w	d0,d1				; (the way ahead this frame, a word)
		muls	tp_kx(a1),d0
		asr.l	#8,d0
		asr.l	#4,d0
		add.l	d0,tp_x(a1)
		muls	tp_ky(a1),d1
		asr.l	#8,d1
		asr.l	#4,d1
		add.l	d1,tp_y(a1)
	ifeq	escortMux
		cmp.w	#morphTorpHitAge,tp_age(a1)
		blo.s	.n
	else
		move.w	tp_age(a1),d0
		cmp.w	tp_hit(a1),d0
		blo.s	.n
	endc
		move.w	#-1,tp_age(a1)		; there (the hits: the next scene)
		subq.w	#1,morphTorpLeft
.n:		lea		tp_len(a1),a1
		dbf		d7,.t
		rts
	ifeq	escortMux
; d2 = the torpedo's (1/256 units), d3 = the ship's (1/4096) -> d2 = |d2-d3|
.d:		asr.l	#4,d3
		sub.l	d3,d2
		bpl.s	.d0
		neg.l	d2
.d0:	rts
	else
; a1 = a torpedo -> d3 = the row below its glow at its biggest, and the
; gaps ($7fff: not ahead of us). keeps the rest
simMxTorpLo:
		movem.l	d4/d5,-(a7)
		move.l	tp_z(a1),d5
		move.l	tp_y(a1),d4
.sh:	cmp.l	#32000,d5
		blt.s	.s0
		asr.l	#1,d5
		asr.l	#1,d4
		bra.s	.sh
.s0:	move.w	#$7fff,d3
		tst.l	d5
		ble.s	.o
		muls	#morphF,d4
		divs	d5,d4
		move.w	d4,d3
		add.w	#morphVY+MSPR_RMAX+2+morphMxGap,d3
.o:		movem.l	(a7)+,d4/d5
		rts

; the afterburner's rows on the screen, about (simEncode, d7 its flags:
; the points this frame): each glow of the chain somewhere on the way out
; from the plate's middle (morphChain: 1/8, 3/8, 11/16, all of it - times
; f, 0.25 .. 1.15), its size round that -> simMxR (a glow's top, bottom),
; all of them simMxTop..simMxBot. kept on for a while once it is gone (its
; glows die away). uses d0-d6/a1/a2
simMxRange:
		moveq	#RF_MODE,d0
		and.w	d7,d0
		beq.s	.old
		btst	#RB_GLOW,d7
		beq.s	.old
		lea		morphXY+7*4,a1		; the plate's middle (y, * 4)
		move.w	2(a1),d1
		add.w	6(a1),d1
		add.w	10(a1),d1
		add.w	14(a1),d1
		asr.w	#2,d1
		move.w	d1,d2				; the way: the middle - the nose
		sub.w	morphXY+2,d2
		lea		simMxR,a1
		move.l	#$7fff8000,simMxTop
		lea		.c(pc),a2
		moveq	#4-1,d6
.g:		move.w	(a2)+,d3			; (its share of the way, 1/16)
		muls	d2,d3
		move.l	d3,d4
		muls	#65,d3				; f at its least ...
		asr.l	#8,d3
		asr.l	#4,d3
		muls	#295,d4				; ... and most (* 256)
		asr.l	#8,d4
		asr.l	#4,d4
		add.w	d1,d3
		add.w	d1,d4
		cmp.w	d3,d4
		bge.s	.o0
		exg		d3,d4
.o0:	sub.w	#MSPR_RMAX+1,d3		; (the glows: R 7 at most)
		add.w	#MSPR_RMAX+1,d4
		move.w	d3,(a1)+
		move.w	d4,(a1)+
		cmp.w	simMxTop,d3
		bge.s	.o1
		move.w	d3,simMxTop
.o1:	cmp.w	simMxBot,d4
		ble.s	.o2
		move.w	d4,simMxBot
.o2:	dbf		d6,.g
		move.w	#24,simMxHold		; (the glows' sizes follow softly)
		rts
.old:	tst.w	simMxHold
		beq.s	.none
		subq.w	#1,simMxHold
		rts
.none:	move.l	#$7fff8000,d0
		move.l	d0,simMxTop
		lea		simMxR,a1
		moveq	#4-1,d6
.n:		move.l	d0,(a1)+
		dbf		d6,.n
		rts
.c:		dc.w	2,6,11,16
	endc

;---------------------------------------------
; the sound: the fighter's engine (music.s drone on channel 1, the music's
; quiet pad) and a torpedo's hiss for a while after its whoosh (channel 3,
; the drums - only briefly): louder the nearer, the Doppler - higher coming
; at us, lower going away (from how the distance changes); the engine
; howls (louder, higher) when it pushes
simSound:
		clr.w	simSnd3V
		tst.b	simEngine
		bne.s	.on
		clr.w	simSnd1V
		bra		.torp
.on:
		cmp.w	#SP_END,simPhase
		bne.s	.on1
		clr.w	simSnd1V
		bra		.torp
.on1:	cmp.w	#SP_LOOP,simPhase
		beq		.loop
		move.l	simZ,d0				; the distance (units): |z| + |x|/2
		asr.l	#8,d0
		bpl.s	.s0
		neg.l	d0
.s0:	move.l	d0,d2
		lsr.l	#4,d0
		move.l	simX,d1
		asr.l	#8,d1
		bpl.s	.s1
		neg.l	d1
.s1:	lsr.l	#5,d1
		add.l	d1,d0
		addq.l	#1,d0
		cmp.l	#$ffff,d0
		bls.s	.s2
		move.l	#$ffff,d0
.s2:	move.l	#morphSndShip,d1	; the volume
		divu	d0,d1
		cmp.w	#56,d1
		bls.s	.s3
		moveq	#56,d1
.s3:	move.w	simThrust,d3		; (pushing: louder)
		lsr.w	#4,d3
		add.w	d3,d1
		cmp.w	#64,d1
		bls.s	.s4
		moveq	#64,d1
.s4:	bsr		.vsm
		move.l	d2,d0				; the Doppler: how |z| changes
		sub.l	simZOld,d0
		move.l	d2,simZOld
		asr.l	#4,d0				; units a frame
		bsr		.dopp
		muls	#morphPerShip,d0
		asr.l	#4,d0
.per:	move.w	simThrust,d1		; (pushing: higher, an eighth at most)
		lsr.w	#3,d1
		neg.w	d1
		add.w	#256,d1
		muls	d1,d0
		asr.l	#8,d0
		bsr		.pclip
		sub.w	simSnd1P,d0			; (it glides: no steps)
		asr.w	#2,d0
		add.w	d0,simSnd1P
		bra.s	.torp
.loop:	; behind us, round in its loop: quieter, then nearer again
		move.w	simPT,d1
		mulu	d1,d1
		divu	#morphLoopT*morphLoopT/24,d1
		cmp.w	#24,d1
		bls.s	.l0
		moveq	#24,d1
.l0:	add.w	#12,d1
		bsr		.vsm
		move.l	#morphEZ0,simZOld	; (the entry from near)
		move.w	#morphPerShip*14/16,d0
		ext.l	d0
		bra.s	.per
.torp:	; the nearest torpedo burning, a while after its whoosh
		lea		morphTorps,a2
		moveq	#morphTorpN-1,d7
		move.l	#$7fffffff,d2
		sub.l	a3,a3
.t:		move.w	tp_burn(a2),d0
		beq.s	.tn
		cmp.w	#morphTorpHissT,d0
		bhs.s	.tn
		cmp.l	tp_z(a2),d2
		ble.s	.tn
		move.l	tp_z(a2),d2
		move.l	a2,a3
.tn:	lea		tp_len(a2),a2
		dbf		d7,.t
		move.l	a3,d0
		beq.s	.out
		lsr.l	#8,d2				; units
		addq.l	#1,d2
		cmp.l	#$ffff,d2
		bhi.s	.out
		move.l	#morphSndTorp,d1
		divu	d2,d1
		cmp.w	#48,d1
		bls.s	.t0
		moveq	#48,d1
.t0:	move.w	#morphTorpHissT,d0	; (dying away)
		sub.w	tp_burn(a3),d0
		mulu	d0,d1
		divu	#morphTorpHissT,d1
		cmp.w	#2,d1
		blo.s	.out
		move.w	d1,simSnd3V
		move.l	tp_vz(a3),d0		; going away: lower
		asr.l	#8,d0
		bsr.s	.dopp
		muls	#morphPerTorp,d0
		asr.l	#4,d0
		bsr.s	.pclip
		move.w	d0,simSnd3P
.out:	rts
; d1 = the engine's volume wanted: it glides there
.vsm:	sub.w	simSnd1V,d1
		asr.w	#2,d1
		add.w	d1,simSnd1V
		rts
; d0 = how fast it goes away (units a frame) -> d0 = 16 + that (4.4 times
; the pitch's period), kept within reason
.dopp:	cmp.l	#8,d0
		ble.s	.d0
		moveq	#8,d0
.d0:	cmp.l	#-6,d0
		bge.s	.d1
		moveq	#-6,d0
.d1:	add.w	#16,d0
		rts
.pclip:	cmp.l	#124,d0
		bge.s	.p0
		moveq	#124,d0
.p0:	cmp.l	#1000,d0
		ble.s	.p1
		move.w	#1000,d0
.p1:	rts

;---------------------------------------------
; the frame into morphRec (see morphPlayFrame for its form)
simEncode:
		move.l	morphSimW,a0
		cmp.l	#morphRecEnd-256,a0	; (full: the end here)
		blo.s	.room
		move.w	#1<<RB_END,(a0)+
		bra		.last
.room:	move.l	a0,a3				; (the flags: at the end)
		addq.l	#2,a0
		move.w	simEv,d7
		; the ship: not drawn, or all of it off the screen, or too near
		tst.b	simHidden
		bne		.noShip
		tst.b	morphClip
		bne		.gone
		moveq	#$f,d4				; (the sides all its points are off)
		and.b	morphOutAnd,d4
		beq.s	.on
.gone:	cmp.w	#SP_PASS,simPhase	; (gone past us in the pass)
		bne		.noShip
		st		simGone
		bra		.noShip
.on:	; how its points changed: nibbles, bytes or words
		moveq	#3,d4
		tst.b	simPrevHid
		bne.s	.mode
		lea		morphXY,a1
		lea		simPrev,a2
		moveq	#0,d5
		moveq	#2*morphNP-1,d6
.dl:	move.w	(a1)+,d0
		sub.w	(a2)+,d0
		bpl.s	.dp
		not.w	d0					; (-1-d: -8 counts as 7)
.dp:	cmp.w	d0,d5
		bhs.s	.dn
		move.w	d0,d5
.dn:	dbf		d6,.dl
		moveq	#1,d4
		cmp.w	#7,d5
		bls.s	.mode
		moveq	#2,d4
		cmp.w	#127,d5
		bls.s	.mode
		moveq	#3,d4
.mode:	or.w	d4,d7
		move.w	morphFMask,d0
		tst.b	simEngine			; the engine burning, its plate seen: the
		beq.s	.m0					; glow
		btst	#6,d0
		beq.s	.m0
		bset	#RB_GLOW,d7
.m0:	tst.b	simPrevHid
		bne.s	.m1
		cmp.w	simPrevMask,d0
		beq.s	.m2
.m1:	bset	#RB_MASK,d7
		move.w	d0,simPrevMask
		move.w	d0,(a0)+
.m2:	bra.s	.vz
.noShip:
		st		simPrevHid
.vz:	; the stars' speed (bit 15: from the pass on, thinned out anyway)
		move.w	simVz,d0
		bset	#15,d0
.v0:	cmp.w	simPrevVz,d0
		beq.s	.v1
		bset	#RB_VZ,d7
		move.w	d0,simPrevVz
		move.w	d0,(a0)+
.v1:	; the sounds
		move.w	simSnd1V,d0
		cmp.w	#2,d0
		blo.s	.n1
		bset	#RB_SND1,d7
		move.w	d0,(a0)+
		move.w	simSnd1P,(a0)+
.n1:	move.w	simSnd3V,d0
		beq.s	.n3
		bset	#RB_SND3,d7
		move.w	d0,(a0)+
		move.w	simSnd3P,(a0)+
.n3:	; the glow: 9 units across at its depth, bigger with the thrust
		moveq	#RF_MODE,d0
		and.w	d7,d0
		beq.s	.g9
		move.l	morphSZ,d2
		lsr.l	#4,d2
		beq.s	.g9
		move.l	#9*morphF,d0
		divu	d2,d0
		move.w	simThrust,d1
		lsr.w	#1,d1
		add.w	#256,d1
		mulu	d1,d0
		lsr.l	#8,d0
		cmp.w	#255,d0
		bls.s	.g0
		move.w	#255,d0
.g0:	lsl.w	#8,d0
		move.w	simThrust,d1
		cmp.w	#255,d1
		bls.s	.g1
		move.w	#255,d1
.g1:	move.b	d1,d0
		cmp.w	simPrevGlow,d0
		beq.s	.g9
		bset	#RB_GLOWP,d7
		move.w	d0,simPrevGlow
		move.w	d0,(a0)+
.g9:	; the points
		moveq	#RF_MODE,d0
		and.w	d7,d0
		beq		.p9
		lea		morphXY,a1
		lea		simPrev,a2
		subq.w	#2,d0
		bmi.s	.pn
		beq.s	.pb
		moveq	#morphNP-1,d6		; words
.pw:	move.l	(a1),(a0)+
		move.l	(a1)+,(a2)+
		dbf		d6,.pw
		bra.s	.p8
.pb:	moveq	#2*morphNP-1,d6		; bytes
.pb0:	move.w	(a1)+,d0
		move.w	d0,d1
		sub.w	(a2),d0
		move.w	d1,(a2)+
		move.b	d0,(a0)+
		dbf		d6,.pb0
		bra.s	.p8
.pn:	moveq	#morphNP-1,d6		; nibbles
.pn0:	move.w	(a1)+,d0
		move.w	d0,d1
		sub.w	(a2),d0
		move.w	d1,(a2)+
		lsl.b	#4,d0
		move.w	(a1)+,d1
		move.w	d1,d2
		sub.w	(a2),d1
		move.w	d2,(a2)+
		and.b	#$0f,d1
		or.b	d1,d0
		move.b	d0,(a0)+
		dbf		d6,.pn0
.p8:	sf		simPrevHid
.p9:	; the torpedoes: onto the screen
	ifne	escortMux
		bsr		simMxRange			; (their glows clear of the afterburner's)
	endc
		bsr		simTorps
		lsl.w	#8,d0
		lsl.w	#3,d0
		or.w	d0,d7
		; the last frame?
		cmp.w	#SP_END,simPhase
		bne.s	.nl
		bset	#RB_END,d7
.nl:	move.w	d7,(a3)
.last:	move.l	a0,morphSimW
		addq.w	#1,morphSimN
		btst	#RB_END,d7
		beq.s	.out
		st		morphSimEnd
.out:	rts

; the torpedoes on the screen into the frame at a0 (-> a0 on, d0 = how
; many): x = mid + x*lens/z (1/256 units; all halved till z fits a word),
; the radius by the distance (and a twinkle), a dot far off, the flare
; behind it (every other frame) once it burns
simTorps:
		movem.l	d7/a3,-(a7)
		lea		morphTorps,a4
		moveq	#0,d7
		swap	d7					; (count in the high word)
		move.w	#morphTorpN-1,d7
.t:		move.w	tp_age(a4),d0
		ble		.n
		move.l	tp_z(a4),d5
		move.l	tp_x(a4),d3
		move.l	tp_y(a4),d4
		moveq	#0,d6
.sh:	cmp.l	#32000,d5
		blt.s	.s0
		asr.l	#1,d5
		asr.l	#1,d3
		asr.l	#1,d4
		addq.w	#1,d6
		bra.s	.sh
.s0:	tst.l	d5
		ble		.n
		muls	#morphF,d3
		divs	d5,d3
		add.w	#morphVX,d3			; x
		muls	#morphF,d4
		divs	d5,d4
		add.w	#morphVY,d4			; y
		move.l	#morphTorpR*16*morphF,d0	; the radius
		lsr.l	d6,d0
		divu	d5,d0				; px
		move.w	tp_age(a4),d1
		move.w	tp_burn(a4),d2		; (falling: cold, still)
		beq.s	.tw
		cmp.w	#1,d2				; the first frame it burns: a flash,
		bne.s	.tw0				; half as big again
		move.w	d0,d2
		lsr.w	#1,d2
		addq.w	#1,d2
		add.w	d2,d0
.tw0:	btst	#0,d1				; the twinkle
		beq.s	.tw
		addq.w	#1,d0
.tw:	cmp.w	#127,d0
		bls.s	.r0
		moveq	#127,d0
.r0:	move.w	d3,(a0)+
		move.w	d4,(a0)+
		move.b	d0,(a0)+
		moveq	#0,d2				; the flags
		cmp.w	#2,d0
		bhs.s	.f0
		bset	#TF_DOT,d2
.f0:	move.w	tp_burn(a4),d6
		beq.s	.f9
		bset	#TF_BURN,d2
		cmp.w	#1,d6
		bne.s	.f1
		bset	#TF_FLASH,d2
.f1:
	ifne	escortMux
		movem.l	d0/d5/a1,-(a7)		; its glow (as morphMxTGeo): clear of the
		move.l	d7,d5				; afterburner's glow in the same sprite
		swap	d5					; (its place in the frame's list), else
		lsl.w	#2,d5				; left out
		lea		simMxR,a1
		add.w	d5,a1
		subq.w	#1,d0
		btst	#TF_FLASH,d2
		beq.s	.mx0
		addq.w	#4,d0
.mx0:	cmp.w	#MSPR_RMAX,d0
		ble.s	.mx1
		moveq	#MSPR_RMAX,d0
.mx1:	cmp.w	#1,d0
		bge.s	.mx2
		moveq	#1,d0
.mx2:	move.w	d4,d5				; (above it)
		add.w	d0,d5
		addq.w	#2+morphMxGap,d5
		cmp.w	(a1),d5
		ble.s	.mx9
		move.w	d4,d5				; (below it)
		sub.w	d0,d5
		subq.w	#2+morphMxGap,d5
		cmp.w	2(a1),d5
		bge.s	.mx9
		bset	#TF_NOSPR,d2
		addq.w	#1,simMxSkip
.mx9:	movem.l	(a7)+,d0/d5/a1
	endc
		btst	#0,d1				; (every other frame: it flickers)
		bne.s	.f9
		; the flare: 2r + 0..3 long, from its aim through the ball
		move.w	d1,d6
		and.w	#3,d6
		add.w	d0,d6
		add.w	d0,d6
		move.w	d3,d0
		sub.w	tp_ax(a4),d0
		move.w	d4,d1
		sub.w	tp_ay(a4),d1
		move.w	d0,d5				; scaled to the length (by the bigger
		bpl.s	.a0					; of the two)
		neg.w	d5
.a0:	move.w	d1,d3
		bpl.s	.a1
		neg.w	d3
.a1:	cmp.w	d3,d5
		bhs.s	.a2
		move.w	d3,d5
.a2:	tst.w	d5
		beq.s	.f9
		muls	d6,d0
		divs	d5,d0
		muls	d6,d1
		divs	d5,d1
		bset	#TF_FLARE,d2
		move.b	d2,(a0)+
		move.b	d0,(a0)+
		move.b	d1,(a0)+
		bra.s	.cnt
.f9:	move.b	d2,(a0)+
		clr.b	(a0)+
		clr.b	(a0)+
.cnt:	swap	d7
		addq.w	#1,d7
		swap	d7
.n:		lea		tp_len(a4),a4
		dbf		d7,.t
		swap	d7
		move.w	d7,d0
		movem.l	(a7)+,d7/a3
		rts

		section "morphchip",bss_c
morphSprBuf:	ds.b	2*4*MSPR_LEN	; (morphSprFrame) two frames' sprites 0..3

		section "morphdata",data	; (CPU only: copied into the sprites)
		include	"abflame.i"

		section "morphbss",bss
	ifeq	escortMux
morphSprImg:	ds.l	3+5+7+9+11+13+15	; (morphSprMake) the glows' rows
	endc
	ifne	showdownLean
morphLean::		ds.b	1		; the ship gone: the torpedoes alone (morphLnFrame)
morphRecFree::	ds.b	1		; ... all there: sdOvl free
morphLnN:		ds.w	1		; ... how many (the record's last frame)
morphLnS:		ds.w	1		; ... the frame they set off
morphLnV:		ds.w	1		; ... the engine then: volume (0: not heard),
morphLnP:		ds.w	1		; period
morphLnT:		ds.w	6*morphTorpN	; ... each: from (x, y), to, its hit's
									; frame, its blob (R + 1)
	endc

morphRcp:	ds.w	morphRcpN
; the flight, frame by frame (the sim writes, the play reads)
	ifeq	escortMux
morphRecSize	= 64*1024
	else
morphRecSize	= 62*1024-16*spr8	; (escortMux: 58.1 KB of it written - the
	endc					; total memory must not grow: spr8's code)
morphRec:	ds.b	morphRecSize
morphRecEnd: