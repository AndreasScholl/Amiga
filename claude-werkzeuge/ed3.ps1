$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\scroller.s"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
Rep "src_adr			= `$6e000		; scroll buffer source adress`n" "; src_adr: the scroll buffer's source, in chip memory the system gives us`n; (section `"screens`" at the end; it was the fixed address `$6e000, never`n; reserved - the loaded program could lie there and get drawn over)`n"
Rep "bufA			= `$70000`nbufB			= `$78000`n" "; bufA/bufB: section `"screens`" at the end (were the fixed `$70000/`$78000)`n"
Rep "ss		 		= `$6e014		; source start of scoller turn`n" "ss		 		= src_adr+`$14	; source start of scoller turn`n"
# clearScroller: hi words too
Rep @"
		move.w	#scrollA&`$ffff,bp0+2		; show A ...
		move.w	#(scrollA+screenHeight*li)&`$ffff,emberbpl
		move.w	#bufA&`$ffff,gamebpl4
		move.l	#scrollB,screenlocScroller	; ... draw B
		move.l	#bufB,screenloc				; asteroids draw on the whole screen
		bra.s	.s1
.s0:
		move.w	#scrollB&`$ffff,bp0+2
		move.w	#(scrollB+screenHeight*li)&`$ffff,emberbpl
		move.w	#bufB&`$ffff,gamebpl4
		move.l	#scrollA,screenlocScroller
		move.l	#bufA,screenloc
.s1:
"@.Replace("`r`n","`n") @"
		move.l	#bufA,d0					; show A ...
		move.l	#scrollB,screenlocScroller	; ... draw B
		move.l	#bufB,screenloc				; asteroids draw on the whole screen
		bra.s	.s1
.s0:
		move.l	#bufB,d0
		move.l	#scrollA,screenlocScroller
		move.l	#bufA,screenloc
.s1:	; the shown buffer into the copper (high words too: the buffers are
		; where the system put them)
		move.w	d0,gamebpl4
		swap	d0
		move.w	d0,gamebpl4h
		swap	d0
		add.l	#topLines*li,d0				; the scroller part
		move.w	d0,bp0+2
		swap	d0
		move.w	d0,gamebp0h
		swap	d0
		add.l	#screenHeight*li,d0			; the ember plane
		move.w	d0,emberbpl
		swap	d0
		move.w	d0,emberbplh
"@.Replace("`r`n","`n")
Rep "		lea		`$6e000-li,a0		; one more line for empty line -> sprite display`n" "		lea		src_adr-li,a0		; one more line for empty line -> sprite display`n"
Rep @"
			move.w	#`$0006,logobp0h			; ... aimed at the empty line
			move.w	#`$e000-li,logobp0l
"@.Replace("`r`n","`n") @"
			move.l	#src_adr-li,d0			; ... aimed at the empty line
			move.w	d0,logobp0l
			swap	d0
			move.w	d0,logobp0h
"@.Replace("`r`n","`n")
Rep @"
			move.w	#`$0006,gamebp0h
			move.w	#`$e000-li,bp0+2
"@.Replace("`r`n","`n") @"
			move.l	#src_adr-li,d0
			move.w	d0,bp0+2
			swap	d0
			move.w	d0,gamebp0h
"@.Replace("`r`n","`n")
Rep "			move.w	#`$0007,gamebp0h`n			move.w	#`$0000,gamePlaneMod`n" "			move.w	#`$0000,gamePlaneMod	; (gamebp0h: clearScroller, each frame)`n"
# copper list words
Rep @"
		dc.w	`$00ec,bufA>>16
		dc.w	`$00ee
gamebpl4:
		dc.w	bufA&`$ffff
		dc.w	`$0182,`$0000	   ; black plane
		dc.w	`$00e0,`$0006
		dc.w	`$00e2,`$e000-li
		dc.w	`$00e8,`$0006
		dc.w	`$00ea,`$e000-li
"@.Replace("`r`n","`n") @"
		dc.w	`$00ec
gamebpl4h:
		dc.w	0				; (clearScroller)
		dc.w	`$00ee
gamebpl4:
		dc.w	0
		dc.w	`$0182,`$0000	   ; black plane
		dc.w	`$00e0
blankTop1h:
		dc.w	0				; (the blank line: patchScreens)
		dc.w	`$00e2
