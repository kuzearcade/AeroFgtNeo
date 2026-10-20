; Real-cart video conversion (not assembled into the MAME-only assist build).
;
; Runs in the HAL slot of every virtual vblank k, outside virtual time:
;   hal_vid_prep    before the real vblank: anything that does not touch the display
;   hal_vid_commit  inside the real vblank: Neo palette / VRAM writes, until the
;                   deadline (the wake expiry must find the CPU in STOP)
;
; What the original shows for frame k (the reference the harness compares against):
; tilemaps/scroll/sprites as they are at virtual vblank k (MAME draws at vblank start),
; colours as they are after the vblank handler's palette writes (MAME converts the
; indexed bitmap to RGB afterwards).  Those writes happen at the very start of the
; handler, right after this slot with no game code in between, and are all
; predictable, so the HAL performs them early (the handler then rewrites the same
; values: no state the game can observe differs).

; ================================================================ prep
hal_vid_prep:
	ifne HAL_DIAG
	bsr     hal_vpos
	move.w  d0,HAL_DBG_PREP
	endif
	bsr     hal_spr_slot
	ifeq DIRECT-1
	ifne FUSED
	jsr     fz_prep                 ; (hal/fz.s)
	else
	jsr     fx_snap_begin           ; (hal/fx.s: this slot's walk over the objects)
	endif
	endif
	clr.w   HAL_EARLY_ST
	bsr     hal_pal_predict
	ifne HAL_DIAG
	bsr     hal_vpos
	move.w  d0,HAL_DBG_PRED
	endif
	bsr     hal_pal_sentinel
	bsr     hal_pal_scrub
	ifeq DIRECT-1
	bsr     hal_pal_stage           ; (converted now, written in the vblank at once)
	endif
	bra     hal_bg_prep

; ================================================================ early work
; One unit of work that does not touch the display, while the slot waits for the real
; vblank (the idle entry starts the slot long before it).  Z set: nothing to do.
SPR_RES_EARLY   equ 10              ; scanlines the vblank work needs (place + flip + some)
SPR_RES_COMMIT  equ -2              ; after the commit: up to the deadline + 1 line, less
SPR_TAIL        equ 1100/16             ; the tail after a budget stop (~950 cycles, 16-cycle
                                    ; units; each sprite is charged an upper bound of its
                                    ; cost): it still ends a line before the overrun guard
; Stages: 0 tilemap rows in view (a column left out stays wrong until it is done),
; 1 sprites, 2 the rest of the tilemap columns, 3 verification (DIRECT=1: a carried
; walk over the objects, hal/fx.s, between 0 and 1).
hal_vid_early:
	move.w  HAL_EARLY_ST,d0
	add.w   d0,d0
	move.w  .st(pc,d0.w),d0
	jmp     .st(pc,d0.w)
	ifeq DIRECT-1
	ifne FUSED
.st:	dc.w    .bg1-.st,.car-.st,.spr-.st,.bg2-.st,.scrub-.st  ; (hal/fz.s: no walk stage)
	else
	ifne CONV_FIRST
.st:	dc.w    .bg1-.st,.car-.st,.spr-.st,.wk-.st,.bg2-.st,.scrub-.st  ; (experiment: the
	else                            ; last list's conversion before this slot's walk)
.st:	dc.w    .bg1-.st,.car-.st,.wk-.st,.spr-.st,.bg2-.st,.scrub-.st
	endif
	endif
	else
.st:	dc.w    .bg1-.st,.spr-.st,.bg2-.st,.scrub-.st
	endif
.bg1:	st      HAL_BG_P1
	bsr.s   .bg
	sf      HAL_BG_P1
	bne.w   .x
	addq.w  #1,HAL_EARLY_ST
.x:	rts
.spr:	addq.w  #1,HAL_EARLY_ST
	move.w  #SPR_RES_EARLY,HAL_SPR_RES      ; keep the real-vblank work's share
	st      HAL_BG_EARLY            ; (and stop at the real vblank: resumed after
	bsr     hal_spr_work            ; the commit)
	sf      HAL_BG_EARLY
	rts
.bg2:	bsr.s   .bg
	bne.w   .x
	addq.w  #1,HAL_EARLY_ST
	rts
	; tilemap columns waiting (into their buffers), keeping the commit's share: the
	; real vblank on (only the commit can use it), COMMIT_LINES at least
.bg:	st      HAL_BG_EARLY
	move.w  #242+8+$f8,d0           ; the real vblank's start (as HAL_KDL counts)
	cmp.w   HAL_K0R,d0
	bhs.s   .b1
	addi.w  #264,d0
.b1:	neg.w   d0
	add.w   HAL_KDL,d0              ; lines from there to the deadline
	cmpi.w  #COMMIT_LINES,d0
	bge.s   .b2
	moveq   #COMMIT_LINES,d0
.b2:	move.w  d0,HAL_RESV
	bsr     hal_bg_convert
	sf      HAL_BG_EARLY
	clr.w   HAL_RESV
	tst.w   d0
	rts
	; then verify tilemap columns with the time left (text the game erases in
	; place is only noticed this way); a stale one is converted at stage 2
.scrub:
	ifeq DIRECT-1
	tst.b   HAL_SCH_BUSY            ; (hal/sched.s: the game busy - its time rather;
	bne.w   .x                      ; the writers' marks find the changes, hal/tm.s)
	endif
	moveq   #COMMIT_LINES+SCRUB_LINES,d0
	bsr     hal_late_n
	bne.w   .x
	tst.w   HAL_BG_BURST            ; (fast verification after a stale find)
	beq.s   .s1
	subq.w  #1,HAL_BG_BURST
.s1:	bsr     hal_bg_scrub1
	tst.b   HAL_BG_WORK
	beq.w   .x
	lea     HAL_BG_PEND,a0          ; something to convert: back to stage 2
	moveq   #64/4-1,d0
.sp:	tst.l   (a0)+
	dbne    d0,.sp
	beq.w   .x
	move.w  #2,HAL_EARLY_ST
	rts

	ifeq DIRECT-1
	; a conversion carried from the last slot first (this slot's flip shows it), no new
	; one begun yet (the walk comes first then: the slot is its only time)
.car:	addq.w  #1,HAL_EARLY_ST
	tst.w   HAL_SPR_W
	bmi.s   .cx
	move.b  HAL_SPR_DONE,-(sp)
	st      HAL_SPR_DONE
	move.w  #SPR_RES_EARLY,HAL_SPR_RES
	st      HAL_BG_EARLY
	bsr     hal_spr_work
	sf      HAL_BG_EARLY
	move.b  (sp)+,HAL_SPR_DONE
.cx:	rts
	; the walk in batches until the real vblank (keeping the commit's share, as .bg)
.wk:	move.w  #242+8+$f8,d0           ; (as .bg: the lines from the real vblank's start
	cmp.w   HAL_K0R,d0              ; to the deadline, COMMIT_LINES at least)
	bhs.s   .w1
	addi.w  #264,d0
.w1:	neg.w   d0
	add.w   HAL_KDL,d0
	cmpi.w  #COMMIT_LINES,d0
	bge.s   .w2
	moveq   #COMMIT_LINES,d0
.w2:	move.w  d0,HAL_RESV
	moveq   #0,d0                   ; (hal/tx.s: tilemap-1 masks first: cheap, and a
	jsr     hal_bg_maskwork         ; column waits shown whole meanwhile; the columns
	tst.b   FX1_DIRTY               ; showing nothing hidden)
	beq.s   .w3
	moveq   #TX_LINES,d0
	bsr     hal_late_n
	bne.s   .w3
	jsr     hal_bg_l1hide
.w3:
	moveq   #0,d0
	jsr     fx_snap_step
	clr.w   HAL_RESV
	ifne CONV_FIRST
	beq.s   .w4                     ; (not done: the rest after the commit)
	tst.b   HAL_SPR_DONE            ; the walk done and the conversion not begun (its
	bne.s   .w4                     ; list was this walk's, fx_listrdy): now
	move.w  #SPR_RES_EARLY,HAL_SPR_RES
	st      HAL_BG_EARLY
	bsr     hal_spr_work
	sf      HAL_BG_EARLY
.w4:
	endif
	addq.w  #1,HAL_EARLY_ST         ; (done, or no time for a batch before the vblank:
	rts                             ; the rest after the commit)
	endif

; ================================================================ commit
	ifnd WALK_TAIL
	ifne OVR_FIX
WALK_TAIL       equ 3               ; scanlines the commit's walk rest keeps back (its batch
	else                            ; may end ~2 lines over its charge, 2026-10-17)
WALK_TAIL       equ 1
	endif
	endif
hal_vid_commit:
	bsr     hal_slip_log            ; the last frame's slips are final now
	clr.w   HAL_SLIP
	tst.b   HAL_BG_RETROP           ; tilemap staleness found since the last commit
	beq.s   .rp                     ; (logged as a range: hal/bg.s)
	sf      HAL_BG_RETROP
	bset    #1,HAL_SLIP+1
.rp:
	ifne OVR_DIAG
	move.l  #$7fff7fff,OVD_T        ; (this commit's steps only)
	move.l  #$7fff7fff,OVD_T+4
	move.l  #$7fff7fff,OVD_T+8
	move.l  #$7fff7fff,OVD_T+12
	move.w  #$7fff,OVD_T+16
	endif
	OVT     0
	sf      HAL_OUT                 ; (the early work's failed checks reserved time)
	ifne HAL_DIAG
	bsr     hal_vpos
	move.w  d0,HAL_DBG_COMMIT
	endif
	ifne BG_SETSCR
	bsr     hal_spr_flip            ; (BG_SETSCR: the set shown first, the tilemaps
	OVT     1                       ; placed for it)
	bsr     hal_bg_place
	OVT     2
	else
	bsr     hal_bg_place
	OVT     1
	bsr     hal_spr_flip
	OVT     2
	endif
	ifeq DIRECT-1
	move.w  #PAL_TAIL,HAL_RESV      ; (after the flip: the palettes are the commit's
	bsr     hal_pal_apply           ; part that can wait, its check keeps the lines
	clr.w   HAL_RESV                ; the unchecked steps after it take)
	endif
	OVT     4
	ifne OVR_FIX
	moveq   #2,d0                   ; (the palettes may end at the deadline in a fade: the
	bsr     hal_late_n              ; tail's own checks then overran by ~2 lines, 2026-10-17)
	bne.w   .out
	endif
	ifne HAL_DIAG
	bsr     hal_vpos
	move.w  d0,HAL_DBG_T2
	endif
	ifne DIRECT-1
	bsr     hal_pal_convert
	endif
	ifne HAL_DIAG
	bsr     hal_vpos
	move.w  d0,HAL_DBG_T3
	endif
	bsr     hal_bg_blast            ; the columns converted before the vblank
	OVT     5
	st      HAL_BG_P1               ; then the rows in view still waiting (keeping
	move.w  #BLAST_LINES+1,HAL_RESV ; time to copy one)
	bsr     hal_bg_convert
	clr.w   HAL_RESV
	sf      HAL_BG_P1
	bsr     hal_bg_blast
	OVT     6
	ifeq DIRECT-1
	jsr     fx_hud_flush            ; (hal/fx.s: the fix layer with the flip's sprites,
					; before the picture starts)
	ifne OVR_DIAG
	st      OVD_INC
	endif
	ifeq FUSED
	moveq   #WALK_TAIL,d0           ; (hal/fx.s) the walk's rest (its HUD pass runs up
	jsr     fx_snap_step            ; to ~5 lines over its charge: the reserve, 2026-10-17)
	endif
	ifne OVR_DIAG
	sf      OVD_INC
	endif
	endif
	OVT     7
	move.w  #SPR_RES_COMMIT,HAL_SPR_RES     ; sprites not (all) converted before the
	move.w  #SPR_TAIL+FZ_TAILX,HAL_SPR_TAILU ; real vblank: go on with what is left
	bsr     hal_spr_work
	clr.w   HAL_SPR_TAILU
	OVT     8
	moveq   #1,d0                   ; no room for the rest (the sprites may run into
	bsr     hal_late_n              ; the margin, finished or not; what follows checks
	bne.s   .out                    ; before it works): HAL_OUT, only the blast's slip
					; log is left
	ifeq DIRECT-1
	moveq   #1,d0                   ; (hal/tx.s) masks of the columns just blasted
	jsr     hal_bg_maskwork
	endif
	move.w  #BLAST_LINES+1,HAL_RESV ; rows out of view: not a slip when they wait
	bsr     hal_bg_convert
	clr.w   HAL_RESV
	bsr     hal_bg_blast
	ifeq DIRECT-1
	tst.b   HAL_SCH_BUSY            ; (the game busy: its time rather; the idle-time
	bne.s   .end                    ; verification stage still runs)
	endif
	bsr     hal_bg_scrub_more
	bra.s   .end
