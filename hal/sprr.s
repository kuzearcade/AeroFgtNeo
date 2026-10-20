; Real-cart video, sprites kept from frame to frame (SPR_RETAIN builds; hal/spr.s
; holds the conversion proper: hal_spr_go and the shape routines).
;
; Most of a frame's sprites are the previous frame's again, the same tiles, often at
; the same place (movie7: 49% the same, 35% moved, 17% new tiles; work/retainsim.py).
; So the shown frame's Neo sprites stay where they are: a sprite of the next list with
; the same tiles (attribute words but the position) as one shown keeps its columns
; (moved: its head's y (SCB3) and x (SCB4) rewritten at the flip), only the others are
; converted, into free columns, and the shown ones not kept are hidden at the flip.
;
; Draw order: higher Neo number on top, the list's last entry on top, so the columns
; follow the list: the shown table is in list order with increasing columns, a list
; entry keeps a shown sprite only in order (the match walks both lists forwards, with
; a look-ahead), and the new ones go into the gaps between the kept ones around them.
; A new sprite that does not fit makes the next kept one give its columns up (it is
; converted again, elsewhere); with none left after it, what does not fit is dropped
; (a logged slip).
;
; Columns: the pool SPR_PB..SPR_PT.  A free column has SCB3 0 (height 0, not chained):
; a placed sprite gets its chained columns' SCB3 ($40) when it is placed (its head
; stays 0, so the chain is hidden), its head at the flip; the flip writes 0 into the
; head of every shown sprite not kept (its chain hangs off a height-0 head), and the
; reclaim after it zeroes the chain and restores zoomed columns' SCB2, and only then
; frees the columns (R_BUSY: shown, placed or not reclaimed yet).
;
; Tables (two, swapped at each flip: the shown one, S, and the pending one, P), in the
; sprite RAM's unused 0x1d1000-0x1d1fff (the game writes it only in its boot RAM test
; and clear; R_MAGIC notices that and starts over with every pool column hidden):
;   T_LIST  the conversion's list (words 32 + j for the new entries j)
;   T_ATTR  per entry j: w0-w3 (at 8 x (32 + j): hal_spr_go reads them as sprite RAM)
;   T_META  per entry j: first column, end column, SCB3 head value, link
; and the state block (0x1d0400-, also unused by the game).
;
; Work (hal_spr_work, budgeted like the ring's conversion, resumable): reclaim the old
; table, then for the slot's list: match (copy the visible entries into P, find the
; kept ones), place (columns for the new ones; the flip's writes: moved heads, hides),
; convert (hal_spr_go on P's list).  Complete: shown by the next flip.

PR_N            equ 112             ; entries a table holds (more: dropped)
PR_LB           equ 32              ; list word of entry j: PR_LB + j
PR_LOOK         equ 16              ; match look-ahead in the shown table
T_LIST          equ 0
T_ATTR          equ 8*PR_LB
T_META          equ T_ATTR+8*PR_N
T_SIZE          equ T_META+8*PR_N
M_COL           equ 0               ; first column
M_END           equ 2               ; one past the last
M_SCB3          equ 4               ; its head's SCB3 (height, sticky 0)
M_LINK          equ 6               ; P: the shown entry kept (-1: new); S: -2 once kept
	if T_SIZE>$800
	fail "retained sprite table too large"
	endif
PR_T0           equ G_SPRRAM+$1000
PR_T1           equ G_SPRRAM+$1800
PR_ST           equ G_SPRRAM+$400   ; state block (0x1d0400, unused by the game)
R_MAGIC         equ PR_ST+0         ; w
R_SBASE         equ PR_ST+2         ; l: the shown table
R_PBASE         equ PR_ST+6         ; l: the table P is built in
R_SN            equ PR_ST+10        ; w: shown entries
R_PN            equ PR_ST+12        ; w: pending entries
R_PH            equ PR_ST+14        ; w: P: 0 none, 1 match, 2 place, 3 convert
R_LI            equ PR_ST+16        ; w: match: list word index
R_SP            equ PR_ST+18        ; w: match: entries of the matched table passed
R_PI            equ PR_ST+20        ; w: place: next entry
R_LEND          equ PR_ST+22        ; w: place: end column of the entries placed
R_RCL           equ PR_ST+24        ; w: reclaim: next R_RL entry (-1: none pending)
R_RLN           equ PR_ST+26        ; w: reclaim list entries
R_NEW           equ PR_ST+28        ; w: convert: entries in the list (-1: done)
R_HP0           equ PR_ST+30        ; w: convert: head pairs before it
R_RDY           equ PR_ST+32        ; w: P: shown from frame
R_HID           equ PR_ST+34        ; w: place: next shown entry checked for hiding
R_NK            equ PR_ST+36        ; w: place: the next kept entry (cached)
R_MBASE         equ PR_ST+38        ; l: the table P is matched against (Q if waiting)
R_MN            equ PR_ST+42        ; w: its entries
R_QF            equ PR_ST+44        ; w: a complete frame Q waits for its flip
R_QBASE         equ PR_ST+46        ; l: Q's table
R_QN            equ PR_ST+50        ; w: Q's entries
R_QRDY          equ PR_ST+52        ; w: Q: shown from frame
R_QMIX          equ PR_ST+54        ; w: Q's slip flags (HAL_SPR_MIX)
R_PSS           equ PR_ST+56        ; l: P's set state (its flip list; hal_spr_go's a6)
R_QSS           equ PR_ST+60        ; l: Q's
R_RLH           equ PR_ST+112       ; w: reclaim ring: next to reclaim
R_RLT           equ PR_ST+114       ; w: next free
R_RLB           equ PR_ST+116       ; w: reclaim up to here (the last flip's)
R_QRLT          equ PR_ST+118       ; w: Q's end in the ring
R_BKI           equ PR_ST+120       ; w: place: backtrack: next entry to take back (0: none)
R_BKS           equ PR_ST+122       ; w: place: backtrack: the kept entry given up
R_BUSY          equ PR_ST+64        ; 48 bytes: column bitmap (bit c&7 of byte c>>3)
R_RL            equ PR_ST+128       ; reclaim ring: per sprite hidden at a flip: first
RL_MAX          equ (1024-128)/4    ; column, columns << 8 | zoomed (2 x PR_N at most)
	if RL_MAX<2*PR_N
	fail "reclaim ring too small"
	endif
PR_MAGIC        equ $52e7
RES_LINES       equ 4               ; lines one step of match/place/reclaim may take

; ================================================================ slot start
; A frame still in work began in an earlier slot (a carried, maybe mixed frame).
hal_spr_slot:
	sf      HAL_SPR_DONE
	cmpi.w  #1,R_PH                 ; (only while its list is being read)
	bne.w   .x
	bset    #0,HAL_SPR_MIX
	addq.l  #1,HAL_SPR_CARRY
.x:	rts

; ================================================================ init
hal_spr_init:
	clr.w   HAL_SPR_W               ; (hal_spr_go's slip flags: HAL_SPR_MIX+0)
	move.w  #-1,HAL_SPR_SHOWN
	clr.l   HAL_SPR_MIX
	sf      HAL_SPR_DONE
	clr.l   HAL_SPR_RA5
	clr.l   HAL_SPR_DROP
	clr.l   HAL_SPR_LATE
	clr.l   HAL_SPR_ZOOM
	clr.l   HAL_SPR_CARRY
	clr.l   HAL_SPR_MIXN
	clr.l   HAL_SPR_DROPN
	clr.l   HAL_SPR_VZN
	clr.l   HAL_SPR_PRIN
	clr.w   HAL_SPR_TAILU
	clr.w   HAL_SPR_DBGI
	clr.w   HAL_SPR_DBGD
; (and from hal_spr_work when R_MAGIC is gone: the boot RAM test)
pr_reset:
	lea     REG_VRAMRW,a3
	move.w  #1,REG_VRAMMOD
	move.w  #SCB2+SPR_PB,REG_VRAMADDR
	move.w  #SPR_POOL-1,d1
.s2:	move.w  #$0fff,(a3)
	move.b  d0,REG_WATCHDOG
	dbra    d1,.s2
	move.w  #SCB3+SPR_PB,REG_VRAMADDR
	move.w  #SPR_POOL-1,d1
.s3:	move.w  #0,(a3)
	move.b  d0,REG_WATCHDOG
	dbra    d1,.s3
	lea     R_BUSY,a0
	moveq   #48/4-1,d1
.b:	clr.l   (a0)+
	dbra    d1,.b
	move.l  #PR_T0,R_SBASE
	move.l  #PR_T1,R_PBASE
	clr.w   R_SN
	clr.w   R_PN
	clr.w   R_PH
	clr.w   R_QF
	clr.w   R_RLH
	clr.w   R_RLT
	clr.w   R_RLB
	move.l  #G_SPRBUF,R_PSS
	move.l  #G_SPRBUF+SS_SIZE,R_QSS
	move.w  #-1,R_RCL
	clr.w   SS_HOFF+G_SPRBUF
	clr.w   SS_HOFF+G_SPRBUF+SS_SIZE
	move.w  #PR_MAGIC,R_MAGIC
	rts

; ================================================================ budget
; Each step is charged an upper bound of its cost (16-cycle units) from the credit in
; d7 (hal_spr_refill: from the line counter, when it runs out); out of time: .out.
PR_KS           equ 1               ; (charge scale)
; the same, the units in a data register (not d0)
PR_CHARGE_D	macro
	sub.w   \1,d7
	bpl.s   .q\@
	move.w  \1,d0
	bsr     hal_spr_refill
	bmi.w   .out
.q\@:
	endm
PR_CHARGE	macro
	subi.w  #(\1)*PR_KS,d7
	bpl.s   .q\@
	move.w  #(\1)*PR_KS,d0
	bsr     hal_spr_refill
	bmi.w   .out
.q\@:
	endm

; Z clear (and d0 > 0): fewer than RES_LINES lines left to KER.  Clobbers d0.
pr_short:
	bsr     hal_spr_left
	addq.w  #RES_LINES,d0
	tst.w   d0
	bgt.w   .s
	moveq   #0,d0                   ; (Z set)
	rts
.s:	moveq   #1,d0
	rts

; ================================================================ work
; Z set: nothing left to do now; Z clear: the budget stopped it.
hal_spr_work:
	tst.b   HAL_OUT
	bne.w   .no
	bsr     hal_spr_klim
	addq.w  #3,d0
	bgt.w   .no
	cmpi.w  #PR_MAGIC,R_MAGIC       ; tables overwritten (boot RAM test): start over
	beq.w   .m
	bsr     hal_spr_left            ; (only with time: ~16k cycles)
	addi.w  #24,d0
	bgt.w   .no
	bsr     pr_reset
.m:	tst.w   R_RCL                   ; the sprites the last flip hid first
	bmi.w   .ph
	bsr     pr_reclaim
	bne.w   .no
	; each phase: d0 = 0 done (on to the next), 1 out of time, 2 blocked (Q waits)
	moveq   #0,d7                   ; (no credit: the first step refills)
.ph:	move.w  R_PH,d0
	add.w   d0,d0
	move.w  .tab(pc,d0.w),d0
	jsr     .tab(pc,d0.w)
	tst.w   d0
	beq.w   .ph
	subq.w  #1,d0
	beq.w   .no
.ok:	moveq   #0,d0                   ; Z set
	rts
.tab:	dc.w    .idle-.tab,pr_mp-.tab,pr_hide-.tab,pr_conv-.tab
.idle:	moveq   #2,d0
	tst.b   HAL_SPR_DONE            ; this slot's list taken already
	bne.w   .ix
	bsr     pr_short
	bne.w   .ix1
	st      HAL_SPR_DONE
	bsr     pr_begin
	moveq   #0,d0
.ix:	rts
.ix1:	moveq   #1,d0
	rts
.no:	tst.b   HAL_BG_EARLY            ; (after the real vblank: the slot is out of
	bne.w   .no1                    ; time, the rest ends quickly)
	st      HAL_OUT
.no1:	moveq   #1,d0                   ; Z clear
	rts

; a new frame: P empty, its set state cleared
pr_begin:
	clr.w   R_PN
	clr.w   R_LI
	clr.w   R_SP
	clr.w   R_PI
	clr.w   R_HID
	clr.w   R_NK
	clr.w   R_BKI
	move.w  #SPR_PB,R_LEND
	move.w  #1,R_PH
	move.w  HAL_FRAMES+2,d0         ; shown from the next slot on
	addq.w  #1,d0
	move.w  d0,R_RDY
	sf      HAL_SPR_MIX
	movea.l R_QSS,a6                ; P's flip list: the one Q's is not
	cmpa.l  #G_SPRBUF,a6
	beq.w   .s1
	lea     G_SPRBUF,a6
	bra.w   .s2
.s1:	lea     G_SPRBUF+SS_SIZE,a6
.s2:	move.l  a6,R_PSS
	sf      SS_PRIO(a6)
	clr.w   SS_HOFF(a6)
	clr.w   SS_ZN(a6)
	move.l  R_SBASE,R_MBASE         ; matched against what will be shown before it:
	move.w  R_SN,R_MN               ; Q if one waits, else the shown frame
	tst.w   R_QF
	beq.w   .m
	move.l  R_QBASE,R_MBASE
	move.w  R_QN,R_MN
.m:	movea.l R_MBASE,a0              ; none of its entries kept yet
	move.w  R_MN,d1
	bra.w   .l1
.l:	move.w  #-1,T_META+M_LINK(a0)
	addq.l  #8,a0
.l1:	dbra    d1,.l
	rts

; ================================================================ match
; The slot's list (from R_LI) into P: the visible entries' words, each linked to the
; shown entry with the same tiles if there is one in order (R_SP on, PR_LOOK of them).
; Z set: done (R_PH 2); Z clear: out of time.
; ================================================================ match and place
; The slot's list (from R_LI) in one pass, in list order (columns increasing): each
; visible entry is copied into P and looked for in the matched table M (Q if one
; waits, else the shown frame) from the cursor on (PR_LOOK entries, the same tiles).
; Found: kept, in the M entry's columns (M's columns increase in its order, the cursor
; only moves forwards, so the order holds); moved: its head and x into the flip list.
; Not found: new, placed now in the first free run of its columns from the last
; placed entry's end up to the cursor entry's first column (every entry kept later
; lies above that); not fitting, the cursor entry is passed (it will not be kept: the
; gap grows).  With M passed and still no room: only the entries before it that it
; overlaps on screen must lie below it (not all), or it is dropped.
; State in registers through the pass (written back at every exit):
;   a3 list position, a4 next P entry (attributes), a5 the cursor (M attributes),
;   a6 M's end, a0 G_SPRRAM, d6 the last placed entry's end column, d7 the credit.
; d0: 0 done (R_PH 2), 1 out of time.
MP_ENTRY        equ 120             ; units: decode, copy, the match, a kept one
MP_NEW          equ 60              ; a take (+ 3 a column of the gap searched)
MP_OVL          equ 60              ; the overlap fallback (+ 12 an entry, 3 a column)
pr_mp:
	lea     G_SPRRAM,a0
	movea.l a0,a3
	move.w  R_LI,d0
	add.w   d0,d0
	adda.w  d0,a3
	movea.l R_PBASE,a4
	lea     T_ATTR(a4),a4
	move.w  R_PN,d0
	lsl.w   #3,d0
	adda.w  d0,a4
	movea.l R_MBASE,a6
	lea     T_ATTR(a6),a6
	movea.l a6,a5
	move.w  R_SP,d0
	lsl.w   #3,d0
	adda.w  d0,a5
	move.w  R_MN,d0
	lsl.w   #3,d0
	adda.w  d0,a6
	move.w  R_LEND,d6
.e:	PR_CHARGE MP_ENTRY
	cmpa.l  #G_SPRRAM+$400,a3       ; (MAME's limit: 0x200 words)
	bhs.w   .end
	move.w  (a3)+,d1                ; list word
	btst    #14,d1
	bne.w   .end
	tst.w   d1
	bmi.w   .e                      ; (not drawn)
	andi.w  #$3ff,d1
	lsl.w   #3,d1
	movem.w (a0,d1.w),d2-d5         ; w0-w3
	; visible: oy < 224 or oy + 16 rows > 512, the same in x (as hal_spr_go)
	move.w  d2,d0
	andi.w  #$1ff,d0
	cmpi.w  #224,d0
	blo.w   .yv
	move.w  d2,d1
	andi.w  #$0e00,d1
	lsr.w   #5,d1                   ; 16 x ysize
	add.w   d0,d1
	cmpi.w  #512-16,d1
	bls.w   .e
.yv:	move.w  d3,d0
	andi.w  #$1ff,d0
	cmpi.w  #320,d0
	blo.w   .xv
	move.w  d3,d1
	andi.w  #$0e00,d1
	lsr.w   #5,d1
	add.w   d0,d1
	cmpi.w  #512-16,d1
	bls.w   .e
.xv:	movea.l R_PBASE,a1              ; P full?
	adda.w  #T_ATTR+8*PR_N,a1
	cmpa.l  a1,a4
	blo.w   .r
	addq.l  #1,HAL_SPR_DROP         ; (dropped, a slip)
	bset    #1,HAL_SPR_MIX
	bra.w   .e
.r:	movem.w d2-d5,(a4)
	; the same tiles in M from the cursor on (w3 first: it differs most)
	andi.w  #$fe00,d2               ; the key: w0 / w1 but the position
	andi.w  #$fe00,d3
	movea.l a5,a2
	lea     8*PR_LOOK(a5),a1
	cmpa.l  a6,a1
	bls.w   .f1
	movea.l a6,a1
	bra.w   .f1
.f:	cmp.w   6(a2),d5
	bne.w   .n
	cmp.w   4(a2),d4
	bne.w   .n
	move.w  (a2),d1
	andi.w  #$fe00,d1
	cmp.w   d1,d2
	bne.w   .n
	move.w  2(a2),d1
	andi.w  #$fe00,d1
	cmp.w   d1,d3
	beq.w   .k
.n:	addq.l  #8,a2
.f1:	cmpa.l  a1,a2
	blo.w   .f
	bra.w   .new
	; kept: M entry a2's columns
.k:	move.w  T_META-T_ATTR+M_COL(a2),d0
	cmp.w   d6,d0                   ; (below the ones placed: new after all)
	blo.w   .new
	move.w  #-2,T_META-T_ATTR+M_LINK(a2)    ; (not hidden)
	clr.w   T_META-T_ATTR+M_LINK(a4)        ; (kept)
	move.w  d0,T_META-T_ATTR+M_COL(a4)
	move.w  T_META-T_ATTR+M_END(a2),d6
	move.w  d6,T_META-T_ATTR+M_END(a4)
	move.w  T_META-T_ATTR+M_SCB3(a2),d2
	move.l  (a4),d1                 ; moved: y and x at the flip
	cmp.l   (a2),d1
	beq.w   .km
	move.w  (a4),d3                 ; SCB3 = (496 - oy) << 7 | height (w0's higher
	neg.w   d3                      ; bits fall off)
	lsl.w   #7,d3
	addi.w  #496<<7,d3
	andi.w  #$7f,d2
	or.w    d3,d2
	movea.l R_PSS,a1                ; two flip pairs: SCB3, SCB4 = ox << 7
	move.w  SS_HOFF(a1),d1
	cmpi.w  #2*SS_MAXHEAD-4,d1
	bhi.w   .pf
	addq.w  #4,SS_HOFF(a1)
	adda.w  d1,a1
	move.w  d0,d4
	addi.w  #SCB3,d4
	move.w  d4,SS_HADR(a1)
	move.w  d2,SS_HVAL(a1)
	addi.w  #SCB4-SCB3,d4
	move.w  d4,SS_HADR+2(a1)
	move.w  2(a4),d3
	lsl.w   #7,d3
	move.w  d3,SS_HVAL+2(a1)
	bra.w   .km
.pf:	addq.l  #1,HAL_SPR_DROP         ; (no room in the flip list: a slip)
	bset    #1,HAL_SPR_MIX
.km:	move.w  d2,T_META-T_ATTR+M_SCB3(a4)
	lea     8(a2),a5                ; the cursor after it
	addq.l  #8,a4
	bra.w   .e
	; new: the first free run up to the cursor entry's first column
.new:	move.w  #-1,T_META-T_ATTR+M_LINK(a4)
	move.w  2(a4),d1                ; columns: xsize + 1
	rol.w   #7,d1
	andi.w  #7,d1
	addq.w  #1,d1
.nt:	move.w  #SPR_PT+1,d5            ; the gap's end
	cmpa.l  a6,a5
	bhs.w   .ng
	move.w  T_META-T_ATTR+M_COL(a5),d5
.ng:	move.w  d5,d2                   ; charge: ~48 cycles a column of the gap at
	sub.w   d6,d2                   ; most (the search), + the take
	bpl.w   .g1
	moveq   #0,d2
.g1:	move.w  d2,d4
	add.w   d2,d2
	add.w   d4,d2
	addi.w  #MP_NEW,d2
	PR_CHARGE_D d2
	move.w  d6,d4
	bsr     pr_free_run             ; d4 from, d5 limit, d1 columns -> d4 start (N: none)
	bmi.w   .nf
	move.w  d4,T_META-T_ATTR+M_COL(a4)
	bsr     pr_take
	add.w   d1,d4
	move.w  d4,T_META-T_ATTR+M_END(a4)
	move.w  d4,d6
	addq.l  #8,a4
	bra.w   .e
.nf:	cmpa.l  a6,a5                   ; pass the cursor entry: the gap grows
	bhs.w   .ov
	addq.l  #8,a5
	addq.w  #1,HAL_SPR_DBGI         ; (diagnostics: entries passed)
	bra.w   .nt
	; M passed: below it only the earlier entries it overlaps on screen
.ov:	move.l  a4,d2                   ; charge: the scan of P (~180 cycles an entry)
	sub.l   R_PBASE,d2              ; and a search of the whole pool
	subi.w  #T_ATTR,d2
	lsr.w   #3,d2
	mulu    #12,d2
	addi.w  #MP_OVL+3*SPR_POOL,d2
	PR_CHARGE_D d2
	bsr     pr_overlap_lo           ; d4 = the lowest column allowed
	move.w  #SPR_PT+1,d5
	bsr     pr_free_run
	bmi.w   .dr
	move.w  d4,T_META-T_ATTR+M_COL(a4)
	bsr     pr_take
	add.w   d1,d4
	move.w  d4,T_META-T_ATTR+M_END(a4)
	cmp.w   d6,d4                   ; (the strict order's bound: at least its end)
	bls.w   .ov1
	move.w  d4,d6
.ov1:	addq.w  #1,HAL_SPR_DBGD         ; (diagnostics: out of strict order)
	addq.l  #8,a4
	bra.w   .e
.dr:	move.w  #-3,T_META-T_ATTR+M_LINK(a4)    ; no room: dropped
	clr.w   T_META-T_ATTR+M_COL(a4)
	clr.w   T_META-T_ATTR+M_END(a4)
	addq.l  #1,HAL_SPR_DROP
	bset    #1,HAL_SPR_MIX
	addq.l  #8,a4
	bra.w   .e
.end:	bsr.s   .wb
	move.w  #2,R_PH
	clr.w   R_HID
	moveq   #0,d0
	rts
.out:	bsr.s   .wb
	moveq   #1,d0
	rts
.wb:	move.l  a3,d0                   ; the state back
	sub.l   #G_SPRRAM,d0
	lsr.w   #1,d0
	move.w  d0,R_LI
	move.l  a4,d0
	sub.l   R_PBASE,d0
	subi.w  #T_ATTR,d0
	lsr.w   #3,d0
	move.w  d0,R_PN
	move.l  a5,d0
	sub.l   R_MBASE,d0
	subi.w  #T_ATTR,d0
	lsr.w   #3,d0
	move.w  d0,R_SP
	move.w  d6,R_LEND
	rts

; d4 = the end column of the last-placed entry before a4 (in P) that overlaps a4's
; on screen (zoom not counted: full size), SPR_PB if none.  Keeps all but d4.
pr_overlap_lo:
	movem.l d0-d3/d5/a1-a2,-(sp)
	move.w  #SPR_PB,d4
	bsr.w   .rect                   ; d0-d3: x0 y0 x1 y1 of (a4)
	movem.w d0-d3,-(sp)
	movea.l R_PBASE,a1
	lea     T_ATTR(a1),a1
.l:	cmpa.l  a4,a1
	bhs.w   .x
	move.w  T_META-T_ATTR+M_END(a1),d5
	cmp.w   T_META-T_ATTR+M_COL(a1),d5
	bls.w   .nx                     ; (not placed)
	cmp.w   d4,d5
	bls.w   .nx                     ; (no higher bound)
	movea.l a4,a2
	movea.l a1,a4
	bsr.w   .rect
	movea.l a2,a4
	cmp.w   4(sp),d2                ; x0 < x1' and x0' < x1, y the same
	ble.w   .nx
	cmp.w   (sp),d0
	bge.w   .nx
	cmp.w   6(sp),d3
	ble.w   .nx
	cmp.w   2(sp),d1
	bge.w   .nx
	move.w  d5,d4
.nx:	addq.l  #8,a1
	bra.w   .l
.x:	addq.l  #8,sp
	movem.l (sp)+,d0-d3/d5/a1-a2
	rts
.rect:	move.w  2(a4),d0                ; x0 (ox, ox >= 320 counted from -512)
	move.w  d0,d2
	andi.w  #$1ff,d0
	cmpi.w  #320,d0
	blo.s   .r1
	subi.w  #512,d0
.r1:	rol.w   #7,d2                   ; x1 = x0 + 16 columns
	andi.w  #7,d2
	addq.w  #1,d2
	lsl.w   #4,d2
	add.w   d0,d2
	move.w  (a4),d1                 ; y0, y1 the same with rows
	move.w  d1,d3
	andi.w  #$1ff,d1
	cmpi.w  #224,d1
	blo.s   .r2
	subi.w  #512,d1
.r2:	rol.w   #7,d3
	andi.w  #7,d3
	addq.w  #1,d3
	lsl.w   #4,d3
	add.w   d1,d3
	rts

; ================================================================ hide
; The M entries not kept: hidden at the flip (and reclaimed after it), one a step.
; d0: 0 done (R_PH 3), 1 out of time.
pr_hide:
	movea.l R_PSS,a6
.e:	PR_CHARGE 50
	move.w  R_HID,d0
	cmp.w   R_MN,d0
	bhs.w   .hx
	addq.w  #1,R_HID
	movea.l R_MBASE,a0
	lsl.w   #3,d0
	lea     (a0,d0.w),a0
	cmpi.w  #-2,T_META+M_LINK(a0)
	beq.w   .e
	move.w  T_META+M_COL(a0),d4
	move.w  T_META+M_END(a0),d1
	sub.w   d4,d1                   ; (dropped: no columns)
	ble.w   .e
	move.w  R_RLT,d0                ; reclaimed after the flip (ring)
	addq.w  #1,d0
	cmpi.w  #RL_MAX,d0
	blo.w   .rw
	moveq   #0,d0
.rw:	cmp.w   R_RLH,d0                ; (full: never, see RL_MAX)
	beq.w   .rf
	move.w  R_RLT,-(sp)
	move.w  d0,R_RLT
	move.w  (sp)+,d0
	lsl.w   #2,d0
	lea     R_RL,a1
	move.w  d4,(a1,d0.w)
	lsl.w   #8,d1
	move.w  T_ATTR(a0),d2           ; zoomed?
	or.w    T_ATTR+2(a0),d2
	andi.w  #$f000,d2
	beq.w   .rz
	addq.w  #1,d1
.rz:	move.w  d1,2(a1,d0.w)
.rf:	moveq   #0,d2
	bsr     pr_pair_scb3
	bra.w   .e
.hx:	move.w  #3,R_PH
	clr.w   R_NEW
	moveq   #0,d0
	rts
.out:	moveq   #1,d0
	rts

; a flip pair for SCB3 of column d4 = d2 (pr_pair: address d4, value d3; past the
; list's room: not written, a slip).  Keeps d0-d2, d5-d7, a0-a7; d3 = d2, d4 = address.
pr_pair_scb3:
	addi.w  #SCB3,d4
	move.w  d2,d3
pr_pair:
	move.l  a2,-(sp)
	move.w  d0,-(sp)
	movea.l R_PSS,a2
	move.w  SS_HOFF(a2),d0
	cmpi.w  #2*SS_MAXHEAD,d0
	bhs.w   .f
	addq.w  #2,SS_HOFF(a2)
	move.w  d4,SS_HADR(a2,d0.w)
	adda.w  d0,a2
	move.w  d3,SS_HVAL(a2)
.x:	move.w  (sp)+,d0
	movea.l (sp)+,a2
	rts
.f:	addq.l  #1,HAL_SPR_DROP
	bset    #1,HAL_SPR_MIX
	bra.w   .x

; d4 = the first free run of d1 columns at or after d4 that ends at d5 at most (N set:
; none).  Full bitmap bytes are skipped 8 columns at a time.  Keeps d0-d3, d5-d7, a0-a7.
pr_free_run:
	movem.l d0/d2/d6/a0,-(sp)
	lea     R_BUSY,a0
.s:	move.w  d4,d0
	add.w   d1,d0
	cmp.w   d5,d0
	bhi.w   .none
	move.w  d4,d0
	lsr.w   #3,d0
	moveq   #7,d2
	and.w   d4,d2
	bne.w   .b1
	cmpi.b  #$ff,(a0,d0.w)          ; (a whole busy byte)
	bne.w   .b1
	addq.w  #8,d4
	bra.w   .s
.b1:	btst    d4,(a0,d0.w)
	beq.w   .f
	addq.w  #1,d4
	bra.w   .s
.f:	move.w  d4,d2                   ; d4 free: the rest of the run?
	move.w  d1,d6
	subq.w  #2,d6
	bmi.w   .ok
.c:	addq.w  #1,d2
	move.w  d2,d0
	lsr.w   #3,d0
	btst    d2,(a0,d0.w)
	bne.w   .b
	dbra    d6,.c
.ok:	movem.l (sp)+,d0/d2/d6/a0       ; free: d4
	move    #0,ccr
	rts
.b:	move.w  d2,d4                   ; busy: on after it
	addq.w  #1,d4
	bra.w   .s
.none:	movem.l (sp)+,d0/d2/d6/a0
	move    #8,ccr                  ; N
	rts

; d1 columns from d4: busy, all but the first chained ($40; the first, the head,
; stays 0 until the flip).  Keeps d0-d7, a0-a2, a4-a6.
pr_take:
	move.l  a3,-(sp)
	movem.l d0-d2/a0,-(sp)
	lea     R_BUSY,a0
	move.w  d4,d2
	move.w  d1,d0
	subq.w  #1,d0
.b:	move.w  d2,d1
	lsr.w   #3,d1
	bset    d2,(a0,d1.w)
	addq.w  #1,d2
	dbra    d0,.b
	movem.l (sp),d0-d2/a0
	subq.w  #2,d1                   ; chained columns - 1
	bmi.w   .x
	lea     REG_VRAMRW,a3
	move.w  #1,REG_VRAMMOD
	move.w  d4,d0
	addi.w  #SCB3+1,d0
	move.w  d0,REG_VRAMADDR
	moveq   #$40,d0
.c:	move.w  d0,(a3)                 ; (18 cycles apart)
	dbra    d1,.c
.x:	movem.l (sp)+,d0-d2/a0
	movea.l (sp)+,a3
	rts

; d1 columns from d4 back: free, all SCB3 0 again (the chained ones were $40).  Keeps
; d0-d7, a0-a2, a4-a6.
pr_untake:
	move.l  a3,-(sp)
	movem.l d0-d2/a0,-(sp)
	lea     R_BUSY,a0
	move.w  d4,d2
	move.w  d1,d0
	subq.w  #1,d0
.b:	move.w  d2,d1
	lsr.w   #3,d1
	bclr    d2,(a0,d1.w)
	addq.w  #1,d2
	dbra    d0,.b
	movem.l (sp),d0-d2/a0
	subq.w  #2,d1                   ; chained columns - 1
	bmi.w   .x
	lea     REG_VRAMRW,a3
	move.w  #1,REG_VRAMMOD
	move.w  d4,d0
	addi.w  #SCB3+1,d0
	move.w  d0,REG_VRAMADDR
	moveq   #0,d0
.c:	move.w  d0,(a3)
	dbra    d1,.c
.x:	movem.l (sp)+,d0-d2/a0
	movea.l (sp)+,a3
	rts

; ================================================================ convert
; P's new entries (link -1) into the columns pr_place chose: hal_spr_go on a list of
; them (it reads the attribute words from P, and each entry's columns: SPR_RETAIN code
; at its .ent).  The heads go into the flip's list; their values into P (for moves).
; Z set: done (R_PH 4).
pr_conv:
	movea.l R_PSS,a6
	tst.l   HAL_SPR_RA5
	bne.w   .go
	tst.w   R_NEW
	bne.w   .fin                    ; (built: nothing was left to convert)
	PR_CHARGE 300                   ; the list (<= 112 x ~40 cycles)
	movea.l R_PBASE,a0
	lea     T_LIST(a0),a5
	lea     T_META+M_LINK(a0),a1
	move.w  R_PN,d1
	moveq   #PR_LB,d0
	bra.w   .l1
.l:	cmpi.w  #-1,(a1)
	bne.w   .l2
	move.w  d0,(a5)+
	addq.w  #1,R_NEW
.l2:	addq.w  #1,d0
	addq.l  #8,a1
.l1:	dbra    d1,.l
	move.w  SS_HOFF(a6),R_HP0
	tst.w   R_NEW
	beq.w   .fin
	move.l  a5,HAL_SPR_RA5
.go:	movea.l HAL_SPR_RA5,a5
	bsr     hal_spr_go
	beq.s   .gd
	moveq   #0,d7                   ; (its own credit is gone: refill)
	bra.w   .out
.gd:	moveq   #0,d7
	PR_CHARGE 300                   ; the head values (<= 112 x ~40 cycles)
	; heads written (front first: the list from its end) -> P's head values
	movea.l R_PBASE,a0
	move.w  SS_HOFF(a6),d1
	move.w  R_HP0,d0
	sub.w   d0,d1
	lsr.w   #1,d1                   ; heads converted
	lea     SS_HVAL(a6),a1
	adda.w  d0,a1
	move.w  R_NEW,d2
	add.w   d2,d2
	lea     T_LIST(a0,d2.w),a2      ; the list's end
	lea     T_META+M_SCB3(a0),a3
	bra.w   .h1
.h:	move.w  -(a2),d0
	subi.w  #PR_LB,d0
	lsl.w   #3,d0
	move.w  (a1)+,(a3,d0.w)
.h1:	dbra    d1,.h
	move.w  #-1,R_NEW               ; (done)
.fin:	moveq   #2,d0                   ; (a Q still waits: this one after its flip)
	tst.w   R_QF
	bne.w   .fx
	move.l  R_PBASE,R_QBASE        ; complete: Q, waiting for its flip; P is built
	move.w  R_PN,R_QN               ; in the shown table from now on (all it holds
	move.w  R_RDY,R_QRDY            ; for later is in the flip and reclaim lists)
	move.b  HAL_SPR_MIX,R_QMIX+1
	move.l  R_PSS,R_QSS
	move.w  R_RLT,R_QRLT
	move.w  #1,R_QF
	move.l  R_SBASE,R_PBASE
	clr.w   R_PH
	moveq   #0,d0                   ; (on: this slot's list, if not taken yet)
.fx:	rts
.out:	moveq   #1,d0
	rts

; ================================================================ reclaim
; The old table's sprites not kept (hidden by the flip): their chained columns 0 again,
; zoomed ones' SCB2 full size, the columns free.  Z set: done.
pr_reclaim:
.e:	move.w  R_RLH,d0
	cmp.w   R_RLB,d0
	beq.w   .done
	PR_CHARGE 80
	move.w  R_RLH,d0
	move.w  d0,d1
	addq.w  #1,d1
	cmpi.w  #RL_MAX,d1
	blo.w   .h1
	moveq   #0,d1
.h1:	move.w  d1,R_RLH
	lsl.w   #2,d0
	lea     R_RL,a0
	move.w  (a0,d0.w),d4            ; first column
	move.w  2(a0,d0.w),d1
	move.w  d1,d5                   ; (bit 0: zoomed)
	lsr.w   #8,d1                   ; columns
	lea     REG_VRAMRW,a3
	move.w  #1,REG_VRAMMOD
	move.w  d1,d2
	subq.w  #2,d2                   ; chained columns - 1
	bmi.w   .z
	move.w  d4,d0
	addi.w  #SCB3+1,d0
	move.w  d0,REG_VRAMADDR
	moveq   #0,d0
.c:	move.w  d0,(a3)
	dbra    d2,.c
.z:	btst    #0,d5                   ; zoomed: SCB2 full size again
	beq.w   .f
	move.w  d4,d0
	addi.w  #SCB2,d0
	move.w  d0,REG_VRAMADDR
	move.w  d1,d2
	subq.w  #1,d2
	move.w  #$0fff,d0
.zc:	move.w  d0,(a3)
	dbra    d2,.zc
.f:	lea     R_BUSY,a1               ; free
	move.w  d4,d2
	subq.w  #1,d1
.fb:	move.w  d2,d0
	lsr.w   #3,d0
	bclr    d2,(a1,d0.w)
	addq.w  #1,d2
	dbra    d1,.fb
	bra.w   .e
.done:	move.w  #-1,R_RCL
	moveq   #0,d0
	rts
.out:	moveq   #1,d0
	rts

; ================================================================ flip
; Inside the real vblank: a complete P that may be shown now: its writes (heads of the
; new and moved sprites, x of the moved, 0 into the hidden ones' heads), then P is the
; shown table, the old one waits for its reclaim.  Time: 24 cycles a write + 400.
hal_spr_flip:
	tst.w   R_QF
	beq.w   .none
	move.w  R_QRDY,d1
	sub.w   HAL_FRAMES+2,d1
	bgt.w   .none                   ; (from the next slot on)
	movea.l R_QSS,a5
	move.w  SS_HOFF(a5),d1
	moveq   #98,d0
	add.w   d1,d0
	lsr.w   #6,d0
	bsr     hal_late_n
	bne.w   .defer
	lea     REG_VRAMRW,a3
	lea     REG_VRAMADDR,a4
	lea     SS_HADR(a5),a0
	lea     SS_HVAL(a5),a1
	move.w  SS_HOFF(a5),d2
	add.w   d2,d2
	lea     .se(pc),a2
	suba.w  d2,a2
	jmp     (a2)
	rept SS_MAXHEAD
	move.w  (a0)+,(a4)
	move.w  (a1)+,(a3)
	endr
.se:	move.l  R_QBASE,R_SBASE         ; Q is shown now; the sprites it hid: reclaimed
	move.w  R_QN,R_SN
	clr.w   R_QF
	move.w  R_QRLT,R_RLB            ; its hidden sprites: reclaim
	clr.w   R_RCL
	clr.w   SS_HOFF(a5)
	clr.w   HAL_SPR_SHOWN
	tst.b   SS_PRIO(a5)             ; sprites behind tilemap 1 shown in front?
	beq.w   .np
	addq.l  #1,HAL_SPR_PRIN
	bset    #2,HAL_SLIP+1
.np:	move.b  R_QMIX+1,d0
	btst    #1,d0                   ; sprites dropped?
	beq.w   .nd
	addq.l  #1,HAL_SPR_DROPN
	bset    #2,HAL_SLIP+1
.nd:	btst    #2,d0                   ; vertically zoomed sprites (approximated)?
	beq.w   .nz
	addq.l  #1,HAL_SPR_VZN
	bset    #2,HAL_SLIP+1
.nz:	btst    #0,d0                   ; carried over slots (a mixed list)?
	beq.w   .ex
	addq.l  #1,HAL_SPR_MIXN
	bset    #2,HAL_SLIP+1
.ex:	rts
.defer:	addq.l  #1,HAL_SPR_LATE         ; no time to flip: it waits
	addq.w  #1,HAL_SPR_DBGD
	bset    #2,HAL_SLIP+1
	rts
.none:	addq.l  #1,HAL_SPR_LATE         ; nothing complete to show
	bset    #2,HAL_SLIP+1
	rts
