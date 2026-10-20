; Not cycle-exact (AEROFGT_DIRECT=1): tilemap-1 columns hidden while they show nothing.
;
; Every tilemap column is a Neo sprite on every scanline it covers, and the Neo draws
; 96 sprites a line at most (it drops the highest-numbered: the original's sprites
; first).  Tilemap 1 (the front layer) is mostly transparent: a column whose rows in
; view are all transparent gets height 0 and covers no line (frames with a line over
; 96 in Neo VRAM: movie7 32 -> 0, attract 127 -> 80; trimming columns to their rows,
; or the wrap trick on top, gained nothing more in work/wraptrick.py's estimate).
;
; Per slot a mask of its 32 block rows (FX1_MASK: bit = not transparent, from its
; buffer and BG_TRANSP, a bit per C tile).  A slot the blast changes is shown at once
; (hal_bg_mask1, in the same vblank as its rows) and counted whole until its mask is
; made again outside the real vblank (hal_bg_maskwork).  Shown: the slots with a bit in
; the 14-15 rows in view (FX1_PAT); a shown slot is a head (its own y, height 32, x)
; unless the slot left of it is shown (then chained, as all slots were), a hidden one
; has height 0.  In the real vblank (hal_bg_l1place) only what must change then: the
; heads' y and x (FX1_HL), all of it when the slots change or the y scroll brings rows
; with content into view in a hidden slot.  Hiding waits for hal_bg_l1hide, outside the
; real vblank: a slot showing nothing shows the same hidden (its right neighbour made a
; head first).

FX1_MASK        equ FXS+$780        ; 21 l: per tilemap-1 slot, its rows with content
FX1_PAT         equ FXS+$7d4        ; l: slots shown (bit per slot)
FX1_DIRTY       equ FXS+$7d8        ; b: the pattern may have slots to hide
FX1_PEND        equ FXS+$7da        ; l: slots whose mask is to be made again
FX1_YW          equ FXS+$7de        ; w: SCB3 of a head (y, 32 tiles) as last placed
FX1_X0          equ FXS+$7e0        ; w: SCB4 of slot R as last placed
FX1_WIN         equ FXS+$7e2        ; l: the block rows in view as last placed
FX1_HN          equ FXS+$7e6        ; w: heads (shown slots with their own y, x)
FX1_R           equ FXS+$7e8        ; b: R as last placed (hal_bg_window changes it
FX1_CLR         equ FXS+$7e9        ; b: (BG_HIDECLR) the game cleared the layer: every column
                                    ; off the screen at the commit (hal_bg_l1place)
                                    ; for the next slot before hal_bg_l1hide runs)
FX1_HL          equ FXS+$700        ; 21 x (w slot, w its x from slot R's): the heads
TX_LINES        equ 5               ; scanlines hal_bg_l1hide may take (the pattern, 21
                                    ; SCB3, the heads' SCB4: ~3000 cycles at most)

; Blast hook: d2 = slot index (bit 5: tilemap 1).  Its rows change: shown whole until
; its mask is made again outside the real vblank (hal_bg_maskwork).  Keeps every
; register.
hal_bg_mask1:
	btst    #5,d2
	beq.w   .x
	movem.l d0-d2/a2,-(sp)
	moveq   #31,d0
	and.w   d2,d0
	move.l  FX1_PEND,d1
	bset    d0,d1
	move.l  d1,FX1_PEND
	lsl.w   #2,d0
	lea     FX1_MASK,a2
	move.l  (a2,d0.w),d1
	addq.l  #1,d1
	beq.s   .k                      ; (shown whole already)
	move.l  #-1,(a2,d0.w)
	st      FX1_DIRTY
.k:	lsr.w   #2,d0                   ; hidden now: shown at once (in this vblank, before
	ifne BG_HIDECLR
	lea     HAL_BG_PEND+32,a2       ; (BG_HIDECLR: once its rows in view are all
	tst.b   (a2,d0.w)               ; converted - a blast of the first rows alone showed
	bne.s   .v                      ; the rest stale: a band of the old scene)
	endif
	move.l  FX1_PAT,d1              ; its new rows: a head of its own; the slot right
	bset    d0,d1                   ; of it is a head already)
	bne.s   .v
	move.l  d1,FX1_PAT
	moveq   #0,d1
	move.b  FX1_R,d1
	neg.w   d1
	add.w   d0,d1                   ; slot - R
	bpl.s   .p
	addi.w  #BG_COLS,d1
.p:	ror.w   #5,d1                   ; (16 px a column)
	move.w  FX1_HN,d2               ; (a head: on the list)
	addq.w  #1,FX1_HN
	lsl.w   #2,d2
	lea     FX1_HL,a2
	adda.w  d2,a2
	move.w  d0,(a2)+
	move.w  d1,(a2)
	add.w   FX1_X0,d1
	addi.w  #SCB4+SPR_L1,d0
	move.w  d0,REG_VRAMADDR
	move.w  d1,REG_VRAMRW
	addi.w  #SCB3-SCB4,d0
	move.w  d0,REG_VRAMADDR
	move.w  FX1_YW,REG_VRAMRW
.v:	movem.l (sp)+,d0-d2/a2
.x:	rts

; The masks of the slots the blasts changed (FX1_PEND), while hal_late_n allows d0
; lines + one mask (~3300 cycles: 32 rows).  Keeps all but d0.
TX_MLINES       equ 6
hal_bg_maskwork:
	tst.l   FX1_PEND
	beq.w   .z
	movem.l d1-d7/a0/a4-a5,-(sp)
	move.w  d0,d7
.s:	move.l  FX1_PEND,d4
	beq.w   .x
	move.w  d7,d0
	addq.w  #TX_MLINES,d0
	jsr     hal_late_n
	bne.w   .x
	moveq   #-1,d0                  ; its lowest slot
.f:	addq.w  #1,d0
	btst    d0,d4
	beq.s   .f
	bclr    d0,d4
	move.l  d4,FX1_PEND
	lea     G_BGSTG+32,a0           ; rows staged, not copied yet: its buffer is not
	tst.b   (a0,d0.w)               ; what shows (the copy sets it pending again)
	bne.w   .s
	move.w  d0,-(sp)
	addi.w  #32,d0                  ; (tilemap 1's buffers: 32..)
	lsl.w   #7,d0
	lea     G_BGBUF,a5
	adda.w  d0,a5
	lea     BG_TRANSP,a4
	moveq   #0,d5
	moveq   #0,d1
	moveq   #31,d3
.r:	move.w  (a5)+,d2                ; tile bits 15-0
	move.w  (a5)+,d6                ; attr: tile bits 19-16 in bits 7-4
	andi.w  #$f0,d6
	beq.s   .lo
	lsl.w   #8,d6
	add.w   d6,d6
.lo:	move.w  d2,d0
	lsr.w   #3,d0
	add.w   d6,d0                   ; tile >> 3
	btst    d2,(a4,d0.w)            ; (bit tile & 7)
	bne.s   .t
	bset    d1,d5                   ; not transparent
.t:	addq.w  #1,d1
	dbra    d3,.r
	move.w  (sp)+,d0
	lsl.w   #2,d0
	lea     FX1_MASK,a0
	cmp.l   (a0,d0.w),d5
	beq.w   .s
	move.l  d5,(a0,d0.w)
	st      FX1_DIRTY
	bra.w   .s
.x:	movem.l (sp)+,d1-d7/a0/a4-a5
.z:	rts

; Tilemap 1's placement in the real vblank (hal_bg_place): cheap unless the slots
; changed (all of it, as the other layer) or the y scroll brings rows with content into
; view in a hidden slot (shown now: all of it).  A slot only to be hidden waits for
; hal_bg_l1hide outside the real vblank (it shows nothing meanwhile).  Clobbers d0-d7,
; a0, a2, a3.
hal_bg_l1place:
	ifne BG_HIDECLR
	tst.b   FX1_CLR                 ; (BG_HIDECLR) the game cleared the layer: every column
	beq.w   .nc                     ; off the screen now, no heads; a column is a head
	sf      FX1_CLR                 ; again as its blast comes (hal_bg_mask1) - the idle
	clr.l   FX1_PAT                 ; hide (hal_bg_l1hide) never ran during the burst
	clr.w   FX1_HN
	sf      FX1_DIRTY
	move.w  #1,REG_VRAMMOD
	move.w  #SCB3+SPR_L1,REG_VRAMADDR
	lea     REG_VRAMRW,a2
	rept BG_COLS
	move.w  #0,(a2)
	endr
.nc:
	endif
	lea     HAL_BG_POS,a0
	moveq   #7,d4
	and.b   1(a0),d4                ; bit 0 x moved, 1 y moved, 2 slots changed
	ifeq BG_SETSCR
	beq.w   .x
	endif
	sf      1(a0)
	moveq   #1,d7
	ifne BG_SCRRING
	jsr     hal_bg_scrcur           ; (BG_SCRRING, hal/bg.s: from the ring)
	else
	jsr     hal_bg_scroll           ; d0 x, d1 y
	endif
	ifne BG_SETSCR
	jsr     hal_bg_held             ; (BG_SETSCR, hal/bg.s: the shown set's slot's scroll)
	cmp.w   HAL_BG_SX+2,d0
	beq.s   .mx
	bset    #0,d4
.mx:	cmp.w   HAL_BG_SY+2,d1
	beq.s   .my
	bset    #1,d4
.my:	tst.b   d4
	beq.w   .x
	endif
	move.w  d0,HAL_BG_SX+2
	move.w  d1,HAL_BG_SY+2
	move.b  HAL_BG_R+1,FX1_R
	move.w  #1,REG_VRAMMOD
	lea     REG_VRAMADDR,a3
	lea     REG_VRAMRW,a2
	move.w  HAL_BG_C0+2,d2          ; SCB4 of slot R: (c0 << 11) - (sx << 7)
	ror.w   #5,d2
	lsl.w   #7,d0
	sub.w   d0,d2
	move.w  d2,FX1_X0
	move.w  #496,d5                 ; SCB3 of a head: y, 32 tiles high
	add.w   d1,d5
	andi.w  #511,d5
	lsl.w   #7,d5
	ori.w   #32,d5
	move.w  d5,FX1_YW
	btst    #1,d4
	beq.s   .xo
	bsr.w   tx_window               ; y moved: the rows in view
	cmp.l   FX1_WIN,d5
	beq.s   .yo
	move.l  d5,FX1_WIN
	bsr.w   tx_pattern
	move.l  FX1_PAT,d2
	not.l   d2
	and.l   d3,d2
	bne.s   .all                    ; (some to be shown: now)
	cmp.l   FX1_PAT,d3
	beq.s   .yo
	st      FX1_DIRTY               ; (some to be hidden: later)
.yo:	btst    #2,d4
	bne.s   .sl
	move.w  FX1_YW,d5               ; the heads' y
	lea     FX1_HL,a0
	move.w  FX1_HN,d7
	bra.s   .y1
.y0:	move.w  (a0),d0
	addi.w  #SCB3+SPR_L1,d0
	move.w  d0,(a3)
	move.w  d5,(a2)
	addq.w  #4,a0
.y1:	dbra    d7,.y0
.xo:	btst    #2,d4
	bne.s   .sl
	btst    #0,d4
	beq.s   .x
					; the heads' x
	move.w  FX1_X0,d1
	lea     FX1_HL,a0
	move.w  FX1_HN,d7
	bra.s   .x1
.x0:	move.w  (a0)+,d0
	addi.w  #SCB4+SPR_L1,d0
	move.w  d0,(a3)
	move.w  (a0)+,d0
	add.w   d1,d0
	move.w  d0,(a2)
.x1:	dbra    d7,.x0
.x:	rts
.sl:	bsr.w   tx_window               ; slots changed: all of it
	move.l  d5,FX1_WIN
	bsr.w   tx_pattern
.all:	sf      FX1_DIRTY
	bra.w   tx_apply

; Outside the real vblank (it shows the same picture: only slots showing nothing are
; hidden): the pattern the masks give now, if they changed it.  Keeps all registers.
hal_bg_l1hide:
	tst.b   FX1_DIRTY
	beq.s   .z
	movem.l d0-d7/a0/a2-a3,-(sp)
	sf      FX1_DIRTY
	move.l  FX1_WIN,d5
	bsr.w   tx_pattern
	cmp.l   FX1_PAT,d3
	beq.s   .x
	move.w  #1,REG_VRAMMOD
	lea     REG_VRAMADDR,a3
	lea     REG_VRAMRW,a2
	bsr.w   tx_apply
.x:	movem.l (sp)+,d0-d7/a0/a2-a3
.z:	rts

; d1 = y -> d5 = the block rows in view (14 or 15 from y >> 4, wrapping at 32).
; Clobbers d2, d3.
tx_window:
	move.w  d1,d2
	lsr.w   #4,d2
	move.w  d1,d3
	andi.w  #15,d3
	addi.w  #223,d3
	lsr.w   #4,d3
	addq.w  #1,d3
	moveq   #0,d5
	bset    d3,d5
	subq.l  #1,d5
	rol.l   d2,d5
	rts

; d5 = rows -> d3 = the slots with something in them.  Clobbers d2, d7, a0.
tx_pattern:
	lea     FX1_MASK,a0
	moveq   #0,d3
	moveq   #0,d7
.p:	move.l  (a0)+,d2
	and.l   d5,d2
	beq.s   .n
	bset    d7,d3
.n:	addq.w  #1,d7
	cmpi.w  #BG_COLS,d7
	blo.s   .p
	rts

; d3 = slots shown (FX1_PAT), a2/a3 = REG_VRAMRW/ADDR (modulo 1), with FX1_YW, FX1_X0 and
; R: every slot's SCB3 and the heads' SCB4, in an order that never shows what was not
; (heads first, then the chained, then the hidden).  A shown slot is a head unless the
; slot left of it is shown (slot R and 0 head their chains).  Clobbers d0-d7, a0.
tx_apply:
	move.l  d3,FX1_PAT
	moveq   #0,d6
	move.b  FX1_R,d6
	move.l  d3,d4                   ; heads: shown, left one not (or slot 0, R)
	add.l   d4,d4                   ; (bit s: slot s - 1 shown)
	bset    d6,d4
	bclr    d6,d4                   ; (R: whatever is left of it)
	bclr    #0,d4
	not.l   d4
	and.l   d3,d4                   ; d4 heads
	tst.w   d6
	beq.s   .r0
	btst    d6,d3
	beq.s   .r0
	bset    d6,d4
.r0:	btst    #0,d3
	beq.s   .h
	bset    #0,d4
.h:	lea     FX1_HL,a0               ; the heads: SCB4, SCB3, and the list
	move.w  FX1_X0,d1
	move.w  FX1_YW,d5
	moveq   #0,d2                   ; their count
	moveq   #0,d7
.hl:	btst    d7,d4
	beq.s   .hn
	move.w  d7,d0
	sub.w   d6,d0
	bpl.s   .hp
	addi.w  #BG_COLS,d0
.hp:	ror.w   #5,d0                   ; (16 px a column)
	move.w  d7,(a0)+
	move.w  d0,(a0)+
	add.w   d1,d0
	move.w  d7,d3                   ; (d3 back below)
	addi.w  #SCB4+SPR_L1,d3
	move.w  d3,(a3)
	move.w  d0,(a2)
	addi.w  #SCB3-SCB4,d3
	move.w  d3,(a3)
	move.w  d5,(a2)
	addq.w  #1,d2
.hn:	addq.w  #1,d7
	cmpi.w  #BG_COLS,d7
	blo.s   .hl
	move.w  d2,FX1_HN
	move.l  FX1_PAT,d3
	move.l  d3,d2                   ; the chained: shown, not heads
	eor.l   d4,d2
	move.w  #$40,d5
	bsr.s   .w3
	move.l  d3,d2                   ; the hidden
	not.l   d2
	andi.l  #(1<<BG_COLS)-1,d2
	moveq   #0,d5
.w3:	moveq   #0,d7                   ; d5 to the SCB3 of the slots in d2
.wl:	btst    d7,d2
	beq.s   .wn
	move.w  d7,d0
	addi.w  #SCB3+SPR_L1,d0
	move.w  d0,(a3)
	move.w  d5,(a2)
.wn:	addq.w  #1,d7
	cmpi.w  #BG_COLS,d7
	blo.s   .wl
	rts
