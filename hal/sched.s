; Not cycle-exact (AEROFGT_DIRECT=1): a plain raster-driven scheduler instead of the
; virtual-time core (probe, sleds, vernier, exact wake: hal.s / idle.s).
;
; The fused build gave up RAM equivalence, so the game's vblank interrupt need not come
; at the original board's cycle.  Per real frame:
;   * the slot starts when the game reaches its idle loop (the trampoline jumps to
;     sch_idle) or, if it is still busy then, at the LSPC timer at PHASE_LINE
;     (sch_timer: the game's own exception frame is kept),
;   * the HAL works as before (prep, early work until the real vblank, inputs, the
;     commit) up to the deadline line SCH_DL_VPOS after the real vblank,
;   * then the timer is armed for the next PHASE_LINE and the game's handler (ORIG_IRQ)
;     runs at once: no STOP, no wake expiry, no probe.
; Slowdown instead of a late frame: when the commit's flip would find no new sprite set
; (the conversion for it still going on), the commit waits a real frame - the game
; with it, its vblank not given - and the conversion goes on (SCH_EXT_MAX frames at
; most).  Counted in HAL_SLOWN (HAL_SCH_EXT: this slot's extensions).  And when a slot
; ends without having begun its conversion (the next commit's), the game waits until it
; is begun and done: HAL_SLOWB.

SCH_DL_VPOS     equ 10              ; the slot's deadline (vpos after the real vblank)
SCH_HOLD_VPOS   equ 200             ; a held frame's work ends here (then the commit's
                                    ; usual deadline: the next real vblank and on)
	ifnd SCH_EXT_MAX
SCH_EXT_MAX     equ 0               ; held frames in a row at most (a commit waiting): none
                                    ; (user choice 2026-10-15: full speed, late sprites
                                    ; instead; 2 held dense scenes to ~1.33x)
	endif
	ifnd SCH_EXTB_MAX
SCH_EXTB_MAX    equ 2               ; (and after a commit, for a conversion not begun)
	endif
SCH_YLINE       equ 236             ; a yielded slot goes on at this vpos (the timer)
SCH_YMIN        equ 6               ; lines before it a yield needs at least
SCH_ST_SCRUB    equ 5-FUSED         ; (hal/video.s: hal_vid_early's last stage, filler)

; Timer IRQ (hal_timer, HAL_MODE = MODE_GAME): the game did not reach its idle loop by
; PHASE_LINE.  Its exception frame stays on its stack for the handler.
sch_timer:
	move.l  sp,HAL_SAVED_SP
	lea     HAL_STACK_TOP,sp
	movem.l d0-d7/a0-a6,-(sp)
	move.w  #ACK_TIMER,REG_IRQACK
	move.w  #$2700,sr
	st      HAL_SCH_BUSY
	tst.b   HAL_SCH_YLD             ; (a yielded slot's own timer: not a new slot)
	bne.s   sch_slot
	addq.l  #1,HAL_SCH_TIMN
	bra.s   sch_slot

; The idle loop's bcs (trampoline, IPL 7): the game waits for its vblank.  The handler
; gets an exception frame that returns to the loop's cmpi (it then finds the flag set).
sch_idle:
	tst.b   G_VBFLAG
	bne.w   hal_post                ; (back from a vblank taken between cmpi and bcs)
	move    sr,HAL_IDLE_SR
	move.l  sp,HAL_SAVED_SP
	lea     HAL_STACK_TOP,sp
	movem.l d0-d7/a0-a6,-(sp)
	movea.l HAL_SAVED_SP,a0
	subq.l  #6,a0
	move.l  a0,HAL_SAVED_SP
	move.w  HAL_IDLE_SR,d0
	andi.w  #$0010,d0
	ori.w   #$2109,d0               ; IPL 1, X, the cmpi.b #1 of a 0 flag: N C
	move.w  d0,(a0)
	move.l  #$b84,2(a0)
	sf      HAL_SCH_BUSY
	addq.l  #1,HAL_IDLES
	; (falls into sch_slot)

; The slot: HAL_SAVED_SP = the game's exception frame (SR, PC).
sch_slot:
	movea.l HAL_SAVED_SP,a0
	move.w  (a0),HAL_CCR            ; interrupted SR: CCR for the handler
	move.b  d0,REG_WATCHDOG
	tst.b   HAL_SCH_YLD             ; a yielded slot: on where it stopped
	beq.s   .new
	sf      HAL_SCH_YLD
	movea.l HAL_SCH_RES,a0
	jmp     (a0)
.new:	addq.l  #1,HAL_FRAMES
	bsr     sch_tramp
	clr.b   HAL_SCH_EXT
	move.w  #SCH_DL_VPOS,d0
	bsr     sch_dl
	cmpi.l  #1,HAL_FRAMES
	beq.s   .wvb                    ; (the first slot: inputs only)
	jsr     hal_vid_prep
	; work that does not touch the display until the real vblank (vpos 242..263),
	; keeping the commit's share (as hal_frame)
.wvb:	move.w  REG_LSPCMODE,d0
	lsr.w   #7,d0
	cmpi.w  #$100+242,d0
	bhs.s   .inp
	cmpi.w  #$100,d0
	blo.s   .inp
	moveq   #COMMIT_LINES,d0
	jsr     hal_late_n
	bne.s   .inp
	lea     .wvb(pc),a0             ; only filler left, the game busy: it runs until
	bsr.w   sch_yield               ; SCH_YLINE (no return then)
	jsr     hal_vid_early
	bra.w   .wvb
.inp:	jsr     hal_inputs
	cmpi.l  #1,HAL_FRAMES
	ifne WALK_HOLD
	beq.w   .end
	else
	beq.s   .end
	endif
	bsr     sch_ready
	bne.w   .slow
	jsr     hal_vid_commit
	; no conversion begun for this slot (the walk took its time): the next commit
	; would have nothing new.  The game waits until it is done (or SCH_HOLD_VPOS).
	ifne WALK_HOLD
	tst.b   FX_SDONE                ; (hal/fx.s: the walk unfinished: the game waits
	bne.s   .hc                     ; for it too, else its objects move under it and
	addq.l  #1,HAL_WHOLD            ; the list mixes two of its frames)
	bra.s   .hold
.hc:
	endif
	tst.b   HAL_SPR_DONE
	bne.s   .end
.hold:	cmpi.b  #SCH_EXTB_MAX,HAL_SCH_EXT
	bhs.s   .end
	if (FUSED=1)&FZ_EARLY
	jsr     fz_urgent               ; (hal/fz.s: the set in work is for the flip after
	beq.s   .end                    ; the next: no hold for it, 2026-10-18)
	endif
	addq.b  #1,HAL_SCH_EXT
	addq.l  #1,HAL_SLOWB
	move.w  #SCH_HOLD_VPOS,d0
	bsr     sch_dl
	move.w  #1,HAL_EARLY_ST         ; (hal/video.s: the walk, then the conversion)
.bw:
	ifne WALK_HOLD
	tst.b   FX_SDONE                ; the walk done?
	beq.s   .bn
	endif
	tst.b   HAL_SPR_DONE            ; begun and done?
	beq.s   .bn
	tst.w   HAL_SPR_W
	bmi.s   .end
.bn:	moveq   #0,d0
	jsr     hal_late_n
	bne.s   .end
	cmpi.w  #SCH_ST_SCRUB,HAL_EARLY_ST      ; (only filler left: it waits for columns
	beq.s   .end                    ; a flip frees - the game rather runs)
	jsr     hal_vid_early
	bra.s   .bw
.end:	moveq   #2,d0                   ; ran past the deadline (diagnostics: the game
	neg.w   d0                      ; only loses the time)
	jsr     hal_late_raw
	beq.s   .ot
	addq.l  #1,HAL_OVERRUN
	ifne OVR_DIAG
	move.w  #2,OVD_SITE
	jsr     ovd_note
	endif
.ot:	bsr     sch_arm
	move.w  #$2200,sr               ; (as a level-2 interrupt's handler)
	lea     HAL_STACK_TOP-15*4,sp
	movem.l (sp)+,d0-d7/a0-a6
	move.l  HAL_SAVED_SP,sp
	move.w  HAL_CCR,ccr
	jmp     ORIG_IRQ
	; held frame: no commit, the game waits; the conversion goes on until
	; SCH_HOLD_VPOS of the next frame, then the usual way to its real vblank
.slow:	addq.b  #1,HAL_SCH_EXT
	addq.l  #1,HAL_SLOWN
	move.w  #SCH_HOLD_VPOS,d0
	bsr     sch_dl
	move.w  #1,HAL_EARLY_ST         ; (hal/video.s: the carried conversion first)
.sw:	moveq   #0,d0
	jsr     hal_late_n
	bne.s   .sx
	cmpi.w  #SCH_ST_SCRUB,HAL_EARLY_ST      ; (only filler left: the hold's work done
	beq.s   .sx                     ; or waiting - on to the real vblank's)
	jsr     hal_vid_early
	bra.s   .sw
.sx:	move.w  #SCH_DL_VPOS,d0
	bsr     sch_dl
	bra.w   .wvb

; Z set: commit now (a new set for the flip is complete, or waiting would not complete
; one: no conversion for this slot going on - one begun now would be for the next slot -,
; it waits for columns only a flip frees, or SCH_EXT_MAX held frames already).  Clobbers d0-d3, a0-a1.
sch_ready:
	ifeq FUSED-2
	bra.w   .go                     ; (hal/fz.s: the conversion is the game's own; the
	endif                           ; flip shows what is complete, nothing waits)
	cmpi.b  #SCH_EXT_MAX,HAL_SCH_EXT
	bhs.w   .go
	tst.b   HAL_SPR_BLK
	bne.w   .go
	ifeq FUSED
	tst.b   FX_PON                  ; (hal/dl.s: an update in place pending, for now)
	beq.s   .nd
	move.w  FX_PRDY,d1
	sub.w   HAL_FRAMES+2,d1         ; (frame numbers wrap: the sign of the difference)
	tst.w   d1
	ble.w   .go
.nd:
	endif
	lea     HAL_SPR_ST,a0
	lea     HAL_SPR_RDY,a1
	move.w  HAL_FRAMES+2,d3
	moveq   #NSPRSETS-1,d0
.c:	cmpi.b  #1,(a0,d0.w)            ; complete, may be shown from this slot on?
	bne.s   .n
	move.w  d0,d2
	add.w   d2,d2
	move.w  (a1,d2.w),d1
	sub.w   d3,d1
	tst.w   d1                      ; (frame numbers wrap: the sign only)
	ble.w   .go
.n:	dbra    d0,.c
	move.w  HAL_SPR_W,d0            ; none: the one going on is for this slot?
	bmi.w   .go
	ifeq FUSED
	cmpi.b  #1,FX_DELTA             ; (an update in place: its own slot)
	bne.s   .nw
	move.w  FX_DRDY,d1
	sub.w   d3,d1                   ; (frame numbers wrap: the sign of the difference)
	tst.w   d1
	bgt.w   .go
	move.w  #0,ccr
	rts
.nw:
	endif
	add.w   d0,d0
	move.w  (a1,d0.w),d1
	sub.w   d3,d1
	tst.w   d1                      ; (frame numbers wrap: the sign only)
	bgt.w   .go
	move.w  #0,ccr                  ; hold the frame
	rts
.go:	move.w  #4,ccr
	rts

; d0 = vpos the work may run to (its next occurrence after now): HAL_K0, HAL_K0R,
; HAL_KDL, HAL_DEADLINE, HAL_PROBE_VPOS as hal_deadline sets them.  Clobbers d0-d1.
sch_dl:
	move.w  d0,d1
	jsr     hal_vpos
	move.w  d0,HAL_PROBE_VPOS
	addq.w  #8,d0                   ; k = (vpos + 8) mod 264 (0 at vpos 256)
	cmpi.w  #264,d0
	blo.s   .k
	subi.w  #264,d0
.k:	move.w  d0,HAL_K0
	addi.w  #$f8,d0                 ; (as the line counter reads it)
	move.w  d0,HAL_K0R
	addq.w  #8,d1
	cmpi.w  #264,d1
	blo.s   .d
	subi.w  #264,d1
.d:	addi.w  #$f8,d1
	cmp.w   d0,d1
	bhi.s   .s
	addi.w  #264,d1
.s:	move.w  d1,HAL_KDL
	sub.w   d0,d1
	move.w  d1,HAL_DEADLINE
	sf      HAL_OUT
	rts

; Yield (the slot's loops, a0 = where it goes on): when the game was busy (the timer
; began the slot) and hal_vid_early has only filler left (the verification), it runs
; until SCH_YLINE, its own work on (the dense scenes: the slot's work done or waiting,
; the HAL scrubbed while the game waited, ~15% of its time, 2026-10-15); the timer, or
; the game's idle loop if it gets there first, resumes the slot at a0 (sch_slot).
; Returns (nothing changed) when it does not.  Clobbers d0-d1.
sch_yield:
	tst.b   HAL_SCH_BUSY
	beq.s   .x
	cmpi.w  #SCH_ST_SCRUB,HAL_EARLY_ST
	bne.s   .x
	jsr     hal_vpos
	cmpi.w  #SCH_YLINE-SCH_YMIN,d0
	bhs.s   .x
	cmpi.w  #SCH_DL_VPOS+8,d0       ; (after the real vblank's commit: not this way)
	blo.s   .x
	move.l  a0,HAL_SCH_RES
	st      HAL_SCH_YLD
	addq.l  #1,HAL_SCH_YN
	move.w  #SCH_YLINE,d1
	bsr.s   sch_arml
	lea     HAL_STACK_TOP-15*4,sp
	movem.l (sp)+,d0-d7/a0-a6
	move.l  HAL_SAVED_SP,sp
	rte
.x:	rts

; The timer: an expiry at the next PHASE_LINE (counted from now; a line or so off does
; not matter here), then far away until armed again.  Clobbers d0-d1.
sch_arm:
	move.w  #PHASE_LINE,d1
; (sch_arml: at vpos d1)
sch_arml:
	move.w  #ACK_TIMER,REG_IRQACK   ; (one that came while the slot ran: dropped)
	move.w  d1,-(sp)
	jsr     hal_vpos
	move.w  (sp)+,d1
	sub.w   d0,d1
	bgt.s   .p
	addi.w  #264,d1
.p:	mulu    #384,d1                 ; (2 cycles a count)
	subq.l  #1,d1
	move.w  #AUTOANIM_OFF|TIMER_IRQ_EN|TIMER_REPEAT|TIMER_LOAD_REL,REG_LSPCMODE
	swap    d1
	move.w  d1,REG_TIMERHIGH
	swap    d1
	move.w  d1,REG_TIMERLOW
	move.w  #AUTOANIM_OFF|TIMER_IRQ_EN|TIMER_REPEAT,REG_LSPCMODE
	move.w  #$00ff,REG_TIMERHIGH
	move.w  #$ffff,REG_TIMERLOW
	rts

; The idle loop's trampoline (the game's boot RAM test/clear runs over it): harvest.
sch_tramp:
	lea     G_TRAMP,a0
	move.l  #$007c0700,(a0)+        ; ori.w #$0700,sr
	move.w  #$4ef9,(a0)+            ; jmp sch_idle
	move.l  #sch_idle,(a0)
	rts

; From the takeover: the first PHASE_LINE armed, then the original's reset code.
sch_boot:
	move.b  #MODE_GAME,HAL_MODE
	clr.l   HAL_SLOWN
	clr.l   HAL_SLOWB
	clr.l   HAL_SCH_TIMN
	bsr     sch_tramp
	bsr     sch_arm
	move.l  #$00d01000,sp           ; original boot SSP (relocated 0x1b1000)
	moveq   #0,d0
	moveq   #0,d1
	move.w  #$2700,sr
	jmp     ORIG_RESET
