
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
        rts

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

; --- sound effects: the Defender laser's zap (sfxLaser, set by
;     scroller.s launchLaser). it goes out on channel sfxCh, which the
;     music then leaves alone till it is over: sfxKeep masks the channel
;     out of LSP's note restarts, and every tick the zap's own sample,
;     period and volume go back in over whatever the music has just
;     written there. afterwards the channel is the music's again from its
;     next note on it. called from the CIA irq right after
;     LSP_MusicPlayTick, all registers are free
sfxCh           = 3
sfxAud          = $dff0a0+sfxCh*16

sfxTick::
        tst.b   sfxLaser
        beq.s   .run
        sf      sfxLaser
        move.w  #1<<sfxCh,$dff096           ; off, a new start
        move.b  #$0f-(1<<sfxCh),sfxKeep     ; the music keeps off it
        clr.w   sfxT
        st      sfxOn
        move.l  LSP_State+m_dmaconPatch,a0  ; on again with LSP's own late
        bset    #sfxCh,(a0)                 ; DMACON write (CIA timer B)
.run:
        tst.b   sfxOn
        beq.s   .out
        lea     sfxAud,a0
        move.l  #sfxWave,(a0)               ; (over the music's, every tick)
        move.w  #sfxWaveLen/2,4(a0)
        move.w  sfxT,d0
        cmp.w   #sfxTicks,d0
        bhs.s   .end
        addq.w  #1,sfxT
        add.w   d0,d0
        lea     sfxPer,a1
        move.w  (a1,d0.w),6(a0)
        lea     sfxVol,a1
        move.w  (a1,d0.w),8(a0)
.out:
        rts
.end:
        sf      sfxOn
        clr.w   8(a0)
        move.w  #1<<sfxCh,$dff096           ; the channel back to the music
        move.b  #$0f,sfxKeep
        rts

sfxTicks        = 16
; the zap: high and bright, down and out - period up, volume down
sfxPer:         dc.w    112,118,126,136,148,162,178,196,216,238,262,290,320,352,388,428
sfxVol:         dc.w    64,63,61,58,55,51,47,42,37,32,26,21,16,11,6,2
sfxT:           dc.w    0
sfxOn:          dc.b    0
sfxLaser::      dc.b    0               ; set: the zap starts on the next tick
sfxKeep:        dc.b    $0f             ; LSP's channels (and.b, see there)
                even
; one cycle of the zap: a hard pulse with grit on it (chip memory, this
; section is)
sfxWave:        dc.b    112,96,120,90,124,100,116,84,127,104,118,92,122,98,114,88
                dc.b    -112,-100,-120,-86,-124,-96,-116,-104,-127,-90,-118,-108,-122,-94,-114,-100
sfxWaveLen      = *-sfxWave

musicPalCountdown:: dc.w    musicPalTicks
logoPalTarget::     dc.w    0   ; bumped once per cue
musicPalStream:     dc.l    0   ; LSP byte stream pointer after the last tick

LSPBank:	
        incbin	"rink-a-dink.lsbank"
        even

        data
LSPMusic:	
        incbin	"rink-a-dink.lsmusic"
		even