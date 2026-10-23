
; --- which music. one switch, everything else follows from it: only the
;     chosen tune's files go into the build (the other bank costs no chip
;     memory at all), and the effects pick their channels to suit it.
;     back to the old music: MUSIC = MUSIC_RINK, build, done.
MUSIC_RINK      = 0             ; rink-a-dink (209.7 KB chip bank)
MUSIC_CCABANA   = 1             ; CopperCabana by Mark II, from our own demo
                                ; (16.9 KB chip bank; see Own Demos/CopperCabana-Musik)
        IFND    MUSIC           ; (or from outside: vasm -DMUSIC=0)
MUSIC           = MUSIC_CCABANA
        ENDC

        INCLUDE "switches.i"            ; (the ending's switches: drumSeq)
        IFEQ    MUSIC-MUSIC_CCABANA
musDrums        = drumSeq               ; (the drums at the end are CopperCabana's:
        ELSE                            ; drumseq.i)
musDrums        = 0
        ENDC
        IFNE    musChase
        IFEQ    musDrums
        FAIL    "musChase needs drumSeq and CopperCabana"
        ENDC
        ENDC

        section "code",data,chip

initMusic::
        move.w  #musicPalTicks,musicPalCountdown
        clr.w   logoPalTarget
        clr.l   musicPalStream

        ; Init LSP and start replay using easy CIA toolbox
        lea		LSPMusic,a0
        lea		LSPBank,a1
        suba.l	a2,a2			; suppose VBR=0 ( A500 )
        moveq	#0,d0			; suppose PAL machine
        bsr		LSP_MusicDriver_CIA_Start

        move.w	#$e000,$dff09a
        bsr     sfxInit
        bra     sfxGen

        ; Include simple CIA toolkit
        include	"LSP\LightSpeedPlayer_cia.asm"

        ; Include generic LSP player
        include	"LSP\LightSpeedPlayer.asm"

; --- logo palette cues. counts music ticks (CIA timed, so it follows the
;     tempo) and bumps logoPalTarget every musicPalTicks, which makes the
;     logo cross fade to its next palette (logoColorEngine, scroller.s).
;     when the song loops the count restarts, so the cues keep landing on
;     the same spots in the music. called from the CIA irq right after
;     LSP_MusicPlayTick, all registers are free.
musicPalTicks = $300            ; 768 ticks between cues

        IFNE    musDrums
; --- (switches.i drumSeq) the end of the music. from the fighter's break on
;     (morph.i sets musFadeGo, and musHitIn: ticks to the first hit) the
;     music's voices 0-2 fade out over musFadeT ticks while its drums (3)
;     play on. at the next bar after that LSP stops and the drums go on by
;     themselves (dsTick: the song's own, bar by bar - drumseq.i, the same
;     samples, periods and volumes), on channels 0 and 2 now, so 1 and 3
;     stay free for the effects; quiet for the beat before the first hit,
;     in again with it. LSP's volumes come here through lspVol (patched in
;     LightSpeedPlayer.asm) and go out faded (musVolOut). once LSP is
;     stopped its DMACON byte (m_dmaconPatch: CIA timer B writes it out a
;     little later) is cleared here every tick, as LSP did, and set for the
;     drums' new notes
musFadeT        = 275                   ; ticks (5.5 s)
musSongT        = 128*96                ; the song's ticks (it starts over: drumseq.i)
MS_PLAY         = 0                     ; musState: the music as it is
MS_FADE         = 1                     ; ... its voices 0-2 fade
MS_BAR          = 2                     ; ... gone: the next bar
MS_DRUMS        = 3                     ; ... LSP stopped, the drums alone
MS_QUIET        = 4                     ; ... (musChase) the drums faded too: silence
musDrumT        = 150                   ; (musChase) ticks the drums fade (3 s)

        section "musdrums",data         ; (no chip memory: the CPU's alone. data,
                                        ; not code: vlink puts code hunks first,
                                        ; and the first hunk is where the program
                                        ; starts - main.s init)
; the CIA irq's tick (LightSpeedPlayer_cia.asm), all registers free
musicTick:
        IFNE    musChase
        cmp.b   #MS_QUIET,musState      ; (musChase) all gone: silence
        bne.s   .nq
        move.l  LSP_State+m_dmaconPatch,a0
        clr.b   (a0)
        jsr     musicPalTick
        jmp     sfxTick
.nq:    tst.b   musDrumOut              ; the fighter gone: the drums fade
        beq.s   .nd
        bsr     musDrumFade