.out:	bsr     hal_bg_blast
.end:
	ifeq DIRECT-1
	tst.b   FX1_DIRTY               ; (hal/tx.s: empty columns hidden, if there is time)
	beq.s   .nd
	moveq   #TX_LINES,d0
	bsr     hal_late_n
	bne.s   .nd
	jsr     hal_bg_l1hide
.nd:
	endif
	tst.w   HAL_BG_APXN             ; columns showing approximated cells
	beq.s   .ap
	addq.l  #1,HAL_BG_APXF
	bset    #1,HAL_SLIP+1
.ap:
	ifne HAL_DIAG
	bsr     hal_vpos
	move.w  d0,HAL_DBG_END
	endif
	rts

; ================================================================ slip log
; Every frame whose display may differ from the original's, kept at G_SLIPLOG (a gap
; in the game's RAM map): counters, then a ring of the newest SL_N records
;   first slot (long, HAL_FRAMES), frames (word), slip bits (word)
; Consecutive frames with the same bits share a record (the newest record is open:
; it may still grow).  Bits: 0 palette, 1 tilemap, 2 sprites, 3 tilemap shown stale
; before the HAL saw it (a range logged afterwards: hal/bg.s), 4 boot frame (no
; video work).  All zero is the empty log (the game's boot RAM clear may run after
; the HAL's init).
SL_NREC         equ 0               ; long: records written
SL_NFR          equ 4               ; long: frames with a slip (bits 0-2, 4)
SL_NPAL         equ 8               ; long: frames per bit 0, 1, 2
SL_NBG          equ 12
SL_NSPR         equ 16
SL_NRETRO       equ 20              ; long: frames in bit-3 ranges
SL_HEAD         equ 24              ; word: ring index of the newest record
SL_REC          equ 32
SL_N            equ ($700-SL_REC)/8

; At the start of the commit of slot k: log slot k-1 (HAL_SLIP), then the stale range
; found since the last commit (HAL_BG_RETROF .. k-1).  Clobbers d0-d3, a0-a1.
hal_slip_log:
	lea     G_SLIPLOG,a0
	move.l  HAL_FRAMES,d1
	subq.l  #1,d1                   ; the frame HAL_SLIP belongs to
	move.w  HAL_SLIP,d0
	beq.s   .rt
	addq.l  #1,SL_NFR(a0)
	btst    #0,d0
	beq.s   .c1
	addq.l  #1,SL_NPAL(a0)
.c1:	btst    #1,d0
	beq.s   .c2
	addq.l  #1,SL_NBG(a0)
.c2:	btst    #2,d0
	beq.s   .c3
	addq.l  #1,SL_NSPR(a0)
.c3:	tst.l   SL_NREC(a0)             ; does it extend the newest record?
	beq.s   .nw
	move.w  SL_HEAD(a0),d2
	lsl.w   #3,d2
	lea     SL_REC(a0,d2.w),a1
	cmp.w   6(a1),d0
	bne.s   .nw
	moveq   #0,d2
	move.w  4(a1),d2
	cmpi.w  #$ffff,d2
	beq.s   .nw
	add.l   (a1),d2
	cmp.l   d1,d2
	bne.s   .nw
	addq.w  #1,4(a1)
	bra.s   .rt
.nw:	moveq   #1,d3
	bsr.s   .app
.rt:	tst.b   HAL_BG_RETROP           ; a stale range: RETROF (low word) .. k-1
	beq.s   .x
	move.w  HAL_FRAMES+2,d3
	sub.w   HAL_BG_RETROF,d3        ; frames, modulo 65536
	beq.s   .x
	moveq   #0,d0
	move.w  d3,d0
	add.l   d0,SL_NRETRO(a0)
	addq.l  #1,d1
	sub.l   d0,d1
	moveq   #8,d0
	; append a record: d1 first slot, d3 frames, d0 bits
.app:	moveq   #0,d2
	tst.l   SL_NREC(a0)
	beq.s   .a0
	move.w  SL_HEAD(a0),d2
	addq.w  #1,d2
	cmpi.w  #SL_N,d2
	blo.s   .a0
	moveq   #0,d2
.a0:	move.w  d2,SL_HEAD(a0)
	addq.l  #1,SL_NREC(a0)
	lsl.w   #3,d2
	lea     SL_REC(a0,d2.w),a1
	move.l  d1,(a1)+
	move.w  d3,(a1)+
	move.w  d0,(a1)
.x:	rts

; ================================================================ palette
; Original palette q (16 entries, q = entry >> 4) -> Neo palettes, see tools/gfx.py.
; Relevant q: 0..7 (tilemap 0), 16..23 (tilemap 1), 32..63 (sprites).

; Perform the vblank handler's palette writes early (same order as the handler):
; quarter copies from the RAM buffer (0x2bcd4), the 16-entry copy, palette cycling
; (0x2a2de).  Every palette whose contents change is marked dirty.
hal_pal_predict:
	move.w  G_PALFLAGS,d0
	btst    #0,d0
	beq.s   .q1
	lea     G_PALBUF,a0
	lea     G_PALETTE,a1
	moveq   #0,d1
	moveq   #8-1,d2
	bsr     hal_pal_copycmp
.q1:	btst    #1,d0
	beq.s   .q2
	lea     G_PALBUF+$200,a0
	lea     G_PALETTE+$200,a1
	moveq   #16,d1
	moveq   #8-1,d2
	bsr     hal_pal_copycmp
.q2:	btst    #2,d0
	beq.s   .q3
	lea     G_PALBUF+$400,a0
	lea     G_PALETTE+$400,a1
	moveq   #32,d1
	moveq   #16-1,d2
	bsr     hal_pal_copycmp
.q3:	btst    #3,d0
	beq.s   .cpy
	lea     G_PALBUF+$600,a0
	lea     G_PALETTE+$600,a1
	moveq   #48,d1
	moveq   #16-1,d2
	bsr     hal_pal_copycmp

	; 16-entry copy (only its palette-RAM destinations matter for this frame)
.cpy:	tst.w   G_PCPY_ON
	beq.s   .cyc
	movea.l G_PCPY_DST,a1
	bsr     hal_pal_in
	bcs.s   .cyc
	movea.l G_PCPY_SRC,a0
	moveq   #8-1,d2
.cl:	move.l  (a0)+,(a1)+
	dbra    d2,.cl
	subq.l  #2,a1
	bsr     hal_pal_mark            ; last entry's palette
	lea     -30(a1),a1
	bsr     hal_pal_mark            ; first entry's palette

	; palette cycling: emulate one call of 0x2a2de without its side effects
.cyc:	tst.b   G_CYC_OFF
	bne.s   .flash
	tst.w   G_CYC_ON
	beq.s   .flash
	bmi.s   .flash
	move.w  G_CYC_CNT,d0
	addq.w  #1,d0
	andi.w  #$f,d0
	bne.s   .flash
	move.w  G_CYC_POS,d0
	addq.w  #2,d0
	andi.w  #$e,d0
	lea     G_CYC_SRC,a2
	lea     G_CYC_DST,a3
	moveq   #16-1,d7
.cn:	tst.w   (a2)
	bmi.s   .flash
	movea.l (a2)+,a4
	movea.l (a3)+,a1
	bsr     hal_pal_in
	bcs.s   .cs
	move.w  (a4,d0.w),(a1)
	bsr     hal_pal_mark
.cs:	dbra    d7,.cn

	; tilemap-1 white flash (0x1e922 / 0x22624 fill palette RAM directly, then set
	; G_FLASH bit 1): a change of that bit means quarter 1 changed
.flash:	move.b  G_FLASH,d0
	andi.b  #2,d0
	cmp.b   HAL_FLASH_PREV,d0
	beq.s   .done
	move.b  d0,HAL_FLASH_PREV
	lea     HAL_PALDIRTY+16,a0
	moveq   #-1,d0
	move.l  d0,(a0)+
	move.l  d0,(a0)+
.done:	rts

; a1 = palette RAM address?  C clear if inside the original palette.  Clobbers nothing.
hal_pal_in:
	cmpa.l  #G_PALETTE,a1
	blo.s   .no
	cmpa.l  #G_PALETTE+$800,a1
	bhs.s   .no
	andi    #$fe,ccr
	rts
.no:	ori     #1,ccr
	rts

; mark the palette containing palette RAM address a1 dirty.  Clobbers d1, a6.
hal_pal_mark:
	move.l  a1,d1
	sub.l   #G_PALETTE,d1
	lsr.w   #5,d1
	lea     HAL_PALDIRTY,a6
	st      (a6,d1.w)
	rts

; copy d2+1 palettes a0 -> a1 (8 longs each) where they differ; d1 = first q.
; Marks the changed ones dirty.  Clobbers d1-d7, a0-a6 except d0.
hal_pal_copycmp:
	lea     HAL_PALDIRTY,a2
	adda.w  d1,a2
.pal:	movea.l a0,a3
	movea.l a1,a4
	moveq   #8-1,d3
.c:	cmpm.l  (a3)+,(a4)+
	dbne    d3,.c
	beq.s   .same
	movem.l (a0),d3-d7/a3-a5
	movem.l d3-d7/a3-a5,(a1)
	st      (a2)
.same:	lea     32(a0),a0
	lea     32(a1),a1
	addq.l  #1,a2
	dbra    d2,.pal
	rts

; Bulk fills (0x2bde4 / 0x2bdec clear all 1024 entries) are the only writes that
; reach the never-displayed entries 128-255: the HAL keeps a canary there (the game
; never reads them), and a changed canary means every palette changed.
PAL_CANARY      equ $80018001
hal_pal_sentinel:
	cmpi.l  #PAL_CANARY,G_PALETTE+128*2
	beq.s   .x
	move.l  #PAL_CANARY,G_PALETTE+128*2
	bra     hal_pal_alldirty
.x:	rts

hal_pal_alldirty:
	lea     HAL_PALDIRTY,a0
	lea     hal_pal_used(pc),a1
	moveq   #16-1,d0
.d:	move.l  (a1)+,(a0)+
	dbra    d0,.d
	rts

; Safety net for any write the HAL did not predict: each frame re-check one relevant
; palette against its Neo conversion; a stale one is converted and counted.
hal_pal_scrub:
	move.w  HAL_SCRUB,d2
	addq.w  #1,d2
	andi.w  #63,d2
	move.w  d2,HAL_SCRUB
	lea     hal_pal_used(pc),a0
	tst.b   (a0,d2.w)
	beq.s   .x
	lea     HAL_PALDIRTY,a0
	tst.b   (a0,d2.w)
	bne.s   .x                      ; already pending
	bsr     hal_pal_where           ; a0 = original palette, a1 = Neo palette (v0)
	ifeq DIRECT-1
	move.w  d2,d0                   ; (DIRECT: against the stage, what the commit wrote
	lsl.w   #5,d0                   ; last - not palette RAM: read during the display,
	movea.l #PAL_STG,a1             ; it took the pixel drawn, a dotted line of "snow"
	adda.w  d0,a1                   ; on the hardware and the MiSTer core, 2026-10-17)
	endif
	lea     PALTAB_MID,a2
	addq.l  #2,a1
	moveq   #15-1,d3
.c:	move.w  (a0)+,d0
	add.w   d0,d0
	move.w  (a2,d0.w),d1
	cmp.w   (a1)+,d1
	dbne    d3,.c
	bne.s   .stale
	cmpi.w  #8,d2
	bhs.s   .x
	move.w  (a0),d0                 ; tilemap 0: colour 15 lives in the variants
	add.w   d0,d0
	move.w  (a2,d0.w),d1
	ifeq DIRECT-1
	cmp.w   -32(a1),d1              ; (the stage: in its colour 0)
	else
	cmp.w   32-32+2*L0_SLOT1(a1),d1  ; a1 = v0 + 32 = v1
	endif
	beq.s   .x
.stale:	addq.l  #1,HAL_PALMISS
	bra     hal_pal_alldirty        ; an unpredicted writer: convert everything
.x:	rts

; d2 = q -> a0 = original palette q, a1 = its Neo palette (variant 0).  Clobbers d0.
hal_pal_where:
	move.w  d2,d0
	lsl.w   #3,d0
	movem.l .t(pc,d0.w),a0-a1
	rts
.t:
pq	set 0
	rept 64
	dc.l    G_PALETTE+32*pq
	if pq<8
	dc.l    PALETTES+32*(NPAL_L0+4*pq)
	else
	if pq<32
	dc.l    PALETTES+32*(NPAL_L1+pq-16)
	else
	dc.l    PALETTES+32*(NPAL_SPR+pq-32)
	endif
	endif
pq	set pq+1
	endr

	ifeq DIRECT-1
; Not cycle-exact: a fade changes every palette at once, more than the vblank converts
; (~600 cycles each).  The prep converts each dirty palette q into palette 128 + q
; (tilemap 0's colour 15 in its colour 0), the commit copies them all (~300 cycles each)
; or, no time for all, none (they wait a frame: a change is split only if it does not
; fit even then).  The stage is work RAM, not palettes 128+ (unshown): on the hardware
; and the MiSTer core a CPU access to palette RAM during the display takes the pixel
; being drawn - the staging writes, ~44 cycles apart, left a dotted line of "snow" a
; frame, moving down with the prep's timing (2026-10-17).
; HAL_PALDIRTY: 0 clean, PAL_STAGED staged, else dirty.
PAL_STG         equ G_PALSTG
PAL_STAGED      equ 2

; Every dirty palette into the stage.  Clobbers d0-d2, d6, a0-a2, a5.
hal_pal_stage:
	lea     HAL_PALDIRTY,a5
	moveq   #0,d2
.next:	tst.l   (a5)                    ; skip four clean palettes at a time
	beq.s   .sk4
	cmpi.l  #PAL_STAGED*$01010101,(a5)      ; (or four staged: a fade)
	bne.s   .chk
.sk4:	addq.l  #4,a5
	addq.w  #4,d2
	cmpi.w  #64,d2
	blo.s   .next
	rts
.chk:	moveq   #4-1,d6
.one:	move.b  (a5),d0
	beq.w   .s
	cmpi.b  #PAL_STAGED,d0
	beq.w   .s
	tst.b   HAL_PALSTT              ; (in the commit: one palette ~600 cycles, if
	beq.s   .nt                     ; there is time, else none now: the next prep's)
	bsr     hal_pal_now
	addq.w  #1,d0
	cmp.w   HAL_DEADLINE,d0
	blt.s   .nt
	st      HAL_PALSTT
	rts
.nt:	bsr     hal_pal_where           ; a0 = original palette
	move.w  d2,d0
	lsl.w   #5,d0
	movea.l #PAL_STG+2,a1
	adda.w  d0,a1
	lea     PALTAB_MID,a2
	rept 15
	move.w  (a0)+,d0
	add.w   d0,d0
	move.w  (a2,d0.w),(a1)+
	endr
	cmpi.w  #8,d2
	bhs.s   .st
	move.w  (a0),d0                 ; tilemap 0: colour 15 (its variants' slots), in
	add.w   d0,d0                   ; the stage's colour 0
	move.w  (a2,d0.w),-32(a1)
.st:	move.b  #PAL_STAGED,(a5)
.s:	addq.l  #1,a5
	addq.w  #1,d2
	dbra    d6,.one
	cmpi.w  #64,d2
	blo.w   .next
	rts

; In the real vblank, before the flip: the staged palettes where they show, all of them
; in time or none (HAL_PALFIRST: then the next commit as many as there is time for, a
; long fade must not wait for ever).  Clobbers d0-d7, a0-a6.
PAL_C           equ 300                 ; cycles a palette
	ifeq DIRECT-1
PAL_CD          equ 400                 ; (DIRECT, measured ~370) a palette copied alone
PAL_CG          equ 320                 ; and a group of four with dirty ones, its clean
                                        ; ones skipped one by one (~70 each: the copy
                                        ; ran ~2x the estimate, 2026-10-17)
	endif
PAL_C4B         equ 760                 ; (DIRECT) four staged palettes of tilemap 1 or the
                                        ; sprites at once (consecutive Neo palettes: 128
                                        ; bytes, colour 0 too - never drawn; ~600 + the
                                        ; fix layer's HUD copies)
PAL_SCANG       equ 10                  ; (DIRECT) the dirty scans' time, 16ths of a line
                                        ; a group of four with dirty ones (~9 lines for 16)
PAL_TAIL        equ 2                   ; (DIRECT) lines the commit's steps after
                                        ; hal_pal_apply take unchecked (blasts, HUD flush)
PAL_CV          equ 280                 ; more for tilemap 0's (its variants)
hal_pal_apply:
	sf      HAL_PALPART
	lea     HAL_PALDIRTY,a5         ; anything at all? (most frames: no) - the groups
	moveq   #16-1,d2                ; of four with dirty ones (the scans' time)
	moveq   #0,d1
.z:	tst.l   (a5)+
	beq.s   .z0
	addq.w  #1,d1
.z0:	dbra    d2,.z
	tst.w   d1
	beq.w   .x
	if OVR_DIAG=2
	tst.b   HAL_OUT
	beq.s   .o2
	addq.w  #1,OVD_S
.o2:
	endif
	tst.b   HAL_OUT
	bne.w   .defer
	mulu    #PAL_SCANG,d1           ; time for the scans below at all (a fade: ~9
	addi.w  #15,d1                  ; lines with no palette copied - they ran past
	lsr.w   #4,d1                   ; the deadline, 2026-10-17)
	bsr     hal_pal_now
	add.w   d1,d0
	cmp.w   HAL_DEADLINE,d0
	if OVR_DIAG=2
	blt.s   .o3
	addq.w  #1,OVD_S+2
	bra.w   .defer
.o3:
	endif
	bge.w   .defer
	move.b  #1,HAL_PALSTT           ; anything marked since the prep (normally none;
	bsr     hal_pal_stage           ; the game ran in a yielded slot: a fade's start)
	move.b  HAL_PALSTT,d0           ; staged in time, or all of them wait
	sf      HAL_PALSTT
	OVT     3
	if OVR_DIAG=2
	cmpi.b  #1,d0
	beq.s   .o4
	addq.w  #1,OVD_S+4
.o4:
	endif
	cmpi.b  #1,d0
	bne.w   .defer
	lea     HAL_PALDIRTY,a5         ; the cost (four palettes at a time)
	moveq   #0,d1
	moveq   #0,d2                   ; q
.c4:	tst.l   (a5)
	beq.s   .c40
	cmpi.l  #PAL_STAGED*$01010101,(a5)      ; (four staged: a fade, at once)
	bne.s   .c
	bsr.w   .blk
	bne.s   .c41
	addi.w  #PAL_C4B,d1             ; (copied as one block)
	bra.s   .c40
.c41:	addi.w  #4*PAL_CD,d1
	cmpi.w  #8,d2
	bhs.s   .c40
	addi.w  #4*PAL_CV,d1
.c40:	addq.l  #4,a5
	addq.w  #4,d2
	cmpi.w  #64,d2
	blo.s   .c4
	bra.s   .ct
.c:	moveq   #3,d0                   ; (a group's first: its clean ones' time)
	and.w   d2,d0
	bne.s   .c1
	addi.w  #PAL_CG,d1
.c1:	tst.b   (a5)+
	beq.s   .cn
	addi.w  #PAL_CD,d1
	cmpi.w  #8,d2
	bhs.s   .cn
	addi.w  #PAL_CV,d1
.cn:	addq.w  #1,d2
	moveq   #3,d0
	and.w   d2,d0
	bne.s   .c
	cmpi.w  #64,d2
	blo.s   .c4
.ct:
	mulu    #(65536+767)/768,d1     ; lines
	swap    d1
	bsr     hal_pal_now
	add.w   d1,d0
	if (OVR_DIAG=1)&(OVB_ON=0)
	move.w  d1,OVD_S+6              ; (diagnostics: cost, margin, decision, copied)
	move.w  d0,OVD_S+4
	move.w  HAL_DEADLINE,d2
	sub.w   d2,OVD_S+4
	moveq   #0,d2
	move.w  #1,OVD_S
	clr.w   OVD_S+2
	cmp.w   HAL_DEADLINE,d0
	blt.s   .cp
	move.w  #2,OVD_S
	tst.b   HAL_PALFIRST
	bne.s   .dg
	move.w  #3,OVD_S
.dg:
	endif
	cmp.w   HAL_DEADLINE,d0
	blt.s   .cp
	if OVR_DIAG=2
	tst.b   HAL_PALFIRST
	bne.s   .o5
	addq.w  #1,OVD_S+6
.o5:
	endif
	tst.b   HAL_PALFIRST
	beq.w   .defer
	st      HAL_PALPART             ; (waited already: as many as fit)
.cp:	lea     hal_pal_neo(pc),a2
	movea.l #PAL_STG,a0
	lea     HAL_PALDIRTY,a5
	moveq   #0,d2                   ; q
	suba.l  a3,a3                   ; 4 q
.g:	tst.l   (a5)                    ; skip four clean palettes at a time
	bne.s   .gq
.gn:	addq.l  #4,a5
	lea     4*32(a0),a0
	addq.w  #4,d2
	adda.w  #16,a3
	cmpi.w  #64,d2
	blo.s   .g
	sf      HAL_PALFIRST
.x:	rts
.gq:	tst.b   HAL_PALPART             ; four staged ones of tilemap 1 or the sprites:
	bne.w   .q                      ; one block (128 bytes) to their consecutive Neo
	cmpi.l  #PAL_STAGED*$01010101,(a5)      ; palettes
	bne.w   .q
	bsr.w   .blk
	bne.w   .q
	movea.l (a2,a3.w),a1
	movem.l (a0),d0-d1/d3-d7/a4/a6
	movem.l d0-d1/d3-d7/a4/a6,(a1)
	movem.l 36(a0),d0-d1/d3-d7/a4/a6
	movem.l d0-d1/d3-d7/a4/a6,36(a1)
	movem.l 72(a0),d0-d1/d3-d7/a4/a6
	movem.l d0-d1/d3-d7/a4/a6,72(a1)
	movem.l 108(a0),d0-d1/d3-d4/d5
	movem.l d0-d1/d3-d4/d5,108(a1)
	clr.l   (a5)
	if OVR_DIAG=1
	addq.w  #4,OVD_S+2
	endif
	cmpi.w  #48,d2                  ; (hal/fx.s) the HUD's q 48, 49 / 52, 53 also in
	beq.s   .gh                     ; the fix layer's palettes 4, 5 / 6, 7
	cmpi.w  #52,d2
	bne.w   .gn
	movea.l #PALETTES+32*6,a1
	bra.s   .gf
.gh:	movea.l #PALETTES+32*4,a1
.gf:	movem.l 2(a0),d0-d1/d3-d7       ; (colours 1-15 of both)
	movea.w 30(a0),a4
	movem.l d0-d1/d3-d7,2(a1)
	move.w  a4,30(a1)
	movem.l 34(a0),d0-d1/d3-d7
	movea.w 62(a0),a4
	movem.l d0-d1/d3-d7,34(a1)
	move.w  a4,62(a1)
	bra.w   .gn
	; Z set: palettes d2..d2+3 (d2 a multiple of 4) copied as one block: tilemap 1's
	; (q 16-23) or the sprites' (32-63).  Keeps all.
.blk:	cmpi.w  #32,d2
	bhs.s   .bz
	cmpi.w  #16,d2
	blo.s   .bn
	cmpi.w  #24,d2
	blo.s   .bz
.bn:	move.w  #0,ccr                  ; Z clear: not
	rts
.bz:	move.w  #4,ccr
	rts
.q:	tst.b   (a5)
	beq.w   .nx
	tst.b   HAL_PALPART
	beq.s   .go
	bsr     hal_pal_now
	addq.w  #1,d0
	cmp.w   HAL_DEADLINE,d0
	bge.w   .part
.go:
	if OVR_DIAG=1
	addq.w  #1,OVD_S+2
	endif
	movea.l (a2,a3.w),a1            ; (tilemap 0: variant 0)
	movem.l 2(a0),d0-d1/d3-d7       ; colours 1-14
	movea.w 30(a0),a4               ; colour 15
	movem.l d0-d1/d3-d7,2(a1)
	move.w  a4,30(a1)
	sf      (a5)
	cmpi.w  #8,d2
	bhs.s   .h
	; tilemap 0: variants 1..3 the same, colour 15 also on each one's slot
	movea.w (a0),a6
	movem.l d0-d1/d3-d7,32+2(a1)
	move.w  a4,32+30(a1)
	move.w  a6,32+2*L0_SLOT1(a1)
	movem.l d0-d1/d3-d7,64+2(a1)
	move.w  a4,64+30(a1)
	move.w  a6,64+2*L0_SLOT2(a1)
	movem.l d0-d1/d3-d7,96+2(a1)
	move.w  a4,96+30(a1)
	move.w  a6,96+2*L0_SLOT3(a1)
	bra.s   .nx
.h:	cmpi.w  #48,d2                  ; (hal/fx.s) the HUD's sprite palettes q 48, 49,
	blo.s   .nx                     ; 52, 53 also in the fix layer's palettes 4-7
	cmpi.w  #53,d2
	bhi.s   .nx
	lea     hal_pal_fix-4*48(pc),a1
	movea.l (a1,a3.w),a1
	cmpa.w  #0,a1
	beq.s   .nx
	movem.l d0-d1/d3-d7,2(a1)
	move.w  a4,30(a1)
.nx:	addq.l  #1,a5
	lea     32(a0),a0
	addq.w  #4,a3
	addq.w  #1,d2
	moveq   #3,d0
	and.w   d2,d0
	bne.w   .q
	cmpi.w  #64,d2
	blo.w   .g
	sf      HAL_PALFIRST
	rts
.part:	addq.l  #1,HAL_PALDEFER         ; (split: the rest next commit)
	bset    #0,HAL_SLIP+1
	rts
.defer:	addq.l  #1,HAL_PALDEFER
	bset    #0,HAL_SLIP+1
	st      HAL_PALFIRST
	rts

; d0 = scanlines since the slot's start (+ 2 + HAL_RESV), against HAL_DEADLINE.
hal_pal_now:
	move.w  REG_LSPCMODE,d0
	lsr.w   #7,d0
	subi.w  #$f8,d0
	sub.w   HAL_K0,d0
	bpl.s   .kp
	addi.w  #264,d0
.kp:	addq.w  #2,d0
	add.w   HAL_RESV,d0
	rts

; per q its Neo palette (tilemap 0: variant 0)
hal_pal_neo:
pq	set 0
	rept 64
	if pq<8
	dc.l    PALETTES+32*(NPAL_L0+4*pq)
	else
	if pq<32
	dc.l    PALETTES+32*(NPAL_L1+pq-16)
	else
	dc.l    PALETTES+32*(NPAL_SPR+pq-32)
	endif
	endif
pq	set pq+1
	endr
; q 48-53: its fix-layer copy (0: none)
hal_pal_fix:
	dc.l    PALETTES+32*4,PALETTES+32*5,0,0,PALETTES+32*6,PALETTES+32*7
	endif

; Convert the dirty palettes until the deadline (inside the real vblank).
hal_pal_convert:
	lea     HAL_PALDIRTY,a5
	moveq   #0,d2
.next:	tst.l   (a5)                    ; skip four clean palettes at a time
	bne.s   .chk
	addq.l  #4,a5
	addq.w  #4,d2
	cmpi.w  #64,d2
	blo.s   .next
	rts
.chk:	moveq   #4-1,d6
.one:	tst.b   (a5)
	beq.w   .clean
	tst.b   HAL_OUT                 ; budget (hal_late_n inline: 2 lines, a tilemap-0
	bne.w   .defer                  ; palette takes over one)
	move.w  REG_LSPCMODE,d0
	lsr.w   #7,d0
	subi.w  #$f8,d0
	sub.w   HAL_K0,d0
	bpl.s   .kp
	addi.w  #264,d0
.kp:	addq.w  #2,d0                   ; (a tilemap-0 palette: 3)
	cmpi.w  #8,d2
	bhs.s   .k1
	addq.w  #1,d0
.k1:	add.w   HAL_RESV,d0
	cmp.w   HAL_DEADLINE,d0
	bge.w   .late
	bsr     hal_pal_where
	lea     PALTAB_MID,a2
	addq.l  #2,a1
	rept 15
	move.w  (a0)+,d0
	add.w   d0,d0
	move.w  (a2,d0.w),(a1)+
	endr
	ifeq DIRECT-1
	; (hal/fx.s) the HUD's sprite palettes q 48, 49, 52, 53 also in the fix layer's
	; palettes 4, 5, 6, 7
	move.w  d2,d0
	subi.w  #48,d0
	cmpi.w  #5,d0
	bhi.s   .nf
	btst    #1,d0
	bne.s   .nf
	move.w  d2,d0                   ; 48, 49, 52, 53 -> 4, 5, 6, 7
	andi.w  #1,d0
	btst    #2,d2
	beq.s   .f1
	addq.w  #2,d0
.f1:	addq.w  #4,d0
	lsl.w   #5,d0
	movea.l #PALETTES+2,a3
	adda.w  d0,a3
	lea     -30(a1),a4
	rept 15
	move.w  (a4)+,(a3)+
	endr
.nf:
	endif
	cmpi.w  #8,d2
	bhs.s   .done1
	; tilemap 0: copy variant 0 to 1..3, then colour 15 onto each variant's slot
	move.w  (a0),d0
	add.w   d0,d0
	move.w  (a2,d0.w),d1
	lea     -32(a1),a3
	movem.l (a3),d0/d3-d5/a0/a2/a4/a6
	movem.l d0/d3-d5/a0/a2/a4/a6,32(a3)
	movem.l d0/d3-d5/a0/a2/a4/a6,64(a3)
	movem.l d0/d3-d5/a0/a2/a4/a6,96(a3)
	move.w  d1,32+2*L0_SLOT1(a3)
	move.w  d1,64+2*L0_SLOT2(a3)
	move.w  d1,96+2*L0_SLOT3(a3)
.done1:	sf      (a5)
.clean:	addq.l  #1,a5
	addq.w  #1,d2
	dbra    d6,.one
	cmpi.w  #64,d2
	blo.w   .next
	rts
.late:	st      HAL_OUT
.defer:	addq.l  #1,HAL_PALDEFER
	bset    #0,HAL_SLIP+1
	rts

; which original palettes are displayed at all
hal_pal_used:
	dc.b    1,1,1,1,1,1,1,1, 0,0,0,0,0,0,0,0
	dc.b    1,1,1,1,1,1,1,1, 0,0,0,0,0,0,0,0
	dcb.b   32,1
	even

; initial state: every relevant palette dirty
hal_vid_init:
	bsr     hal_bg_init
	bsr     hal_spr_init
	bsr     hal_pal_alldirty
	clr.b   HAL_FLASH_PREV
	ifeq DIRECT-1
	sf      HAL_PALFIRST
	endif
	clr.w   HAL_SCRUB
	clr.l   HAL_PALMISS
	clr.l   HAL_PALDEFER
	move.w  #$10,HAL_SLIP           ; the boot frame: calibration, no video work
	rts

	include "bg.s"
	include "spr.s"
