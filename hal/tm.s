; Not cycle-exact (AEROFGT_DIRECT=1): tilemap changes told by the game's writers instead
; of found by sampling (hal_bg_sample, ~2500 cycles a slot).
;
; Only four routines write the tilemaps (traced over movie7 and the attract run): the
; block writers 0x2c924 and 0x5e0c (one 16x16 block at A3), the block fill 0x81c8 (D0
; block rows x D1 block columns from A3) and the clear 0x1250 (a whole layer).  Each
; goes through a stub that marks what it writes (TM_DIRTY: per layer and block column a
; bit per block row; TM_ALL: a layer cleared), then does what the patched instructions
; did.  The slot's prep turns the marks into work (tm_apply): a cleared layer is
; reconverted (hal_bg_layer_stale), a column in view with one changed row and nothing
; being converted gets just that row (its conversion state set to the last of 32 rows:
; R0, ROW), any other change in view reconverts the column.  Columns out of view need
; nothing (converted when they come in).  The spare-time verification (hal_bg_scrub1)
; stays.

TM_DIRTY        equ G_SPRRAM+$400   ; 2 x 32 l: per layer and block column, its rows
TM_ALL          equ G_SPRRAM+$500   ; 2 b: layer cleared
TM_ANY          equ G_SPRRAM+$502   ; b: anything marked

; a3 = a block's top-left cell: its row marked.  Keeps every register and SR.
tm_mark:
	move.w  sr,-(sp)
	movem.l d0-d1/a0,-(sp)
	move.l  a3,d0
	subi.l  #G_VRAM0,d0
	cmpi.l  #$4000,d0
	bhs.s   .x                      ; (not a tilemap)
	move.w  d0,d1
	lsr.w   #8,d1
	andi.w  #31,d1                  ; block row
	lsr.w   #2,d0
	andi.w  #$81f,d0                ; layer (bit 11), block column
	cmpi.w  #$800,d0
	blo.s   .l
	subi.w  #$800-32,d0
.l:	lsl.w   #2,d0
	lea     TM_DIRTY,a0
	adda.w  d0,a0
	move.l  (a0),d0
	bset    d1,d0
	move.l  d0,(a0)
	st      TM_ANY
.x:	movem.l (sp)+,d0-d1/a0
	move.w  (sp)+,sr
	rts

; the block fill (0x81c8): D0 block rows x D1 block columns from A3.  Keeps everything.
tm_rect:
	move.w  sr,-(sp)
	movem.l d0-d3/a3,-(sp)
	move.w  d1,d3
	subq.w  #1,d3
	bmi.s   .x
.c:	move.w  d0,d2                   ; a column: its rows
	subq.w  #1,d2
	bmi.s   .x
	move.l  a3,-(sp)
.r:	bsr.s   tm_mark
	lea     $100(a3),a3
	dbra    d2,.r
	movea.l (sp)+,a3
	addq.l  #4,a3
	dbra    d3,.c
.x:	movem.l (sp)+,d0-d3/a3
	move.w  (sp)+,sr
	rts

; The writers' stubs (patched by tools/aerofgt2neo.py: jmp abs.l over the first
; instructions, which each stub does after marking).
tm_blk1:
	bsr.w   tm_mark                 ; 0x2c924
	addq.w  #2,d0
	move.w  d0,(a3)+
	subq.w  #2,d0
	jmp     $2c92a
tm_blk2:
	bsr.w   tm_mark                 ; 0x5e0c
	addq.w  #2,d0
	move.w  d0,(a3)+
	subq.w  #2,d0
	jmp     $5e12
tm_clr0:
	st      TM_ALL                  ; 0x1254: layer 0 cleared
	st      TM_ANY
	movea.l #G_VRAM0,a3
	jmp     $1264
tm_clr1:
	st      TM_ALL+1                ; 0x125e: layer 1
	st      TM_ANY
	movea.l #G_VRAM1,a3
	jmp     $1264
tm_fill:
	bsr.w   tm_rect                 ; 0x81c8
	movem.l d2-d7/a0-a2,-(sp)
	movea.l TM_FILLPTR,a0
	jmp     $81d2
