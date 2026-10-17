
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