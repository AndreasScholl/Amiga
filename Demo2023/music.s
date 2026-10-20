
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
        bra     sfxInit

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
;     and a zap of our own for the TV going off. delta packed, 4 bits a sample (sfx.i,
;     sfxpack.py), unpacked once into chip memory by sfxInit.
;     sfxPlay (from the game, the VBL) asks for one; it goes out on channel
;     sfxCh, which the music then leaves alone till it is over: sfxKeep
;     masks the channel out of LSP's note restarts, and every tick the
;     effect's period and volume go back in over whatever the music has
;     just written there. the sample plays once (the next sample pointer
;     is a silent word) - only the thrust loops, quietly, while sfxThrust
;     says the ship burns and nothing else plays. a new one cuts in when
;     it matters as much or more, or when the one playing is past its first
;     sfxGuard ticks. afterwards the channel is the music's again from its
;     next note on it. sfxTick is called from the CIA irq right after
;     LSP_MusicPlayTick, all registers are free
sfxCh           = 3
sfxAud          = $dff0a0+sfxCh*16
sfxGuard        = 4
SFX_SHOT        = 1
SFX_BOOM        = 2
SFX_LASER       = 3
SFX_THRUST      = 4
SFX_ZAP         = 5                 ; the TV goes off (scroller.s tvStart)

; one effect: sample, length (words), period, volume, ticks (0: loops),
; priority
                rsreset
sfx_ptr:        rs.l    1
sfx_len:        rs.w    1
sfx_per:        rs.w    1
sfx_vol:        rs.w    1
sfx_ticks:      rs.w    1
sfx_prio:       rs.w    1
sfx_size:       rs.b    0

sfxTable:
                dc.l    sfxLaserBuf                         ; SFX_SHOT: the laser,
                dc.w    sfxLaserS_len/2,300,40,7,1          ; higher and short
                dc.l    sfxBoomBuf                          ; SFX_BOOM
                dc.w    sfxBoomS_len/2,443,64,15,2
                dc.l    sfxLaserBuf                         ; SFX_LASER
                dc.w    sfxLaserS_len/2,443,64,10,3
                dc.l    sfxThrustBuf                        ; SFX_THRUST, a loop
                dc.w    sfxThrustS_len/2,443,26,0,0
                dc.l    sfxZapBuf                           ; SFX_ZAP: above all
                dc.w    sfxZapS_len/2,443,64,58,4

; d0.b = the effect wanted (from the game). keeps every register
sfxPlay::
        move.l  d1,-(a7)
        move.b  sfxReq,d1                   ; (one asked for already this
        cmp.b   d1,d0                       ; tick: the one that matters more)
        bls.s   .keep
        move.b  d0,sfxReq
.keep:
        move.l  (a7)+,d1
        rts

sfxTick::
        lea     sfxAud,a0
        moveq   #0,d0
        move.b  sfxReq,d0
        beq.s   .noReq
        sf      sfxReq
        tst.b   sfxOn
        beq.s   .start
        cmp.w   #sfxGuard,sfxT              ; well on its way: anything cuts in
        bhs.s   .start
        move.l  sfxCur,a1
        moveq   #0,d1                       ; else only what matters as much
        move.b  d0,d1
        mulu    #sfx_size,d1
        lea     sfxTable-sfx_size,a2
        move.w  sfx_prio(a2,d1.w),d1
        cmp.w   sfx_prio(a1),d1
        blo.s   .noReq
.start:
        mulu    #sfx_size,d0
        lea     sfxTable-sfx_size,a1
        add.w   d0,a1
        move.l  a1,sfxCur
        move.w  #1<<sfxCh,$dff096           ; off, a new start
        move.b  #$0f-(1<<sfxCh),sfxKeep     ; the music keeps off it
        clr.w   sfxT
        st      sfxOn
        move.l  LSP_State+m_dmaconPatch,a2  ; on again with LSP's own late
        bset    #sfxCh,(a2)                 ; DMACON write (CIA timer B)
        move.l  sfx_ptr(a1),(a0)            ; (first tick: the sample)
        move.w  sfx_len(a1),4(a0)
        bra.s   .regs
.noReq:
        tst.b   sfxOn
        bne.s   .run
        tst.b   sfxThrust                   ; nothing on: the thrust, if the
        beq.s   .out                        ; ship burns
        moveq   #SFX_THRUST,d0
        bra.s   .start
.run:
        move.l  sfxCur,a1
        tst.w   sfx_ticks(a1)
        bne.s   .once
        tst.b   sfxThrust                   ; the loop: on while it burns
        beq.s   .end
        move.l  sfx_ptr(a1),(a0)
        move.w  sfx_len(a1),4(a0)
        bra.s   .regs
.once:
        move.w  sfxT,d0
        cmp.w   sfx_ticks(a1),d0
        bhs.s   .end
        move.l  #sfxSilence,(a0)            ; after the sample: silence (the
        move.w  #1,4(a0)                    ; music may have put its own there)
.regs:
        move.w  sfx_per(a1),6(a0)
        move.w  sfx_vol(a1),8(a0)
        addq.w  #1,sfxT
.out:
        rts
.end:
        sf      sfxOn
        clr.w   8(a0)
        move.w  #1<<sfxCh,$dff096           ; the channel back to the music
        move.b  #$0f,sfxKeep
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

sfxCur:         dc.l    sfxTable
sfxT:           dc.w    0
sfxOn:          dc.b    0
sfxReq:         dc.b    0               ; asked for, for the next tick
sfxThrust::     dc.b    0               ; the ship burns (the thrust loop)
sfxKeep:        dc.b    $0f             ; LSP's channels (and.b, see there)
                even
sfxSilence:     dc.w    0,0
musicPalCountdown:: dc.w    musicPalTicks
logoPalTarget::     dc.w    0   ; bumped once per cue
musicPalStream:     dc.l    0   ; LSP byte stream pointer after the last tick

LSPBank:	
        incbin	"rink-a-dink.lsbank"
        even

        include "sfx.i"

        data
LSPMusic:	
        incbin	"rink-a-dink.lsmusic"
		even
; the effects, unpacked (sfxInit) - chip memory, Paula plays them
        section "sfxbuf",bss,chip
sfxLaserBuf:    ds.b    sfxLaserS_len
sfxBoomBuf:     ds.b    sfxBoomS_len
sfxThrustBuf:   ds.b    sfxThrustS_len
sfxZapBuf:      ds.b    sfxZapS_len
