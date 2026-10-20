; Real-cart video: the two original tilemaps as Neo sprite columns.
;
; A tilemap (64x64 cells of 8x8) is 32x32 "blocks" of 16x16: the game writes the map
; one block at a time (0x2c924, 0x5e0c), the four cells holding w+2, w / w+3, w+1, and
; tools/gfx.py turned every such block into one Neo tile.  A block column is one Neo
; sprite 32 tiles (512 lines) high, which wraps exactly like the tilemap does, so the
; y scroll is just the sprite's y.  21 sprites per layer cover the 320-pixel screen;
; each "slot" shows one block column and is re-assigned when the coarse x scroll moves
; (only the columns entering the screen are converted).
;
; Conversions go through a RAM buffer per slot (G_BGBUF, the column's 32 SCB1 pairs),
; so they can run at any time of the slot (idle time before the real vblank); the
; real vblank only copies the buffers that changed (hal_bg_blast, ~1 line each).
;
; Change detection: a shadow of every block's w (HAL scratch RAM) is compared with the
; tilemap a few columns per frame; a stale column is reconverted and verification
; speeds up for a while (the game redraws whole screens at scene changes).
;
; Cells that are not part of a block (text written one character at a time by
; 0x129e on tilemap 1) are drawn on the fix layer while tilemap 1 is 8-pixel aligned.
;
; Sprite numbers (draw order): tilemap 0 at SPR_L0.., tilemap 1 at SPR_L1..; the
; original's sprites go in between / above (step 4).

BG_COLS         equ 21
SPR_L0          equ 1
SPR_L1          equ 22              ; (sprite sets above it: hal/spr.s)
VIS_ROWS        equ 15              ; block rows covering the 224 visible lines
COL_LINES       equ 10              ; scanlines to start a column: fix clear (~2.5) + 2 block rows
ROWS2_LINES     equ 7               ; 2 block rows: <= 2 fix-layer blocks, each up to ~2470
                                    ; cycles with all four cells drawn (hal_bg_odd ~550 + four
                                    ; cells of ~420 + ~250; traced 2026-10-11, staff screens)
SCRUB_LINES     equ 10              ; scanlines one verification may take (tilemap 1: ~200 cycles a row)
SCRUB_SLOW      equ 2               ; columns verified per frame
SCRUB_FAST      equ 6               ; ... after a stale column was found
BURST_FRAMES    equ 12
BG_CAP          equ 3               ; (BG_CUTCAP) columns of a cleared layer converted a slot

BG_SHADOW       equ G_HALSCRATCH    ; 2 layers x 32 columns x 32 words

; d0 = hash of the four cells of the block at a0 (TL); clobbers d1.  Shadow value for
; columns holding cells that are not game blocks (the top-right cell alone does not
; show changes there).
; (all tilemap-1 shadows hold this hash; tilemap 0 keeps the cheaper top-right cell)
BLKHASH	macro                           ; ~56 cycles, order-sensitive
	move.w  (a0),d0
	add.w   d0,d0
	add.w   2(a0),d0
	add.w   d0,d0
	add.w   128(a0),d0
	add.w   d0,d0
	add.w   130(a0),d0
	endm

; ================================================================ prep (no VRAM writes)
hal_bg_prep:
	moveq   #0,d7
	bsr.w   hal_bg_window
	moveq   #1,d7
	bsr.w   hal_bg_window
	bsr.w   hal_bg_banks
	ifeq DIRECT-1
	jmp     tm_apply                ; (hal/tm.s: the writers mark what they change)
	else
	bra.w   hal_bg_sample           ; (column verification: hal_vid_early)
	endif

; ================================================================ change watch
; The tilemaps are polled, so a change is only seen once something compares it:
;   * tile banks (G_GFXBANK, 4 per layer) every slot: a change re-maps every tile
;     of the layer without a single tilemap write;
;   * half a visible block row of one layer every slot (hal_bg_sample): a
;     whole-screen redraw is caught at once, any visible block within SAMP_N slots;
;   * whole columns, in view or not, in the time left (hal_bg_scrub1).
; A stale find reconverts the layer.  The frames it may already have been shown
; wrong in (since the last check that found it right) are logged afterwards as a
; slip range: HAL_BG_RETROF .. the detecting slot (HAL_BG_RETRON counts them), and
; the slot's HAL_SLIP gets the tilemap bit.

SAMP_N          equ 4*VIS_ROWS          ; half a visible block row per slot
SAMP_COLS       equ (BG_COLS+1)/2       ; (the halves share their middle column)

; d7 = layer whose conversion is stale, d0 = first slot (HAL_FRAMES) that may have
; shown it wrong.  Reconverts the whole layer (visible changes are almost always
; whole-screen redraws) and verifies fast for a while.  Clobbers d0, a0.
hal_bg_layer_stale:
	addq.l  #1,HAL_BGMISS
	move.w  #BURST_FRAMES,HAL_BG_BURST
	cmp.w   HAL_FRAMES+2,d0         ; (changed only since the last slot: not shown yet;
	bpl.s   .nr                     ; slot numbers compare modulo 65536)
	tst.b   HAL_BG_RETROP           ; a range not logged yet: it starts at the earlier
	beq.s   .rf                     ; of the two
	cmp.w   HAL_BG_RETROF,d0
	bpl.s   .rn
.rf:	move.w  d0,HAL_BG_RETROF
.rn:
	addq.l  #1,HAL_BG_RETRON
	st      HAL_BG_RETROP
.nr:	lea     HAL_BG_PEND,a0
	move.w  d7,d0
	lsl.w   #5,d0
	adda.w  d0,a0
	moveq   #BG_COLS-1,d0
	st      HAL_BG_WORK
.all:	st      (a0)                    ; (one already converting starts again: the
	sf      HAL_BG_LOW-HAL_BG_PEND(a0)  ; rows it did may be stale; conversion goes
	sf      HAL_BG_ROW-HAL_BG_PEND(a0)  ; column by column, so little is lost)
	addq.l  #1,a0
	dbra    d0,.all
	rts

; Tile banks: a layer whose banks changed since the last slot is reconverted.
hal_bg_banks:
	moveq   #0,d7
	bsr.s   .l
	moveq   #1,d7
.l:	move.w  d7,d0
	lsl.w   #2,d0
	lea     G_GFXBANK,a0
	move.l  (a0,d0.w),d1
	lea     HAL_BG_BANK,a0
	cmp.l   (a0,d0.w),d1
	beq.s   .x
	move.l  d1,(a0,d0.w)
	move.w  HAL_FRAMES+2,d0
	bra.w   hal_bg_layer_stale
.x:	rts

; Half a visible block row of one layer against the shadow: sample i (0 .. SAMP_N-1)
; is layer i & 1, half (i >> 1) & 1, visible block row i >> 2.  Slots being
; converted are left out.
hal_bg_sample:
	sf      HAL_BG_SKIP
	move.w  HAL_BG_SAMP,d6
	move.w  d6,d2
	addq.w  #1,d2
	cmpi.w  #SAMP_N,d2
	blo.s   .s
	moveq   #0,d2
.s:	move.w  d2,HAL_BG_SAMP
	moveq   #1,d7
	and.w   d6,d7                   ; layer
	move.w  d6,d3
	lsr.w   #2,d3                   ; visible block row
	moveq   #0,d2                   ; first window column of the half
	btst    #1,d6
	beq.s   .h0
	moveq   #BG_COLS-SAMP_COLS,d2
.h0:	move.w  d7,d0
	add.w   d0,d0
	lea     HAL_BG_C0,a0
	move.w  (a0,d0.w),d4            ; first visible block column (-1: none yet)
	bmi.w   .ok
	lea     HAL_BG_SY,a0
	move.w  (a0,d0.w),d1
	bmi.w   .ok
	add.w   d2,d4
	andi.w  #31,d4                  ; first column of the half
	lsr.w   #4,d1
	add.w   d3,d1
	andi.w  #31,d1                  ; block row
	move.w  d2,-(sp)
	bsr     hal_bg_colptr           ; a0 = tilemap TR, block row 0, a1 = its shadow
	move.w  (sp)+,d2
	move.w  d1,d0
	lsl.w   #8,d0
	adda.w  d0,a0
	adda.w  d1,a1
	adda.w  d1,a1
	tst.w   d7
	beq.s   .t0
	subq.l  #2,a0                   ; tilemap 1: hashed shadow (TL based)
.t0:	tst.b   HAL_BG_WORK
	bne.w   .slow
	; nothing being converted: the columns up to the map's wrap, then the rest
	moveq   #32,d5
	sub.w   d4,d5                   ; columns before the wrap
	moveq   #SAMP_COLS,d3
	cmp.w   d3,d5
	bls.s   .w1
	move.w  d3,d5
.w1:	sub.w   d5,d3                   ; columns after it
	subq.w  #1,d5
	bsr.s   .run
	bne.s   .stale
	lea     -128(a0),a0
	lea     -2048(a1),a1
	move.w  d3,d5
	subq.w  #1,d5
	bmi.s   .ok
	bsr.s   .run
	bne.s   .stale
.ok:	tst.b   HAL_BG_SKIP             ; (a slot left out: not checked, a stale find
	bne.s   .okx                    ; later must reach back past now)
	lea     HAL_BG_SAMPF,a0         ; this row checked right now
	add.w   d6,d6
	move.w  HAL_FRAMES+2,(a0,d6.w)
.okx:	rts
.stale:	lea     HAL_BG_SAMPF,a0         ; wrong since its last check at most
	add.w   d6,d6
	move.w  (a0,d6.w),d0
	addq.w  #1,d0
	move.w  HAL_FRAMES+2,(a0,d6.w)
	bra.w   hal_bg_layer_stale
	; d5 + 1 blocks from a0 / a1 on: Z clear at the first difference
.run:	tst.w   d7
	bne.s   .r1
.r0:	move.w  (a0),d0                 ; tilemap 0: top-right cell
	cmp.w   (a1),d0
	bne.s   .rx
	addq.l  #4,a0
	lea     64(a1),a1
	dbra    d5,.r0
.rx:	rts
.r1:	BLKHASH                         ; tilemap 1: hash of the four cells
	cmp.w   (a1),d0
	bne.s   .rx
	addq.l  #4,a0
	lea     64(a1),a1
	dbra    d5,.r1
	rts
	; some slots being converted: those are left out
.slow:	lea     HAL_BG_R,a2
	moveq   #0,d5
	move.b  (a2,d7.w),d5
	add.w   d2,d5                   ; slot of column d4
	cmpi.w  #BG_COLS,d5
	blo.s   .sl
	subi.w  #BG_COLS,d5
.sl:	lea     HAL_BG_PEND,a2
	lea     HAL_BG_LOW,a3
	lea     HAL_BG_ROW,a4
	move.w  d7,d0
	lsl.w   #5,d0
	adda.w  d0,a2
	adda.w  d0,a3
	adda.w  d0,a4
	moveq   #SAMP_COLS,d3           ; blocks left
	; runs up to the map's column wrap / the slot wrap, whichever comes first
.seg:	moveq   #32,d2
	sub.w   d4,d2
	moveq   #BG_COLS,d0
	sub.w   d5,d0
	cmp.w   d0,d2
	bls.s   .m1
	move.w  d0,d2
.m1:	cmp.w   d3,d2
	bls.s   .m2
	move.w  d3,d2
.m2:	sub.w   d2,d3
	add.w   d2,d4
	subq.w  #1,d2
	tst.w   d7
	bne.s   .l1
	; tilemap 0: top-right cell.  A slot being converted is left out; one with
	; rows out of view left counts if this conversion did the row (HAL_BG_R0 on,
	; HAL_BG_ROW rows)
.l0:	tst.b   (a2,d5.w)
	bne.s   .k0
	tst.b   (a3,d5.w)
	beq.s   .c0
	move.w  d1,d0
	sub.b   HAL_BG_R0-HAL_BG_LOW(a3,d5.w),d0
	andi.w  #31,d0
	cmp.b   (a4,d5.w),d0
	bhs.s   .k0
.c0:	move.w  (a0),d0
	cmp.w   (a1),d0
	bne.w   .stale
	bra.s   .x0
.k0:	st      HAL_BG_SKIP
.x0:	addq.w  #1,d5
	addq.l  #4,a0
	lea     64(a1),a1
	dbra    d2,.l0
	bra.s   .es
	; tilemap 1: hash of the four cells
.l1:	tst.b   (a2,d5.w)
	bne.s   .k1
	tst.b   (a3,d5.w)
	beq.s   .c1
	move.w  d1,d0
	sub.b   HAL_BG_R0-HAL_BG_LOW(a3,d5.w),d0
	andi.w  #31,d0
	cmp.b   (a4,d5.w),d0
	bhs.s   .k1
.c1:	BLKHASH
	cmp.w   (a1),d0
	bne.w   .stale
	bra.s   .x1
.k1:	st      HAL_BG_SKIP
.x1:	addq.w  #1,d5
	addq.l  #4,a0
	lea     64(a1),a1
	dbra    d2,.l1
.es:	cmpi.w  #32,d4
	blo.s   .e1
	moveq   #0,d4
	lea     -128(a0),a0
	lea     -2048(a1),a1
.e1:	cmpi.w  #BG_COLS,d5
	blo.s   .e2
	moveq   #0,d5
.e2:	tst.w   d3
	bne.w   .seg
	bra.w   .ok

; d7 = layer.  Track the scroll; re-assign slots when the first visible column moves.
hal_bg_window:
	bsr     hal_bg_scroll           ; d0 = sx, d1 = sy
	move.w  d7,d2
	add.w   d2,d2
	lea     HAL_BG_POS,a1
	lea     HAL_BG_SX,a0
	cmp.w   (a0,d2.w),d0
	beq.w   .sxs
	bset    #0,(a1,d7.w)
	bsr.w   .fixmv
.sxs:	lea     HAL_BG_SY,a0
	cmp.w   (a0,d2.w),d1
	beq.w   .same
	bset    #1,(a1,d7.w)
	bsr.w   .fixmv
	move.w  d7,d3                   ; rows that were left for later may come into view
	lsl.w   #5,d3
	lea     HAL_BG_LOW,a0
	adda.w  d3,a0
	moveq   #BG_COLS-1,d3
.pr:	tst.b   (a0)+
	beq.w   .pn
	sf      -1(a0)
	st      HAL_BG_PEND-HAL_BG_LOW-1(a0)
	st      HAL_BG_WORK
.pn:	dbra    d3,.pr
	bra.w   .same
.fixmv:	tst.w   d7                      ; tilemap 1 moved under fix-layer text: redo it
	beq.w   .fx
	tst.w   HAL_FIXUSED
	beq.w   .fx
	clr.w   HAL_FIXCLR              ; clear the fix layer, then reconvert tilemap 1
	lea     HAL_BG_PEND+32,a0       ; every tilemap-1 slot: again from row 0
	moveq   #BG_COLS-1,d3
	st      HAL_BG_WORK
.fp:	st      (a0)
	sf      HAL_BG_LOW-HAL_BG_PEND(a0)
	sf      HAL_BG_ROW-HAL_BG_PEND(a0)
	addq.l  #1,a0
	dbra    d3,.fp
.fx:	rts
.same:	lsr.w   #4,d0                   ; c0
	lea     HAL_BG_C0,a0
	move.w  (a0,d2.w),d1
	cmp.w   d1,d0
	beq.w   .x
	move.w  d0,(a0,d2.w)
	lea     HAL_BG_POS,a0
	move.b  #7,(a0,d7.w)            ; slots change: rewrite y and x, heads
	; slot of window column k: (R + k) mod 21, R following the columns as they
	; scroll (a kept column keeps its slot, one entering takes the one leaving's)
	lea     HAL_BG_R,a0
	moveq   #0,d3
	tst.w   d1
	bmi.s   .r1                     ; (first time: any)
	move.b  (a0,d7.w),d3
	sub.w   d1,d0                   ; columns moved: -16..15
	addi.w  #16,d0
	andi.w  #31,d0
	subi.w  #16,d0
	add.w   d0,d3
	bpl.s   .r0
	addi.w  #BG_COLS,d3
.r0:	cmpi.w  #BG_COLS,d3
	blo.s   .r1
	subi.w  #BG_COLS,d3
.r1:	move.b  d3,(a0,d7.w)
	move.w  (HAL_BG_C0-HAL_BG_R,a0,d2.w),d0
	move.w  d7,d1
	lsl.w   #5,d1
	lea     HAL_BG_SLOTCOL,a1
	adda.w  d1,a1                   ; slot -> column
	lea     HAL_BG_COLSLOT,a2
	adda.w  d1,a2                   ; column -> slot
	lea     HAL_BG_PEND,a3
	adda.w  d1,a3
	lea     G_BGSTG,a4
	adda.w  d1,a4
	moveq   #BG_COLS-1,d4
.k:	andi.w  #31,d0                  ; d0 = column, d3 = its slot
	moveq   #0,d5
	move.b  (a1,d3.w),d5
	cmp.b   d0,d5
	beq.w   .kn                     ; shown there already
	tst.b   d5
	bmi.s   .kf
	cmp.b   (a2,d5.w),d3            ; (the old column may have moved elsewhere)
	bne.s   .kf
	st      (a2,d5.w)
.kf:	move.b  d0,(a1,d3.w)
	move.b  d3,(a2,d0.w)
	st      (a3,d3.w)               ; convert it, from block row 0
	sf      (a4,d3.w)               ; (the buffer was for the old column)
	lea     HAL_BG_ROW-HAL_BG_PEND(a3),a0
	sf      (a0,d3.w)
	lea     HAL_BG_LOW-HAL_BG_PEND(a3),a0
	sf      (a0,d3.w)
	st      HAL_BG_WORK
.kn:	addq.w  #1,d0
	addq.w  #1,d3
	cmpi.w  #BG_COLS,d3
	blo.s   .kw
	moveq   #0,d3
.kw:	dbra    d4,.k
.x:	rts

; d7 = layer -> d0 = x scroll, d1 = y scroll (0..511), as the original draws them
hal_bg_scroll:
	tst.w   d7
	bne.w   .l1
	move.w  G_SCROLLX0,d0
	subi.w  #18,d0
	move.w  G_SCROLLY0,d1
	bra.w   .m
.l1:	move.w  G_SCROLLX1,d0
	subi.w  #20,d0
	move.w  G_SCROLLY1,d1
.m:	andi.w  #511,d0
	andi.w  #511,d1
	rts

; Verify a few slots against the tilemap (top-right cell of each block).
hal_bg_scrub:
	ifne BG_CUTCAP
	tst.b   HAL_BG_CAPN             ; (BG_CUTCAP) a cleared layer reconverting: no
	bne.w   .stop                   ; verification (its burst - 6 columns a frame for 12
	endif                           ; frames - was the cut's lost frames, AUDIT 40)
	moveq   #SCRUB_SLOW-1,d6
	tst.w   HAL_BG_BURST
	beq.w   .n
	subq.w  #1,HAL_BG_BURST
	moveq   #SCRUB_FAST-1,d6
.n:	bsr     hal_vpos                ; before the real vblank only: commit time
	sub.w   HAL_PROBE_VPOS,d0
	bpl.w   .ep
	addi.w  #264,d0
.ep:	cmpi.w  #240-PHASE_LINE-2,d0
	bhs.w   .stop
	move.w  d6,-(sp)
	bsr     hal_bg_scrub1
	move.w  (sp)+,d6
	dbra    d6,.n
.stop:	rts

; After the commit: keep verifying while time is left (one full pass at most).
hal_bg_scrub_more:
	moveq   #2*BG_COLS-1,d6
.n:	moveq   #SCRUB_LINES,d0
	bsr     hal_late_n
	bne.w   .x
	move.w  d6,-(sp)
	bsr     hal_bg_scrub1
	move.w  (sp)+,d6
	dbra    d6,.n
.x:	rts

; Verify the next slot that is not being converted.  Clobbers d0-d5, d7, a0-a3.
hal_bg_scrub1:
	moveq   #2*BG_COLS-1,d5         ; find the next slot that can be verified
.f:	move.w  HAL_BG_SCRUB,d2
	addq.w  #1,d2
	moveq   #31,d3
	and.w   d2,d3
	cmpi.w  #BG_COLS,d3
	blo.w   .v
	andi.w  #32,d2                  ; past the last slot of a layer: next layer
	addi.w  #32,d2
.v:	andi.w  #63,d2
	move.w  d2,HAL_BG_SCRUB
	lea     HAL_BG_PEND,a0
	tst.b   (a0,d2.w)
	beq.w   .cand
	dbra    d5,.f
	rts                             ; everything is pending
.cand:
	lea     HAL_BG_SLOTCOL,a0
	moveq   #0,d4
	move.b  (a0,d2.w),d4            ; column
	bmi.w   .nx
	moveq   #32,d5                  ; rows converted: all, or (rows out of view still
	lea     HAL_BG_LOW,a0           ; pending) those done so far from the start row
	tst.b   (a0,d2.w)
	beq.w   .full
	lea     HAL_BG_ROW,a0
	move.b  (a0,d2.w),d5
.full:	lea     HAL_BG_R0,a0
	moveq   #0,d3
	move.b  (a0,d2.w),d3
	move.w  d2,d7
	lsr.w   #5,d7                   ; layer
	bsr     hal_bg_colptr           ; a0 = tilemap TR of block row 0, a1 = shadow
	tst.w   d7
	beq.w   .tr
	subq.l  #2,a0                   ; tilemap 1: hashed shadow (TL based)
.tr:	movea.l a0,a2
	movea.l a1,a3
	move.w  d3,d0
	lsl.w   #8,d0
	adda.w  d0,a0
	adda.w  d3,a1
	adda.w  d3,a1
	subq.w  #1,d5
	addq.l  #1,HAL_DBG_SCRUBN
	tst.w   d7
	bne.w   .hl
.tl:	move.w  (a0),d0                 ; tilemap 0: top-right cell
	cmp.w   (a1)+,d0
	bne.w   .stale
	bsr.w   .adv
	dbra    d5,.tl
	bra.w   .nx
.hl:	BLKHASH                         ; tilemap 1: hash of the four cells
	cmp.w   (a1)+,d0
	bne.w   .stale
	bsr.w   .adv
	dbra    d5,.hl
	bra.w   .nx
.adv:	lea     256(a0),a0              ; next block row, wrapping at 32
	addq.w  #1,d3
	cmpi.w  #32,d3
	bne.w   .ar
	moveq   #0,d3
	movea.l a2,a0
	movea.l a3,a1
.ar:	rts
.stale:	lea     HAL_BG_SAMPF,a0         ; shown wrong (if in view) since the layer's oldest
	adda.w  d7,a0                   ; visible check at most
	adda.w  d7,a0
	move.w  HAL_FRAMES+2,d0
	moveq   #SAMP_N/2-1,d1
.mn:	move.w  (a0),d3
	sub.w   d0,d3
	bpl.s   .mo
	move.w  (a0),d0
.mo:	addq.l  #4,a0
	dbra    d1,.mn
	addq.w  #1,d0
	bra.w   hal_bg_layer_stale
.nx:	rts


; d7 = layer, d4 = block column -> a0 = tilemap cell (row 0, col 2c+1), a1 = shadow column
hal_bg_colptr:
	lea     G_VRAM0+2,a0
	lea     BG_SHADOW,a1
	tst.w   d7
	beq.w   .c
	lea     G_VRAM1+2,a0
	lea     BG_SHADOW+$800,a1
.c:	move.w  d4,d0
	lsl.w   #2,d0
	adda.w  d0,a0
	lsl.w   #4,d0
	adda.w  d0,a1
	rts

; ================================================================ commit
; Sprite positions (always, they are cheap); conversions later, under the deadline.
hal_bg_place:
	ifne BG_SETSCR
	bsr.w   hal_bg_hist             ; (BG_SETSCR) this slot's scroll on the history
	endif
	moveq   #0,d7
	bsr.w   .lay
	ifeq DIRECT-1
	jmp     hal_bg_l1place          ; (hal/tx.s: tilemap 1's columns hidden when empty)
	else
	moveq   #1,d7
	endif
.lay:	lea     HAL_BG_POS,a0
	ifne BG_HIDECLR
	lea     HAL_BG_HID,a1           ; (BG_HIDECLR) hidden since the game cleared it: shown
	tst.b   (a1,d7.w)               ; again once every column is converted (HAL_BG_PEND)
	beq.s   .nh                     ; and blasted (G_BGSTG) - bit 3: the heads written
	move.w  d7,d0
	lsl.w   #5,d0
	lea     HAL_BG_PEND,a1
	adda.w  d0,a1
	lea     G_BGSTG,a2
	adda.w  d0,a2
	moveq   #32/4-1,d1
.hs:	tst.l   (a1)+
	bne.s   .nh
	tst.l   (a2)+
	dbne    d1,.hs
	bne.s   .nh
	lea     HAL_BG_HID,a1
	sf      (a1,d7.w)
	bset    #3,(a0,d7.w)
.nh:
	endif
	move.b  (a0,d7.w),d4            ; bit 0: x moved, 1: y moved, 2: slots changed (3:
	ifeq BG_SETSCR                  ; BG_HIDECLR, hidden or shown again: the heads)
	beq.w   .x
	endif
	sf      (a0,d7.w)
	ifne BG_SCRRING
	bsr.w   hal_bg_scrcur           ; (BG_SCRRING: this slot's scroll from the ring)
	else
	bsr     hal_bg_scroll
	endif
	move.w  d7,d2
	add.w   d2,d2
	ifne BG_SETSCR
	bsr.w   hal_bg_held             ; (BG_SETSCR) the shown set's slot's scroll instead,
	lea     HAL_BG_SX,a0            ; when it is late; moved against what is placed
	cmp.w   (a0,d2.w),d0
	beq.s   .mx
	bset    #0,d4
.mx:	lea     HAL_BG_SY,a0
	cmp.w   (a0,d2.w),d1
	beq.s   .my
	bset    #1,d4
.my:	tst.b   d4
	beq.w   .x
	endif
	lea     HAL_BG_SX,a0
	move.w  d0,(a0,d2.w)
	lea     HAL_BG_SY,a0
	move.w  d1,(a0,d2.w)
	move.w  #1,REG_VRAMMOD
	lea     REG_VRAMADDR,a3
	lea     REG_VRAMRW,a2
	move.w  #SPR_L0,d3
	tst.w   d7
	beq.s   .s
	move.w  #SPR_L1,d3
.s:	lea     HAL_BG_R,a0
	moveq   #0,d6
	move.b  (a0,d7.w),d6            ; R: slot of the first column
	; the slots are two chains in screen order: R..20 and 0..R-1, so only their
	; first sprites (slots R and 0) carry y, height and x
	btst    #2,d4
	beq.s   .y
	move.w  d3,d5                   ; slots changed: every slot chained ...
	addi.w  #SCB3,d5
	move.w  d5,(a3)
	rept BG_COLS
	move.w  #$40,(a2)               ; (12 cycles: VRAM writes 8 apart lose one)
	endr
	moveq   #3,d4                   ; ... then the heads
.y:
	ifne BG_HIDECLR
	btst    #3,d4
	beq.s   .y3
	bset    #1,d4
.y3:
	endif
	btst    #1,d4
	beq.s   .xo
	move.w  #496,d5                 ; SCB3: y, 32 tiles high
	add.w   d1,d5
	andi.w  #511,d5
	lsl.w   #7,d5
	ifne BG_HIDECLR
	lea     HAL_BG_HID,a0
	tst.b   (a0,d7.w)               ; (hidden: no tiles)
	bne.s   .yh
	endif
	ori.w   #32,d5
.yh:
	move.w  d3,d1
	addi.w  #SCB3,d1
	move.w  d1,(a3)
	move.w  d5,(a2)
	tst.w   d6
	beq.s   .xo
	add.w   d6,d1
	move.w  d1,(a3)
	move.w  d5,(a2)
.xo:	btst    #0,d4
	beq.s   .x
	lea     HAL_BG_C0,a0            ; x word of the first column: (c0 << 11) - (sx << 7)
	move.w  (a0,d2.w),d1
	ror.w   #5,d1
	lsl.w   #7,d0
	sub.w   d0,d1
	addi.w  #SCB4,d3
	move.w  d3,d0
	add.w   d6,d0
	move.w  d0,(a3)
	move.w  d1,(a2)
	tst.w   d6
	beq.s   .x
	moveq   #BG_COLS,d0             ; slot 0: 21 - R columns further right
	sub.w   d6,d0
	ror.w   #5,d0
	add.w   d0,d1
	move.w  d3,(a3)
	move.w  d1,(a2)
.x:	rts

	ifne BG_SETSCR
; (BG_SETSCR) The scroll of this slot on the history: HAL_SCRH holds this slot's and
; the two before (sx0, sy0, sx1, sy1 each).  Clobbers d0, d1, d7, a1.
hal_bg_hist:
	ifne BG_SCRRING
	moveq   #0,d0                   ; (BG_SCRRING) a ring of three: the entry HAL_SCRI
	move.b  HAL_SCRI,d0
	addq.b  #1,d0
	cmpi.b  #3,d0
	blo.s   .k
	moveq   #0,d0
.k:	move.b  d0,HAL_SCRI
	lsl.w   #3,d0
	lea     HAL_SCRH,a1
	adda.w  d0,a1
	else
	lea     HAL_SCRH,a1
	move.l  8(a1),16(a1)
	move.l  12(a1),20(a1)
	move.l  (a1),8(a1)
	move.l  4(a1),12(a1)
	endif
	moveq   #0,d7
	bsr.w   hal_bg_scroll
	move.w  d0,(a1)
	move.w  d1,2(a1)
	moveq   #1,d7
	bsr.w   hal_bg_scroll
	move.w  d0,4(a1)
	move.w  d1,6(a1)
	rts

	ifne BG_SCRRING
; (BG_SCRRING) d7 = layer -> d0/d1 = this slot's scroll, from the ring's current entry
; (hal_bg_hist ran at the commit's start).  Clobbers a1.
hal_bg_scrcur:
	moveq   #0,d0
	move.b  HAL_SCRI,d0
	lsl.w   #3,d0
	lea     HAL_SCRH,a1
	adda.w  d0,a1
	move.w  d7,d0
	lsl.w   #2,d0
	move.w  2(a1,d0.w),d1
	move.w  (a1,d0.w),d0
	rts
	endif

; (BG_SETSCR) d7 = layer, d0/d1 = this slot's scroll -> the scroll of the slot the
; shown sprite set was due in (HAL_SPR_RDY), when the set is late by one or two slots
; and that scroll is within 3 pixels on both axes (a cut keeps this slot's: the columns
; were assigned for it).  The sprites were composed with their slot's scroll: shown
; late, they lagged the tilemaps by it - a 1-pixel wobble of every ground sprite on a
; tenth of the frames (the buildings).  Keeps all but d0, d1.
hal_bg_held:
	movem.l d2-d3/a1,-(sp)
	move.w  HAL_SPR_SHOWN,d2
	bmi.s   .x
	add.w   d2,d2
	lea     HAL_SPR_RDY,a1
	move.w  HAL_FRAMES+2,d3
	sub.w   (a1,d2.w),d3            ; late by
	beq.s   .x
	cmpi.w  #2,d3
	bhi.s   .x
	ifne BG_SCRRING
	moveq   #0,d2                   ; the entry: HAL_SCRI - late, mod 3
	move.b  HAL_SCRI,d2
	sub.w   d3,d2
	bpl.s   .e
	addq.w  #3,d2
.e:	lsl.w   #3,d2
	lea     HAL_SCRH,a1
	adda.w  d2,a1
	else
	lsl.w   #3,d3                   ; the entry: 8 bytes a slot
	lea     HAL_SCRH,a1
	adda.w  d3,a1
	endif
	move.w  d7,d2
	lsl.w   #2,d2
	adda.w  d2,a1                   ; the layer's pair
	move.w  (a1),d2
	sub.w   d0,d2
	addq.w  #3,d2
	cmpi.w  #6,d2
	bhi.s   .x
	move.w  2(a1),d2
	sub.w   d1,d2
	addq.w  #3,d2
	cmpi.w  #6,d2
	bhi.s   .x
	move.w  (a1),d0
	move.w  2(a1),d1
.x:	movem.l (sp)+,d2-d3/a1
	rts
	endif

; Convert pending slots until the deadline.
hal_bg_convert:
	tst.b   HAL_OUT                 ; out of time: a slip only for the rows in view
	bne.w   .out                    ; (pass 1 runs first: what it left is counted)
	tst.b   HAL_BG_WORK             ; anything to do at all?
	beq.s   .none
	bsr     hal_late                ; (the scans take up to ~1.2 lines)
	bne.w   .out
	lea     HAL_BG_PEND,a0
	moveq   #64/4-1,d0
.any:	tst.l   (a0)+
	dbne    d0,.any
	bne.s   .some
	tst.b   HAL_BG_P1
	bne.s   .none
	lea     HAL_BG_LOW,a0
	moveq   #64/4-1,d0
.anl:	tst.l   (a0)+
	dbne    d0,.anl
	bne.s   .some
	sf      HAL_BG_WORK             ; (none set: no scan until one is)
.none:	tst.w   HAL_FIXUSED
	beq.s   .done
	cmpi.w  #40,HAL_FIXCLR
	blo.s   .some
.done:	moveq   #0,d0
	rts
.some:	bsr     hal_late                ; (the scans below are not free)
	bne.w   .late
	tst.w   HAL_FIXUSED
	beq.w   .nofix
	cmpi.w  #40,HAL_FIXCLR
	bhs.w   .nofix
	bsr     hal_fix_clear           ; finish clearing stale text first
	bne.w   .late
.nofix:	lea     HAL_BG_PEND,a5          ; pass 1: what is on screen
	bsr.w   .pass
	bne.w   .late
	tst.b   HAL_BG_P1               ; (pass 1 only)
	bne.s   .p1
	lea     HAL_BG_LOW,a5           ; pass 2: rows out of view, if time is left
	bsr.w   .pass                   ; (not a slip when it stops: they come back to
	bne.w   .le                     ; pass 1 when they scroll into view)
.p1:	moveq   #0,d0
	rts

; a5 = flag array to work on (PEND or LOW).  Z clear when the deadline stopped it.
.pass:	moveq   #0,d2
.q:	tst.l   (a5,d2.w)               ; skip four idle slots at a time
	bne.w   .n
	addq.w  #4,d2
	cmpi.w  #64,d2
	blo.w   .q
	moveq   #0,d0
	rts
.n:	tst.b   (a5,d2.w)
	beq.w   .nx
	ifne BG_CUTCAP
	tst.b   HAL_BG_CAPN             ; (BG_CUTCAP) a cleared layer's columns: BG_CAP a slot
	beq.s   .ncap                   ; (the layer is hidden, BG_HIDECLR: no deadline; the
	move.w  HAL_FRAMES+2,d0         ; game keeps its frames - 6 lost a cut before)
	cmp.w   HAL_BG_CAPF,d0
	beq.s   .cs
	move.w  d0,HAL_BG_CAPF
	clr.b   HAL_BG_CAPS
.cs:	cmpi.b  #BG_CAP,HAL_BG_CAPS
	bhs.w   .capped
	addq.b  #1,HAL_BG_CAPS
	subq.b  #1,HAL_BG_CAPN
.ncap:
	endif
	moveq   #COL_LINES,d0
	bsr     hal_late_n
	bne.w   .stop
	movem.l d2/a5,-(sp)
	bsr     hal_bg_column           ; d0: 0 done, 1 deadline, 2 rows in view done
	movem.l (sp)+,d2/a5
	tst.w   d0
	beq.w   .fin
	cmpi.w  #2,d0
	bne.w   .stop
	sf      (a5,d2.w)               ; the rest is low priority
	lea     HAL_BG_LOW,a0
	st      (a0,d2.w)
	bra.w   .nx
.fin:	sf      (a5,d2.w)
.nx:	addq.w  #1,d2
	moveq   #3,d0
	and.w   d2,d0
	bne.w   .n
	cmpi.w  #64,d2
	blo.w   .q
	moveq   #0,d0
	rts
.stop:	moveq   #1,d0
	rts
	ifne BG_CUTCAP
.capped:
	moveq   #0,d0                   ; (as done: the pending flags stay for the next slot)
	rts
	endif
.late:	tst.b   HAL_BG_EARLY            ; (before the real vblank: the commit goes on)
	bne.s   .le
	addq.l  #1,HAL_BGDEFER
	bset    #1,HAL_SLIP+1
.le:	moveq   #1,d0                   ; Z clear: not done
	rts
.out:	tst.b   HAL_BG_P1
	bne.s   .late
	bra.s   .le

; Clear fix-layer columns HAL_FIXCLR..39 (stale text), stopping at the deadline.
; Z clear on return when the deadline stopped it.
hal_fix_clear:
.c:	bsr     hal_late
	bne.w   .x
	move.w  HAL_FIXCLR,d0
	lsl.w   #5,d0
	addi.w  #FIXMAP,d0
	move.w  d0,REG_VRAMADDR
	lea     REG_VRAMRW,a0
	rept 32
	move.w  #0,(a0)
	endr
	addq.w  #1,HAL_FIXCLR
	cmpi.w  #40,HAL_FIXCLR
	blo.w   .c
	clr.w   HAL_FIXUSED
	move.w  #4,ccr
.x:	rts

; d2 = layer*32 + slot: convert its block column into the sprite's SCB1 + shadow.
; Rows go visible-first: from the first visible block row (fixed per conversion in
; HAL_BG_R0), wrapping; HAL_BG_ROW counts the rows done when the deadline stops it.
; Z set on return when the column is complete.
hal_bg_column:
	move.w  d2,d7
	lsr.w   #5,d7                   ; layer
	moveq   #31,d6
	and.w   d2,d6                   ; slot
	lea     HAL_BG_SLOTCOL,a0
	moveq   #0,d4
	move.b  (a0,d2.w),d4            ; column
	move.w  d2,-(sp)
	lea     HAL_BG_PEND,a0          ; pass 1 work stops once the rows in view are done
	moveq   #0,d0
	tst.b   (a0,d2.w)
	beq.w   .hp
	moveq   #1,d0
.hp:	move.w  d0,-(sp)
	lea     HAL_BG_ROW,a0
	moveq   #0,d5
	move.b  (a0,d2.w),d5            ; rows already done
	bne.w   .resume
	lea     HAL_BG_APX,a0           ; new conversion: no approximated cells yet
	tst.b   (a0,d2.w)
	beq.s   .na
	sf      (a0,d2.w)
	subq.w  #1,HAL_BG_APXN
.na:	tst.w   d7
	beq.w   .nf
	tst.w   HAL_FIXUSED
	beq.w   .nf
	bsr     hal_fix_clearcol
.nf:	bsr     hal_bg_scroll           ; d1 = sy
	lsr.w   #4,d1
	move.w  2(sp),d2
	lea     HAL_BG_R0,a0
	move.b  d1,(a0,d2.w)
.resume:
	move.w  2(sp),d2
	lea     HAL_BG_R0,a0
	moveq   #0,d3
	move.b  (a0,d2.w),d3
	add.w   d5,d3
	andi.w  #31,d3                  ; current block row
	move.w  d3,HAL_BG_CS            ; (the rows this call converts get copied)
	move.b  d5,HAL_BG_CD
	move.w  HAL_KDL,d0              ; the line counter (as hal_late_raw counts it)
	sub.w   HAL_RESV,d0             ; 2 more rows may not start at: the deadline
	subq.w  #ROWS2_LINES,d0         ; check inline
	move.w  d0,HAL_BG_KSTOP
	; tile base per bank select (code bits 11-12): BLKx_BASE + (bank << 9)
	lea     G_GFXBANK,a3
	move.w  d7,d0
	lsl.w   #2,d0
	adda.w  d0,a3
	lea     HAL_BG_SUB,a4
	move.w  #BLK0_BASE,d1
	tst.w   d7
	beq.w   .bb
	move.w  #BLK1_BASE,d1
.bb:	moveq   #4-1,d2
.sb:	moveq   #0,d0
	move.b  (a3)+,d0
	lsl.w   #8,d0
	add.w   d0,d0
	andi.w  #$1fff,d0
	add.w   d1,d0
	move.w  d0,(a4)+
	dbra    d2,.sb
	; uniform blocks (a cleared map, often half a screen): per bank select the
	; tile (UNIx_BASE + bank & 15, at HAL_BG_SUB + 8) and the tilemap-0 pen-15
	; variant (bytes at HAL_BG_SUB + 16)
	subq.l  #4,a3
	lea     8(a4),a5
	lea     UNIVAR,a6
	move.w  #UNI0_BASE,d1
	tst.w   d7
	beq.s   .ub
	move.w  #UNI1_BASE,d1
.ub:	moveq   #4-1,d2
.su:	moveq   #15,d0
	and.b   (a3)+,d0
	move.b  (a6,d0.w),(a5)+
	add.w   d1,d0
	move.w  d0,(a4)+
	dbra    d2,.su
	neg.w   d5
	addi.w  #31,d5                  ; dbra count: rows left - 1
	bsr     hal_bg_setrow
	lea     HAL_BG_SUB,a3
	tst.w   d7
	bne.w   .s1
	lea     hal_attrb0(pc),a4
	lea     L0VAR+$10000-BLK0_BASE,a5   ; indexed by the (negative) tile word
	lea     .b0(pc),a6
	bra.w   .b0
.s1:	lea     hal_attr1(pc),a4
	lea     .b1(pc),a6
	bra.w   .b1

	; ---- tilemap 0 block
.b0:	move.w  2(a0),d0                ; w (TR)
	move.w  d0,(a1)+                ; shadow
	move.w  d0,d1
	addq.w  #2,d1
	cmp.w   (a0),d1                 ; TL = w+2
	bne.w   .uz0
	addq.w  #1,d1
	cmp.w   128(a0),d1              ; BL = w+3
	bne.w   .odd
	subq.w  #2,d1
	cmp.w   130(a0),d1              ; BR = w+1
	bne.w   .odd
	moveq   #3,d1
	and.w   d0,d1
	bne.w   .h0
	move.w  d0,d1
	rol.w   #5,d1
	andi.w  #3,d1
	add.w   d1,d1
	move.w  (a3,d1.w),d2
	move.w  d0,d1
	andi.w  #$7fc,d1
	lsr.w   #2,d1
	add.w   d1,d2
	move.w  d2,(a2)+                 ; tile
	move.b  (a5,d2.w),d2            ; pen-15 variant
	move.w  d0,d1
	rol.w   #3,d1
	andi.w  #7,d1
	move.b  (a4,d1.w),d1            ; NPAL_L0 + 4 palette
	add.b   d2,d1
	lsl.w   #8,d1
	move.w  d1,(a2)+
	bra.w   .nb

	; w & 3 = 2: a block shifted by half (the staff screens' pictures), its own tile
	; (BLKS0_BASE + g: bits 0-15 here, bit 16 in the attributes)
.h0:	subq.w  #2,d1
	bne.w   .odd
	bsr.w   .hg
	beq.w   .odd
	move.w  d1,(a2)+                ; tile (low 16 bits)
	move.b  (a5,d1.w),d2            ; pen-15 variant (L0VAR + $8000 on: L0SVAR)
	bpl.s   .hv
	moveq   #0,d2                   ; $80: no variant possible (pen 15 transparent)
	bsr     hal_bg_apx
.hv:	move.w  d0,d1
	rol.w   #3,d1
	andi.w  #7,d1
	move.b  (a4,d1.w),d1            ; NPAL_L0 + 4 palette
	add.b   d2,d1
	lsl.w   #8,d1
	ori.w   #$10,d1                 ; tile bit 16
	move.w  d1,(a2)+
	bra.w   .nb
.h1:	subq.w  #2,d1
	bne.w   .odd
	bsr.w   .hg
	beq.w   .odd
	move.w  d1,(a2)+
	move.w  d0,d1
	rol.w   #3,d1
	andi.w  #7,d1
	add.w   d1,d1
	move.w  (a4,d1.w),d1            ; (NPAL_L1 + palette) << 8
	ori.w   #$10,d1
	move.w  d1,(a2)+
	bra.w   .nb
	; d1 = low 16 bits of the shifted block's tile (block + 0x8000); Z set: none (its
	; left half would come from the next bank select)
.hg:	move.w  d0,d1
	andi.w  #$7fc,d1
	cmpi.w  #$7fc,d1
	beq.s   .hx
	lsr.w   #2,d1
	move.w  d0,d2
	rol.w   #5,d2
	andi.w  #3,d2
	add.w   d2,d2
	add.w   (a3,d2.w),d1
	addi.w  #BLKS0_BASE-BLK0_BASE,d1        ; (= BLKS1_BASE - BLK1_BASE; clears Z)
.hx:	rts

	; ---- tilemap 1 block
.b1:	BLKHASH                         ; tilemap 1 shadow: hash of the four cells
	move.w  d0,(a1)+
	move.w  2(a0),d0
	move.w  d0,d1
	addq.w  #2,d1
	cmp.w   (a0),d1
	bne.w   .uz1
	addq.w  #1,d1
	cmp.w   128(a0),d1
	bne.w   .odd
	subq.w  #2,d1
	cmp.w   130(a0),d1
	bne.w   .odd
	moveq   #3,d1
	and.w   d0,d1
	bne.w   .h1
	move.w  d0,d1
	rol.w   #5,d1
	andi.w  #3,d1
	add.w   d1,d1
	move.w  (a3,d1.w),d2
	move.w  d0,d1
	andi.w  #$7fc,d1
	lsr.w   #2,d1
	add.w   d1,d2
	move.w  d2,(a2)+
	move.w  d0,d1
	rol.w   #3,d1
	andi.w  #7,d1
	add.w   d1,d1
	move.w  (a4,d1.w),(a2)+          ; (NPAL_L1 + palette) << 8
	bra.w   .nb

	; ---- uniform blocks (all four cells w, w & 0x7ff = 0), else hal_bg_odd
.uz0:	bsr.s   .uni
	bne.s   .odd
	move.w  d0,d1
	rol.w   #5,d1
	andi.w  #3,d1
	move.b  16(a3,d1.w),d2          ; pen-15 variant
	add.w   d1,d1
	move.w  8(a3,d1.w),(a2)+        ; tile
	move.w  d0,d1
	rol.w   #3,d1
	andi.w  #7,d1
	move.b  (a4,d1.w),d1            ; NPAL_L0 + 4 palette
	add.b   d2,d1
	lsl.w   #8,d1
	move.w  d1,(a2)+
	bra.s   .nb
.uz1:	bsr.s   .uni
	bne.s   .odd
	move.w  d0,d1
	rol.w   #5,d1
	andi.w  #3,d1
	add.w   d1,d1
	move.w  8(a3,d1.w),(a2)+        ; tile
	move.w  d0,d1
	rol.w   #3,d1
	andi.w  #7,d1
	add.w   d1,d1
	move.w  (a4,d1.w),(a2)+         ; (NPAL_L1 + palette) << 8
	bra.s   .nb
.uni:	cmp.w   (a0),d0                 ; Z set: uniform
	bne.s   .ux
	cmp.w   128(a0),d0
	bne.s   .ux
	cmp.w   130(a0),d0
	bne.s   .ux
	move.w  d0,d1
	andi.w  #$7ff,d1
.ux:	rts
.odd:	bsr     hal_bg_odd
.nb:	lea     256(a0),a0
	addq.w  #1,d3
	cmpi.w  #32,d3
	bne.w   .nw
	moveq   #0,d3                   ; wrap to block row 0
	bsr     hal_bg_setrow
.nw:	cmpi.w  #32-VIS_ROWS,d5         ; rows in view done?
	bne.w   .nv
	tst.w   (sp)
	bne.w   .vis
.nv:	tst.w   d5
	beq.w   .nc                     ; last row: finish
	btst    #0,d5
	bne.w   .nc
	move.w  REG_LSPCMODE,d0         ; every 2 block rows: time for 2 more?
	lsr.w   #7,d0
	cmp.w   HAL_K0R,d0
	bhs.s   .kp
	addi.w  #264,d0
.kp:	cmp.w   HAL_BG_KSTOP,d0
	bge.w   .defer
.nc:	subq.w  #1,d5
	bmi.w   .end
	jmp     (a6)
.end:	addq.l  #2,sp
	move.w  (sp)+,d2
	moveq   #32,d0
	bsr.s   .stage
	lea     HAL_BG_ROW,a0
	sf      (a0,d2.w)
	moveq   #0,d0                   ; column done
	rts
.vis:	moveq   #2,d1                   ; rows in view done: the rest is low priority
	bra.w   .keep
.defer:	moveq   #1,d1                   ; deadline: resume later
.keep:	addq.l  #2,sp
	move.w  (sp)+,d2                ; d5 rows still to do
	moveq   #32,d0
	sub.w   d5,d0
	lea     HAL_BG_ROW,a0
	move.b  d0,(a0,d2.w)
	move.w  d1,-(sp)
	bsr.s   .stage
	move.w  (sp)+,d0
	rts
	; the buffer changed (rows HAL_BG_CS on, d0 - HAL_BG_CD of them): copy them in
	; the real vblank.  G_BGSTG = rows staged (0: none) from HAL_BG_STGF on; rows
	; that do not continue the staged run make it the whole column.  Clobbers d0-d1,
	; a0-a1.
.stage:	sub.b   HAL_BG_CD,d0
	beq.s   .sx
	lea     G_BGSTG,a0
	lea     HAL_BG_STGF,a1
	move.b  (a0,d2.w),d1
	beq.s   .snew
	add.b   (a1,d2.w),d1
	andi.b  #31,d1
	cmp.b   HAL_BG_CS+1,d1
	bne.s   .sall
	add.b   (a0,d2.w),d0
	cmpi.b  #32,d0
	bhi.s   .sall
	move.b  d0,(a0,d2.w)
	bra.s   .sany
.sall:	move.b  #32,(a0,d2.w)
	sf      (a1,d2.w)
	bra.s   .sany
.snew:	move.b  HAL_BG_CS+1,(a1,d2.w)
	move.b  d0,(a0,d2.w)
.sany:	st      BGSTG_ANY(a0)
.sx:	rts

; d3 = block row, d4 = column, d6 = slot, d7 = layer: point a0 (TL cell), a1 (shadow)
; and a2 (the slot's buffer) at that row.  Clobbers d0.
hal_bg_setrow:
	bsr     hal_bg_colptr
	subq.l  #2,a0
	move.w  d3,d0
	lsl.w   #8,d0
	adda.w  d0,a0
	adda.w  d3,a1
	adda.w  d3,a1
	move.w  d7,d0
	lsl.w   #5,d0
	add.w   d6,d0
	lsl.w   #5,d0
	add.w   d3,d0
	add.w   d0,d0
	add.w   d0,d0                   ; (32 * layer + slot) * 128 + 4 * row
	lea     G_BGBUF,a2
	adda.w  d0,a2
	rts

; Copy the changed buffers into the slots' SCB1 (inside the real vblank), until the
; deadline (Z clear then: the rest waits).
	ifne OVR_FIX
BLAST_LINES     equ 6               ; (4 let a column run to the deadline after a fade's
	else                            ; palettes and the commit's tail overrun, 2026-10-17)
BLAST_LINES     equ 4
	endif
BGSTG_ANY       equ 64              ; (byte after the 64 flags: any flag set)
hal_bg_blast:
	lea     G_BGSTG,a1
	tst.b   BGSTG_ANY(a1)
	beq.w   .x
	moveq   #BLAST_LINES,d0         ; (the scan below takes up to ~1.3 lines: the
	bsr     hal_late_n              ; check covers it and the first column)
	bne.w   .late
	lea     G_BGSTG,a1
	move.w  #1,REG_VRAMMOD
	lea     REG_VRAMRW,a3
	moveq   #0,d2
.q:	tst.l   (a1,d2.w)               ; four slots at a time
	bne.s   .n
	addq.w  #4,d2
	cmpi.w  #64,d2
	blo.s   .q
	sf      BGSTG_ANY(a1)           ; all copied
.x:	moveq   #0,d0
	rts
.n:	tst.b   (a1,d2.w)
	beq.w   .nx
	moveq   #BLAST_LINES,d0
	bsr     hal_late_n
	bne.w   .late
	moveq   #31,d1
	and.w   d2,d1
	addq.w  #SPR_L0,d1
	btst    #5,d2
	beq.s   .l0
	addi.w  #SPR_L1-SPR_L0,d1
.l0:	lsl.w   #6,d1                   ; the slot's SCB1
	move.w  d2,d0
	lsl.w   #7,d0
	lea     G_BGBUF,a0
	adda.w  d0,a0                   ; its buffer
	moveq   #0,d3
	move.b  (a1,d2.w),d3            ; rows staged
	sf      (a1,d2.w)
	moveq   #0,d0
	lea     HAL_BG_STGF,a2
	move.b  (a2,d2.w),d0            ; from
	ifeq DIRECT-1
	jsr     hal_bg_mask1            ; (hal/tx.s: tilemap 1's rows with content)
	endif
	move.w  d0,d4
	add.w   d3,d4
	subi.w  #32,d4                  ; rows past the column's end (wrapped)
	bls.s   .w1
	sub.w   d4,d3
	move.w  d1,REG_VRAMADDR         ; those first: rows 0 ..
	move.l  a0,-(sp)
	bsr.s   .cp
	movea.l (sp)+,a0
.w1:	add.w   d0,d0
	add.w   d0,d1
	add.w   d0,d0
	adda.w  d0,a0
	move.w  d1,REG_VRAMADDR
	move.w  d3,d4
	bsr.s   .cp
.nx:	addq.w  #1,d2
	moveq   #3,d0
	and.w   d2,d0
	bne.w   .n
	cmpi.w  #64,d2
	blo.w   .q
	sf      BGSTG_ANY(a1)
	moveq   #0,d0
	rts
.late:	addq.l  #1,HAL_BGDEFER
	bset    #1,HAL_SLIP+1
	rts
	; d4 rows (2 words each) from a0 on to the VRAM port.  Clobbers d4, a0, a2.
.cp:	add.w   d4,d4
	add.w   d4,d4
	neg.w   d4
	lea     .ce(pc),a2
	jmp     (a2,d4.w)
	rept 64
	move.w  (a0)+,(a3)
	endr
.ce:	rts

; attribute tables: tilemap 1 (NPAL_L1 + palette) << 8, tilemap 0 NPAL_L0 + 4 palette
hal_attr1:
pq	set 0
	rept 8
	dc.w    (NPAL_L1+pq)<<8
pq	set pq+1
	endr
hal_attrb0:
pq	set 0
	rept 8
	dc.b    NPAL_L0+4*pq
pq	set pq+1
	endr

; d0 = cell word, d7 = layer, a3 = layer banks -> d1 = block group g (phys >> 2)
hal_bg_group:
	move.w  d0,d1
	rol.w   #5,d1
	andi.w  #3,d1
	moveq   #0,d2
	move.b  (a3,d1.w),d2            ; bank
	lsl.w   #8,d2
	add.w   d2,d2
	move.w  d0,d1
	andi.w  #$7fc,d1
	lsr.w   #2,d1
	or.w    d2,d1
	andi.w  #$1fff,d1
	rts

;  A block whose cells are not one of the game's 2x2 blocks: d0 = TR word, a0 = TL
; cell, d3 = block row, d4 = column, d6 = slot, d7 = layer.  Preserves a0-a6, d3-d7.
hal_bg_odd:
	movem.l a3-a5,-(sp)
	lea     G_GFXBANK,a3
	move.w  d7,d1
	lsl.w   #2,d1
	adda.w  d1,a3
	lea     L0VAR,a4
	bsr     hal_bg_odd_in
	movem.l (sp)+,a3-a5
	rts

;   all four cells tile k*0x800 (a cleared map): the uniform tile
;   tilemap 1: blank sprite tile, the cells go on the fix layer
;   tilemap 0: drawn as the block of its top-right cell (counted)
; d0 = TR word, a0 = TL cell, d3 = block row, d4 = column, d6 = slot, d7 = layer.
; Writes the SCB1 pair.  Clobbers d1, d2, a5.
hal_bg_odd_in:
	cmp.w   (a0),d0
	bne.w   .gen
	cmp.w   128(a0),d0
	bne.w   .gen
	cmp.w   130(a0),d0
	bne.w   .gen
	move.w  d0,d1
	andi.w  #$7ff,d1
	bne.w   .gen
	move.w  d0,d1                   ; uniform: k = bank of the cells
	rol.w   #5,d1
	andi.w  #3,d1
	moveq   #15,d2
	and.b   (a3,d1.w),d2
	tst.w   d7
	bne.w   .u1
	move.w  d2,d1
	addi.w  #UNI0_BASE,d1
	move.w  d1,(a2)+
	lea     UNIVAR,a5
	move.b  (a5,d2.w),d2            ; its pen-15 variant
	bra.w   .attr0
.u1:	addi.w  #UNI1_BASE,d2
	move.w  d2,(a2)+
	bra.w   .attr1
.gen:	tst.w   d7
	bne.w   .fix
	addq.l  #1,HAL_BGODD            ; tilemap 0: approximate with the TR block
	bsr     hal_bg_apx
	bsr     hal_bg_group
	move.w  d1,d2
	addi.w  #BLK0_BASE,d2
	move.w  d2,(a2)+
	moveq   #0,d2
	move.b  (a4,d1.w),d2
.attr0:	move.w  d0,d1
	rol.w   #3,d1
	andi.w  #7,d1
	lsl.w   #2,d1
	add.w   d2,d1
	addi.w  #NPAL_L0,d1
	lsl.w   #8,d1
	move.w  d1,(a2)+
	rts
.attr1:	move.w  d0,d1
	rol.w   #3,d1
	andi.w  #7,d1
	addi.w  #NPAL_L1,d1
	lsl.w   #8,d1
	move.w  d1,(a2)+
	rts
.fix:
	ifeq DIRECT-1
	bsr.w   hal_bg_solid1           ; four identical cells of one opaque pen: a column
	bmi.s   .fx                     ; tile (the fix layer would hide the sprites over it)
	addi.w  #SOLID_BASE,d1
	move.w  d1,(a2)+
	bra.w   .attr1
.fx:
	endif
	move.w  #BLANK_TILE,(a2)+        ; tilemap 1: text on the fix layer
	move.w  #0,(a2)+
	; fall through

; Put the four cells of tilemap-1 block (d3 = row, d4 = column, a0 = TL cell, a3 =
; tilemap-1 banks) on the fix layer.  Needs tilemap 1 8-pixel aligned; otherwise the
; cells are counted as approximated (not drawn).  Empty / blank cells are skipped (the
; fix layer under a column is cleared before it is converted).  Restores the SCB1
; buffer pointer (a2) as it was.
hal_fix_block:
	movem.l d0-d5/a1,-(sp)
	move.w  HAL_BG_SX+2,d5          ; tilemap-1 scroll as placed this frame
	move.w  HAL_BG_SY+2,d1
	move.w  d5,d2
	or.w    d1,d2
	andi.w  #7,d2
	bne.w   .mis
	move.w  #1,HAL_FIXUSED
	lsl.w   #4,d3
	sub.w   d1,d3                   ; y of the block's top (mod 512)
	lsl.w   #4,d4
	sub.w   d5,d4                   ; x of its left edge (mod 512)
	lea     S_REMAP,a1
	move.w  (a0),d0                 ; TL
	moveq   #0,d1
	moveq   #0,d2
	bsr.w   .cell
	move.w  2(a0),d0                ; TR
	moveq   #8,d1
	moveq   #0,d2
	bsr.w   .cell
	move.w  128(a0),d0              ; BL
	moveq   #0,d1
	moveq   #8,d2
	bsr.w   .cell
	move.w  130(a0),d0              ; BR
	moveq   #8,d1
	moveq   #8,d2
	bsr.w   .cell
	bra.w   .r
.mis:	addq.l  #1,HAL_BGODD
	bsr     hal_bg_apx
.r:	movem.l (sp)+,d0-d5/a1
	rts

; d0 = cell, d1/d2 = x/y offset in the block; d3/d4 = block y/x.  Clobbers d0-d2, d5.
.cell:	tst.w   d0
	beq.w   .cx                     ; cleared cell
	move.w  d0,d5                   ; tile = (w & 0x7ff) | bank << 11 -> S tile (S_REMAP)
	rol.w   #5,d5
	andi.w  #3,d5
	move.b  (a3,d5.w),d5
	lsl.w   #8,d5
	lsl.w   #3,d5
	move.w  d0,-(sp)
	andi.w  #$7ff,d0
	or.w    d0,d5
	move.w  (sp)+,d0
	andi.l  #$7fff,d5
	add.l   d5,d5
	move.w  (a1,d5.l),d5
	bmi.w   .cs                     ; transparent, or not in the S ROM
	add.w   d4,d1
	andi.w  #511,d1                 ; screen x
	cmpi.w  #320,d1
	bhs.w   .cx
	add.w   d3,d2
	andi.w  #511,d2                 ; screen y
	cmpi.w  #224,d2
	bhs.w   .cx
	lsr.w   #3,d1
	lsl.w   #5,d1
	lsr.w   #3,d2
	add.w   d2,d1
	addi.w  #FIXMAP+2,d1
	move.w  d1,REG_VRAMADDR
	rol.w   #3,d0                   ; palette
	andi.w  #7,d0
	addi.w  #NPAL_L1,d0
	ror.w   #4,d0
	or.w    d5,d0
	move.w  d0,REG_VRAMRW
.cx:	rts
.cs:	cmpi.w  #S_TRANSP,d5
	beq.s   .cx
.co:	addq.l  #1,HAL_BGODD            ; tile not in the S ROM
	bra     hal_bg_apx

	ifeq DIRECT-1
; d0 = TR word, a0 = TL cell, a3 = tilemap-1 banks -> d1 = the pen (0..14) of four
; identical cells of a solid opaque tile (the staff screens' panels), else -1 (N set).
; Clobbers d2, a5.
hal_bg_solid1:
	cmp.w   (a0),d0
	bne.s   .no
	cmp.w   128(a0),d0
	bne.s   .no
	cmp.w   130(a0),d0
	bne.s   .no
	move.w  d0,d1                   ; tile = (w & 0x7ff) | bank << 11
	rol.w   #5,d1
	andi.w  #3,d1
	moveq   #15,d2
	and.b   (a3,d1.w),d2
	lsl.w   #8,d2
	lsl.w   #3,d2
	move.w  d0,d1
	andi.w  #$7ff,d1
	or.w    d2,d1
	lea     SOLIDPEN,a5             ; a nibble per tile, even tiles high
	lsr.w   #1,d1
	bcs.s   .od
	move.b  (a5,d1.w),d1
	lsr.b   #4,d1
	bra.s   .t
.od:	move.b  (a5,d1.w),d1
.t:	andi.w  #15,d1
	cmpi.w  #15,d1
	bne.s   .y
.no:	moveq   #-1,d1
.y:	tst.w   d1
	rts
	endif

; The column of slot d6 (layer d7) shows approximated cells until it is converted
; again: a tilemap slip in every frame meanwhile (hal/video.s).  Keeps all registers.
hal_bg_apx:
	move.l  a0,-(sp)
	move.w  d7,-(sp)
	lsl.w   #5,d7
	add.w   d6,d7
	lea     HAL_BG_APX,a0
	tst.b   (a0,d7.w)
	bne.s   .x
	st      (a0,d7.w)
	addq.w  #1,HAL_BG_APXN
.x:	move.w  (sp)+,d7
	movea.l (sp)+,a0
	rts

; Tilemap-1 column d4 is about to be redrawn: clear the fix cells under it.
hal_fix_clearcol:
	movem.l d0-d2/d4/d7,-(sp)
	moveq   #1,d7
	bsr     hal_bg_scroll
	lsl.w   #4,d4
	sub.w   d0,d4
	andi.w  #511,d4
	lsr.w   #3,d4                   ; first fix column (when aligned)
	moveq   #2-1,d2
.c:	cmpi.w  #40,d4
	bhs.w   .n
	move.w  d4,d0
	lsl.w   #5,d0
	addi.w  #FIXMAP,d0
	move.w  d0,REG_VRAMADDR
	moveq   #32-1,d1
.w:	move.w  #0,REG_VRAMRW
	dbra    d1,.w
.n:	addq.w  #1,d4
	andi.w  #63,d4
	dbra    d2,.c
	movem.l (sp)+,d0-d2/d4/d7
	rts

; initial state: no slots, everything re-placed on the first frame
hal_bg_init:
	lea     HAL_BG_SLOTCOL,a0
	moveq   #-1,d0
	moveq   #(64+64)/4-1,d1         ; SLOTCOL and COLSLOT
.f:	move.l  d0,(a0)+
	dbra    d1,.f
	moveq   #64/4-1,d1              ; PEND
	moveq   #0,d0
.p:	move.l  d0,(a0)+
	dbra    d1,.p
	lea     HAL_BG_ROW,a0
	moveq   #64/4-1,d1
.r:	move.l  d0,(a0)+
	dbra    d1,.r
	clr.w   HAL_BG_APXN
	clr.l   HAL_BG_APXF
	lea     HAL_BG_APX,a0
	moveq   #64/4-1,d1
.o:	move.l  d0,(a0)+
	dbra    d1,.o
	lea     HAL_BG_LOW,a0
	moveq   #64/4-1,d1
.lo:	move.l  d0,(a0)+
	dbra    d1,.lo
	move.l  #$ffffffff,HAL_BG_C0
	move.l  #$ffffffff,HAL_BG_SX
	move.l  #$ffffffff,HAL_BG_SY
	clr.w   HAL_BG_POS
	st      HAL_BG_WORK
	clr.w   HAL_BG_SCRUB
	clr.w   HAL_BG_BURST
	clr.w   HAL_FIXUSED
	move.w  #40,HAL_FIXCLR
	ifne BG_HIDECLR
	clr.w   HAL_BG_HID
	endif
	ifne BG_CUTCAP
	clr.b   HAL_BG_CAPN
	clr.b   HAL_BG_CAPS
	endif
	ifne BG_SCRRING
	clr.b   HAL_SCRI
	endif
	clr.l   HAL_BGMISS
	move.l  #$ffffffff,HAL_BG_BANK  ; (the first slot reconverts both layers anyway)
	move.l  #$ffffffff,HAL_BG_BANK+4
	clr.w   HAL_BG_SAMP
	sf      HAL_BG_RETROP
	clr.l   HAL_BG_RETRON
	lea     HAL_BG_SAMPF,a0
	moveq   #SAMP_N-1,d1
.sf:	clr.w   (a0)+
	dbra    d1,.sf
	clr.l   HAL_BGDEFER
	clr.l   HAL_BGODD
	; full size (no shrink) for the tilemap sprites
	move.w  #1,REG_VRAMMOD
	move.w  #SCB2+SPR_L0,REG_VRAMADDR
	moveq   #BG_COLS-1,d1
.z0:	move.w  #$0fff,REG_VRAMRW
	dbra    d1,.z0
	move.w  #SCB2+SPR_L1,REG_VRAMADDR
	moveq   #BG_COLS-1,d1
.z1:	move.w  #$0fff,REG_VRAMRW
	dbra    d1,.z1
	rts