blankTop1l:
		dc.w	0
		dc.w	`$00e8
blankTop3h:
		dc.w	0
		dc.w	`$00ea
blankTop3l:
		dc.w	0
"@.Replace("`r`n","`n")
Rep @"
		dc.w	`$00e0,`$0006
		dc.w	`$00e2,`$e000-li
		dc.w	`$00e8,`$0006
		dc.w	`$00ea,`$e000-li
		dc.w	`$00e4
midZero2h:
"@.Replace("`r`n","`n") @"
		dc.w	`$00e0
blankMid1h:
		dc.w	0
		dc.w	`$00e2
blankMid1l:
		dc.w	0
		dc.w	`$00e8
blankMid3h:
		dc.w	0
		dc.w	`$00ea
blankMid3l:
		dc.w	0
		dc.w	`$00e4
midZero2h:
"@.Replace("`r`n","`n")
Rep "gamebp0h:`n		dc.w	`$0007			; bitplane 0, patched to the blank line while`n" "gamebp0h:`n		dc.w	0				; bitplane 0, patched to the blank line while`n"
Rep "		dc.w	`$00e8,`$0007`n		dc.w	`$00ea`nemberbpl:`n		dc.w	screenHeight*li`n" "		dc.w	`$00e8`nemberbplh:`n		dc.w	0`n		dc.w	`$00ea`nemberbpl:`n		dc.w	0`n"
Rep "		dc.w	`$00e4,(scrollA+(li*(51+gameShift))-2)>>16	; bitplane 01`n" "		dc.w	`$00e4`nshadowH:`n		dc.w	0				; bitplane 01 (patchScreens)`n"
Rep "		dc.w	`$00e6,(scrollA+(li*(51+gameShift))-2)&`$ffff	; + lines offset to adjust shadow pos`n" "		dc.w	`$00e6`nshadowL:`n		dc.w	0				; + lines offset to adjust shadow pos`n"
Rep "		dc.w	`$00e4,(scrollA+(li*(51+gameShift))-2)>>16`n		dc.w	`$00e6,(scrollA+(li*(51+gameShift))-2)&`$ffff`n" "		dc.w	`$00e4`ntvShadowH:`n		dc.w	0`n		dc.w	`$00e6`ntvShadowL:`n		dc.w	0`n"
# init: patch
Rep "		bsr		buildLogoPadded`n		move.l	#zeroArea,d0		; plane 2 above and below the logo`n" "		bsr		patchScreens		; the screens' addresses into the copper`n		bsr		buildLogoPadded`n		move.l	#zeroArea,d0		; plane 2 above and below the logo`n"
Rep "`n;-------`n; --- intro build up -------" @"

; the screens are where the system put them (section "screens"): their
; addresses into the copper lists, once
patchScreens:
		move.l	#src_adr-li,d0		; the blank line above and below the logo
		move.w	d0,blankTop1l
		move.w	d0,blankTop3l
		move.w	d0,blankMid1l
		move.w	d0,blankMid3l
		swap	d0
		move.w	d0,blankTop1h
		move.w	d0,blankTop3h
		move.w	d0,blankMid1h
		move.w	d0,blankMid3h
		move.l	#scrollA+(li*(51+gameShift))-2,d0	; the bar's shadow plane
		move.w	d0,shadowL
		move.w	d0,tvShadowL
		swap	d0
		move.w	d0,shadowH
		move.w	d0,tvShadowH
		rts
;-------
; --- intro build up -------
"@.Replace("`r`n","`n")
Rep "`t`tsection `"scrollerchip`",bss_c`n" "`t`tsection `"scrollerchip`",bss_c`n"
$m=$m.TrimEnd() + "`n`n;--------------------------------------------------------------`n; the screens: the scroll text's source (with a blank line in front of it,`n; which the empty planes repeat) and the two game buffers, one after the`n; other as they were at `$6e000-li, `$6e000, `$70000, `$78000 - now in chip`n; memory the system has given us, so the program itself never lies there`n		section `"screens`",bss_c`n		ds.b	li					; the blank line`nsrc_adr::		ds.b	`$2000`nbufA::			ds.b	`$8000`nbufB::			ds.b	`$8000`n"
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
