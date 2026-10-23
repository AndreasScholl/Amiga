$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
Rep @"
		move.w	#128,simThrT
		; across and up/down: hovering, a correction now and then
		bsr		simJitter
		move.w	simX0,d0
		add.w	simJX,d0
		ext.l	d0
		asl.l	#8,d0
		lea		simX,a1
		bsr		simSpringP
		move.w	simY0,d0
		add.w	simJY,d0
"@ @"
		move.w	#128,simThrT
		; as we come near: its dodge - a quick roll and a jink to the side
		moveq	#0,d5
		cmp.l	#(morphDodgeZ*16)<<8,simZ
		bgt.s	.nd
		move.w	simDodgeT,d0
		cmp.w	#morphDodgeT,d0
		bhs.s	.nd1
		addq.w	#1,simDodgeT
		move.w	#256,simThrT		; (it howls)
.nd1:	move.w	simDodgeT,d0
		move.w	#morphDodgeT,d1
		bsr		morphUnit
		move.w	d1,d5
.nd:	move.w	d5,simA0
		; across and up/down: hovering, a correction now and then
		bsr		simJitter
		move.w	#morphDodgeX*16,d0
		muls	simA0,d0
		asr.l	#8,d0
		add.w	simX0,d0
		add.w	simJX,d0
		ext.l	d0
		asl.l	#8,d0
		lea		simX,a1
		bsr		simSpringP
		move.w	#morphDodgeY*16,d0
		muls	simA0,d0
		asr.l	#8,d0
		add.w	simY0,d0
		add.w	simJY,d0
"@
Rep @"
		muls	#10*16,d0
		add.l	d0,d0
		swap	d0
		sub.w	simRoll,d0
		asr.w	#3,d0
		add.w	d0,simRoll
		rts
"@ @"
		muls	#10*16,d0
		add.l	d0,d0
		swap	d0
		sub.w	simBank,d0
		asr.w	#3,d0
		add.w	d0,simBank
		move.w	#360*16,d0			; (the dodge's roll, left)
		mulu	simA0,d0
		lsr.l	#8,d0
		add.w	simBank,d0
		move.w	d0,simRoll
		rts
"@
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
