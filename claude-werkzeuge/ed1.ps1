$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
$sp="C:\Users\konta\AppData\Local\Temp\claude\D--Thrust---Quadlite-Amiga-Projekt-Demo2023\43b28c74-8c82-4140-adc7-790e8fda5229\scratchpad"
$i0=$m.IndexOf("; the points, quicker (the sim)"); $i1=$m.IndexOf("morphPA:	ds.l	3")
$m=$m.Substring(0,$i0)+[IO.File]::ReadAllText("$sp\ptsf.txt").Replace("`r`n","`n")+$m.Substring($i1)
Rep "morphPA:	ds.l	3`nmorphPB:	ds.l	3`n" "morphOutAnd:	dc.b	0		; (morphPtsF) the sides all points are off`n				even`n"
$e0="		lea		morphXY,a1`n		moveq	#`$f,d4"; $e1=".c3:	dbf		d6,.os`n		tst.w	d4`n		beq.s	.on`n"
$a0=$m.IndexOf($e0); $a1=$m.IndexOf($e1); if($a0 -lt 0 -or $a1 -lt 0){throw "enc"}
$m=$m.Substring(0,$a0)+"		moveq	#`$f,d4				; (the sides all its points are off)`n		and.b	morphOutAnd,d4`n		beq.s	.on`n"+$m.Substring($a1+$e1.Length)
Rep "		sf		morphClip`n		clr.w	simMX`n" "		sf		morphClip`n		move.b	#`$f,morphOutAnd`n		clr.w	simMX`n"
Rep "		cmp.w	#morphLeadMin,morphSimN	; worked out far enough ahead?`n		bhs.s	.h1`n		tst.b	morphSimEnd`n		beq.s	.out`n.h1:" "		tst.b	morphSimEnd			; the whole flight worked out?`n		beq.s	.out`n"
Rep "morphLeadMin = 240		; frames worked out ahead before the play may start`n" ""
Rep "		cmp.w	#morphRcpN,d1`n		bne.s	.r`n		rts`n" "		cmp.w	#morphRcpN,d1`n		bne.s	.r`n		bra		morphSimInit		; the flight is worked out from now on`n"
Rep "morphAtkRoll = 60		; degrees: it comes out of the loop banked (right)`nmorphEntryT	= 5*morphBeat	; frames: up from the lower left corner (x, y, z`nmorphEX0	= -75*16		; 1/16 units) ...`nmorphEY0	= 52*16`n" "morphAtkRoll = -60		; degrees: it comes out of the loop banked (left)`nmorphEntryT	= 5*morphBeat	; frames: in from the upper right corner (x, y, z`nmorphEX0	= 75*16			; 1/16 units) ...`nmorphEY0	= -52*16`n"
Rep "morphPassBehind = 150*16	; ... heard on until it is this far behind us`n" "morphPassBehind = 150*16	; ... heard on until it is this far behind us`nmorphDodgeZ	= 620		; units: this near, it dodges - a quick roll and a`nmorphDodgeT	= 50		; ... jink (frames) to our left (units across,`nmorphDodgeX	= -70		; down)`nmorphDodgeY	= 24`n"
Rep "simJit:			dc.w	0		; (the pilot) frames till the next correction`n" "simJit:			dc.w	0		; (the pilot) frames till the next correction`nsimDodgeT:		dc.w	0		; (the pass) frames into its dodge`n"
Rep "		clr.w	simJit`n		clr.w	simJX`n" "		clr.w	simJit`n		clr.w	simDodgeT`n		clr.w	simJX`n"
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
