
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
;     a zap of our own for the TV going off and a big boom with weight under
;     it for the Defender ending. delta packed, 4 bits a sample (sfx.i,
;     sfxpack.py), unpacked once into chip memory by sfxInit.
;     sfxPlay (from the game, the VBL) asks for one; it goes out on channel
;     sfxCh - or, once the TV is off and it is Defender (sfxWide), on the
;     channels sfxChW says: the laser stays on 3, the booms and the zap go
;     out on 0 and 1 at once (the music's two quietest voices, left and
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
sfxBoomAgain    = 9                 ; a big boom rolls on this long at least

; the channels of each effect once it is Defender (bits 0..3)
sfxChW:         dc.b    0,%1000,%0011,%1000,%1000,%0011,%0011
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
        rts

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
sfxBigBoomBuf:  ds.b    sfxBigBoomS_len
