; Real-cart video: the original's sprites as Neo sprites.
;
; MAME (vsystem_spr, aerofgt) draws at vblank V the sprite RAM it buffered at vblank
; V-1, i.e. the state the vblank handler of V-2 left (the handler is the only writer
; of the list; the lookup RAM changes rarely).  At slot k (before handler k) the RAM
; holds exactly what MAME buffers at vblank k and shows with the tilemaps of vblank
; k+1, which the HAL places in slot k+1.
;
; NSPRSETS sets of Neo sprites take turns: slot k converts the list straight into a
; hidden set (any time: before the real vblank, usually in harvested idle time), and
; slot k+1 flips it in inside its real vblank, which only rewrites the y/size word
; (SCB3) of each sprite's first column: every other column is chained to it, and a
; first column of size 0 hides its whole chain.  A set is only shown complete: a
; conversion the budget stops goes on in the next slot (in the list as it is then: a
; logged slip), and the slot's own list starts as soon as a set is free, so the time
; left once the older one is done is not lost.
;
; List (MAME draw_sprites): words 0..0x1ff until one has bit 14; entries with bit 15
; set are skipped; drawn from the last to the first with pdrawgfx, where a pixel a
; sprite has covered is never drawn again: the LAST entry ends on top (checked
; against MAME's own render of the original, 2026-10-11).  An entry
; points (bits 0-9, x4 words) at 4 attribute words:
;   0: zoomy:4 ysize:3 oy:9    1: zoomx:4 xsize:3 ox:9
;   2: flipy flipx color:6 (bit 5 = in front of tilemap 1) ---- --- map:1
;   3: map (low 16)            tile at (row, column) = lookup[(map + k) & 0x3fff],
;                              k in drawing order (flips reverse the order)
; Each sprite becomes xsize+1 chained Neo sprites (16-pixel columns) of ysize+1 tiles,
; behind tilemap 1 (Neo sprites between the two tilemaps' columns) or in front (above
; tilemap 1's), higher Neo number on top.  The list is converted front (last entry)
; first, back to the first entry, each set filled downwards, so the front gets the
; higher numbers.
;
; Column ring: the sets share the pool SPR_PB..SPR_PT (338 columns).  A set's columns
; are one run, numbered down from its start (the draw order needs that: a set that
; wrapped would put its back sprites on top), which is chosen when it begins
; (hal_spr_where): below the previous set's last column, or from SPR_PT (the columns
; left at the bottom wait for the ring to come round) when the room down to SPR_PB
; looks short and the top has more.  A set that reaches the tail can wait for it to
; move, one at SPR_PB can only drop, so a set that would start short at the bottom
; waits for a pending flip instead.  It may not reach the oldest set still in use
; (HAL_SPR_ORD, oldest first; the ring's tail is the column above that set's first
; one, HAL_SPR_START).  Out of columns there, the conversion waits (HAL_SPR_BLK, a
; logged slip when it is shown late) until the flip shows a newer set and the oldest
; is reclaimed; with nothing complete to show (nothing would free columns) or at
; SPR_PB (where it first starts again from SPR_PT, if that may help) it drops the
; rest instead.  One set at a time may be split: a set that began at SPR_PT and reaches
; the tail with nothing complete goes on below the previous set's end (its back
; sprites in the lower run keep the draw order); the column above that run (the
; previous set's last head, HAL_SPR_SPG) stays height 0 until the split set is
; reclaimed, even if the previous set is reclaimed first.  A set also drops sprites past SS_MAXHEAD heads
; (hal_spr_glim; drops are logged slips).
; Hidden columns: a non-head column is chained ($40) to the one below it, so every
; column outside the shown set must lead down to one of height 0 before it reaches a
; shown column (or tilemap 1's, below SPR_PB): SPR_PB and the tail column are kept 0
; (the tail is the column above the oldest set's first one), heads are written only by
; the flip (shown) and its hide (0), and a reclaimed set's heads and old tail are
; chained ($40) again.  The column above a set's first one is the previous set's last
; head, the tail, or past SPR_PT, so nothing chained can hang off a shown set either.
; Zoom is approximated (each column's shrink width = the gap to the next column, as
; MAME places them, but the Neo's shrink keeps other pixels than MAME's zoom except at
; widths 8 and 16; vertical zoom by the Neo's vertical shrink): a zoomed sprite makes
; its set a logged slip.
; Entirely off-screen sprites are dropped.
;
; VRAM: two writes to the data port 8 cycles apart lose one on the MiSTer core (and
; presumably the LSPC: it serves CPU accesses in slots); every write sequence here
; keeps them at least 12 cycles apart (measured with hal/vlab.s, 2026-10-11).
;
; Neo sprite numbers:  1..21 tilemap 0 | 22..42 tilemap 1 | 43..380 the column ring.
; Sprites behind tilemap 1 (colour bit 5 clear) get no Neo sprites
; between the tilemaps: neither movie has one, and the columns go to the sets.  One
; is put in front instead (wrong only where tilemap 1 covers it): SS_PRIO, a slip
; when the set is shown (HAL_SPR_PRIN).

	ifeq SPR_RETAIN
NSPRSETS        equ 3               ; sets taking turns
	else
NSPRSETS        equ 2               ; (hal/sprr.s: the frame waiting and the one in work)
	endif
SPR_PB          equ SPR_L1+21       ; the column ring: its lowest column
	ifnd SPR_PT
SPR_PT          equ 380             ; and its highest
	endif
SPR_POOL        equ SPR_PT+1-SPR_PB
	ifnd SPR_ANCH
SPR_ANCH        equ 1               ; (DIRECT: a set not begun at the top ends at SPR_PB)
	endif
	ifnd SPR_SHARE2
SPR_SHARE2      equ 0               ; (DIRECT: a set at the ring's tail whose list's rest is
	endif                           ; the shown set's back: those taken over, hal/dl.s sh2_try)
	ifnd SPR_SHARE
SPR_SHARE       equ 0               ; (DIRECT, off: AUDIT.md 14; a set begun in a split set's hole takes over
	endif                           ; its lower run for its back entries: hal/dl.s sh_match)
SPLN            equ 64
ANLN            equ 96
	ifne FUSED
ANCH_LINES      equ 8               ; (fz_anch; (FUSED>0) is -1 in vasm: 4, until 2026-10-18)
	else
ANCH_LINES      equ 6               ; (spr_begin_anch: ~70 cycles an entry, lists ~60;
	endif
                                    ; hal/fz.s fz_anch: ~60 a piece, 96 at most)

; Every ring column's SCB2 (shrink) stays full size, except the columns of the zoomed
; sprites of the sets in the ring (listed, restored when the set is reclaimed).

; set state (3 x SS_SIZE at G_SPRBUF; the game's boot RAM test may overwrite it, so
; the ring's own state is in HAL variables and every use of this one is bounded)
SS_PRIO         equ 0               ; byte: a sprite behind tilemap 1 was put in front
SS_HNEXT        equ 4               ; word: next free column (allocated downwards)
SS_HMIN         equ 8               ; word: the lowest column the conversion may take now
SS_HOFF         equ 10              ; word: 2 x heads written
SS_ZN           equ 12              ; word: zoomed sprites listed (> ZL_MAX: all columns)
SS_ZL           equ 14              ; (column 0, xsize) per zoomed sprite
ZL_MAX          equ 12
	ifeq SPR_RETAIN
SS_MAXHEAD      equ 112
	else
SS_MAXHEAD      equ 176             ; (hal/sprr.s: the flip's writes: heads, moves, hides)
	endif
SS_HADR         equ SS_ZL+4*ZL_MAX  ; per head: SCB3 address
SS_HVAL         equ SS_HADR+2*SS_MAXHEAD    ; and SCB3 when shown
SS_SIZE         equ SS_HVAL+2*SS_MAXHEAD
	if NSPRSETS*SS_SIZE>G_BGSTG-G_SPRBUF
	fail "sprite set states overrun G_BGSTG"
	endif

; per-entry scratch at HAL_SPR_E
SE_VS           equ 0               ; w: vertical shrink (SCB2 low byte)
SE_ZX           equ 4               ; w: 32 - zoomx

; a6 = state of set d0 (0..NSPRSETS-1).  Clobbers d0.
hal_spr_set:
	add.w   d0,d0
	add.w   d0,d0
	movea.l .tab(pc,d0.w),a6
	rts
.tab:	dc.l    G_SPRBUF,G_SPRBUF+SS_SIZE,G_SPRBUF+2*SS_SIZE      ; (NSPRSETS used)

; ================================================================ slot start
; A conversion still going on was started in an earlier slot: it goes on in this
; slot's list (mixed: a slip when shown).
	ifne RES
hal_spr_slot:	jmp     rs_slot             ; (hal/rs.s, out of the callers' bsr range)
hal_spr_work:	jmp     rs_work
hal_spr_flip:	jmp     rs_flip
hal_spr_init:	jmp     rs_init
	endif
	ifeq SPR_RETAIN+RES
hal_spr_slot:
	else
ring_spr_slot:
	endif
	sf      HAL_SPR_DONE
	move.w  HAL_SPR_W,d0
	bmi.s   .x
	lea     HAL_SPR_MIX,a0
	bset    #0,(a0,d0.w)
	addq.l  #1,HAL_SPR_CARRY
.x:	rts

; KER: the line counter value (as HAL_KDL counts it) the conversion stops at, HAL_SPR_RES
; lines before the deadline (before the real vblank: vpos 242 at most).  Then d0 =
; line counter - KER (> -need: fewer than need lines left).  Clobbers d0, d2.
hal_spr_klim:
	move.w  HAL_KDL,d0
	sub.w   HAL_SPR_RES,d0
	subq.w  #1,d0
	tst.b   HAL_BG_EARLY            ; before the real vblank: until vpos 242 at most
	beq.s   .kl
	move.w  #242+8+$f8,d2
	cmp.w   HAL_K0R,d2
	bhs.s   .k1
	addi.w  #264,d2
.k1:	subq.w  #1,d2
	cmp.w   d2,d0
	ble.s   .kl
	move.w  d2,d0
.kl:	move.w  d0,HAL_SPR_KER
; d0 = line counter - KER.  Clobbers nothing else.
hal_spr_left:
	ifeq FUSED-2
	move.w  #-$4000,d0              ; (hal/fz.s: plenty)
	rts
	endif
	move.w  REG_LSPCMODE,d0
	lsr.w   #7,d0
	cmp.w   HAL_K0R,d0
	bhs.s   .p
	addi.w  #264,d0
.p:	sub.w   HAL_SPR_KER,d0
	rts

; ================================================================ work
; Convert while the budget lasts (HAL_SPR_RES scanlines left to the rest): reclaim
; the ring's freed sets, the set still being converted (unless it waits for columns),
; then this slot's list into a free set (neither shown nor complete nor in the ring).
; Z set: nothing left to do now; Z clear: the budget stopped it.
BEGIN_LINES     equ 5               ; a fresh start: only with time for a useful share of
                                    ; the list (starting late only makes a carried, mixed set)
	ifeq SPR_RETAIN+RES
hal_spr_work:
	else
ring_spr_work:
	endif
	ifeq FUSED-2
	tst.b   FZ_GTWAIT               ; (hal/fz.s: the conversion is the game's, at its
	beq.s   .gs                     ; builder point; one waiting at the ring's tail goes
	tst.w   HAL_SPR_TAILU           ; on after the commit's flip)
	beq.s   .gs
	jsr     fz_gt_resume
.gs:	st      HAL_SPR_DONE
	moveq   #0,d0
	rts
	endif
	tst.b   HAL_OUT                 ; (out of time already)
	bne.w   .no
	ifeq FUSED-1
	cmpi.l  #$46584853,FX_MAGIC     ; (the sprite RAM wiped since hal_vid_prep's check:
	beq.s   .mg                     ; hal/fx.s fx_magic, fz_reset abandons the pass in
	movem.l d0-d7/a0-a6,-(sp)       ; work before it resumes here, 2026-10-18)
	jsr     fx_magic
	movem.l (sp)+,d0-d7/a0-a6
.mg:
	endif
	bsr     hal_spr_klim
	addq.w  #3,d0                   ; (3 lines: the reclaim check, hal_spr_go's set-up
					; and first entry before its first refill, the stop)
	ifeq DIRECT-1
	tst.w   HAL_SPR_TAILU           ; (in the commit: the work after a stop too, as .w
	beq.s   .nt                     ; counts it: a commit late from its palettes ran
	addq.w  #(SPR_TAIL*16+767)/768,d0       ; into the overrun guard, 2026-10-13)
.nt:
	endif
	bgt.w   .no
	ifd FZ_DIAG
	jsr     fz_tbeg
	bsr     hal_spr_reclaim
	jsr     fz_tlin
	cmp.w   FZ_RMAX,d0
	ble.s   .r0
	move.w  d0,FZ_RMAX
.r0:
	else
	bsr     hal_spr_reclaim
	endif
	OVS     0
	tst.b   HAL_SPR_BLK             ; waiting for columns: is there a complete set
	beq.s   .go                     ; for the flip to show (freeing the oldest)?
	ifeq DIRECT-1
	bsr     spr_anyw
	else
	bsr     hal_spr_anyc
	endif
	if SPR_SHARE|SPR_SHARE2|OVR_DIAG|LIST_GUARD|CONV_FIRST|WALK_IDLE
	bne.w   .ok                     ; yes: wait for it
	else
	bne.s   .ok
	endif
	sf      HAL_SPR_BLK             ; no: go on, dropping what does not fit
.go:	move.w  HAL_SPR_W,d0
	bmi.s   .new
	bsr     hal_spr_set
	movea.l HAL_SPR_RA5,a5
	bsr     hal_spr_go
	bne.s   .stp                    ; stopped by the budget (or waits for columns)
	bsr.w   .fin
.new:	tst.b   HAL_SPR_DONE
	bne.s   .ok
	ifeq DIRECT-1
	ifne FUSED
	jsr     fz_due                  ; (hal/fz.s: the records due in this slot: none -
	bne.s   .due                    ; the game made no new round for it: nothing to
	st      HAL_SPR_DONE            ; show but the set shown, as the arcade; not a
	bra.w   .ok                     ; hold's worth of waiting, hal/sched.s)
.due:
	else
	if LIST_GUARD|CONV_FIRST|WALK_IDLE
	jsr     fx_listrdy              ; (hal/fx.s: its list still being walked: not yet)
	beq.w   .ok
	endif
	ifne WALK_IDLE
	jsr     fx_dupq                 ; (hal/fx.s: the list converted or shown already:
	bne.s   .wn                     ; nothing new this slot)
	st      HAL_SPR_DONE
	bra.w   .ok
.wn:
	endif
	ifne SPR_SHARE
	tst.b   SH_ON                   ; (hal/dl.s: a set shares the shown one's lower run:
	bne.w   .ok                     ; nothing new before its flip)
	endif
	ifne SPR_SHARE2
	tst.b   SH2_ON                  ; (hal/dl.s: a set takes the shown one's back over:
	bne.w   .ok                     ; nothing new before its flip)
	endif
	tst.b   FX_DELTA                ; (hal/dl.s: an update in place waits for its
	bne.w   .ok                     ; flip: nothing new before it)
	tst.b   DLR_ON                  ; (a comparison going on: on with it)
	beq.s   .dt
	jsr     dl_step
	bra.s   .de
.dt:	jsr     dl_try                  ; (the shown set updated in place?)
.de:
	OVS     1
	tst.w   d0
	beq.s   .nd
	subq.w  #1,d0
	beq.w   .go                     ; (begun: converted as a carried one)
	bra.w   .no
.nd:
	endif
	endif
	lea     HAL_SPR_ST,a0
	lea     HAL_SPR_INQ,a1
	moveq   #0,d0
.f:	move.b  (a0,d0.w),d1
	or.b    (a1,d0.w),d1
	beq.s   .w
	addq.w  #1,d0
	cmpi.w  #NSPRSETS,d0
	blo.s   .f
.ok:	moveq   #0,d0                   ; Z set (no set free: waits for the flip)
	rts
.stp:	OVS     3
	tst.b   HAL_SPR_BLK
	bne.s   .ok
.no:	tst.b   HAL_BG_EARLY            ; (after the real vblank: the slot is out of
	bne.s   .no1                    ; time, the rest ends quickly)
	st      HAL_OUT
.no1:	moveq   #1,d0                   ; Z clear
	rts
.w:	move.w  d0,d1
	bsr     hal_spr_left
	addi.w  #BEGIN_LINES+SCAN_LINES,d0      ; (+ the scan for the list's end)
	ifeq DIRECT-1
	ifne SPR_ANCH
	addq.w  #ANCH_LINES,d0          ; (spr_begin_anch's / fz_anch's sum)
	endif
	endif
	tst.w   HAL_SPR_TAILU           ; in the commit: the work after a stop too (the
	beq.s   .bt                     ; refills keep it back the same way)
	addq.w  #(SPR_TAIL*16+767)/768,d0
.bt:	bgt.s   .no
	move.w  d1,-(sp)
	bsr     hal_spr_where           ; better wait for the flip to free columns?
	movem.w (sp)+,d1                ; (keeps the flags)
	bne.w   .ok
	ifeq FUSED
	bsr.w   hal_spr_end             ; a5: the list's end (the conversion goes back)
	move.l  a5,HAL_SPR_LEND         ; (kept for a restart)
	endif
	move.w  d1,d0
	lea     HAL_SPR_ST,a0
	st      HAL_SPR_DONE
	move.b  #2,(a0,d0.w)
	move.w  d0,HAL_SPR_W
	sf      HAL_SPR_MIX-HAL_SPR_ST(a0,d0.w)
	lea     HAL_SPR_RDY,a0          ; shown from the next slot on
	move.w  HAL_FRAMES+2,d1
	addq.w  #1,d1
	move.w  d0,d2
	add.w   d2,d2
	move.w  d1,(a0,d2.w)
	if (DIRECT=1)&(FUSED=0)
	jsr     dl_begin                ; (hal/dl.s: its list's buffer, no skips yet)
	endif
	ifd FZ_DIAG
	move.w  d0,-(sp)                ; (d0: the set)
	jsr     fz_tbeg
	move.w  (sp)+,d0
	endif
	bsr     hal_spr_begin               ; (keeps a5)
	ifne FUSED
	jsr     fz_begin                ; (hal/fz.s: the pass over the due records)
	ifd FZ_DIAG
	jsr     fz_tlin
	cmp.w   FZ_BMAX,d0
	ble.s   .b0
	move.w  d0,FZ_BMAX
.b0:
	endif
	endif
	ifeq DIRECT-1
	ifne SPR_SHARE
	jsr     sh_match                ; (hal/dl.s: the shown split set's lower run shared?)
	endif
	endif
	OVS     2
	bsr     hal_spr_go
	bne.w   .stp
	bsr.w   .fin
	bra.w   .ok
.fin:
	OVS     3
	if (DIRECT=1)&(FUSED=0)
	cmpi.b  #1,FX_DELTA             ; (hal/dl.s: an update in place: pending, or
	bne.s   .fi                     ; waiting behind the pending one)
	jsr     dl_done
	move.w  #-1,HAL_SPR_W
	clr.l   HAL_SPR_RA5
	rts
.fi:
	endif
	move.w  HAL_SPR_W,d0            ; complete: waits for its flip
	move.w  d0,d1                   ; (its size: the next start's estimate)
	add.w   d1,d1
	lea     HAL_SPR_START,a0
	move.w  (a0,d1.w),d2
	sub.w   SS_HNEXT(a6),d2
	if (FUSED=1)&FZ_SPLANCH
	cmp.b   HAL_SPR_SPS,d0          ; (a split set: the hole between its runs is not
	bne.s   .pv                     ; its size - hal_spr_where sized the next set's room
	sub.w   HAL_SPR_SPJ,d2          ; by it, 2026-10-18)
	add.w   HAL_SPR_SPG,d2
.pv:
	endif
	move.w  d2,HAL_SPR_PREV
	lea     HAL_SPR_ST,a0
	move.b  #1,(a0,d0.w)
	if (DIRECT=1)&(FUSED=0)
	add.w   d0,d0                   ; (hal/dl.s: its list kept by the walk)
	lea     DL_SETS+DL_SRC,a0
	move.w  (a0,d0.w),FX_CBUF
	endif
	ifne FUSED
	jsr     fz_fin                  ; (hal/fz.s: its records' buffer free)
	endif
	move.w  #-1,HAL_SPR_W
	clr.l   HAL_SPR_RA5
	rts

; a5 = the end of the list (its bit-14 word, or 0x200 words on: MAME's limit), from
; which hal_spr_go works back.  22 cycles a word: lists are < 0x80 words but at boot
; (SCAN_LINES).  Clobbers d0, d2.
SCAN_LINES      equ 4
hal_spr_end:
	ifeq DIRECT-1
	jmp     fx_start                ; (hal/fx.s: the walk from the top)
	endif
	lea     G_SPRRAM,a5
	move.w  #$200-1,d2
.e:	move.w  (a5)+,d0
	add.w   d0,d0                   ; N: bit 14
	dbmi    d2,.e
	bpl.s   .x                      ; (no end word)
	subq.l  #2,a5
.x:	rts

; Set d0 (free, not in the ring) before a conversion: empty, its start chosen (see the
; column ring above), appended to the ring.  Its columns were chained when they were
; reclaimed (hal_spr_reclaim; an empty ring's tail is chained here) and its heads are
; written by the flip.  a6 = its state.  Keeps a5.
hal_spr_begin:
	move.w  d0,d7
	bsr     hal_spr_set
	sf      SS_PRIO(a6)
	clr.w   SS_HOFF(a6)
	clr.w   SS_ZN(a6)
	move.w  HAL_SPR_GNEXT,HAL_SPR_BEGG
	bsr     hal_spr_where           ; where it starts
	if (DIRECT=1)&SPR_ANCH&(FUSED=0)
	bsr.w   spr_begin_anch
	endif
	if (DIRECT=1)&SPR_ANCH&(FUSED=1)
	jsr     fz_anch                 ; (hal/fz.s: the same, from the records)
	endif
	tst.b   HAL_SPR_ORDN
	ifeq DIRECT-1
	beq.s   .em
	ifeq FUSED-2
	bra.s   .st                     ; (hal/fz.s: the column above a set's first one is
	endif                           ; a live set's last head, or past the top: untouched)
	ifne SPR_ANCH
	cmp.w   HAL_SPR_GNEXT,d0        ; (SPR_ANCH: begun below the newest set's end,
	bhs.s   .st                     ; its start column height 0: the free columns
	tst.b   HAL_SPR_SPS             ; above it hang off it, and the reclaim chains
	bpl.s   .st                     ; it again as the set's old tail)
	move.w  d0,d1
	addi.w  #SCB3,d1
	move.w  #1,REG_VRAMMOD
	move.w  d1,REG_VRAMADDR
	move.w  #0,REG_VRAMRW
	endif
	bra.s   .st
.em:
	else
	bne.s   .st
	endif
	move.w  HAL_SPR_GNEXT,d1        ; the ring empty: the tail left there (height 0)
	cmpi.w  #SPR_PB,d1              ; chained again
	bls.s   .st
	ifeq DIRECT-1
	cmp.w   RING_PT,d1
	else
	cmpi.w  #SPR_PT,d1
	endif
	bhi.s   .st
	addi.w  #SCB3,d1
	move.w  #1,REG_VRAMMOD
	move.w  d1,REG_VRAMADDR
	move.w  #$40,REG_VRAMRW
.st:
	ifeq DIRECT-1
	jsr     bp_stop                 ; (hal/fx.s bullet pool: a set at the top it wants)
	endif
	move.w  d0,SS_HNEXT(a6)
	move.w  d7,d1
	add.w   d1,d1
	lea     HAL_SPR_START,a0
	move.w  d0,(a0,d1.w)
	lea     HAL_SPR_RST,a0
	sf      (a0,d7.w)
	lea     HAL_SPR_INQ,a0
	st      (a0,d7.w)
	moveq   #0,d0
	move.b  HAL_SPR_ORDN,d0
	lea     HAL_SPR_ORD,a0
	move.b  d7,(a0,d0.w)
	addq.b  #1,HAL_SPR_ORDN
	rts

; d0 = the list position at which the set being converted (a6; a4 its next head slot)
; could have used up its head slots (one per entry at most), not before a0 (the list's
; start), from a5.  hal_spr_go stops there to look again, so its routines need no
; check of their own.
hal_spr_glim:
	ifne RES
	move.l  a0,d0                   ; (hal/rs.s: no more new ones than head slots)
	rts
	endif
	move.l  a6,d0
	addi.l  #SS_HADR+2*SS_MAXHEAD,d0        ; the slots' end
	sub.l   a4,d0                   ; 2 x the slots left
	ifeq DIRECT-1
	add.l   d0,d0                   ; (hal/fx.s: a5 the entry itself, going up to the
	add.l   d0,d0                   ; list's end, a0)
	add.l   a5,d0
	cmp.l   a0,d0
	bls.s   .k
	move.l  a0,d0
	else
	neg.l   d0
	add.l   a5,d0
	cmp.l   a0,d0
	bhs.s   .k
	move.l  a0,d0
	endif
.k:	rts

; Where the next set starts (d0; see the column ring above): the ring empty, from the
; top; the tail below the newest set's end, there; else there if the room down to
; SPR_PB is 1.25 x the last set's size + 8, else from the top if it has more room (the
; top: below a split set's top run while there is one).
; Z clear: better not start now (short room at the bottom, where a set can only drop,
; while a complete set waits for its flip, which frees the oldest).  Clobbers d0-d4, a1.
hal_spr_where:
	ifeq FUSED-2
	jmp     fz_gt_where             ; (hal/fz.s: the largest free run)
	endif
	ifeq DIRECT-1
	move.w  RING_TOP,d0
	else
	move.w  #SPR_PT+1,d0
	endif
	tst.b   HAL_SPR_ORDN
	beq.s   .go
	move.w  HAL_SPR_GNEXT,d0
	moveq   #0,d1
	move.b  HAL_SPR_ORD,d1
	add.w   d1,d1
	lea     HAL_SPR_START,a1
	move.w  (a1,d1.w),d1            ; the tail
	cmp.w   d0,d1
	blo.s   .go
	move.w  d0,d2                   ; room down to SPR_PB
	subi.w  #SPR_PB,d2
	ifeq DIRECT-1
	bsr.w   spr_where_down
	endif
	move.w  HAL_SPR_PREV,d3
	move.w  d3,d4
	lsr.w   #2,d4
	add.w   d4,d3
	addq.w  #8,d3
	cmp.w   d3,d2
	ifeq DIRECT-1
	blo.s   .tp
	ifne SPR_ANCH
	tst.b   HAL_SPR_SPS             ; (SPR_ANCH: with no set split, the set ends at
	bpl.s   .go                     ; SPR_PB as estimated, not below the newest set:
	move.w  HAL_SPR_PREV,d4         ; the two sets of a dense scene keep to the ring's
	lsr.w   #2,d4                   ; ends, its room one run - else each that began at
	add.w   d3,d4                   ; (1.5 x the last set's size + 16)
	addi.w  #SPR_PB+8,d4
	cmp.w   d0,d4                   ; the top split by a few columns, cutting the room
	bhs.s   .go                     ; in two, both short for the next, 2026-10-16)
	move.w  d4,d0
	endif
	bra.s   .go
.tp:
	else
	bhs.s   .go
	endif
	ifeq DIRECT-1
	move.w  RING_TOP,d3            ; the top: a split set's top run holds it down
	else
	move.w  #SPR_PT+1,d3            ; the top: a split set's top run holds it down
	endif
	tst.b   HAL_SPR_SPS             ; to HAL_SPR_SPJ
	bmi.s   .nt
	move.w  HAL_SPR_SPJ,d3
.nt:	move.w  d3,d4                   ; room between the tail and the top
	subq.w  #1,d4
	sub.w   d1,d4
	ifeq DIRECT-1
	bsr.w   spr_where_hole
	endif
	cmp.w   d2,d4
	ble.s   .sh
	move.w  d3,d0
.go:	moveq   #0,d1                   ; Z set
	rts
.sh:	move.w  d0,-(sp)                ; short: wait if a flip will free columns
	bsr.s   hal_spr_anyc
	movem.w (sp)+,d0                ; (keeps the flags)
	rts

; Z clear when a set is complete (waiting for its flip).  Clobbers d0, a1.
hal_spr_anyc:
	lea     HAL_SPR_ST,a1
	moveq   #NSPRSETS-1,d0
.c:	cmpi.b  #1,(a1,d0.w)
	dbeq    d0,.c
	seq     d0                      ; (N/Z from the byte: -1 found, 0 not)
	tst.b   d0
	rts

	ifeq DIRECT-1
; hal_spr_where with the ring's oldest set split: the hole between its runs is free
; once the sets that were there are reclaimed (the city's sets dropped their back
; sprites, the buildings, at SPR_PB while it stood empty, 2026-10-14).
; d0 = the next start (HAL_SPR_GNEXT), d2 = the room below it: in the hole, only down
; to the guard above the lower run.  Keeps all but d2.
spr_where_down:
	bsr.w   spr_hole
	bne.s   .x
	cmp.w   HAL_SPR_SPG,d0
	bls.s   .x
	move.w  d0,d2
	sub.w   HAL_SPR_SPG,d2
	subq.w  #1,d2
.x:	rts
; d3 = the top (HAL_SPR_SPJ while a set is split), d4 = the room there, d2 = the room
; below the next start: the whole hole when the split set is the ring's only one; with
; no set split, the top's room and the bottom's (a set begun at the top that reaches
; the tail goes on below the newest set's end: hal_spr_go .spl), if the top has 16
; (the city's sets dropped their buildings at the bottom with the top free, 2026-10-14).
; Keeps all but d4.
spr_where_hole:
	tst.b   HAL_SPR_SPS
	bpl.s   .s
	cmpi.w  #16,d4
	blt.s   .x
	add.w   d2,d4
	rts
.s:	bsr.w   spr_hole
	bne.s   .x
	cmpi.b  #1,HAL_SPR_ORDN
	bne.s   .x
	move.w  d3,d4
	sub.w   HAL_SPR_SPG,d4
	subq.w  #1,d4
.x:	rts
; (SPR_ANCH: the lower run ends at SPR_PB as the entries left need, its guard height 0,
; not below the previous set's end: the hole one run - else the next set in it was
; short, split again, 2026-10-16.)  hal_spr_go .spl: d1 = the lower run's start (the
; previous set's end), a5 past the entry, a0 the list's end, a3 the VRAM data port; at
; most SPLN entries looked at (more left: as it was).  Charged in d7.  Clobbers d2-d4,
; a1.
	ifne SPR_ANCH
; hal_spr_begin, after hal_spr_where (d0): a set begun below the newest set's end with
; the room down to SPR_PB (no set split) ends at SPR_PB as its list needs (the walk
; keeps only entries on the Neo screen: each its width's columns), at most at the
; newest set's end - not as 1.5 x the last set's size: after a short or empty set the
; next full list began low, reached SPR_PB and dropped with the room above it free
; (~95% of the drops left, 2026-10-16).  a5 the list's first entry, FX_AEND its end;
; at most ANLN entries looked at (more: as it was).  Clobbers d1-d4, a1.
spr_begin_anch:
	tst.b   HAL_SPR_ORDN
	beq.s   .x
	tst.b   HAL_SPR_SPS
	bpl.s   .x
	move.w  HAL_SPR_GNEXT,d2
	cmp.w   d2,d0
	bhi.s   .x                      ; (from the top)
	moveq   #0,d1
	move.b  HAL_SPR_ORD,d1
	add.w   d1,d1
	lea     HAL_SPR_START,a1
	cmp.w   (a1,d1.w),d2            ; (the tail below the newest set's end: the room
	bhi.s   .x                      ; ends there)
	movea.l a5,a1
	move.l  FX_AEND,d1
	moveq   #4,d2
	moveq   #ANLN-1,d3
.sa:	cmpa.l  d1,a1
	bhs.s   .sb
	move.w  2(a1),d4
	rol.w   #7,d4
	andi.w  #7,d4
	addq.w  #1,d4
	add.w   d4,d2
	addq.l  #8,a1
	dbra    d3,.sa
	rts
.sb:	addi.w  #SPR_PB,d2
	move.w  HAL_SPR_GNEXT,d0
	cmp.w   d0,d2
	bhs.s   .x
	move.w  d2,d0
.x:	rts

spr_split_anch:
	swap    d7
	subi.w  #(SPLN*40+15)/16,d7
	swap    d7
	lea     -8(a5),a1               ; (this entry)
	moveq   #4,d2
	moveq   #SPLN-1,d3
.sa:	cmpa.l  a0,a1
	bhs.s   .sb
	move.w  2(a1),d4
	rol.w   #7,d4
	andi.w  #7,d4
	addq.w  #1,d4
	add.w   d4,d2
	addq.l  #8,a1
	dbra    d3,.sa
	rts
.sb:	addi.w  #SPR_PB,d2
	cmp.w   d1,d2
	bhs.s   .x
	move.w  d2,d1
	addi.w  #SCB3,d2
	move.w  d2,-2(a3)
	move.w  #0,(a3)
.x:	rts
	endif
; Z clear when a set is complete (hal_spr_anyc) or the ring's oldest is freed and only
; waits for its reclaim: then a conversion at its tail waits too (a flip during the
; conversion had freed it: its columns dropped, 2026-10-16).  Clobbers d0, a1.
spr_anyw:
	bsr     hal_spr_anyc
	bne.s   .x
	tst.b   HAL_SPR_ORDN
	beq.s   .x
	moveq   #0,d0
	move.b  HAL_SPR_ORD,d0
	lea     HAL_SPR_ST,a1
	tst.b   (a1,d0.w)
	seq     d0
	tst.b   d0
.x:	rts

; Z set when the ring's oldest set is the split one.  Keeps all.
spr_hole:
	move.l  d0,-(sp)
	move.b  HAL_SPR_SPS,d0
	bmi.s   .n
	cmp.b   HAL_SPR_ORD,d0
	bra.s   .x
.n:	moveq   #1,d0                   ; (Z clear)
.x:	movem.l (sp)+,d0                ; (keeps the flags)
	rts
	endif

; The set being converted (a6, HAL_SPR_W): the lowest column it may take now
; (SS_HMIN).  The ring's tail is the column
; above the oldest set's first one (kept height 0, never taken: the set may go down
; to the one above it) if it is below SS_HNEXT; else the set may go down to SPR_PB
; (so nothing may start at a non-empty oldest set's first column: .rst).
; Clobbers d0, d1, a1.
hal_spr_lim:
	ifeq FUSED-2
	jmp     fz_gt_lim               ; (hal/fz.s: the nearest live set below)
	endif
	moveq   #0,d0
	move.b  HAL_SPR_ORD,d0          ; the oldest set
	add.w   d0,d0
	lea     HAL_SPR_START,a1
	move.w  (a1,d0.w),d0            ; the tail
	move.w  SS_HNEXT(a6),d1
	cmp.w   d1,d0
	blo.s   .t
	ifeq DIRECT-1
	move.b  HAL_SPR_SPS,d0          ; the oldest split, the set in the hole between
	bmi.s   .b                      ; its runs: down to the one above its lower run's
	cmp.b   HAL_SPR_ORD,d0          ; guard
	bne.s   .b
	move.w  HAL_SPR_SPG,d0
	cmp.w   d1,d0
	blo.s   .t
.b:
	endif
	move.w  #SPR_PB,d0
	bra.s   .s
.t:	addq.w  #1,d0
.s:	move.w  d0,SS_HMIN(a6)
	rts

; Reclaim the ring's oldest sets the flip has freed (state 0), while the budget lasts:
; the new tail (the column above the next set's first one, or HAL_SPR_GNEXT) height
; 0, the set's heads and old tail chained again (but SPR_PB and the new tail), its
; zoomed columns full size again.  Clobbers d0-d7, a0, a3, a4, a6.
hal_spr_reclaim:
.r:	tst.b   HAL_SPR_ORDN
	beq.w   .x
	moveq   #0,d7
	move.b  HAL_SPR_ORD,d7          ; the oldest
	lea     HAL_SPR_ST,a0
	tst.b   (a0,d7.w)
	bne.w   .x                      ; still in use
	move.w  d7,d0
	bsr     hal_spr_set
	; time in lines (768 cycles): 24 cycles a head (2 lines for 64 heads), <= 234 a
	; listed zoomed sprite (.zl: 1 line for 2), 18 a column if all (.rl: 9 lines),
	; ~600 the rest (2 lines), rounded up (no multiply or divide: this check comes
	; first in hal_spr_work, which must give up quickly when the slot is out of time)
	move.w  SS_HOFF(a6),d6
	cmpi.w  #2*SS_MAXHEAD,d6
	bls.s   .h1
	move.w  #2*SS_MAXHEAD,d6
.h1:	move.w  d6,d2
	lsr.w   #6,d2
	addq.w  #3,d2
	move.w  SS_ZN(a6),d3
	beq.s   .z0
	cmpi.w  #ZL_MAX,d3
	bhi.s   .za
	lsr.w   #1,d3
	addq.w  #1,d3
	add.w   d3,d2
	bra.s   .z0
.za:	addi.w  #10,d2
.z0:	tst.w   HAL_SPR_TAILU           ; (in the commit: the work after it too)
	beq.s   .tu
	addq.w  #(SPR_TAIL*16+767)/768,d2
.tu:
	if (DIRECT=1)&(FUSED=0)
	move.w  d7,d0                   ; (hal/dl.s: heads its updates hid: all its columns
	lsl.w   #6,d0                   ; chained again, .dead)
	lea     DL_SETS,a0
	tst.b   DL_DEAD(a0,d0.w)
	beq.s   .tn
	addi.w  #(SPR_POOL*18+200+767)/768,d2
.tn:
	endif
	bsr     hal_spr_left
	add.w   d2,d0
	bgt.w   .x                      ; (not now)
	lea     REG_VRAMRW,a3
	lea     REG_VRAMADDR,a4
	move.w  #1,REG_VRAMMOD
	move.w  HAL_SPR_GNEXT,d4        ; the new tail
	cmpi.b  #2,HAL_SPR_ORDN
	blo.s   .t1
	moveq   #0,d0
	move.b  HAL_SPR_ORD+1,d0
	add.w   d0,d0
	lea     HAL_SPR_START,a0
	move.w  (a0,d0.w),d4
.t1:	addi.w  #SCB3,d4
	ifeq DIRECT-1
	cmp.w   RING_S3T,d4
	else
	cmpi.w  #SCB3+SPR_PT,d4
	endif
	bhi.s   .t2
	move.w  d4,(a4)
	move.w  #0,(a3)
.t2:	move.w  d7,d0                   ; the old tail
	add.w   d0,d0
	lea     HAL_SPR_START,a0
	move.w  (a0,d0.w),d5
	addi.w  #SCB3,d5
	cmpi.w  #SCB3+SPR_PB,d5
	bls.s   .o1
	ifeq DIRECT-1
	cmp.w   RING_S3T,d5
	else
	cmpi.w  #SCB3+SPR_PT,d5
	endif
	bhi.s   .o1
	cmp.w   d4,d5
	beq.s   .o1
	ifeq DIRECT-1
	tst.b   HAL_SPR_SPS             ; (a split set's guard stays 0: an empty set had
	bmi.s   .o2                     ; begun at the newest set's end, the next one
	move.w  HAL_SPR_SPG,d0          ; split below it - its reclaim chained the guard
	addi.w  #SCB3,d0                ; as its old tail, the lower run's columns hung
	cmp.w   d0,d5                   ; off the hole, 2026-10-16)
	beq.s   .o1
.o2:
	endif
	move.w  d5,(a4)
	move.w  #$40,(a3)
.o1:	subq.w  #2,d6                   ; the heads but the last (the lowest column:
	bmi.w   .hz                     ; SPR_PB or the new tail, both kept 0)
	lea     SS_HADR(a6),a0
	moveq   #$40,d3
	lea     .hl(pc),a1
	suba.w  d6,a1
	suba.w  d6,a1
	jmp     (a1)
	rept SS_MAXHEAD-1
	move.w  (a0)+,(a4)
	move.w  d3,(a3)
	endr
.hl:	move.w  (a0),d0                 ; the last
	cmpi.w  #SCB3+SPR_PB,d0
	bls.s   .hz
	ifeq DIRECT-1
	cmp.w   RING_S3T,d0
	else
	cmpi.w  #SCB3+SPR_PT,d0
	endif
	bhi.s   .hz
	cmp.w   d4,d0
	beq.s   .hz
	tst.b   HAL_SPR_SPS             ; (above a split set's lower run: 0)
	bmi.s   .hw
	move.w  HAL_SPR_SPG,d1
	addi.w  #SCB3,d1
	cmp.w   d1,d0
	bne.s   .hw
	move.w  d0,(a4)
	move.w  #0,(a3)
	bra.s   .hz
.hw:	move.w  d0,(a4)
	move.w  d3,(a3)
.hz:
	ifeq DIRECT-1
	ifeq FUSED
	move.w  d7,d0
	lsl.w   #6,d0
	lea     DL_SETS,a0
	tst.b   DL_DEAD(a0,d0.w)
	beq.s   .hd
	bsr.w   .dead
	endif
.hd:	cmp.w   RING_S3T,d4             ; (hal/dl.s moves heads to other slots: the last
	bhi.s   .ht                     ; one need not be the lowest column - the new
	move.w  d4,(a4)                 ; tail and SPR_PB 0 again, whichever head they
	move.w  #0,(a3)                 ; were: else the set reclaimed hung off the next
.ht:	move.w  d7,d0                   ; one's top, 2026-10-14)
	add.w   d0,d0
	lea     HAL_SPR_END,a0
	cmpi.w  #SPR_PB,(a0,d0.w)       ; (SPR_PB: if it reached it)
	bhi.s   .hp
	move.w  #SCB3+SPR_PB,(a4)
	move.w  #0,(a3)
.hp:
	endif
	move.w  #$0fff,d3               ; zoomed columns
	move.w  SS_ZN(a6),d2
	beq.s   .zd
	cmpi.w  #ZL_MAX,d2
	bhi.s   .zall
	lea     SS_ZL(a6),a0
	subq.w  #1,d2
.zl:	move.w  (a0)+,d0                ; column 0
	move.w  (a0)+,d1                ; xsize
	cmpi.w  #7,d1
	bhi.s   .zn
	cmpi.w  #SPR_PB,d0
	blo.s   .zn
	ifeq DIRECT-1
	cmp.w   RING_PT,d0
	else
	cmpi.w  #SPR_PT,d0
	endif
	bhi.s   .zn
	addi.w  #SCB2,d0
	move.w  d0,(a4)
.zc:	move.w  d3,(a3)                 ; (18 cycles apart)
	dbra    d1,.zc
.zn:	dbra    d2,.zl
	bra.s   .zd
.zall:	move.w  d7,d1                   ; all its columns: its end .. start - 1
	add.w   d1,d1
	lea     HAL_SPR_END,a0
	move.w  (a0,d1.w),d0
	lea     HAL_SPR_START,a0
	move.w  (a0,d1.w),d1
	cmp.b   HAL_SPR_SPS,d7
	bne.s   .z1
	move.w  HAL_SPR_SPG,d1          ; split: end .. SPG - 1, SPJ .. SPR_PT
	sub.w   d0,d1
	ifeq DIRECT-1
	bsr.w   .run
	else
	bsr.s   .run
	endif
	move.w  HAL_SPR_SPJ,d0
	ifeq DIRECT-1
	move.w  RING_TOP,d1
	else
	move.w  #SPR_PT+1,d1
	endif
.z1:	sub.w   d0,d1
	bsr.s   .run
.zd:	cmp.b   HAL_SPR_SPS,d7          ; the split set: its guard chained again
	bne.s   .zg
	st      HAL_SPR_SPS
	ifeq DIRECT-1
	cmp.w   RING_S3T,d4             ; (and the new tail 0 again: it may be its top
	bhi.s   .zt                     ; run's last head, chained above with the rest;
	move.w  d4,(a4)                 ; then the next set, begun below it, carried the
	move.w  #0,(a3)                 ; top run's stale columns, 2026-10-14)
.zt:
	endif
	move.w  HAL_SPR_SPG,d0
	cmpi.w  #SPR_PB,d0
	bls.s   .zg
	ifeq DIRECT-1
	cmp.w   RING_PT,d0
	else
	cmpi.w  #SPR_PT,d0
	endif
	bhi.s   .zg
	addi.w  #SCB3,d0
	cmp.w   d4,d0
	beq.s   .zg
	move.w  d0,(a4)
	move.w  #$40,(a3)
.zg:	lea     HAL_SPR_INQ,a0          ; out of the ring
	sf      (a0,d7.w)
	move.b  HAL_SPR_ORD+1,HAL_SPR_ORD
	move.b  HAL_SPR_ORD+2,HAL_SPR_ORD+1
	subq.b  #1,HAL_SPR_ORDN
	sf      HAL_SPR_BLK
	addq.l  #1,HAL_SPR_RCLN
	bra.w   .r
.x:	rts
.run:	tst.w   d1                      ; SCB2 of d1 columns from d0: full size
	ble.s   .rx
	cmpi.w  #SPR_POOL,d1
	bhi.s   .rx
	addi.w  #SCB2,d0
	move.w  d0,(a4)
	subq.w  #1,d1
.rl:	move.w  d3,(a3)
	dbra    d1,.rl
.rx:	rts
	if (DIRECT=1)&(FUSED=0)
; The set's heads its updates hid (hal/dl.s dl_flip: height 0) are not among its heads
; any more: all its columns chained again (then the new tail, SPR_PB and the guards 0
; again as before) - else a later set's column there stood alone, height 0, and the
; sprite's columns from it on were not shown (~18% of movie7's frames, 2026-10-16).
; Clobbers d0-d3, a0.
.dead:	move.w  d7,d1
	add.w   d1,d1
	lea     HAL_SPR_END,a0
	move.w  (a0,d1.w),d0
	lea     HAL_SPR_START,a0
	move.w  (a0,d1.w),d1
	moveq   #$40,d3
	cmp.b   HAL_SPR_SPS,d7
	bne.s   .de1
	move.w  d1,-(sp)                ; split: end .. SPG - 1, SPJ .. start - 1
	move.w  HAL_SPR_SPG,d1
	sub.w   d0,d1
	bsr.s   .run3
	move.w  HAL_SPR_SPJ,d0
	move.w  (sp)+,d1
.de1:	sub.w   d0,d1
	bsr.s   .run3
	move.b  HAL_SPR_SPS,d0          ; (another set's guard in its columns: 0 again)
	bmi.s   .dx
	cmp.b   d0,d7
	beq.s   .dx
	move.w  HAL_SPR_SPG,d0
	cmpi.w  #SPR_PB,d0
	bls.s   .dx
	cmp.w   RING_PT,d0
	bhi.s   .dx
	addi.w  #SCB3,d0
	move.w  d0,(a4)
	move.w  #0,(a3)
.dx:	rts
.run3:	tst.w   d1                      ; SCB3 of d1 columns from d0: chained
	ble.s   .r3x
	cmpi.w  #SPR_POOL,d1
	bhi.s   .r3x
	addi.w  #SCB3,d0
	move.w  d0,(a4)
	subq.w  #1,d1
.r3l:	move.w  d3,(a3)
	dbra    d1,.r3l
.r3x:	rts
	endif

; ================================================================ convert
; Neo columns for the sprite (xsize+1 below the set's last ones), its x (SCB4 of
; column 0) and its head for the flip (its SCB3 is left alone: see hal_spr_reclaim).
; d0 = column 0 on exit, d2 = ysize.  In: d1 = ysize, d2-d5 = w0-w3, d6 = xsize.
ALLOC	macro
	btst    #13,d4
	bne.s   .h\@
	st      SS_PRIO(a6)             ; behind tilemap 1: in front (approximated)
.h\@:	move.w  SS_HNEXT(a6),d0         ; the set's lowest column in use
	sub.w   d6,d0
	subq.w  #1,d0                   ; column 0
	cmp.w   SS_HMIN(a6),d0
	blt.w   .drop
	move.w  d0,SS_HNEXT(a6)
	lsl.w   #7,d3                   ; SCB4: ox << 7 (the higher bits fall off)
	addi.w  #SCB4,d0
	move.w  d0,-2(a3)
	move.w  d3,(a3)
	subi.w  #SCB4-SCB3,d0
	neg.w   d2                      ; head: SCB3 = (496 - oy) << 7 | ysize + 1
	addi.w  #496,d2                 ; (w0's higher bits fall off)
	lsl.w   #7,d2
	add.w   d1,d2
	addq.w  #1,d2
	move.w  d2,SS_HVAL-SS_HADR(a4)
	move.w  d0,(a4)+
	andi.w  #$1ff,d0                ; column 0
	move.w  d1,d2
	endm

; List entries from a5 back to the first into set a6, while the budget lasts.  Z set:
; all done; Z clear: stopped (HAL_SPR_RA5: where to go on, the entry below it next).
; Registers: a0 sprite RAM, a1 attribute words, a2 lookup RAM, a3 VRAM data port
; (-2: address port), a4 next head, a5 list position, a6 set state, d7 low: 0x7fff,
; d7 high: budget credit in 16-cycle units.
; Budget: each sprite is charged an upper bound of its cost (from its size) before
; it is converted; when the credit runs out it is refilled from the line counter
; (k = (vpos + 8) mod 264 counts up from vpos 256) and the lines left to KLIM.
DROP_UNITS      equ 32                  ; (16-cycle units: the drop, wait or split path)
LIM_UNITS       equ 10
	ifeq DIRECT-1
WRAP_UNITS      equ 20                  ; (hal/fx.s: .ent and .wrap from the batch: +62)
	else
WRAP_UNITS      equ 16+6*SPR_RETAIN                  ; (.ent .. .gen through a shape routine and
                                        ; spr_lo: <= 538 cycles, the tables allow 314)
	endif
hal_spr_go:
	ifeq FUSED-1
	jmp     fz_go                   ; (hal/fz.s: the pass over the records)
	endif
	move.l  a6,HAL_SPR_WPTR
	ifne SPR_RETAIN
	movea.l R_PBASE,a0              ; (hal/sprr.s: P's list and attribute words)
	else
	ifeq DIRECT-1
	movea.l FX_AEND,a0              ; (hal/fx.s: the list's end; a5 its next entry)
	else
	lea     G_SPRRAM,a0
	endif
	endif
	lea     G_SPRLUT,a2
	lea     REG_VRAMRW,a3
	move.w  #1,REG_VRAMMOD
	ifeq SPR_RETAIN+RES
	bsr     hal_spr_lim
	endif
	lea     SS_HADR(a6),a4
	ifeq DIRECT-1
	cmpi.b  #1,FX_DELTA             ; (hal/dl.s: an update in place: its own count)
	bne.s   .hn
	adda.w  FX_DHOFF,a4
	bra.s   .hd
.hn:
	endif
	adda.w  SS_HOFF(a6),a4
.hd:	move.l  #$7fff,d7               ; (no credit: the first sprite measures)
	bsr     hal_spr_glim            ; (sp): where the head slots could run out
	move.l  d0,-(sp)
	; entries, last (front) first, back to the list's start (a0)
.ent:
	ifne FUSED
	jmp     fz_next                 ; (hal/fz.s: the next piece)
	endif
	cmpa.l  (sp),a5                 ; 14
	beq.w   .lim                    ; 12
	ifeq DIRECT-1
	; (hal/fx.s: the entry from the list; its end: a0, .lim)
	movea.l a5,a1                   ; 4
	addq.l  #8,a5                   ; 8
	ifne RES
	; (hal/rs.s: kept or dropped ones skipped, a new one into its columns: the end
	; column of its run, SS_HMIN at SPR_PB)
	move.l  a5,d0
	sub.l   FX_CL,d0
	lsr.w   #2,d0
	movea.l RS_PC0,a1
	move.w  -2(a1,d0.w),d0
	bmi.w   .skp
	andi.w  #$1ff,d0
	move.w  d0,SS_HNEXT(a6)
	lea     -8(a5),a1
	bra.s   .fxp
	endif
	cmpi.b  #1,FX_DELTA             ; 20 (hal/dl.s: an update in place: its kept
	bne.s   .fxp                    ; 10 entries keep their columns)
	move.l  a1,d0
	sub.l   FX_CL,d0
	lsr.w   #3,d0
	movea.l FX_KTAB,a1
	cmpi.b  #$ff,(a1,d0.w)
	bne.w   .ofk
	lea     -8(a5),a1
	else
	move.w  -(a5),d0                ; 10
	ifne SPR_RETAIN
	; (hal/sprr.s: the entry's columns, chosen by pr_place: ~70 cycles, in PRE_MAX)
	move.w  d0,d1
	lsl.w   #3,d1
	lea     T_META-8*PR_LB(a0),a1
	move.w  M_END(a1,d1.w),SS_HNEXT(a6)
	move.w  M_COL(a1,d1.w),SS_HMIN(a6)
	endif
	add.w   d0,d0                   ; 4   C: bit 15 (not drawn)
	bcs.w   .skp
	andi.w  #$7fe,d0
	add.w   d0,d0
	add.w   d0,d0
	lea     (a0,d0.w),a1
	endif
.fxp:	movem.w (a1),d2-d5              ; w0 zoomy ysize oy, w1 zoomx xsize ox, w2, w3 map
	; visible if oy < 224 or oy + 16 * rows > 512, the same in x (hal/fx.s: the walk
	; lists only those)
	ifne DIRECT-1
	move.w  d2,d0
	andi.w  #$1ff,d0
	cmpi.w  #224,d0
	bhs.w   .yo
	endif
.yv:
	ifne DIRECT-1
	move.w  d3,d0
	andi.w  #$1ff,d0
	cmpi.w  #320,d0
	bhs.w   .xo
	endif
.xv:	; the shape's own routine (sprfast.inc, tools/gen_sprfast.py; a lookup run that
	; wraps goes on at .wrap): index (w2 bits 13-15) << 6 | ysize << 3 | xsize, x4
	move.w  d2,d1
	lsr.w   #4,d1
	andi.w  #$e0,d1
	move.b  2(a1),d0                ; w1 bits 8-15: xsize x2 in bits 1-3
	andi.w  #$e,d0
	add.w   d0,d0
	add.w   d0,d1
	move.w  d4,d0
	lsr.w   #5,d0
	andi.w  #$700,d0
	add.w   d0,d1
	lea     spr_fast_jt(pc),a1
	move.w  d2,d0
	or.w    d3,d0
	cmpi.w  #$1000,d0               ; zoomed: the zoomed shapes' table
	blo.s   .fj
	lea     2048(a1),a1
.fj:	movea.l (a1,d1.w),a1
	jmp     (a1)
.gsz:	move.w  d3,d6                   ; general path: xsize, 8 ysize + xsize
	rol.w   #7,d6
	andi.w  #7,d6
	move.w  d2,d1
	lsr.w   #6,d1
	andi.w  #$38,d1
	add.w   d6,d1
	rts
.nc:	moveq   #0,d0                   ; charge it
	move.b  .cn(pc,d1.w),d0
	bra.s   .cb
.cn:                                    ; ceil((872 + cols * (52 + 38 rows) + 32) / 16):
                                        ; .ent .. .gen worst (314), .gsz, the wrap test less
                                        ; its own 112, COLS; + 32 margin (flips: .flip)
	dc.b    63,68,74,79,85,91,96,102
	dc.b    65,73,81,89,97,105,113,121
	dc.b    67,78,88,98,109,119,130,140
	dc.b    70,82,95,108,121,133,146,159
	dc.b    72,87,102,117,133,148,163,178
	dc.b    74,92,109,127,144,162,179,197
	dc.b    77,97,117,136,156,176,196,216
	dc.b    79,101,124,146,168,190,213,235
.cb:	swap    d7
	sub.w   d0,d7
	bmi.w   .rfn
.rfr:	swap    d7
	lsr.w   #3,d1                   ; ysize
	ALLOC
	; attributes: palette (color bits 0-4) and flips; d5 = lookup offset x2
	move.w  d4,d1
	andi.w  #$1f00,d1
	addi.w  #NPAL_SPR<<8,d1
	andi.w  #$3fff,d5
	add.w   d5,d5
	move.w  d6,d3
	addq.w  #1,d3
	add.w   d3,d3
	movea.w d3,a1                   ; row step x2
	move.w  d4,d3
	andi.w  #$c000,d3
	bne.w   .flip
	; tiles in drawing order k = yi * cols + xi
COLS	macro                           ; \1: column step x2 (addq / subq)
	lsl.w   #6,d0                   ; SCB1 of column 0
	add.w   d2,d2
	move.w  .rj\@(pc,d2.w),d2       ; entry into the unrolled tile copy
.col\@:	move.w  d0,-2(a3)
	move.w  d5,d3
	jmp     .rend\@(pc,d2.w)
.rj\@:	dc.w    -12,-24,-36,-48,-60,-72,-84,-96
	rept 8
	move.w  (a2,d3.w),d4            ; 14
	and.w   d7,d4                   ; 4
	move.w  d4,(a3)                 ; 8
	add.w   a1,d3                   ; 4   (VRAM writes >= 12 cycles apart: hal_vram)
	move.w  d1,(a3)                 ; 8
	endr
.rend\@:	\1     #2,d5
	addi.w  #64,d0
	dbra    d6,.col\@
	bra.w   .ent
	endm
.cols:	COLS    addq.w
.colsx:	COLS    subq.w

.flip:	swap    d7                      ; (charged here: at most 176 cycles)
	subi.w  #11,d7
	swap    d7
	rol.w   #2,d4                   ; vflip (bit 15) -> 1, hflip (bit 14) -> 0
	moveq   #3,d3
	and.w   d4,d3
	or.w    d3,d1
	btst    #1,d4
	beq.s   .fx
	move.w  a1,d3                   ; flip y: last row first
	mulu    d2,d3
	add.w   d3,d5
	move.w  a1,d3
	neg.w   d3
	movea.w d3,a1
.fx:	btst    #0,d4
	beq.w   .cols
	add.w   d6,d5                   ; flip x: last column first
	add.w   d6,d5
	bra.w   .colsx

	; budget: credit used up, refill it (d0 = this sprite's charge)
.rfn:	bsr.w   hal_spr_refill
	bpl.w   .rfr
	swap    d7
	bra.w   .late
.rfz:	bsr.w   hal_spr_refill
	bpl.w   .rzr
	swap    d7
	bra.w   .late
	; entries not drawn / out of view: a small charge
.skp:	swap    d7                      ; (~76 cycles)
	subq.w  #5,d7
	bmi.s   .skq
	swap    d7
	bra.w   .ent
.off:
	ifeq DIRECT-1
	if (RES=0)&(FUSED=0)
	jsr     dl_skip                 ; (hal/dl.s: no head for it)
	endif
.ofk:
	endif
	swap    d7                      ; (~256 cycles)
	subi.w  #17,d7
	bmi.s   .sko
	swap    d7
	bra.w   .ent
.skq:	moveq   #5,d0                   ; (a refill keeps this entry's charge back too)
	bra.s   .skr
.sko:	moveq   #17,d0
.skr:	bsr.w   hal_spr_refill
	bmi.s   .skl
	swap    d7
	bra.w   .ent
.skl:	swap    d7
	bra.w   .late

	; general case: a lookup run that wraps (a shape routine sends it here, d5 = w3 &
	; $3fff): the attribute words again, the way here charged (WRAP_UNITS)
.wrap:
	ifeq DIRECT-1
	ifne FUSED
	lea     FZ_WORDS,a1             ; (hal/fz.s: the entry's words, from d2-d5)
	movem.w d2-d5,(a1)
	else
	lea     -8(a5),a1               ; (hal/fx.s: the entry just taken)
	endif
	else
	move.w  (a5),d0
	add.w   d0,d0
	andi.w  #$7fe,d0
	add.w   d0,d0
	add.w   d0,d0
	lea     (a0,d0.w),a1
	endif
	swap    d7
	subi.w  #WRAP_UNITS,d7
	swap    d7
	; zoom (each column's shrink width = the gap to the next column, vertical shrink
	; 255 - 8*zoomy) and/or a lookup index that wraps.
.gen:	bsr.w   .gsz
	move.w  d2,d0
	or.w    d3,d0
	andi.w  #$f000,d0
	bne.s   .gz
	move.w  d6,-(sp)                ; not zoomed: does the lookup run wrap (map +
	addq.w  #1,d6                   ; tiles > 0x4000)?
	move.w  d1,d0
	lsr.w   #3,d0
	addq.w  #1,d0
	mulu    d0,d6
	move.w  d5,d0
	andi.w  #$3fff,d0
	add.w   d6,d0
	move.w  (sp)+,d6
	swap    d7                      ; (this test: ~100 cycles more than .cn allows)
	subq.w  #7,d7
	swap    d7
	cmpi.w  #$4000,d0
	bls.w   .nc
.gz:	moveq   #0,d0
	move.b  .cz(pc,d1.w),d0
	bra.s   .gb
.cz:                                    ; 64-cycle units: ceil((1554 + cols * (242 + 46 rows)
                                        ; + 32) / 64), the zoomed worst: .ent .. .gen (314),
                                        ; all of .zoom with both flips and vertical zoom, each
                                        ; column's SCB2 (148) and tiles (94 + 46 rows); + 32
                                        ; margin (a wrapping plain entry costs less, even with
                                        ; its wrap test's 20 over the 112 charged there)
	dc.b    30,34,39,43,48,52,57,61
	dc.b    30,36,41,46,51,57,62,67
	dc.b    31,37,43,49,55,61,67,73
	dc.b    32,39,45,52,59,65,72,79
	dc.b    33,40,47,55,62,70,77,84
	dc.b    33,41,50,58,66,74,82,90
	dc.b    34,43,52,61,69,78,87,96
	dc.b    35,44,54,63,73,82,92,102
.gb:	lsl.w   #2,d0                   ; (64-cycle units)
	swap    d7
	sub.w   d0,d7
	bmi.w   .rfz
.rzr:	swap    d7
	lsr.w   #3,d1                   ; ysize
	ALLOC
	addq.l  #4,a1                   ; a1 = attribute word 2, d0 = column 0, d2 = ysize,
	                                ; d4 = w2, d6 = xsize
.zoom:	addq.l  #1,HAL_SPR_ZOOM
	move.b  (-4,a1),d3              ; zoomed at all (the Neo's shrink keeps other
	or.b    (-2,a1),d3              ; pixels than MAME's zoom): the set is a slip
	andi.b  #$f0,d3                 ; when shown
	beq.s   .zv3
	lea     HAL_SPR_MIX,a6
	move.w  HAL_SPR_W,d3
	bset    #2,(a6,d3.w)
	movea.l HAL_SPR_WPTR,a6
.zv3:	move.b  (-4,a1),d3              ; the head's height: the rows the vertical
	andi.w  #$f0,d3                 ; shrink shows (spr_zh)
	lsr.w   #1,d3
	add.w   d2,d3
	lea     spr_zh,a6
	move.b  (a6,d3.w),d3
	movea.l HAL_SPR_WPTR,a6
	andi.w  #$ffc0,SS_HVAL-SS_HADR-2(a4)
	or.w    d3,SS_HVAL-SS_HADR-2(a4)
	move.w  SS_ZN(a6),d3            ; list the columns (hal_spr_reclaim restores them)
	addq.w  #1,SS_ZN(a6)
	cmpi.w  #ZL_MAX,d3
	bhs.s   .zl
	add.w   d3,d3
	add.w   d3,d3
	move.w  d0,SS_ZL(a6,d3.w)
	move.w  d6,SS_ZL+2(a6,d3.w)
.zl:	move.w  d0,d3
	addi.w  #SCB2,d3
	move.w  d3,-2(a3)
	move.w  (-4,a1),d1              ; w0
	rol.w   #4,d1
	andi.w  #$f,d1
	lsl.w   #3,d1
	neg.w   d1
	addi.w  #255,d1
	move.w  d1,HAL_SPR_E+SE_VS      ; vertical shrink
	move.w  (-2,a1),d1              ; w1
	rol.w   #4,d1
	andi.w  #$f,d1
	neg.w   d1
	addi.w  #32,d1
	move.w  d1,HAL_SPR_E+SE_ZX      ; 32 - zoomx
	moveq   #0,d1                   ; SCB2 run: c * (32 - zoomx) -> width of column c
	move.w  d6,d3
.z2:	move.w  d1,-(sp)
	add.w   HAL_SPR_E+SE_ZX,d1
	lsr.w   #1,d1
	move.w  (sp),-(sp)
	lsr.w   (sp)                    ; (memory shift by 1)
	sub.w   (sp)+,d1
	subq.w  #1,d1                   ; this column's width - 1
	lsl.w   #8,d1
	or.w    HAL_SPR_E+SE_VS,d1
	move.w  d1,(a3)
	move.w  (sp)+,d1
	add.w   HAL_SPR_E+SE_ZX,d1
	dbra    d3,.z2
	move.w  d4,d1                   ; attributes
	andi.w  #$1f00,d1
	addi.w  #NPAL_SPR<<8,d1
	rol.w   #2,d4
	moveq   #3,d3
	and.w   d4,d3
	or.w    d3,d1
	move.w  (2,a1),d5               ; w3 (again: the wrap test changed d5)
	andi.w  #$3fff,d5
	add.w   d5,d5
	move.w  d6,d3
	addq.w  #1,d3
	add.w   d3,d3                   ; row step
	btst    #1,d4
	beq.s   .zny
	move.w  d3,-(sp)
	mulu    d2,d3
	add.w   d3,d5
	move.w  (sp)+,d3
	neg.w   d3
.zny:	movea.w d3,a6
	moveq   #2,d3
	btst    #0,d4
	beq.s   .znx
	add.w   d6,d5
	add.w   d6,d5
	moveq   #-2,d3
.znx:	movea.w d3,a1
	lsl.w   #6,d0                   ; SCB1 of column 0
	addq.w  #1,d2                   ; entry into the unrolled rows (a0 borrowed)
	lsl.w   #4,d2
	lea     .zre(pc),a0
	suba.w  d2,a0
.zcol:	move.w  d0,-2(a3)
	move.w  d5,d3
	jmp     (a0)
	rept 8
	andi.w  #$7ffe,d3               ; 8   (wraps)
	move.w  (a2,d3.w),d4            ; 14
	and.w   d7,d4                   ; 4
	move.w  d4,(a3)                 ; 8
	add.w   a6,d3                   ; 4   (VRAM writes >= 12 cycles apart)
	move.w  d1,(a3)                 ; 8
	endr
.zre:	move.w  #BLANK_TILE,(a3)        ; rows after the sprite's: transparent (the
	move.w  #0,(a3)                 ; shrink fetches them below the image)
	move.w  #BLANK_TILE,(a3)
	move.w  #0,(a3)
	add.w   a1,d5
	addi.w  #64,d0
	dbra    d6,.zcol
	movea.l HAL_SPR_WPTR,a6         ; (the row step was in a6)
	ifeq DIRECT-1
	ifne FUSED
	movea.l FZ_RTN,a0
	else
	movea.l FX_AEND,a0
	endif
	else
	lea     G_SPRRAM,a0
	endif
	bra.w   .ent

	; out of view in y or x unless wrapping past 512
.yo:	move.w  d2,d1
	andi.w  #$0e00,d1
	lsr.w   #5,d1                   ; 16 * ysize
	add.w   d0,d1
	cmpi.w  #512-16,d1
	bls.w   .off
	bra.w   .yv
.xo:	move.w  d3,d1
	andi.w  #$0e00,d1
	lsr.w   #5,d1
	add.w   d0,d1
	cmpi.w  #512-16,d1
	bls.w   .off
	bra.w   .xv
	; no columns left below: wait for the oldest set to be reclaimed (if the limit is
	; the tail and a complete set will be shown: else nothing frees any, drop it)
.drop:
	ifne SPR_RETAIN+RES
	bra.w   .hdrop                  ; (hal/sprr.s: the columns were free: never)
	endif
	swap    d7                      ; (charged first: <= ~400 cycles with the split)
	subi.w  #DROP_UNITS,d7
	bpl.s   .dc
	moveq   #DROP_UNITS,d0
	bsr.w   hal_spr_refill
	bpl.s   .dc
	swap    d7
	bra.w   .late
.dc:	swap    d7
	cmpi.w  #SPR_PB,SS_HMIN(a6)
	beq.w   .rst
	ifeq FUSED-2
	tst.b   HAL_SCH_BUSY            ; (hal/fz.s: the slot still to come and a complete
	bne.w   .hdrop                  ; set waiting for its flip: the pass waits, and goes
	bsr     hal_spr_anyc            ; on in the slot's tail; the slot gone by already
	beq.w   .hdrop                  ; (the round overran it: the game would go on, the
	jmp     fz_gt_wait              ; objects with it), or no set waiting: the drop)
	endif
	ifeq DIRECT-1
	bsr     spr_anyw
	else
	bsr     hal_spr_anyc
	endif
	beq.s   .spl
	st      HAL_SPR_BLK
	addq.l  #1,HAL_SPR_BLKN
	bra.w   .late
.spl:	tst.b   HAL_SPR_SPS             ; nothing will free columns: go on below the
	bpl.s   .hdrop                  ; previous set's end if the set began at the
	move.w  HAL_SPR_W,d0            ; top (no other split set)
	move.w  d0,d1
	add.w   d1,d1
	lea     HAL_SPR_START,a1
	ifeq DIRECT-1
	move.w  (a1,d1.w),d2
	cmp.w   RING_TOP,d2
	else
	cmpi.w  #SPR_PT+1,(a1,d1.w)
	endif
	bne.s   .hdrop
	move.w  HAL_SPR_BEGG,d1
	cmpi.w  #SPR_PB,d1
	bls.s   .hdrop
	ifeq DIRECT-1
	cmp.w   RING_TPM,d1
	else
	cmpi.w  #SPR_PT,d1
	endif
	bhi.s   .hdrop
	ifeq DIRECT-1
	ifne SPR_SHARE2
	jsr     sh2_try                 ; (hal/dl.s: the rest is the shown set's back: its
	beq.s   .s2n                    ; columns taken over, the set complete)
	move.l  a0,(sp)
	movea.l a0,a5
	bra.w   .ent
.s2n:	swap    d7                      ; (its time: the next entry refills)
	clr.w   d7
	swap    d7
	move.w  HAL_SPR_W,d0
	move.w  HAL_SPR_BEGG,d1
	endif
	if SPR_ANCH&(FUSED=0)
	bsr.w   spr_split_anch          ; (d1: where the lower run starts)
	endif
	if (FUSED=1)&FZ_SPLANCH
	jsr     fz_split_anch           ; (hal/fz.s: the same from the records left)
	endif
	endif
	move.b  d0,HAL_SPR_SPS
	move.w  SS_HNEXT(a6),HAL_SPR_SPJ
	move.w  d1,HAL_SPR_SPG
	move.w  d1,SS_HNEXT(a6)
	bsr     hal_spr_lim
	ifeq DIRECT-1
	ifne FUSED
	lea     -14(a5),a5              ; this piece again (hal/fz.s)
	addq.w  #1,FZ_LEFT
	else
	subq.l  #8,a5                   ; this entry again
	endif
	else
	addq.l  #2,a5                   ; this entry again
	endif
	bra.w   .ent
.hdrop:
	if (DIRECT=1)&(RES=0)&(FUSED=0)
	jsr     dl_drop                 ; (hal/dl.s: the first one recorded)
	endif
	addq.l  #1,HAL_SPR_DROP         ; no Neo sprites for it: the set is a slip
	lea     HAL_SPR_MIX,a1          ; when shown
	move.w  HAL_SPR_W,d0
	bset    #1,(a1,d0.w)
	bra.w   .ent
	; at SPR_PB: start the set again from SPR_PT (once), the whole list, if the top
	; has more room than it had, or will get some (a complete set waits for its flip,
	; which frees the oldest: the top grows down into it); else drop
.rst:	tst.b   HAL_SPR_SPS             ; (a split set holds the top)
	bpl.w   .hdrop
	move.w  HAL_SPR_W,d0
	lea     HAL_SPR_RST,a1
	tst.b   (a1,d0.w)
	bne.w   .hdrop
	moveq   #0,d1
	move.b  HAL_SPR_ORD,d1
	cmp.w   d0,d1
	beq.w   .hdrop                  ; (the ring's only set)
	if (DIRECT=1)&(FUSED=0)
	tst.b   FX_DELTA                ; (hal/dl.s: an update's base is not begun again)
	bne.w   .hdrop
	endif
	add.w   d1,d1
	lea     HAL_SPR_START,a1
	move.w  (a1,d1.w),d1            ; the tail
	add.w   d0,d0
	move.w  (a1,d0.w),d2            ; this set's start
	cmp.w   d2,d1
	blo.w   .hdrop                  ; (the tail below it: no room at the top)
	ifeq DIRECT-1
	cmp.w   RING_TPM,d1
	else
	cmpi.w  #SPR_PT,d1
	endif
	bhi.w   .hdrop                  ; (the oldest starts at the top)
	ifeq DIRECT-1
	move.w  RING_TPM,d3
	else
	move.w  #SPR_PT,d3
	endif
	sub.w   d1,d3                   ; room at the top now
	subi.w  #SPR_PB,d2              ; room it had
	cmp.w   d2,d3
	bgt.s   .rs1
	bsr     hal_spr_anyc
	beq.w   .hdrop
.rs1:	move.w  SS_ZN(a6),d0            ; charge: its zoomed columns' SCB2 restored
	cmpi.w  #ZL_MAX,d0              ; (<= 256 cycles a listed sprite, all: 20 a
	bls.s   .rs2                    ; column) + ~400
	move.w  #SPR_POOL*20/16,d0
	bra.s   .rs3
.rs2:	lsl.w   #4,d0
.rs3:	addi.w  #25,d0
	swap    d7
	sub.w   d0,d7
	bpl.s   .rs4
	bsr.w   hal_spr_refill
	bpl.s   .rs4
	swap    d7
	bra.w   .late
.rs4:	swap    d7
	move.w  #$0fff,d3               ; SCB2 of the columns it zoomed: full size
	move.w  SS_ZN(a6),d2
	beq.s   .rz
	cmpi.w  #ZL_MAX,d2
	bhi.s   .rza
	lea     SS_ZL(a6),a1
	subq.w  #1,d2
.rzl:	move.w  (a1)+,d0
	move.w  (a1)+,d1
	cmpi.w  #7,d1
	bhi.s   .rzn
	addi.w  #SCB2,d0
	move.w  d0,-2(a3)
.rzc:	move.w  d3,(a3)                 ; (18 cycles apart)
	dbra    d1,.rzc
.rzn:	dbra    d2,.rzl
	bra.s   .rz
.rza:	move.w  SS_HNEXT(a6),d0         ; all: its columns so far
	move.w  HAL_SPR_W,d1
	add.w   d1,d1
	lea     HAL_SPR_START,a1
	move.w  (a1,d1.w),d1
	sub.w   d0,d1
	ble.s   .rz
	addi.w  #SCB2,d0
	move.w  d0,-2(a3)
	subq.w  #1,d1
.rzw:	move.w  d3,(a3)
	dbra    d1,.rzw
.rz:	move.w  HAL_SPR_W,d0            ; start again
	lea     HAL_SPR_RST,a1
	st      (a1,d0.w)
	add.w   d0,d0
	lea     HAL_SPR_START,a1
	ifeq DIRECT-1
	move.w  RING_TOP,d1
	move.w  d1,(a1,d0.w)
	move.w  d1,SS_HNEXT(a6)
	move.w  d0,-(sp)
	move.w  d1,d0
	jsr     bp_stop
	move.w  (sp)+,d0
	else
	move.w  #SPR_PT+1,(a1,d0.w)
	move.w  #SPR_PT+1,SS_HNEXT(a6)
	endif
	clr.w   SS_HOFF(a6)
	clr.w   SS_ZN(a6)
	sf      SS_PRIO(a6)
	if (DIRECT=1)&(FUSED=0)
	move.w  HAL_SPR_W,d0            ; (hal/dl.s: its entry table afresh)
	jsr     dl_begin
	endif
	lea     SS_HADR(a6),a4
	ifne FUSED
	jsr     fz_rst                  ; (hal/fz.s: the pass from its start)
	ifeq FUSED-1
	move.l  a6,d0
	addi.l  #SS_HADR+2*SS_MAXHEAD,d0
	move.l  d0,(sp)
	endif
	else
	movea.l HAL_SPR_LEND,a5
	bsr     hal_spr_glim
	move.l  d0,(sp)
	endif
	bsr     hal_spr_lim
	addq.w  #1,HAL_SPR_DBGI         ; (diagnostics: restarts)
	bra.w   .ent
.late:
	ifeq FUSED-2
	jmp     fz_gt_hud               ; (hal/fz.s: never, the game's pass has no budget;
	endif                           ; if ever: the set complete as it is)
	ifeq DIRECT-1
	ifne FUSED
	lea     -14(a5),a5              ; this piece again (hal/fz.s)
	addq.w  #1,FZ_LEFT
	ifd FZ_DIAG                     ; (hal/fz.s: stops here counted)
	addq.l  #1,FZ_D4
	endif
	else
	subq.l  #8,a5                   ; this entry again (hal/fx.s: a5 the entry)
	endif
	else
	addq.l  #2,a5                   ; this entry again
	endif
.stop:	move.l  a5,HAL_SPR_RA5
	ifne FUSED
	move.l  a0,FZ_RTN
	ifd FZ_DIAG
	jsr     fz_tend
	endif
	endif
	addq.l  #4,sp
	bsr.s   .hoff
	moveq   #1,d0                   ; Z clear
	rts
.lim:	cmpa.l  a0,a5                   ; the list's start, or as many entries as there
	beq.s   .done                   ; were head slots: how many are left now?
	swap    d7                      ; (charged first: ~130 cycles)
	subi.w  #LIM_UNITS,d7
	bpl.s   .lc
	moveq   #LIM_UNITS,d0
	bsr.w   hal_spr_refill
	bpl.s   .lc
	swap    d7
	bra.s   .stop
.lc:	swap    d7
	bsr     hal_spr_glim
	cmp.l   a5,d0
	beq.s   .nsl
	move.l  d0,(sp)
	bra.w   .ent
.nsl:
	if (DIRECT=1)&(RES=0)&(FUSED=0)
	jsr     dl_nod
	endif
	addq.l  #1,HAL_SPR_DROP         ; none: the entries left are dropped (if any is
	lea     HAL_SPR_MIX,a1          ; visible: a slip either way)
	move.w  HAL_SPR_W,d0
	bset    #1,(a1,d0.w)
.done:
	ifne FUSED
	ifd FZ_DIAG
	jsr     fz_tend
	endif
	endif
	clr.l   HAL_SPR_RA5
	addq.l  #4,sp
	bsr.s   .hoff
	moveq   #0,d0                   ; Z set
	rts
.hoff:	move.l  a4,d0                   ; heads written
	sub.l   a6,d0
	subi.w  #SS_HADR,d0
	ifne RES
	move.w  d0,SS_HOFF(a6)          ; (hal/rs.s: no ring)
	rts
	endif
	if (DIRECT=1)&(FUSED=0)
	cmpi.b  #1,FX_DELTA             ; (hal/dl.s: the set's own flip shows its own)
	bne.s   .ho
	move.w  d0,FX_DHOFF
	bra.s   .hp
.ho:
	endif
	move.w  d0,SS_HOFF(a6)
.hp:
	if (DIRECT=1)&(FUSED=0)
	tst.b   DL_HOLEC                ; (hal/dl.s: an update into its split base's hole:
	beq.s   .hq                     ; the top run grows down, the set's end stays)
	move.w  SS_HNEXT(a6),HAL_SPR_SPJ
	rts
.hq:
	endif
	move.w  SS_HNEXT(a6),HAL_SPR_GNEXT      ; (the next set starts below)
	move.w  HAL_SPR_W,d0
	add.w   d0,d0
	lea     HAL_SPR_END,a1
	move.w  SS_HNEXT(a6),(a1,d0.w)
	rts
spr_go_ent	equ .ent                ; (for the shape routines)
	ifeq DIRECT-1
	; a pair bullet (hal/fx.s fxb_obj: w2 low byte 0x80; spv_1100 sends it here): 2
	; columns of 2 rows, the upper row the lower one's lookup run turned (flips 3)
.bul:	andi.w  #$3fff,d5               ; lookup run: wraps?
	cmpi.w  #$3ffe,d5
	bls.s   .bw
	jmp     spr_go_wrap
.bw:	swap    d7                      ; charge it
	subi.w  #BUL_UNITS,d7
	bpl.s   .bc
	move.w  #BUL_UNITS,d0
	jsr     spr_fast_refill
.bc:	swap    d7
	move.w  SS_HNEXT(a6),d0
	subq.w  #2,d0
	cmp.w   SS_HMIN(a6),d0
	bge.s   .ba
	jmp     spr_go_drop
.ba:	move.w  d0,SS_HNEXT(a6)
	lsl.w   #7,d3                   ; SCB4: ox << 7
	neg.w   d2                      ; head: SCB3 = (496 - oy) << 7 | 2 rows
	lsl.w   #7,d2
	addi.w  #(496<<7)+2,d2
	move.w  d0,d6
	addi.w  #SCB3,d6
	move.w  d6,(a4)+
	move.w  d2,SS_HVAL-SS_HADR-2(a4)
	addi.w  #SCB4-SCB3,d6
	move.w  d6,-2(a3)
	move.w  d3,(a3)
	move.w  d4,d1                   ; attributes: lower row, upper row (flips 3)
	andi.w  #$1f00,d1
	addi.w  #NPAL_SPR<<8,d1
	move.w  d1,d6
	addq.w  #3,d6
	add.w   d5,d5                   ; lookup run
	lea     (a2,d5.w),a1
	lsl.w   #6,d0                   ; column 0: tile 1 turned, tile 0
	move.w  d0,-2(a3)
	move.w  2(a1),d4
	and.w   d7,d4
	move.w  d4,(a3)
	move.w  (a1),d4
	move.w  d6,(a3)
	and.w   d7,d4
	move.w  d4,(a3)
	nop
	move.w  d1,(a3)
	addi.w  #64,d0                  ; column 1: tile 0 turned, tile 1
	move.w  d0,-2(a3)
	move.w  (a1),d4
	and.w   d7,d4
	move.w  d4,(a3)
	move.w  2(a1),d4
	move.w  d6,(a3)
	and.w   d7,d4
	move.w  d4,(a3)
	nop
	move.w  d1,(a3)
	jmp     spr_go_ent
BUL_UNITS	equ (PRE_MAX_C+14+448+32+15)/16   ; (.ent .. dispatch, spv_1100's test, this)
spr_go_bul	equ .bul
	endif
spr_go_drop	equ .drop
spr_go_hdrop	equ .hdrop
spr_go_late	equ .late
spr_go_wrap	equ .wrap
spr_go_stop	equ .stop
spr_go_done	equ .done

; Credit used up in a shape routine (d0 = its charge, d7 swapped): refill and return,
; or, out of time, leave hal_spr_go the way its own budget stop does.
spr_fast_refill:
	bsr     hal_spr_refill
	bmi.s   .out
	rts
.out:	addq.l  #4,sp
	swap    d7
	bra.w   spr_go_late

; Budget credit refill: the lines left to KER (the current one counted as gone) in
; 16-cycle units, less HAL_SPR_TAILU, less d0.  In/out with d7 swapped.  N clear: d7 = the credit left
; after this sprite; N set: out of time.  Keeps d0-d6.
SPR_CL	set     264                 ; (credit of n lines at spr_credit - 2n)
	rept 264
	dc.w    48*SPR_CL-10            ; (less the ~150 cycles the refill takes after
SPR_CL	set     SPR_CL-1                ; its line counter read)
	endr
spr_credit:
	ifd FZ_COST
FZ_COST0        equ G_SPRRAM+$3e8   ; (hal/fz.s FZ_V+232, after FZ_VEND) w: the credit short
FZ_COST1        equ G_SPRRAM+$3ea   ; w: the credit given
FZ_COST2        equ G_SPRRAM+$3ec   ; l: (FZ_FAST) the fast record fz_fast begins
	endif
hal_spr_refill:
	ifeq FUSED-2
	move.w  #$4000,d7               ; (hal/fz.s: the game's pass has no budget)
	sub.w   d0,d7
	rts
	endif
	ifd FZ_COST
	move.w  d7,FZ_COST0             ; (diagnostics, work/play/fh/fzev.lua: the credit
	endif                           ; short, then the credit given)
	move.w  REG_LSPCMODE,d7
	lsr.w   #7,d7
	cmp.w   HAL_K0R,d7
	bhs.s   .p
	addi.w  #264,d7
.p:	sub.w   HAL_SPR_KER,d7          ; - lines left
	bpl.s   .l
	add.w   d7,d7
	move.w  spr_credit(pc,d7.w),d7
	sub.w   HAL_SPR_TAILU,d7        ; (time the work after a stop needs)
	sub.w   d0,d7
	ifd FZ_COST
	move.w  d7,FZ_COST1
	endif
	rts
.l:	moveq   #-1,d7                  ; N set
	rts

; ================================================================ flip
; Inside the real vblank: show the newest complete set that may be shown in this
; slot, hide the one shown so far.  None (no time at all): the old one stays (a slip).
; Time it needs: 24 cycles per head written (hidden or shown) + 400, in lines rounded
; up, at most (2 x heads + 98) / 64.
	ifeq SPR_RETAIN+RES
hal_spr_flip:
	else
ring_spr_flip:
	endif
	if (DIRECT=1)&(FUSED=0)
	tst.b   FX_PON                  ; (hal/dl.s: an update in place pending, for now?)
	beq.s   .dnd
	move.w  FX_PRDY,d0
	sub.w   HAL_FRAMES+2,d0         ; (frame numbers wrap: the sign of the difference)
	tst.w   d0
	bgt.s   .dnd
	jsr     dl_flip
	bne.w   .defer
	rts
.dnd:
	endif
	lea     HAL_SPR_ST,a0
	lea     HAL_SPR_RDY,a1
	move.w  HAL_FRAMES+2,d3
	moveq   #-1,d6                  ; best so far
	move.w  #-32768,d5              ; its RDY - now
	moveq   #NSPRSETS-1,d0
	moveq   #2*(NSPRSETS-1),d2
.c:	cmpi.b  #1,(a0,d0.w)
	bne.s   .cn
	move.w  (a1,d2.w),d1
	sub.w   d3,d1
	ifeq DIRECT-1
	tst.w   d1                  ; (frame numbers wrap: the sign only)
	endif
	bgt.s   .cn                     ; (from the next slot on)
	cmp.w   d5,d1
	ble.s   .cn
	ifeq DIRECT-1
	move.w  HAL_SPR_SHOWN,d4        ; (hal/dl.s: not older than the set shown, which
	bmi.s   .cy                     ; an update in place may have made newer: it
	add.w   d4,d4                   ; would go back in time; dropped below)
	move.w  (a1,d2.w),d7
	sub.w   (a1,d4.w),d7
	tst.w   d7                      ; (frame numbers wrap: the sign only)
	ble.s   .cn
.cy:
	endif
	move.w  d1,d5
	move.w  d0,d6
.cn:	subq.w  #2,d2
	dbra    d0,.c
	tst.w   d6
	bmi.w   .none
	move.w  d6,d0
	bsr     hal_spr_set
	movea.l a6,a5                   ; the new set
	move.w  SS_HOFF(a5),d1
	move.w  HAL_SPR_SHOWN,d0
	bmi.s   .t
	bsr     hal_spr_set             ; a6: the old one
	add.w   SS_HOFF(a6),d1
.t:
	ifeq DIRECT-1
	ifne SPR_SHARE
	tst.b   SH_ON                   ; (hal/dl.s sh_flip: ~30 cycles a shared head, its
	beq.s   .ts                     ; x; ~300 the rest)
	move.w  SH_N,d0
	add.w   d0,d1
	add.w   d0,d1
	addi.w  #24,d1
.ts:
	endif
	ifne SPR_SHARE2
	tst.b   SH2_ON                  ; (hal/dl.s sh2_flip: the same)
	beq.s   .t2s
	move.w  SH2_N,d0
	add.w   d0,d1
	add.w   d0,d1
	addi.w  #24,d1
.t2s:
	endif
	endif
	moveq   #98,d0
	add.w   d1,d0
	lsr.w   #6,d0
	ifeq DIRECT-1
	move.l  d0,-(sp)                ; (hal/fx.s: its list's pair bullets in the pool)
	move.w  d6,d0
	ifeq FUSED
	add.w   d0,d0
	lea     DL_SETS+DL_SRC,a1
	move.w  (a1,d0.w),d0
	endif
	jsr     bp_cost
	addi.l  #767,d0
	divu    #768,d0
	move.l  (sp)+,d1
	add.w   d1,d0
	move.w  d0,-(sp)                ; (hal/fx.s: its list's fix-layer text with it,
	move.w  d6,d0                   ; ~900 cycles a strip)
	ifeq FUSED
	add.w   d0,d0
	lea     DL_SETS+DL_SRC,a1
	move.w  (a1,d0.w),d0
	endif
	jsr     fx_hud_count
	mulu    #FX_HSTRIP,d0           ; (hal/fx.s: cycles a strip)
	addi.l  #767,d0
	divu    #768,d0
	add.w   (sp),d0
	sf      FX_FNOH
	bsr     hal_late_n
	beq.s   .fit
	cmpi.b  #2,FX_FLATE             ; (hal/dl.s fx_flip_hud: deferred twice: without)
	blo.s   .nft
	st      FX_FNOH
	move.w  (sp),d0
	bsr     hal_late_n
	beq.s   .fit
.nft:	addq.l  #2,sp
	bra.w   .defer
.fit:	addq.l  #2,sp
	else
	bsr     hal_late_n
	bne.w   .defer
	endif
	lea     REG_VRAMRW,a3
	lea     REG_VRAMADDR,a4
	lea     SS_HADR(a5),a0          ; show
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
.se:	lea     HAL_SPR_ST,a1
	move.w  HAL_SPR_SHOWN,d0        ; hide
	bmi.w   .sw
	clr.b   (a1,d0.w)
	lea     SS_HADR(a6),a0
	move.w  SS_HOFF(a6),d2
	add.w   d2,d2
	lea     .he(pc),a2
	suba.w  d2,a2
	moveq   #0,d2
	jmp     (a2)
	rept SS_MAXHEAD
	move.w  (a0)+,(a4)
	move.w  d2,(a3)
	endr
.he:
	ifeq DIRECT-1
	ifne SPR_SHARE
	tst.b   SH_ON                   ; (hal/dl.s: the new set shares the old one's lower
	beq.s   .hx                     ; run: its heads now, the ring not split)
	move.b  SH_SET,d0
	cmp.b   d6,d0
	bne.s   .hab
	jsr     sh_flip
	bra.s   .hx
.hab:	jsr     sh_drop
.hx:
	endif
	ifne SPR_SHARE2
	tst.b   SH2_ON                  ; (hal/dl.s: the new set took the old one's back
	beq.s   .h2x                    ; over: their x, the old one's columns its)
	move.b  SH2_SET,d0
	cmp.b   d6,d0
	bne.s   .h2d
	jsr     sh2_flip
	bra.s   .h2x
.h2d:	jsr     sh2_drop
.h2x:
	endif
	endif
.sw:	move.w  d6,HAL_SPR_SHOWN
	ifeq DIRECT-1
	move.w  d6,d0                   ; (hal/dl.s: its list's buffer, kept by the walk)
	ifeq FUSED
	add.w   d0,d0
	move.l  a0,-(sp)
	lea     DL_SETS+DL_SRC,a0
	move.w  (a0,d0.w),FX_SBUF
	move.w  (a0,d0.w),d0            ; (hal/fx.s: the fix layer with these sprites,
	else
	move.l  a0,-(sp)                ; (hal/fz.s: d0 the set)
	endif
	OVB     0
	jsr     fx_flip_hud             ; in this vblank)
	OVB     1
	jsr     bp_apply                ; (and its pair bullets in the pool)
	OVB     2
	movea.l (sp)+,a0
	endif
	move.b  #3,(a1,d6.w)
	lea     HAL_SPR_RDY,a0          ; older complete sets: never shown
	moveq   #NSPRSETS-1,d0
	moveq   #2*(NSPRSETS-1),d2
.o:	cmpi.b  #1,(a1,d0.w)
	bne.s   .on
	move.w  (a0,d2.w),d1
	sub.w   d3,d1
	ifeq DIRECT-1
	tst.w   d1                  ; (frame numbers wrap: the sign only)
	endif
	bgt.s   .on
	clr.b   (a1,d0.w)
	ifeq DIRECT-1
	bsr     spr_cut
	endif
.on:	subq.w  #2,d2
	dbra    d0,.o
	tst.b   SS_PRIO(a5)             ; sprites behind tilemap 1 shown in front?
	beq.s   .np
	addq.l  #1,HAL_SPR_PRIN
	bset    #2,HAL_SLIP+1
.np:	move.b  HAL_SPR_MIX-HAL_SPR_ST(a1,d6.w),d0
	btst    #1,d0                   ; sprites dropped (no Neo sprites left)?
	beq.s   .nd
	addq.l  #1,HAL_SPR_DROPN
	bset    #2,HAL_SLIP+1
.nd:	btst    #2,d0                   ; vertically zoomed sprites (approximated)?
	beq.s   .nz
	addq.l  #1,HAL_SPR_VZN
	bset    #2,HAL_SLIP+1
.nz:	btst    #0,d0                   ; this slot's list, converted in one go?
	bne.s   .mix
	tst.w   d5
	beq.s   .ex
.mix:	addq.l  #1,HAL_SPR_MIXN
	bset    #2,HAL_SLIP+1
.ex:	rts
.defer:	addq.l  #1,HAL_SPR_LATE         ; no time to flip: it waits (or is replaced by a
	addq.w  #1,HAL_SPR_DBGD         ; newer one)
	ifeq DIRECT-1
	cmpi.b  #2,FX_FLATE             ; (hal/dl.s fx_flip_noh)
	bhs.s   .df
	addq.b  #1,FX_FLATE
.df:
	endif
	bset    #2,HAL_SLIP+1
	rts
.none:	addq.l  #1,HAL_SPR_LATE         ; nothing complete to show
	bset    #2,HAL_SLIP+1
	ifeq DIRECT-1
	move.w  HAL_SPR_SHOWN,d4        ; (hal/dl.s: complete sets older than the one
	bmi.s   .nx                     ; shown: never shown, their columns back)
	lea     HAL_SPR_ST,a0
	lea     HAL_SPR_RDY,a1
	add.w   d4,d4
	move.w  (a1,d4.w),d3
	moveq   #NSPRSETS-1,d0
	moveq   #2*(NSPRSETS-1),d2
.nl:	cmpi.b  #1,(a0,d0.w)
	bne.s   .nn
	move.w  (a1,d2.w),d1
	sub.w   d3,d1
	tst.w   d1                      ; (frame numbers wrap: the sign only)
	bgt.s   .nn
	clr.b   (a0,d0.w)
	bsr     spr_cut
.nn:	subq.w  #2,d2
	dbra    d0,.nl
.nx:
	endif
	rts

	ifeq DIRECT-1
; Set d0, complete but dropped never shown: its last head (its lowest column) height 0.
; Its heads still carry the $40 the reclaim chained them with (only a flip writes a
; set's heads), so the whole set hung below from that head onto the top of the set below
; it - shown once that one is (44 columns over a set for a frame, 2026-10-15).  Keeps all.
spr_cut:
	movem.l d0/d1/a0,-(sp)
	add.w   d0,d0
	lea     HAL_SPR_END,a0
	move.w  (a0,d0.w),d1            ; its lowest column
	lea     HAL_SPR_START,a0
	cmp.w   (a0,d0.w),d1            ; (none at all: nothing to cut)
	bhs.s   .x
	cmpi.w  #SPR_PB,d1
	blo.s   .x
	cmpi.w  #SPR_PT,d1
	bhi.s   .x
	addi.w  #SCB3,d1
	move.w  d1,REG_VRAMADDR
	move.w  #0,REG_VRAMRW
.x:	movem.l (sp)+,d0/d1/a0
	rts
	endif

; ================================================================ init
; The ring empty; its columns: SCB2 full size, SCB3 chained ($40) but SPR_PB (0).
	ifeq SPR_RETAIN+RES
hal_spr_init:
	else
ring_spr_init:
	endif
	move.w  #-1,HAL_SPR_SHOWN
	move.w  #SPR_PT+1,HAL_SPR_GNEXT
	ifeq DIRECT-1
	move.w  #SPR_PT+1,RING_TOP      ; (hal/fx.s: no bullet pool)
	move.w  #SPR_PT,RING_PT
	move.w  #SPR_PT,RING_TPM
	move.w  #SCB3+SPR_PT,RING_S3T
	sf      BP_ST
	endif
	sf      HAL_SPR_ORDN
	clr.l   HAL_SPR_BLK             ; (and HAL_SPR_INQ, the 3 bytes after it)
	clr.l   HAL_SPR_RCLN
	clr.w   HAL_SPR_PREV
	st      HAL_SPR_SPS
	clr.l   HAL_SPR_BLKN
	lea     REG_VRAMRW,a3
	move.w  #1,REG_VRAMMOD
	move.w  #SCB2+SPR_PB,REG_VRAMADDR
	move.w  #SPR_POOL-1,d1
.s2:	move.w  #$0fff,(a3)
	move.b  d0,REG_WATCHDOG
	dbra    d1,.s2
	move.w  #SCB3+SPR_PB,REG_VRAMADDR
	move.w  #0,(a3)
	move.w  #SPR_POOL-2,d1
.s3:	move.w  #$40,(a3)
	move.b  d0,REG_WATCHDOG
	dbra    d1,.s3
	move.w  #-1,HAL_SPR_W
	clr.l   HAL_SPR_ST
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
	rts

; Fast-path entries behind tilemap 1 (no Neo sprites between the tilemaps): flag the
; set, charge this stub (84 cycles at most), go on in the same shape's routine (the
; table entry with w2 bit 13 set).  In: d1 = table offset, a6 = set state.
LO_UNITS        equ (84+15)/16+1
spr_lo_v:
	lea     spr_fast_jt,a1
	bra.s   spr_lo
spr_lo_z:
	lea     spr_fast_jt+2048,a1
spr_lo:	st      SS_PRIO(a6)
	swap    d7
	subi.w  #LO_UNITS,d7
	swap    d7
	ori.w   #$100,d1
	movea.l (a1,d1.w),a1
	jmp     (a1)

	ifne SPR_RETAIN
	include "sprr.s"
	endif
	include "sprfast.inc"
