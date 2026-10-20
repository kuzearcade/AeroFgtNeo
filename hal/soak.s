; Sound soak test (SND_SOAK=1, diagnostics only - never in a release): the game's own
; sound commands go to a sink (tools/aerofgt2neo.py maps its latch elsewhere), and its
; once-a-frame sound sender (0x103c, called from its vblank handler) jumps here instead:
; a recorded command stream (AEROFGT_SOAK, built into SOAK_AT by the tool) is replayed
; one command per call, with the recorded gaps, so the sound driver gets the exact
; command traffic of a real game while the game sits in its attract mode.  The stream
; loops at its end.  Stream: pairs (command, frames to wait after it); command 0 sends
; nothing (a long wait split in parts); (0, 0) ends the stream.

SK_PTR          equ $d00f00             ; l: the next pair (OVR_DIAG's RAM: never together)
SK_WAIT         equ $d00f04             ; w: calls left before it
SK_START        equ 900                 ; (calls before the first command: ~15 s of boot)
SOAK_AT         equ $0f0000             ; the stream, over the palette table (tools/aerofgt2neo.py: 64 KB; the colours are wrong)

snd_soak:
	movem.l d0-d1/a0,-(sp)
	move.l  SK_PTR,d0
	bne.s   .run
	move.l  #SOAK_AT,SK_PTR         ; (the HAL cleared this RAM at the takeover)
	move.w  #SK_START,SK_WAIT
.run:	subq.w  #1,SK_WAIT
	bpl.s   .x
	movea.l SK_PTR,a0
	move.b  (a0)+,d1                ; the command
	moveq   #0,d0
	move.b  (a0)+,d0                ; the calls to wait after it
	bne.s   .go
	tst.b   d1
	bne.s   .go
	move.l  #SOAK_AT,SK_PTR         ; the end: from the start again
	move.w  #60,SK_WAIT
	bra.s   .x
.go:	move.l  a0,SK_PTR
	tst.b   d1
	beq.s   .w
	move.b  d1,REG_SOUND
.w:	subq.w  #1,d0
	move.w  d0,SK_WAIT
.x:	movem.l (sp)+,d0-d1/a0
	moveq   #0,d0
	rts
