$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
Rep @"
		move.w	d1,d6
		move.w	#256,d5
		sub.w	d0,d5
		mulu	d5,d5
		lsr.l	#8,d5
		neg.w	d5
		add.w	#256,d5				; e = 1 - (1-u)^2
		move.w	#morphEX0,d2
		move.w	#morphEX1,d3
		bsr		simLerp
		ext.l	d2
		asl.l	#8,d2
		move.l	d2,simX
		move.w	#morphEY0,d2
		move.w	#morphEY1,d3
		bsr		simLerp
		ext.l	d2
		asl.l	#8,d2
		move.l	d2,simY
		move.l	#(morphEZ1-morphEZ0)>>4,d2
		mulu	d5,d2
		lsl.l	#4,d2
		add.l	#morphEZ0<<8,d2
		move.l	d2,simZ
"@.Replace("`r`n","`n") @"
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
		add.w	#32768,d5			; e (32768 = 1: the bit pattern of -32768,
		move.w	#morphEX1-morphEX0,d2	; so used as unsigned below)
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
"@.Replace("`r`n","`n")
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
