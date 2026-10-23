$f="D:\Thrust & Quadlite\Amiga Projekt\Demo2023\music.s"; $m=[IO.File]::ReadAllText($f).Replace("`r`n","`n")
function Rep($a,$b){ if(-not $script:m.Contains($a)){ throw "missing: $a" }; $script:m=$script:m.Replace($a,$b) }
Rep "sfxEngLen       = 512                   ; the engine: a loop, a rumble and a hum`n" "sfxEngLen       = 8192                  ; the engine: a long loop (0.8 s), a rumble,`n                                        ; a hum and a throb - nothing repeats fast`n"
$i0=$m.IndexOf("        ; the engine: saw 128 and 64 (a hum) and low noise (a rumble)"); $i1=$m.IndexOf("        ; the hiss: noise, a little low passed")
$new=@"
        ; the engine. a rumble: noise, low passed hard - once round to warm
        ; the filter up, then again from the same noise, so the loop's end
        ; meets its start. two saws, 64 and 67 rounds a loop (a hum that
        ; beats slowly against itself), and a throb over it all (3 a loop)
        moveq   #0,d5
        move.w  #sfxEngLen-1,d7
.eng0:
        bsr     .noise
        sub.w   d5,d0
        asr.w   #4,d0
        add.w   d0,d5
        dbf     d7,.eng0
        move.l  #`$1d872b41,d6
        lea     sfxEngBuf,a0
        moveq   #0,d3                   ; the saws' phases
        moveq   #0,d4
        moveq   #0,d2                   ; t
        move.w  #sfxEngLen-1,d7
.eng:
        bsr     .noise
        sub.w   d5,d0
        asr.w   #4,d0
        add.w   d0,d5                   ; the rumble
        add.w   #64*65536/sfxEngLen,d3
        add.w   #67*65536/sfxEngLen,d4
        move.w  d3,d0
        asr.w   #8,d0
        asr.w   #1,d0                   ; -64..63
        move.w  d4,d1
        asr.w   #8,d1
        asr.w   #1,d1
        add.w   d1,d0
        asr.w   #1,d0                   ; the hum, -64..63
        move.w  d5,d1
        add.w   d1,d1
        add.w   d1,d0                   ; + the rumble
        movem.w d0/d2,-(a7)             ; the throb: 0.75 .. 1
        move.w  d2,d1
        mulu    #3*360,d1
        divu    #sfxEngLen,d1           ; degrees
        lsl.w   #2,d1
        lea     sctab,a1
        move.w  (a1,d1.w),d1
        asr.w   #2,d1
        add.w   #24576,d1
        movem.w (a7)+,d0/d2
        muls    d1,d0
        add.l   d0,d0
        swap    d0
        bsr     .clip
        move.b  d0,(a0)+
        addq.w  #1,d2
        dbf     d7,.eng
"@.Replace("`r`n","`n")
$m=$m.Substring(0,$i0)+$new+$m.Substring($i1)
$m=$m.Replace("`n","`r`n"); [IO.File]::WriteAllText($f,$m); "ok"
