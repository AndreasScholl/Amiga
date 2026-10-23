$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\morph.i"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
$i0=$m.IndexOf("; the glow of the engines: sprite 4"); $i0=$m.LastIndexOf(";-------",$i0); $i1=$m.IndexOf("; once, at the start (warp.i warpInit)"); $i1=$m.LastIndexOf(";-------",$i1)
if($i0 -lt 0 -or $i1 -le $i0){throw "idx"}
$m=$m.Substring(0,$i0)+$m.Substring($i1)
if(-not $m.Contains("morphInit:`n		bsr		morphGlowMake`n")){throw "init"}
$m=$m.Replace("morphInit:`n		bsr		morphGlowMake`n","morphInit:`n")
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\scroller.s"; $t=[IO.File]::ReadAllText($f); $a="checkScrollGone:`r`n		lea		src_adr+dissolveByte,a0`r`n"; if(-not $t.Contains($a)){throw "csg"}; $t=$t.Replace($a,"checkScrollGone:`r`n		tst.b	scrollGone			; (gone is gone: no new text comes)`r`n		bne.s	.out`r`n		lea		src_adr+dissolveByte,a0`r`n"); $t=$t.Replace("		tst.l	d0`r`n		seq		scrollGone`r`n		rts`r`n","		tst.l	d0`r`n		seq		scrollGone`r`n.out:	rts`r`n"); [IO.File]::WriteAllText($f,$t); "ok2"