TM_FILLPTR      equ $100000+$ff8cd6-$fef000     ; (the original's 0xff8cd6, relocated)

; Prep (after the window): the marks into work.  Clobbers d0-d7, a0-a4.
tm_apply:
	tst.b   TM_ANY
	beq.w   .x
	sf      TM_ANY
	moveq   #0,d7                   ; layer
.lay:	lea     TM_ALL,a0
	tst.b   (a0,d7.w)
	beq.s   .cols
	sf      (a0,d7.w)
	move.w  HAL_FRAMES+2,d0
	jsr     hal_bg_layer_stale      ; the whole layer again
	ifne BG_CUTCAP
	addi.b  #BG_COLS,HAL_BG_CAPN    ; (BG_CUTCAP: its columns under the cap, hal_bg_convert;
	clr.w   HAL_BG_BURST            ; no verification burst for a cleared layer)
	endif
	ifne BG_HIDECLR
	; (BG_HIDECLR) its old columns off the screen meanwhile (the arcade shows the
	; cleared layer: blank): layer 0 whole - its heads' height 0 until every column is
	; converted and blasted (hal_bg_place) -, layer 1 slot by slot - its masks emptied,
	; a column shows again when its blast remakes them (hal_bg_mask1).  Without it the
	; demo-to-hangar cut showed two frames of the city in the hangar's palette.
	tst.w   d7
	bne.s   .h1
	st      HAL_BG_HID
	bset    #3,HAL_BG_POS
	bra.s   .hd
.h1:	lea     FX1_MASK,a0
	moveq   #BG_COLS-1,d0
.hm:	clr.l   (a0)+
	dbra    d0,.hm
	clr.l   FX1_PEND
	st      FX1_CLR                 ; (hal/tx.s hal_bg_l1place: at the commit)
.hd:
	endif
	subq.l  #1,HAL_BGMISS           ; (told, not found: HAL_BGMISS counts finds)
	move.w  d7,d0
	lsl.w   #7,d0
	lea     TM_DIRTY,a0
	adda.w  d0,a0
	moveq   #32-1,d0
.cl:	clr.l   (a0)+
	dbra    d0,.cl
	bra.w   .nl
.cols:	jsr     hal_bg_scroll           ; d1 = y scroll: the first block row in view
	lsr.w   #4,d1
	move.w  d1,d6
	move.w  d7,d0
	lsl.w   #7,d0
	lea     TM_DIRTY,a1
	adda.w  d0,a1
	move.w  d7,d0
	lsl.w   #5,d0
	lea     HAL_BG_COLSLOT,a2
	adda.w  d0,a2                   ; column -> slot
	lea     HAL_BG_PEND,a3
	adda.w  d0,a3                   ; per slot (LOW, ROW, R0 at fixed distances)
	moveq   #0,d4                   ; column
.c:	move.l  (a1),d5
	beq.w   .cn
	clr.l   (a1)
	moveq   #0,d3
	move.b  (a2,d4.w),d3            ; its slot (negative: not in view)
	bmi.w   .cn
	cmpi.w  #BG_COLS,d3
	bhs.w   .cn
	st      HAL_BG_WORK
	tst.b   (a3,d3.w)               ; being converted: all of it again
	bne.s   .full
	lea     HAL_BG_LOW-HAL_BG_PEND(a3),a0
	tst.b   (a0,d3.w)
	bne.s   .full
	move.l  d5,d0                   ; one row?
	subq.l  #1,d0
	and.l   d5,d0
	bne.s   .full
	moveq   #-1,d2                  ; its number
.b:	addq.w  #1,d2
	btst    d2,d5
	beq.s   .b
	move.w  d2,d0                   ; the conversion's last row of 32: R0 = row - 31
	addq.w  #1,d0
	andi.w  #31,d0
	lea     HAL_BG_R0-HAL_BG_PEND(a3),a0
	move.b  d0,(a0,d3.w)
	lea     HAL_BG_ROW-HAL_BG_PEND(a3),a0
	move.b  #31,(a0,d3.w)
	move.w  d2,d0                   ; in view: pass 1, else pass 2
	sub.w   d6,d0
	andi.w  #31,d0
	cmpi.w  #VIS_ROWS,d0
	blo.s   .p1
	lea     HAL_BG_LOW-HAL_BG_PEND(a3),a0
	st      (a0,d3.w)
	bra.s   .cn
.p1:	st      (a3,d3.w)
	bra.s   .cn
.full:	st      (a3,d3.w)               ; (as hal_bg_window does for a new column)
	lea     HAL_BG_ROW-HAL_BG_PEND(a3),a0
	sf      (a0,d3.w)
	lea     HAL_BG_LOW-HAL_BG_PEND(a3),a0
	sf      (a0,d3.w)
.cn:	addq.l  #4,a1
	addq.w  #1,d4
	cmpi.w  #32,d4
	blo.w   .c
.nl:	addq.w  #1,d7
	cmpi.w  #2,d7
	blo.w   .lay
.x:	rts
