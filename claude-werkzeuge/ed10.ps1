$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
$sp="C:\Users\konta\AppData\Local\Temp\claude\D--Thrust---Quadlite-Amiga-Projekt-Demo2023\43b28c74-8c82-4140-adc7-790e8fda5229\scratchpad"
Rep "MV_MOVE		= 12		; its place in the escort: p1 units across, p2 ahead`n" "MV_MOVE		= 12		; its place in the escort: p1 units across, p2 ahead`nMV_CLIMB	= 13		; pulls up and turns to heading p1, climbing p2 units`nMV_WEAVE	= 14		; a slow weave: p1 units across, p2 rounds`n"
Rep "		MV		MV_FEINT,2*morphBeat,35,-24,96		; a feint left ...`n		MV		MV_TURNTO,6*morphBeat,360,0,192		; ... hard right (bar 3) all the`n		dc.w	-1									; way round: past facing us, and off`n" "		MV		MV_FEINT,2*morphBeat,30,-24,96		; a feint left ...`n		MV		MV_CLIMB,8*morphBeat,0,22,192		; ... then it pulls up and turns`n		dc.w	-1									; away into our way, slowly`n"
$e0=$m.IndexOf("morphEscList:`n"); $e1=$m.IndexOf("		dc.w	-1`n",$e0)
$m=$m.Substring(0,$e0)+"morphEscList:`n		MV		MV_WEAVE,4*morphBeat,24,1,96		; (the drops on its beats)`n		MV		MV_BARREL,4*morphBeat,18,1,256`n		MV		MV_BACK,4*morphBeat,90,40,128`n		MV		MV_KNIFE,4*morphBeat,90,0,128`n		MV		MV_BARREL,4*morphBeat,18,-1,256`n		MV		MV_MOVE,3*morphBeat,-50,160,160		; (up left, away: room for`n		MV		MV_VROLL,2*morphBeat,0,1,192		; the victory roll; the break)`n"+$m.Substring($e1)
Rep "		dc.w	mvMove-.tab`n" "		dc.w	mvMove-.tab,mvClimb-.tab,mvWeave-.tab`n"
Rep "; --- its place in the escort from here on (the springs follow)`n" ([IO.File]::ReadAllText("$sp\mv2.txt").Replace("`r`n","`n")+"; --- its place in the escort from here on (the springs follow)`n")
Rep "morphTurnBank = 5		; ... its bank by the turn's speed`n" "morphTurnBank = 5		; ... its bank by the turn's speed`nmorphClimbTilt = 22		; (MV_CLIMB) degrees the nose comes up`nmorphClimbBank = 30		; ... and it banks into the turn`n"
# inertia: soft springs, slow bank, calm pilot
Rep "morphSpK	= 3			; the spring its place follows: pull, damping (1/256) -`nmorphSpD	= 34		; a little overshoot, then it sits`n" "morphSpK	= 1			; the spring its place follows: pull, damping (1/256) -`nmorphSpD	= 20		; heavy: it takes its time, overshoots a little, sits`n"
Rep "		move.w	d1,simJit			; 30..61 frames to the next`n		move.w	d0,d1`n		lsr.w	#5,d1`n		and.w	#127,d1`n		sub.w	#64,d1`n		move.w	d1,simJX			; +-4 units across`n		swap	d0`n		and.w	#63,d0`n		sub.w	#32,d0`n		move.w	d0,simJY			; +-2 up and down`n" "		add.w	d1,d1`n		move.w	d1,simJit			; 60..122 frames to the next`n		move.w	d0,d1`n		lsr.w	#5,d1`n		and.w	#63,d1`n		sub.w	#32,d1`n		move.w	d1,simJX			; +-2 units across`n		swap	d0`n		and.w	#31,d0`n		sub.w	#16,d0`n		move.w	d0,simJY			; +-1 up and down`n"
Rep ".b4:	sub.w	simBank,d0`n		asr.w	#2,d0`n		add.w	d0,simBank`n" ".b4:	sub.w	simBank,d0			; (slowly: a heavy ship)`n		asr.w	#4,d0`n		add.w	d0,simBank`n"
# break: slower, eased both ways
Rep "morphBreakT	= 60		; frames of the turn (quick at first: a hard break)`n" "morphBreakT	= 4*morphBeat	; frames of the turn (eased in and out: heavy)`n"
Rep "		move.w	d0,d6`n		move.w	#256,d5				; e = 1 - (1-u)^2: quick at first`n		sub.w	d0,d5`n		mulu	d5,d5`n		lsr.l	#8,d5`n		neg.w	d5`n		add.w	#256,d5`n" "		move.w	d0,d6`n		move.w	d1,d5				; (eased in and out)`n"
# guns: by their wing's faces again
Rep "		dc.w	`$01ff,`$01ff		; (the guns stick out of the hull: always)`n" "		dc.w	`$0012,`$0024		; (the guns: with their wing's faces)`n"
# flame: slow pulse, the cross always
Rep "		btst	#0,morphT+1			; (the flicker)`n		beq.s	.f0`n		add.w	#26,d6`n.f0:	lea		morphPXY+7*4,a1`n" "		movem.w	d0/d1,-(a7)			; (it pulses: 24 degrees a frame)`n		move.w	morphT,d0`n		mulu	#24*16,d0`n		bsr		morphSinCos16`n		asr.w	#8,d0`n		asr.w	#2,d0				; -32..32`n		add.w	d0,d6`n		movem.w	(a7)+,d0/d1`n		lea		morphPXY+7*4,a1`n"
Rep "		cmp.b	#morphGlowHot,morphPGP+1	; pushing hard: the cross`n		blo.s	.out`n		lea		morphFlP,a2`n" "		lea		morphFlP,a2			; the cross of fire`n"
# sound: louder, deeper
Rep "morphSndShip = 2400		; the engine's loudness (volume times units away)`nmorphPerShip = 330		; ... its pitch (period, standing still)`n" "morphSndShip = 6000		; the engine's loudness (volume times units away)`nmorphPerShip = 400		; ... its pitch (period, standing still)`n"
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
