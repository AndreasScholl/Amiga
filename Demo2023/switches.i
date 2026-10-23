; switches for the ending - asteroids.s and scroller.s both include this
;
; defWords  1: once the TV is off the "magnetic field" can no longer hold
;              the words of the captain's message on the text row - they
;              come in as letters (the game's) at all heights, the Defender
;              ship goes up and down after them and lasers each word where
;              it flies (asteroids.s seq_defwords, scroller.s laserObj)
;           0: the message runs along the text row and is lasered there, as
;              it was (seq_deffire)
defWords		= 0
; defWordsVec 1: (with defWords) the words as the game's vector letters - a
;              misunderstanding, kept: 0 is the running text's own font
defWordsVec		= 0
defLane			= 7				; (defWords) a letter this near the beam's line is hit
defObjGap		= 40			; (defWords) the laser: the next letter of a word is this near

; tvLate    1: the TV does not go off after the flicker: the flicker slows
;              down and dies, the bar goes dark ("off"), five seconds later
;              it comes back to a dark, faulty flicker (the Terminator that
;              rises once more), the Defender part runs on that, and only
;              once the last letter of the message has gone up does the TV
;              go off for good, with its zap - the climax
;           0: the TV goes off after the flicker, as before
tvLate			= 0
; fwAll     1: the cannon's hits on the text go up as fireworks too (latticeAdd
;              instead of blastFx's sparks and rings); 0: as before
fwAll			= 1
; sfxGame   1: shots and letter explosions are heard in the game as well (from
;              the start); 0: only in the logo destruction, as before
sfxGame			= 0
; fastStars 1: (Elite step 2) the Defender stars 50% faster, 4.5 px a frame
;              (asteroids.s seq_defStar), and after the last word they keep
;              that speed on into the ending; 0: 3 px a frame, and they run
;              down to a stand after the last word, as before
fastStars		= 1
; elite3    1: (Elite step 3) after the last word the ship stays a Defender
;              ship, glides to the middle of the screen and unfolds into the
;              Quadlite-Thrust fighter (morph.i); the stars go into depth
;              once it is done (asteroids.s seq_morph); 0: an Asteroids ship
;              again, the stars into depth after warpWait, as before
elite3			= 1
; sprTest  1: (with elite3) the sprite test: from the switch to the bitplane
;              stars on, all eight sprites as tall bars over the logo band
;              and the stars (rows $22..$128, stars3d.i s3SprTest), each pair
;              its own colours - to see in WinUAE which come out clean (with
;              spr8: all eight); the glows are off. no memory of its own
;           0: as it is
sprTest			= 0
; --- the Elite finale (each part on its own switch: 0 is as it was)
; fixQmarks 1: DEFTEST holds a spot under the row and fires at every glyph
;              that comes by (the question marks too) - the hops round the
;              text got it there too seldom to fire
fixQmarks		= 1
; defLine   1: (with fixQmarks) before the message the ship works its way
;              over to the right of the Defender spot, onto the row's height,
;              nose round to the right - swaying a little up and down, still
;              firing at every glyph that comes, the last question marks too.
;              then it has had enough: a beat, the reverse, a burn, the
;              reverse again and a brake onto the Defender spot - and the
;              laser only once it has settled there. the message comes 11
;              spaces later; 0: as it was
defLine			= 1
; a1Cine    1: the first attack staged: out of boredom a single shot - a hit -
;              the ship comes over, slowly, and has a look at the hole; then,
;              liking it, single and double shots from spots it picks, till
;              exactly a1Hits letters are gone: the scroller breaks. it mends
;              a little faster, with "TEXT ONLINE AGAIN!"
;           0: 5..8 shots, hits or not, as it was
a1Cine			= 1
a1Hits			= 6
; def2Cine  1: (with defLine) the second attack: the stars keep going till the
;              monitor is off. then, a step at a time: they slow down to a
;              stand, stand, turn round and speed up the Defender way - and the
;              bridge comments it in the text, more and more upset. the text
;              runs on till the ship has hit def2Hits letters from the monitor
;              going off (and the stars are up to speed), then the question
;              marks, and the way onto the Defender spot as before
;           0: the stars turn round with the flicker, as it was
def2Cine		= 1
; dropRun   1: the old last attack (asteroids.s seq_run, seq_fly .. seq_hold)
;              is left out of the build - it never runs (finalAttackOn is 0),
;              and its bytes go to the flight's record; 0: built in, as it was
dropRun			= 1
; defSalvo  1: (with def2Cine) after the monitor the ship hunts the text from
;              spot to spot in short salvos (no stream of fire); once all is
;              said it goes over to the row, salvos from there too, and the
;              final move comes only once the last sentence is coming in;
;              0: the pastime under the row and the early move, as it was
defSalvo		= 1
; huntRandom 1: the hunt's spots anywhere round the letter it is after - left
;              or right, over or under, near or far (never the logo); 0: always
;              left of it, as it was
huntRandom		= 1
; fwBig     1: the laser's letter fireworks half again as big: the same 24
;              sparks on the same curves, flying 1.5 times as far out and down
;              (scroller.s drawLattice); 0: as they were
fwBig			= 1
; (def2Cine's def2Hits: with defSalvo none - the hunt lasts as long as the
; bridge talks; salvos, not a stream: 20 hits would take half a minute)
	ifne	defSalvo
def2Hits		= 0
	else
def2Hits		= 20
	endc
; starPal2  1: the stars in seven colours from the Defender's own: every
;              layer keeps its colour through the change; after it the
;              bands move out so a star goes through all of them
starPal2		= 1
; escortMux 1: the torpedoes go in the entry already (the fighter still high
;              up), their engines fire once it is safely below them; their
;              glows (abImg, the afterburner's flicker and colours) and the
;              afterburner's share the sprites, one above the other
;              (multiplexed, kept clear by the sim); the hits as they were,
;              the break 7.7 s before the first one (morph.i)
escortMux		= 1
; drumSeq   1: from the break the music's voices fade out (5.5 s), its drums
;              play on; at the next bar LSP stops and the song's own drums go
;              on by themselves on channels 0 and 2 (drumseq.i), quiet for
;              the beat before the first hit (music.s musicTick)
drumSeq			= 1
; showdownLean 1: (with escortMux) once the fighter has gone the flight's
;              work stops - the torpedoes fly on by themselves straight to
;              the logo, as blobs; the record is free then (morph.i sdOvl)
showdownLean	= 1
; --- the Elite: 8 sprites, the launch, the stars' change (each on its own)
; spr8      1: clistElite fetches from DDFSTRT $38 (to $d0: 40 bytes a line)
;              instead of $28 - the sprite DMA slots of 4..7 come free. the
;              pictures stay where they were: every plane pointer of the
;              Elite +4 bytes (the 32 px behind the left border), every
;              modulo +6 (the lines are still li = 46 wide); clist's logo
;              part too, once clistElite runs (stars3d.i s3Flip)
spr8			= 1
; starFlow  1: the 3D stars' change flows on: the converted stars anywhere in
;              their colour band, the new ones on a conveyor right behind
;              the field (no shell, no gap, no wave), the furthest colour
;              hardly there, the front's orange-brown brighter after the
;              blend (stars3d.i s3Spawn, s3FlowAdd)
starFlow		= 1
; launchSeq 1: (with escortMux, spr8) the torpedoes' launch at full speed: the
;              fighter shows off (a big banked arc, a heavy barrel roll),
;              lines up under the logo, then they jump out of its top one a
;              beat (it kicks back, its lines flash), glide cold and fire -
;              each its own sprite (4..6); the hits as they were (morph.i)
launchSeq		= 1
; starCam   1: (with launchSeq) in the escort the stars follow the fighter's
;              thrust (up to 1/8 faster or slower, softly; morph.i morphTick)
starCam			= 1
; --- the cinematic end fight (each on its own switch: 0 is as it was)
; recV2     1: (with launchSeq) the flight's record in segments: a key every
;              1, 2, 4 or 8 frames, the frames between them drawn in a
;              straight line from one to the next (the sim checks every one
;              of them: off by 1 px at most) - the ship's points, the
;              torpedoes, the sounds, the stars' speed alike. a third of the
;              bytes or less: room for a much longer flight (morph.i
;              simCapture, simEncStep, morphPlayFrame)
recV2			= 1
; cineFight 1: (with recV2) the end fight as a film (cine.i): the fighter
;              flies as a real jet - its lift along its bank, gravity, a
;              heavy roll, its pull and throttle only as fast as it can, the
;              pilot flying to the places the film wants. a long, slow
;              formation flight (turns, a slow roll), then down to its aim,
;              low ahead of us: we see its top - the bay's doors open, the
;              torpedoes rise out of it on a lift one by one, are pushed
;              off, glide, fire; the doors shut; it peels off past us
cineFight		= 1
; --- the demo start (drehbuch_verwandlung.md, part 0a)
; startCouple 1: the start follows the names, not the clock: the copper bar fades
;              up 4 s after EXOLON has gone (its last letter's explosion
;              over), EXCITER comes only once the bar is up, the shadow
;              playfield and the text 3 s after EXCITER has gone, DANDEE only
;              once the text has crumbled for 2 s. till the text the bar's
;              shadow playfield is not there at all (BPLCON0 $1200, no DBLPF)
;           0: the bar at introBarStart, the text at introScrollStart, the
;              shadow playfield on with the game, as it was
startCouple		= 1
cpBarWait		= 200		; (startCouple) frames from EXOLON gone to the bar
cpTextWait		= 150		; ... from EXCITER gone to the text and the shadow
cpCrumbleWait	= 100		; ... the text crumbling before DANDEE may come
; dropWarpSpr 1: (with elite3) warp.i's own 3D field in sprites (warpThin ..
;              warpSpawn) is left out of the build - under elite3 the stars go
;              over to stars3d.i before it could ever run; its bytes go to the
;              flight's record. 0: built in, as it was
dropWarpSpr		= 1
; zeroWave 1: (drehbuch_verwandlung.md, part 0b) ZERONINE's honour wave - once
;              the name is up, a wave runs through it from the Z to the E: each
;              letter comes closer (zooms to 150 %), turns once round its own
;              upright axis in true perspective, and springs back. the name
;              drifts on all the while; the ship flies in only after it, at
;              zwShipWait instead of ai_enterwait (variant a, with the turn)
;           2: the same wave without the turn - zoom only (variant b)
;           0: no wave, the ship comes in at ai_enterwait, as it was
zeroWave		= 0
zwStart			= 150		; (zeroWave) frames from ZERONINE's spawn to the Z's start
zwShipWait		= 300		; ... and to the ship flying in
; zwBall 1: (with zeroWave; the user's look, 2026-10-23) each letter flies its
;              wave as a ball with spin, in true perspective: thrown at us
;              (as near as it may: in the picture, below the logo, 200 % at
;              most), it falls away behind its place till it is nearly gone,
;              bounces and springs back to rest; it turns the whole way, two
;              turns, smoothly. its centre goes to the vanishing point and
;              back like everything that recedes. zeroWave 2: the same
;              without the turns. 0: zeroWave's short wave, as built first
zwBall			= 1
zwShipWaitB		= 420		; (zwBall) frames from ZERONINE's spawn to the ship
; zwEntry 1: (with zwBall; the user's look, 2026-10-23) the ball IS the
;              letters' way in: ZERONINE's letters do not zoom in, each comes
;              out of the depth as a spinning ball, 6 frames after the one
;              to its left, bounces at us far too high (as near as it may),
;              hits the ground behind twice, lower each time (one gravity,
;              one bounce factor - on the size the eye sees, drawn in true
;              perspective) and lands softly in its place: an asteroid from
;              there on. 0: zwBall's wave after the letters are up
zwEntry			= 1
zwShipWaitE		= 250		; (zwEntry) frames from ZERONINE's spawn to the ship
; fwHeavy   1: (with fwBig; the user, 2026-10-23: as heavy as it goes) the
;              laser's letter explosions with real physics and twice the
;              sparks: 48 a burst - 24 sparks thrown out at 14..24 px a frame
;              that the air brakes hard (the bang, then the glow hangs and
;              sinks), 8 heavy chunks flying far on falling arcs, a pressure
;              ring at 30 px a frame gone after 5 frames, a white hot core for
;              2. worked out once at the start (fhInit) into bufA's and bufB's
;              dead tails; drawn with a fast way for bursts wholly on the
;              screen. 0: the fwBig fireworks, as they were
fwHeavy			= 0
; fwShow    1: (the user, 2026-10-23: "the fattest you can make, not all the
;              same - a firework!") latticeAdd's explosions as real fireworks,
;              every one worked out live with its own random numbers: a pop
;              at the hit, then a shell climbs with its trail, slows and
;              bursts somewhere above - each at another height, up to the
;              logo. four kinds: chrysanthemum (a ball of streaking sparks),
;              willow (slow glowing rain), ring (with a glowing core),
;              crossette (stars that split in four). the laser's ones bigger
;              still, with a flash and a pressure ring. the glow sinks slowly,
;              some of it flickers. replaces fwBig/fwHeavy's tables (fw.i is
;              left out). 0: as before
fwShow			= 0
; fwBoss    1: (with fwBig; the user, 2026-10-23: the end of the scroller is
;              a mid boss - it needs KRABUMM) ONLY the laser's letter
;              explosions, on the fireworks there are: while white hot two
;              variants at once (one mirrored: 48 sparks), every other hit a
;              chain - 2 more bursts a few frames later above it (up left,
;              up, up right, each its own variant and distance) - and a
;              pressure ring; a budget a frame keeps it at 50 Hz (the oldest
;              glow flickers out first). the cannon's fireworks (the first scroller
;              attack and all before the laser) stay exactly as they are.
;              0: as before
fwBoss			= 0
; transAC   1: (with elite3; drehbuch_verwandlung.md, part 1, A-C) after the
;              glide the stars go into depth first, the Asteroids ship still
;              floating; on the next bar A: it drifts, corrects as ever, comes
;              to rest; B: a pause - then it tips its nose into the stars
;              (impulse, turn, counter impulse, a tiny overshoot) till, in
;              true perspective, only a line is left; C: a hesitant little jet,
;              yawing, rolling, correcting - the flat triangle shows. every
;              axis a pilot's push (impulse, glide, counter) and the body's
;              inertia (a spring, a little underdamped); then the unfolding
;              as before, the pose easing over into its own. 0: as before
transAC			= 1
; gunVis    1: (the user, 2026-10-23: the guns vanish 'plopp' far too early
;              when the ship lies flat) the wing guns are seen in every pose -
;              they stick out past the wing tips, the hull never hides them;
;              they went with their wing's faces, and edge on both of those
;              count as unseen. 0: as before
gunVis			= 1
; transBehind 1: (with transAC; the user, 2026-10-23) B tips the ship so it
;              ends seen from behind, its wings level - a line lying flat,
;              not upright; C's moves from there; it unfolds that way, in its
;              flight's direction (no turning back across the stars), and
;              holds so. (till the chase is live, the recorded flight starts
;              in its old pose.) 0: transAC as first built
transBehind		= 1
; torpWide  1: (the user, 2026-10-23) the torpedoes jump out half again as
;              far (the same push x 1.5, braked as ever); the left and the
;              right one aim 25 px further out on the logo, the third one
;              launched at the logo's middle. 0: as before
torpWide		= 1
; dropWarpMem 1: (with dropWarpSpr) warp.i's own field's tables (wlst,
;              warpStars, warpRTab, warpLineTab, warpDie - ~12 KB) and their
;              making at the start are left out too: nothing reads them under
;              dropWarpSpr. their bytes go to the flight's record (balance).
;              0: as before
dropWarpMem		= 1
; chaseSim  1: (with transBehind; the user, 2026-10-23) the flight's start
;              anew: from where it unfolded (seen from behind) Zeronine wakes
;              up - a slow wing rock, a look left, a look right, a small roll
;              test - then the engine fires: one flame. a long chase: it pulls
;              away, we gain slowly; it feels something behind it - a look
;              over its shoulder - and tries to shake it off: three moves,
;              each a roll, a pull, a roll out, calm between, each turn
;              costing it speed (we come closer); at last near, calm - and on
;              the beat its afterburner (the pass's evade as it was: the slow
;              curve up to the left). the hold only up to the next bar.
;              0: the flight as it was
chaseSim		= 1
; abLong    1: the afterburner's chain thrown out 30 % further (its glows
;              further apart); with chaseSim only the first glow (one flame)
;              till the afterburner first kicks in. 0: as before
abLong			= 1
; holdGap   1: the play's first frame drawn on the frame the hold ends (as
;              it was, that frame had no ship at all: a flicker as the fighter
;              sets off). 0: as before
holdGap			= 1
; hatAlways 1: (cineFight) the bay's doors part of the ship: their seams drawn
;              whenever its top is seen, from the chase on (as it was: only
;              in the film's CB_HAT blocks - they popped in). 0: as before
hatAlways		= 1
; chaseShow 1: (chaseSim) before the afterburner it shows itself: down to the
;              bottom of the screen (seen from above: its top, the bay), up
;              to the top (its belly), a heavy barrel roll down to low on the
;              right - then the afterburner. 0: as before
chaseShow		= 1
; aimUp     1: (cineFight) where it fires the torpedoes 15 px higher (as it
;              was it hung over the bottom of the screen). 0: as before
aimUp			= 1
; torpArc   1: (cineFight) a torpedo off the lift: thrown up, gravity slows it
;              to a standstill, it sinks a little (the air holds it) - then
;              its engine. 0: as before (its jump dying away)
torpArc			= 1
; musChase  1: (drumSeq) the music's voices fade as the fighter comes back
;              into the picture (the entry): the drums alone, left and right;
;              once it has fired, broken away and is out of the picture the drums fade too (3 s) -
;              silence till the hit. 0: as before (all fade at the break)
musChase		= 1
; torpHide  1: (cineFight) a torpedo on the lift is drawn only once it is up
;              out of the bay, all of it above the fighter's top (as it was
;              it showed inside the ship, rising through it). 0: as before
torpHide		= 1
; logoSafe  1: (elite3) the switch to the 3D stars' copper list: clist's logo
;              part made the Elite's (its jump back, the logo's pointers) as
;              soon as the beam is past the logo, in the very frame of the
;              switch - not in the next frame's s3Flip, which came too late
;              when the switch's frame (the field's heaviest) ran long: the
;              logo torn for a frame or two. 0: as before
logoSafe		= 1
; simMore   1: the flight's sim works in the frame's time left till raster
;              line 276 (as it was 230: ~80 lines a frame unused) - done far
;              earlier; and the play may start as soon as morphSimGo of its
;              frames are worked out (it works on ahead of the play)
;              0: as before (230, the whole flight first)
simMore			= 1
; quickAC   1: (transAC) from the stars going into depth to the turn (B) at
;              most 140 frames (2.8 s): the warp 40 frames, no wait for a bar,
;              it floats on meanwhile (pinned only the 8 dear frames), A 100.
;              0: as before (120 + a bar, resting; A 240)
quickAC			= 1
; holdLive  1: (transAC) the live ship never stands dead still: from the warp
;              on it floats down and up again once a bar (2.5 px), held after
;              the unfolding with a slight roll (2 degrees) too - both 0 at
;              the bar's start, where the flight takes over. 0: as before
holdLive		= 1
