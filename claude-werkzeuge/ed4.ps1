$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
$sp="C:\Users\konta\AppData\Local\Temp\claude\D--Thrust---Quadlite-Amiga-Projekt-Demo2023\43b28c74-8c82-4140-adc7-790e8fda5229\scratchpad"
$a0=$m.IndexOf("; --- the pass: we pick up speed and come up to it"); $e="		move.w	d0,simVz`n.l0:	bsr		simOurSpeed"; $a1=$m.IndexOf("		subq.w	#6,d0`n		move.w	d0,simVz`n.l0:	bsr		simOurSpeed")
if($a0 -lt 0 -or $a1 -lt 0){throw "pass"}
$m=$m.Substring(0,$a0)+[IO.File]::ReadAllText("$sp\pass.txt").Replace("`r`n","`n")+".l0:	bsr		simOurSpeed"+$m.Substring($a1+("		subq.w	#6,d0`n		move.w	d0,simVz`n.l0:	bsr		simOurSpeed").Length)
Rep "morphPassVs	= 4			; it comes on towards us (1/16 units a frame)`nmorphPassAim = 6		; its nose after the camera: tenths of the angle`n" "morphVzPass	= 20		; the stars at the end of it: this many times the start's`nmorphClose0	= 16		; we gain on it (1/16 units a frame): at first ...`nmorphClose1	= 62		; ... and at the end (it flies our way, a little slower)`n"
Rep "morphDodgeZ	= 620		; units: this near, it dodges" "morphDodgeZ	= 220		; units: this near, it dodges"
Rep "morphVzLoop	= 6			; ... we ease off to this speed meanwhile`n" "morphVzLoop	= 6			; ... we ease off to this speed meanwhile,`nmorphVzDown	= 24		; ... this much a frame`n"
Rep "		MV		MV_TURNTO,6*morphBeat,180,0,192		; ... hard right (bar 3) and`n		dc.w	-1									; round to face us`n" "		MV		MV_TURNTO,6*morphBeat,360,0,192		; ... hard right (bar 3) all the`n		dc.w	-1									; way round: past facing us, and off`n"
Rep @"
		move.w	simVz,d0			; we speed up with it: top speed
		cmp.w	#morphVzMax*256,d0
		bhs.s	.v
		add.w	#16,d0
		move.w	d0,simVz
.v:		bsr		simOurSpeed
"@.Replace("`r`n","`n") @"
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
"@.Replace("`r`n","`n")
Rep "		add.w	#morphPark0,d0`n.pk:	move.w	d0,warpPark`n" "		add.w	#morphPark0,d0`n.pk:	cmp.w	#morphParkMax,d0		; (no further than the field takes)`n		bls.s	.pk1`n		move.w	#morphParkMax,d0`n.pk1:	move.w	d0,warpPark`n"
Rep "morphPark0	= 400		; ... and from the pass on this much anyway`n" "morphPark0	= 400		; ... and from the pass on this much anyway`nmorphParkMax = 1930		; ... at most (as it was at the old top speed)`n"
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
