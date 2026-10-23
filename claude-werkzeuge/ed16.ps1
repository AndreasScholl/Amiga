$d="D:\Thrust & Quadlite\Amiga Projekt\Demo2023"
function RepF($f,$a,$b){ $t=[IO.File]::ReadAllText($f).Replace("`r`n","`n"); if(-not $t.Contains($a)){ throw "missing in $f : $a" }; $t=$t.Replace($a,$b); [IO.File]::WriteAllText($f,$t.Replace("`n","`r`n")) }
$f="$d\scroller.s"
RepF $f "logoStartWait:`n" "logoStartWait::`n"
RepF $f "logoEndWait:`n" "logoEndWait::`n"
RepF $f "		move.w	d0,emberbplh`n" "		move.w	d0,emberbplh`n	ifne	elite3`n		tst.b	s3Cop				; (the Elite ending: its own copper list,`n		beq.s	.ne					; stars3d.i)`n		jsr		s3Flip`n.ne:`n	endc`n"
$cl=@"
;--------------------------------------------------------------
; the Elite ending's copper list (stars3d.i puts the copper over to it):
; the stars in planes 1..3 (colours 1..7: dim, middle, bright, and the
; engines' glow), the game's lines in plane 4 in front of them (8..15)
; from the top of the window to the bottom - one buffer each, no tricks.
; the logo is clist's own part: a jump there, and back here once it is
; through (stars3d.i s3Activate patches clist right after logoEndWait).
; the pointers: s3Flip (each frame), s3MidPatch (below the logo)
ELC1			= `$0125		; dim (warp.i warpCol1)
ELC2			= `$0371		; middle (warpCol2)
ELC3			= `$0a20		; the glow's rim
ELC4			= `$0842		; bright (warpCol3)
ELC5			= `$0f60		; the glow
ELC6			= `$0fb3
ELC7			= `$0ffe		; ... its core
ELCOLS	macro
		dc.w	`$0182,ELC1,`$0184,ELC2,`$0186,ELC3,`$0188,ELC4
		dc.w	`$018a,ELC5,`$018c,ELC6,`$018e,ELC7
		endm
		cnop	0,4
clistElite::
		dc.w	BPLCON0,`$0200
		dc.w	`$0102,`$0000,`$0104,`$0000,`$0108,`$0000,`$010a,`$0000
		dc.w	DDFSTRT,`$0028
		dc.w	DDFSTOP,`$00d8
		dc.w	DIWSTRT,(fullTop<<8)+`$81
		dc.w	DIWSTOP,((screenBottom&`$ff)<<8)+`$c1
elSpr::	dc.w	`$120,0,`$122,0,`$124,0,`$126,0
		dc.w	`$128,0,`$12a,0,`$12c,0,`$12e,0
		dc.w	`$130,0,`$132,0,`$134,0,`$136,0
		dc.w	`$138,0,`$13a,0,`$13c,0,`$13e,0
		dc.w	`$0180,`$0000
		ELCOLS
		dc.w	`$0190,gameColor,`$0192,gameColor,`$0194,gameColor,`$0196,gameColor
		dc.w	`$0198,gameColor,`$019a,gameColor,`$019c,gameColor,`$019e,gameColor
		dc.w	((fullTop-1)<<8)+`$01,`$fffe
elTop::	dc.w	`$00e0,0,`$00e2,0,`$00e4,0,`$00e6,0
		dc.w	`$00e8,0,`$00ea,0,`$00ec,0,`$00ee,0
		dc.w	BPLCON0,`$4200
		dc.w	`$0084
elJmpH::
		dc.w	0
		dc.w	`$0086
elJmpL::
		dc.w	0
		dc.w	`$008a,`$0000		; into clist for the logo
eliteMid::							; ... and back: the star planes again
		dc.w	`$00e0,0,`$00e2,0,`$00e4,0,`$00e6,0,`$00e8,0,`$00ea,0
		dc.w	BPLCON0,`$4200
		dc.w	`$0108,`$0000
		ELCOLS
		dc.w	`$ffdf,`$fffe
		dc.w	((screenBottom&`$ff)<<8)+`$01,`$fffe
		dc.w	BPLCON0,`$0200
		dc.w	`$ffff,`$fffe

clist:
"@
RepF $f "clist:`n		dc.w	BPLCON0,`$0200		; bitplanes off`n" ($cl.Replace("`r`n","`n")+"		dc.w	BPLCON0,`$0200		; bitplanes off`n")