.nd:
        ENDC
        cmp.b   #MS_BAR,musState        ; faded out: LSP stops at the next bar
        bne.s   .lsp                    ; (before it plays it)
        move.w  musTick,d0
        subq.w  #1,d0
        ext.l   d0
        divu    #96,d0
        swap    d0
        tst.w   d0
        bne.s   .lsp
        bsr     musStop
.lsp:   cmp.b   #MS_DRUMS,musState
        beq.s   .ds
        lea     $dff0a0,a6
        jsr     LSP_MusicPlayTick
        bsr     musVolOut
        bra.s   .t
.ds:    bsr     dsTick
.t:     move.w  musTick,d0              ; the song's tick on
        addq.w  #1,d0
        cmp.w   #musSongT,d0
        blo.s   .t0
        moveq   #0,d0
.t0:    move.w  d0,musTick
        tst.w   musHitIn
        beq.s   .h0
        subq.w  #1,musHitIn
.h0:    tst.b   musState                ; the break: the fade begins
        bne.s   .f0
        tst.b   musFadeGo
        beq.s   .fx
        move.b  #MS_FADE,musState
        move.w  #musFadeT,musFadeN
.f0:    cmp.b   #MS_FADE,musState
        bne.s   .fx
        subq.w  #1,musFadeN
        bhi.s   .f1
        clr.w   musFade
        move.b  #MS_BAR,musState
        bra.s   .fx
.f1:    move.w  musFadeN,d0
        mulu    #256,d0
        divu    #musFadeT,d0
        move.w  d0,musFade
.fx:    jsr     musicPalTick
        jmp     sfxTick

; LSP's volumes (lspVol) into the channels the music has (sfxKeep): 0-2
; faded, the drums (3) as they are
musVolOut:
        lea     $dff0a0,a0
        lea     lspVol,a1
        move.b  sfxKeep,d2
        move.w  musFade,d3
        moveq   #0,d7
.c:     btst    d7,d2
        beq.s   .n
        moveq   #0,d0
        move.b  (a1),d0
        cmp.w   #3,d7
        beq.s   .w
        mulu    d3,d0
        lsr.w   #8,d0
        IFNE    musChase
        bra.s   .w0
