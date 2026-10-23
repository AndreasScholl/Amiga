$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
Rep "simSound:`n		clr.w	simSnd1V`n		clr.w	simSnd3V`n		tst.b	simEngine`n		beq		.torp`n" "simSound:`n		clr.w	simSnd3V`n		tst.b	simEngine`n		bne.s	.on`n		clr.w	simSnd1V`n		bra		.torp`n.on:`n"
Rep "		cmp.w	#SP_END,simPhase`n		beq		.torp`n		cmp.w	#SP_LOOP,simPhase`n" "		cmp.w	#SP_END,simPhase`n		bne.s	.on1`n		clr.w	simSnd1V`n		bra		.torp`n.on1:	cmp.w	#SP_LOOP,simPhase`n"
Rep ".s4:	move.w	d1,simSnd1V`n" ".s4:	bsr		.vsm`n"
Rep "		bsr		.pclip`n		move.w	d0,simSnd1P`n		bra.s	.torp`n" "		bsr		.pclip`n		sub.w	simSnd1P,d0			; (it glides: no steps)`n		asr.w	#2,d0`n		add.w	d0,simSnd1P`n		bra.s	.torp`n"
Rep ".l0:	add.w	#12,d1`n		move.w	d1,simSnd1V`n" ".l0:	add.w	#12,d1`n		bsr		.vsm`n"
Rep "; d0 = how fast it goes away (units a frame) -> d0 = 16 + that (4.4 times`n; the pitch's period), kept within reason`n.dopp:	cmp.l	#12,d0`n		ble.s	.d0`n		moveq	#12,d0`n.d0:	cmp.l	#-10,d0`n		bge.s	.d1`n		moveq	#-10,d0`n" "; d1 = the engine's volume wanted: it glides there`n.vsm:	sub.w	simSnd1V,d1`n		asr.w	#2,d1`n		add.w	d1,simSnd1V`n		rts`n; d0 = how fast it goes away (units a frame) -> d0 = 16 + that (4.4 times`n; the pitch's period), kept within reason`n.dopp:	cmp.l	#8,d0`n		ble.s	.d0`n		moveq	#8,d0`n.d0:	cmp.l	#-6,d0`n		bge.s	.d1`n		moveq	#-6,d0`n"
Rep "morphDodgeZ	= 220		; units" "morphDodgeZ	= 180		; units"
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
