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
;              stars on, all eight sprites as tall bars over the screen and
;              the logo (stars3d.i s3SprTest), each pair its own colours -
;              to see in WinUAE which come out clean; the glows are off
;           0: as it is
sprTest			= 0
