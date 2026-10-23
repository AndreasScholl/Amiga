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