.w:     mulu    musDrumV,d0             ; (musChase: the drums' own fade)
        lsr.w   #8,d0
.w0:    move.w  d0,8(a0)
        ELSE
.w:     move.w  d0,8(a0)
        ENDC
.n:     addq.l  #1,a1
        lea     16(a0),a0
        addq.w  #1,d7
        cmp.w   #4,d7
        blo.s   .c
        rts

; LSP stops: its channels (those the effects have not) quiet, its DMACON
; byte cleared (from now on dsTick's)
musStop:
        move.b  #MS_DRUMS,musState
        lea     $dff0a0,a0
        move.b  sfxKeep,d2
        moveq   #0,d7
.c:     btst    d7,d2
        beq.s   .n
        clr.w   8(a0)
        moveq   #0,d1
        bset    d7,d1
        move.w  d1,$dff096
.n:     lea     16(a0),a0
        addq.w  #1,d7
        cmp.w   #4,d7
        blo.s   .c
        move.l  LSP_State+m_dmaconPatch,a0
        clr.b   (a0)
        rts

; the drums alone, a tick (musTick: the song's tick now)
dsTick:
        move.l  LSP_State+m_dmaconPatch,a2
        clr.b   (a2)
        lea     $dff0a0,a0
        move.b  dsStarted,d0            ; last tick's notes: once (their loop
        beq.s   .l9                     ; silent)
        clr.b   dsStarted
        btst    #0,d0
        beq.s   .l2
        move.l  #sfxSilence,(a0)
        move.w  #1,4(a0)
.l2:    btst    #2,d0
        beq.s   .l9
        move.l  #sfxSilence,$20(a0)
        move.w  #1,$24(a0)
.l9:    move.w  musTick,d0              ; a step now? (every 6 ticks from the
        subq.w  #1,d0                   ; bar's tick 1 on)
        bmi.s   .out
        ext.l   d0
        divu    #96,d0                  ; the bar
        move.l  d0,d1
        clr.w   d1
        swap    d1
        divu    #6,d1
        swap    d1
        tst.w   d1
        bne.s   .out
        swap    d1                      ; the step (0..15)
        tst.b   dsPause                 ; the beat before the first hit: quiet
        bmi.s   .play                   ; (-1: that is over)
        bne.s   .wait
        move.w  musHitIn,d2
        beq.s   .play
        cmp.w   #24+3,d2
        bhi.s   .play
        moveq   #3,d2
        and.w   d1,d2
        bne.s   .play
        move.b  #1,dsPause
        bra.s   .out
.wait:  cmp.w   #6,musHitIn             ; in again with the hit's bar
        bhi.s   .out
        tst.w   d1
        bne.s   .out
        st      dsPause
.play:  lea     dsBar,a1                ; the bar's pattern, the step's note
        moveq   #0,d2
        move.b  (a1,d0.w),d2
        lsl.w   #4,d2
        lea     dsPat,a1
        add.w   d2,a1
        moveq   #0,d2
        move.b  (a1,d1.w),d2
        beq.s   .out
        subq.w  #1,d2
        mulu    #10,d2
        lea     dsIns,a1
        add.w   d2,a1
        move.w  8(a1),d3                ; its channel: off, the sample, on with
        move.w  d3,$dff096              ; timer B (as LSP does)
        cmp.w   #1,d3
        beq.s   .c0
        lea     $20(a0),a0
.c0:    move.l  #LSPBank,d4
        moveq   #0,d5
        move.w  (a1)+,d5
        add.l   d5,d4
        move.l  d4,(a0)
        move.w  (a1)+,4(a0)
        move.w  (a1)+,6(a0)
        IFNE    musChase
        move.w  (a1)+,d5                ; (musChase: its volume as the fade
        cmp.w   #1,d3                   ; has it - and kept for the fade)
        bne.s   .v2
        move.w  d5,dsVol0
        bra.s   .v3
.v2:    move.w  d5,dsVol2
.v3:    mulu    musDrumV,d5
        lsr.w   #8,d5
        move.w  d5,8(a0)
        ELSE
        move.w  (a1)+,8(a0)
        ENDC
        or.b    d3,(a2)
        or.b    d3,dsStarted
.out:   rts

        IFNE    musChase
; (musChase) a tick of the drums' fade: their volume down (musDrumV), the
; notes sounding with it; through: they stop - silence (MS_QUIET)
musDrumFade:
        subq.w  #1,musDrumN
        bhi.s   .f1
        clr.w   musDrumN
        clr.w   musDrumV
        move.b  #MS_QUIET,musState      ; the music's channels quiet, off
        lea     $dff0a0,a0
        move.b  sfxKeep,d2
        moveq   #0,d7
.c:     btst    d7,d2
        beq.s   .n
        clr.w   8(a0)
        moveq   #0,d1
        bset    d7,d1
        move.w  d1,$dff096
.n:     lea     16(a0),a0
        addq.w  #1,d7
        cmp.w   #4,d7
        blo.s   .c
        rts
.f1:    moveq   #0,d0
        move.w  musDrumN,d0
        lsl.l   #8,d0
        divu    #musDrumT,d0
        move.w  d0,musDrumV
        cmp.b   #MS_DRUMS,musState      ; the drums' notes sounding (0, 2)
        bne.s   .out
        move.b  sfxKeep,d2
        btst    #0,d2
        beq.s   .f2
        move.w  dsVol0,d1
        mulu    d0,d1
        lsr.w   #8,d1
        move.w  d1,$dff0a8
.f2:    btst    #2,d2
        beq.s   .out
        move.w  dsVol2,d1
        mulu    d0,d1
        lsr.w   #8,d1
        move.w  d1,$dff0c8
.out:   rts
musDrumN:       dc.w    musDrumT        ; ticks of the fade left
musDrumV:       dc.w    256             ; the drums' volume (* 256)
dsVol0:         dc.w    0               ; the last notes' volumes (0, 2)
dsVol2:         dc.w    0
        ENDC
musTick:        dc.w    0               ; the song's tick (0 .. musSongT-1)
musFadeN:       dc.w    0               ; the fade: ticks left
musFade:        dc.w    256             ; ... the voices' volume (* 256)
lspVol:         dc.b    0,0,0,0         ; LSP's volumes, a channel each
musState::      dc.b    MS_PLAY
dsStarted:      dc.b    0               ; channels with a new note (DMACON bits)
dsPause:        dc.b    0               ; 1: quiet before the hit, -1: over
                even
        ENDC
        IFNE    drumSeq
        IFEQ    musDrums
        section "musdrums",data
        ENDC
musFadeGo::     dc.b    0               ; (morph.i) the break: the music ends
musDrumOut::    dc.b    0               ; (morph.i, musChase) the drums fade too
                even
musHitIn::      dc.w    0               ; (morph.i) ticks to the first hit
        section "code",data,chip
        ENDC

musicPalTick:
        subq.w  #1,musicPalCountdown
        bne.s   .noCue
        move.w  #musicPalTicks,musicPalCountdown
        addq.w  #1,logoPalTarget
.noCue:
        ; the byte stream only ever moves forward, except when LSP
        ; rewinds to the loop point
        move.l  LSP_State+m_byteStream,d0
        move.l  musicPalStream,d1
        move.l  d0,musicPalStream
        cmp.l   d1,d0
        bhs.s   .noLoop
        move.w  #musicPalTicks-1,musicPalCountdown
.noLoop:
        rts

; --- sound effects: Defender's own, from the video (videos\Defender.mp4):
;     the laser (also, higher and shorter, the cannon's shots), the boom of
;     an explosion and the thrust (off for now: asteroids.s seq_thrustSnd),
;     a zap of our own for the TV going off and a big boom with weight under
;     it for the Defender ending. delta packed, 4 bits a sample (sfx.i,
;     sfxpack.py), unpacked once into chip memory by sfxInit.
;     sfxPlay (from the game, the VBL) asks for one; it goes out on channel
;     sfxCh - or, once the TV is off and it is Defender (sfxWide), on the
;     channels sfxChW says: the laser stays on 3, the booms and the zap go
;     out on two channels at once (the music's two quietest voices, left and
;     right: in the middle, and twice as loud). the music leaves a channel
;     alone while an effect is on it: sfxKeep masks it out of LSP's note
;     restarts, and every tick the effect's period and volume go back in
;     over whatever the music has just written there. the sample plays once
;     (the next sample pointer is a silent word) - only the thrust loops,
;     quietly, while sfxThrust says the ship burns and nothing else plays
;     on 3. a new one cuts in when it matters as much or more, or when the
;     one playing is past its first sfxGuard ticks - the same one again
;     only after its own sfx_again ticks (the booms of a word, one every
;     few frames, roll on instead of cutting each other short). afterwards
;     the channel is the music's again from its next note on it. sfxTick is
;     called from the CIA irq right after LSP_MusicPlayTick, all registers
;     are free
sfxCh           = 3
sfxGuard        = 4
SFX_SHOT        = 1
SFX_BOOM        = 2
SFX_LASER       = 3
SFX_THRUST      = 4
SFX_ZAP         = 5                 ; the TV goes off (scroller.s tvStart)
SFX_BIGBOOM     = 6                 ; SFX_BOOM once it is Defender (sfxWide)
SFX_DROP        = 7                 ; (morph.i) a torpedo drops out of the ship
SFX_IGNITE      = 8                 ; (morph.i) ... and its engine fires
SFX_SHIPIGN     = 9                 ; (morph.i) the fighter's engine fires

; one effect: sample, length (words), period, volume, ticks (0: loops),
; priority, ticks before the same one may start again over itself
                rsreset
sfx_ptr:        rs.l    1
sfx_len:        rs.w    1
sfx_per:        rs.w    1
sfx_vol:        rs.w    1
sfx_ticks:      rs.w    1
sfx_prio:       rs.w    1
sfx_again:      rs.w    1
sfx_size:       rs.b    0           ; 16

sfxTable:
                dc.l    sfxLaserBuf                         ; SFX_SHOT: the laser,
                dc.w    sfxLaserS_len/2,300,56,7,1,0        ; higher and short
                dc.l    sfxBoomBuf                          ; SFX_BOOM
                dc.w    sfxBoomS_len/2,443,64,15,2,0
                dc.l    sfxLaserBuf                         ; SFX_LASER
                dc.w    sfxLaserS_len/2,443,64,10,3,0
                dc.l    sfxThrustBuf                        ; SFX_THRUST, a loop
                dc.w    sfxThrustS_len/2,443,26,0,0,0
                dc.l    sfxZapBuf                           ; SFX_ZAP: above all
                dc.w    sfxZapS_len/2,443,64,58,4,0
                dc.l    sfxBigBoomBuf                       ; SFX_BIGBOOM
                dc.w    sfxBigBoomS_len/2,520,64,50,2,sfxBoomAgain      ; (period 520: lower, more bass)
                dc.l    sfxDropBuf                          ; SFX_DROP: a clunk
                dc.w    sfxDropLen/2,360,64,8,3,0
                dc.l    sfxIgnBuf                           ; SFX_IGNITE: a whoosh
                dc.w    sfxIgnLen/2,300,64,30,4,0
                dc.l    sfxIgnBuf                           ; SFX_SHIPIGN: the whoosh,
                dc.w    sfxIgnLen/2,430,64,42,4,0           ; lower, bigger
sfxBoomAgain    = 9                 ; a big boom rolls on this long at least

; the channels of each effect once it is Defender (bits 0..3). rink-a-dink:
; the booms on 0 and 1. CopperCabana: 0 is its main voice (on nearly all
; the time), so the booms go on 1 and 3, its quiet ones (hi-hat on 3) -
; still left and right, in the middle
        IFEQ    MUSIC-MUSIC_RINK
sfxChW:         dc.b    0,%1000,%0011,%1000,%1000,%0011,%0011,%0010,%1000,%0010
        ELSE
sfxChW:         dc.b    0,%1000,%1010,%1000,%1000,%1010,%1010,%0010,%1000,%0010
        ENDC
                even

; d0.b = the effect wanted (from the game). keeps every register
sfxPlay::
        movem.l d0-d2/a0,-(a7)
        and.w   #$ff,d0
        moveq   #1<<sfxCh,d1
        tst.b   sfxWide
        beq.s   .chans
        cmp.b   #SFX_BOOM,d0                ; Defender: the big one
        bne.s   .wide
        moveq   #SFX_BIGBOOM,d0
.wide:
        lea     sfxChW(pc),a0
        move.b  (a0,d0.w),d1
.chans:
        lea     sfxReq,a0
        moveq   #3,d2
.ch:
        btst    d2,d1
        beq.s   .next
        cmp.b   (a0,d2.w),d0                ; (one asked for already this
        bls.s   .next                       ; tick: the one that matters more)
        move.b  d0,(a0,d2.w)
.next:
        dbf     d2,.ch
        movem.l (a7)+,d0-d2/a0
        rts

sfxTick::
        lea     sfxReq,a4
        lea     sfxVoices,a3
        moveq   #0,d7
.ch:
        tst.b   (a4,d7.w)                   ; nothing asked for, nothing on:
        bne.s   .do                         ; next (most ticks, most channels)
        tst.b   v_on(a3)
        bne.s   .do
        cmp.w   #sfxCh,d7
        bne.s   .next
        tst.b   sfxThrust
        beq.s   .next
.do:
        bsr.s   sfxVoice
.next:
        addq.l  #v_size,a3
        addq.w  #1,d7
        cmp.w   #4,d7
        blo.s   .ch
        tst.l   sfxDroneOn                  ; (no drone, none running: done)
        bne.s   sfxDrones
        tst.l   sfxDroneRun
        bne.s   sfxDrones
        rts

; --- drones: sounds that go on and on, their pitch and volume set every
;     frame from outside (morph.i: the fighter's engine, the torpedoes'),
;     the Doppler in the pitch. one per channel, sfxDroneOn says which; an
;     effect on the same channel comes first, the drone starts again after
;     it. the music keeps off the channel meanwhile (sfxKeep), as for the
;     effects; the sample goes in again every tick (the music may have put
;     its own into the loop registers)
sfxDrones:
        lea     sfxVoices,a3
        moveq   #0,d7
.ch:
        move.w  d7,d0
        lsl.w   #4,d0
        lea     $dff0a0,a0
        add.w   d0,a0
        lea     sfxDroneRun,a1
        tst.b   v_on(a3)                    ; an effect here first
        beq.s   .free
        sf      (a1,d7.w)
        bra.s   .next
.free:
        IFNE    musChase
        cmp.b   #MS_QUIET,musState          ; (musChase: silence - no drone
        beq.s   .nw                         ; either, the engine far off)
        ENDC
        lea     sfxDroneOn,a2
        tst.b   (a2,d7.w)
        bne.s   .want
.nw:    tst.b   (a1,d7.w)
        beq.s   .next
        sf      (a1,d7.w)                   ; off: back to the music
        clr.w   8(a0)
        moveq   #0,d1
        bset    d7,d1
        move.w  d1,$dff096
        bset    d7,sfxKeep
        bra.s   .next
.want:
        move.w  d7,d0
        lsl.w   #3,d0
        lea     sfxDroneSmp,a2
        add.w   d0,a2
        cmp.w   #3,d7                       ; (3: the engine as well, near -
        bne.s   .w0                         ; morph.i sfxEng3)
        tst.b   sfxEng3
        beq.s   .w0
        lea     sfxDroneSmp+8,a2
.w0:
        tst.b   (a1,d7.w)
        bne.s   .run
        st      (a1,d7.w)                   ; on: a new start
        moveq   #0,d1
        bset    d7,d1
        move.w  d1,$dff096
        bclr    d7,sfxKeep
        move.l  (a2),(a0)
        move.w  4(a2),4(a0)
        move.l  LSP_State+m_dmaconPatch,a2
        bset    d7,(a2)
        bra.s   .regs
.run:
        move.l  (a2),(a0)
        move.w  4(a2),4(a0)
.regs:
        move.w  d7,d0
        add.w   d0,d0
        lea     sfxDronePer,a2
        move.w  (a2,d0.w),6(a0)
        lea     sfxDroneVol,a2
        IFNE    musChase
        move.w  (a2,d0.w),d1                ; (musChase: fading with the drums)
        mulu    musDrumV,d1
        lsr.l   #8,d1
        move.w  d1,8(a0)
        ELSE
        move.w  (a2,d0.w),8(a0)
        ENDC
.next:
        addq.l  #v_size,a3
        addq.w  #1,d7
        cmp.w   #4,d7
        blo     .ch
        rts

sfxDroneOn::    dc.b    0,0,0,0         ; wanted, a channel each (from outside)
sfxDroneRun:    dc.b    0,0,0,0         ; running
sfxDronePer::   dc.w    400,400,400,400 ; (from outside, every frame)
sfxDroneVol::   dc.w    0,0,0,0
sfxEng3::       dc.b    0               ; channel 3's drone: the engine, not the hiss
                even
; each channel's drone: the loop, its length in words (ch1: the fighter's
; engine - the music's quiet pad; ch3: a torpedo's hiss, briefly - the
; drums; the music's main voices 0 and 2 are never taken)
sfxDroneSmp:    dc.l    sfxHissBuf
                dc.w    sfxHissLen/2,0
                dc.l    sfxEngBuf
                dc.w    sfxEngLen/2,0
                dc.l    sfxHissBuf
                dc.w    sfxHissLen/2,0
                dc.l    sfxHissBuf
                dc.w    sfxHissLen/2,0

; --- the ending's sounds, made at the start (no samples on the disk):
;     noise from a shift register, a saw, envelopes. a5 the noise state
sfxEngLen       = 8192                  ; the engine: a long loop (0.8 s), a rumble,
                                        ; a hum and a throb - nothing repeats fast
sfxHissLen      = 256                   ; the torpedoes' engines: a loop, a hiss
sfxDropLen      = 1400                  ; a torpedo drops: a clunk
sfxIgnLen       = 5000                  ; its engine fires: a whoosh
sfxGen:
        move.l  #$1d872b41,d6           ; the noise
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
        move.l  #$1d872b41,d6
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
        move.w  d2,d1                   ; + a saw an octave below (32 a loop):
        lsl.w   #8,d1                   ; the body
        asr.w   #8,d1
        asr.w   #1,d1
        add.w   d1,d0
        move.w  d5,d1
        add.w   d1,d1
        add.w   d1,d0                   ; + the rumble
        move.w  d0,d1                   ; driven a little (x1.25, clipped):
        asr.w   #2,d1                   ; fat, not thin
        add.w   d1,d0
        movem.w d0/d2,-(a7)             ; the throb: 0.75 .. 1
        move.w  d2,d1
        mulu    #3*360,d1
        divu    #sfxEngLen,d1
        and.l   #$ffff,d1
        divu    #360,d1
        swap    d1                      ; degrees
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
        dbf     d7,.eng        ; the hiss: noise, a little low passed
        lea     sfxHissBuf,a0
        moveq   #0,d5
        move.w  #sfxHissLen-1,d7
.hiss:
        bsr     .noise
        sub.w   d5,d0
        asr.w   #1,d0
        add.w   d0,d5
        move.w  d5,d0
        bsr     .clip
        move.b  d0,(a0)+
        dbf     d7,.hiss
        ; the clunk: two sines that die away (a hollow thump), a click first
        lea     sfxDropBuf,a0
        moveq   #0,d4                   ; t
        move.w  #sfxDropLen-1,d7
.drop:
        move.w  d4,d0                   ; envelope: 127 down to 0
        mulu    #127,d0
        divu    #sfxDropLen,d0
        neg.w   d0
        add.w   #127,d0
        mulu    d0,d0
        lsr.w   #7,d0                   ; (squared: it dies fast)
        move.w  d0,d3
        move.w  d4,d0                   ; sin, 60 samples a round
        mulu    #6,d0                   ; (degrees: t * 360/60)
        divu    #360,d0
        swap    d0
        lsl.w   #2,d0
        lea     sctab,a1
        move.w  (a1,d0.w),d1
        asr.w   #1,d1
        move.w  d4,d0                   ; and 37 a round (a ring)
        mulu    #360,d0
        divu    #37,d0
        ext.l   d0
        divu    #360,d0
        swap    d0
        lsl.w   #2,d0
        move.w  (a1,d0.w),d0
        asr.w   #2,d0
        add.w   d0,d1
        muls    d3,d1
        asr.l   #8,d1
        asr.l   #7,d1
        move.w  d1,d0
        cmp.w   #60,d4                  ; the click
        bhs.s   .d0
        move.w  d0,d1
        bsr     .noise
        asr.w   #1,d0
        add.w   d1,d0
.d0:
        bsr     .clip
        move.b  d0,(a0)+
        addq.w  #1,d4
        dbf     d7,.drop
        ; the whoosh: noise, quick up, slowly away, darker as it goes (the
        ; low pass closes)
        lea     sfxIgnBuf,a0
        moveq   #0,d4
        moveq   #0,d5
        move.w  #sfxIgnLen-1,d7
.ign:
        move.w  d4,d3                   ; envelope: up over 300, then down
        cmp.w   #300,d3
        bhs.s   .i0
        mulu    #127,d3
        divu    #300,d3
        bra.s   .i1
.i0:    sub.w   #300,d3
        mulu    #127,d3
        divu    #sfxIgnLen-300,d3
        neg.w   d3
        add.w   #127,d3
.i1:    bsr     .noise
        sub.w   d5,d0
        move.w  d4,d1                   ; the low pass: 1/2 at first, 1/16 at
        lsr.w   #8,d1                   ; the end
        lsr.w   #2,d1
        addq.w  #1,d1
        cmp.w   #4,d1
        bls.s   .i2
        moveq   #4,d1
.i2:    asr.w   d1,d0
        add.w   d0,d5
        move.w  d5,d0
        muls    d3,d0
        asr.l   #6,d0                   ; (x2: the low pass makes it quiet)
        bsr     .clip
        move.b  d0,(a0)+
        addq.w  #1,d4
        dbf     d7,.ign
        rts
; -> d0 = noise -128..127 (d6: a 32 bit xorshift)
.noise:
        move.l  d6,d0
        lsl.l   #8,d0
        lsl.l   #5,d0
        eor.l   d0,d6
        move.l  d6,d0
        clr.w   d0
        swap    d0
        lsr.l   #1,d0
        eor.l   d0,d6
        move.l  d6,d0
        lsl.l   #5,d0
        eor.l   d0,d6
        move.l  d6,d0
        and.w   #$ff,d0
        sub.w   #128,d0
        rts
.clip:
        cmp.w   #127,d0
        ble.s   .c0
        moveq   #127,d0
.c0:    cmp.w   #-128,d0
        bge.s   .c1
        moveq   #-128,d0
.c1:    rts

; one channel, d7. a0 its registers, a3 its state
                rsreset
v_cur:          rs.l    1
v_t:            rs.w    1
v_on:           rs.b    1
v_pad:          rs.b    1
v_size:         rs.b    0           ; 8

; (a3 and a4 from sfxTick, kept)
sfxVoice:
        move.w  d7,d0
        lsl.w   #4,d0
        lea     $dff0a0,a0
        add.w   d0,a0
        moveq   #0,d0
        move.b  (a4,d7.w),d0
        beq.s   .noReq
        clr.b   (a4,d7.w)
        bsr.s   .entry                      ; -> a2
        tst.b   v_on(a3)
        beq.s   .start
        move.l  v_cur(a3),a1
        move.w  v_t(a3),d1
        cmp.l   a1,a2
        bne.s   .other
        cmp.w   sfx_again(a1),d1            ; the same one again: when its own
        blo.s   .noReq                      ; time has come
        bra.s   .start
.other:
        cmp.w   #sfxGuard,d1                ; well on its way: anything cuts in
        bhs.s   .start
        move.w  sfx_prio(a2),d1             ; else only what matters as much
        cmp.w   sfx_prio(a1),d1
        blo.s   .noReq
.start:
        move.l  a2,a1
        move.l  a1,v_cur(a3)
        moveq   #0,d1
        bset    d7,d1
        move.w  d1,$dff096                  ; off, a new start
        bclr    d7,sfxKeep                  ; the music keeps off it
        clr.w   v_t(a3)
        st      v_on(a3)
        move.l  LSP_State+m_dmaconPatch,a2  ; on again with LSP's own late
        bset    d7,(a2)                     ; DMACON write (CIA timer B)
        move.l  sfx_ptr(a1),(a0)            ; (first tick: the sample)
        move.w  sfx_len(a1),4(a0)
        bra.s   .regs
.noReq:
        tst.b   v_on(a3)
        bne.s   .run
        cmp.w   #sfxCh,d7                   ; nothing on: the thrust, if the
        bne.s   .out                        ; ship burns (on 3 only)
        tst.b   sfxThrust
        beq.s   .out
        moveq   #SFX_THRUST,d0
        bsr.s   .entry
        bra.s   .start
.run:
        move.l  v_cur(a3),a1
        tst.w   sfx_ticks(a1)
        bne.s   .once
        tst.b   sfxThrust                   ; the loop: on while it burns
        beq.s   .end
        move.l  sfx_ptr(a1),(a0)
        move.w  sfx_len(a1),4(a0)
        bra.s   .regs
.once:
        move.w  v_t(a3),d0
        cmp.w   sfx_ticks(a1),d0
        bhs.s   .end
        move.l  #sfxSilence,(a0)            ; after the sample: silence (the
        move.w  #1,4(a0)                    ; music may have put its own there)
.regs:
        move.w  sfx_per(a1),6(a0)
        move.w  sfx_vol(a1),8(a0)
        addq.w  #1,v_t(a3)
.out:
        rts
.end:
        sf      v_on(a3)
        clr.w   8(a0)
        moveq   #0,d1
        bset    d7,d1
        move.w  d1,$dff096                  ; the channel back to the music
        bset    d7,sfxKeep
        rts
; d0 = effect -> a2 its entry
.entry:
        move.w  d0,d1
        lsl.w   #4,d1
        lea     sfxTable-sfx_size,a2
        add.w   d1,a2
        rts

; unpack the effects into chip memory, once (initMusic)
sfxInit:
        lea     sfxLaserS_packed,a0
        lea     sfxLaserBuf,a1
        move.w  #sfxLaserS_len/2-1,d7
        bsr.s   sfxUnpack
        lea     sfxBoomS_packed,a0
        lea     sfxBoomBuf,a1
        move.w  #sfxBoomS_len/2-1,d7
        bsr.s   sfxUnpack
        lea     sfxThrustS_packed,a0
        lea     sfxThrustBuf,a1
        move.w  #sfxThrustS_len/2-1,d7
        bsr.s   sfxUnpack
        lea     sfxZapS_packed,a0
        lea     sfxZapBuf,a1
        move.w  #sfxZapS_len/2-1,d7
        bsr.s   sfxUnpack
        lea     sfxBigBoomS_packed,a0
        lea     sfxBigBoomBuf,a1
        move.w  #sfxBigBoomS_len/2-1,d7
; a0 packed (two samples a byte, high nibble first), a1 out, d7 bytes - 1
sfxUnpack:
        moveq   #0,d0                       ; the sample now
        lea     sfxDeltas(pc),a2
.byte:
        moveq   #0,d1
        move.b  (a0)+,d1
        move.w  d1,d2
        lsr.w   #4,d2
        bsr.s   .step
        moveq   #15,d2
        and.w   d1,d2
        bsr.s   .step
        dbf     d7,.byte
        rts
.step:
        add.w   d2,d2
        add.w   (a2,d2.w),d0
        cmp.w   #127,d0
        ble.s   .s0
        moveq   #127,d0
.s0:
        cmp.w   #-128,d0
        bge.s   .s1
        moveq   #-128,d0
.s1:
        move.b  d0,(a1)+
        rts
sfxDeltas:      dc.w    -96,-64,-42,-28,-18,-11,-6,-2,0,2,6,11,18,28,42,64

sfxVoices:      ds.b    4*v_size        ; each channel's effect now (sfxVoice)
sfxReq:         dc.b    0,0,0,0         ; asked for, for the next tick, a channel each
sfxWide::       dc.b    0               ; Defender: more channels (scroller.s tvStart)
sfxThrust::     dc.b    0               ; the ship burns (the thrust loop)
sfxKeep:        dc.b    $0f             ; LSP's channels (and.b, see there)
                even
sfxSilence:     dc.w    0,0
musicPalCountdown:: dc.w    musicPalTicks
logoPalTarget::     dc.w    0   ; bumped once per cue
musicPalStream:     dc.l    0   ; LSP byte stream pointer after the last tick

LSPBank:
        IFEQ    MUSIC-MUSIC_RINK
        incbin	"rink-a-dink.lsbank"
        ELSE
        incbin	"coppercabana.lsbank"
        ENDC
        even

        data
; (the packed effects only get read by the CPU, once - no need for chip memory)
        include "sfx.i"
        even
        IFNE    musDrums
        include "drumseq.i"             ; (drumSeq: the song's drums, CPU only)
        ENDC
LSPMusic:
        IFEQ    MUSIC-MUSIC_RINK
        incbin	"rink-a-dink.lsmusic"
        ELSE
        incbin	"coppercabana.lsmusic"
        ENDC
		even
; the effects, unpacked (sfxInit) - chip memory, Paula plays them
        section "sfxbuf",bss,chip
sfxLaserBuf:    ds.b    sfxLaserS_len
sfxBoomBuf:     ds.b    sfxBoomS_len
sfxThrustBuf:   ds.b    sfxThrustS_len
sfxZapBuf:      ds.b    sfxZapS_len
sfxBigBoomBuf:  ds.b    sfxBigBoomS_len
sfxEngBuf:      ds.b    sfxEngLen       ; (sfxGen) the ending's sounds
sfxHissBuf:     ds.b    sfxHissLen
sfxDropBuf:     ds.b    sfxDropLen
sfxIgnBuf:      ds.b    sfxIgnLen
