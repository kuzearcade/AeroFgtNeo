; Not cycle-exact (AEROFGT_DIRECT=1): sprites straight from the game's objects.
;
; The game's sprite-list builder (0x2bee0) is skipped and the vblank handler's copy
; (0xa14) does nothing: hal_spr_go takes its entries from lists made here by a walk
; over the object tables the way the builder went (pass 1 0xff0000..0xff30c0, pass 2
; ..0xff42c0, the group ..0xff48c0 sorted by x, pass 3 ..0xff60c0; per object the
; emitters 0x2c0d2 / 0x2c0ec / 0x2c0b4; per piece the builder's own clipping and
; attribute words).
;
; Sprites in step with the tilemaps: the original shows the list its builder made from
; the objects of frame k (as they are at slot k) with the tilemaps of slot k+3 (the
; builder runs in the next frame, the vblank handler copies its output, MAME draws the
; copy a frame later), and the game places its ground objects for that: shown any
; earlier, a building drawn as sprites over its tilemap base moves by the scroll of
; those frames against it (the game scrolls 1/2, 1/3, 1/4 pixel a frame: a one-pixel
; wobble).  So every slot k walks the objects once into list k mod 5 (FX_LISTS,
; FX_LMAX pieces at most; the game is stopped for the whole slot, so a list is one
; frame's state; the walk goes on in the slot's stages while it has time,
; fx_snap_step), and a conversion begun in slot k takes list k - 2 (fx_start; shown
; from slot k + 1, as the original's).  A conversion carried into later slots keeps its
; list; the walk skips the list a conversion still reads.  hal_spr_go goes through
; the list itself (a5 its next entry, from FX_CL up to its end FX_AEND, in a0).
;
; The walk (fx_walk) is straight loops with its state in registers: passes, objects,
; their tables, pieces (one routine per kind of table: zoom from the object or the
; piece, colour from the object or the piece, flips from the object or the piece, pass
; 1 or not; fx_em_*).  Its budget (16-cycle units: the time left in the slot) is
; checked per object against an upper bound from the object's piece counts; it stops
; before an object that may not fit and goes on from there.
;
; The HUD (the strips of lookup entries 0x3fc0-0x3fff, one per 8 entries: three per
; player, rewritten through the lookup RAM) goes to the fix layer instead: a strip the
; fix layer can show (unzoomed, one column, unflipped, colour 0x10/0x11/0x14/0x15,
; 8-pixel aligned, on screen) is kept by its slot (fx_hud_take: its four words), and at
; the walk's end each slot is compared with what the fix layer shows (the words and
; the strip's lookup entries); a changed one is made into cells (HUD_STAB) and
; written, a gone one cleared (fx_hud_draw).  The fix layer is above every sprite (the
; HUD is the front), and its palettes 4-7 are copies of the HUD's (hal_pal_convert).
; Not while the tilemap code has text there (HAL_FIXUSED): then the strips stay
; sprites.

	ifnd FX_WCHK
FX_WCHK         equ 0               ; (diagnostics: each walk done in its own slot -> a
	endif                           ; checksum of its list in FX_WCK, for tests)
FX_WCK          equ $d00f18         ; 4 x (walk number w, pieces << 8 | pool w, sum l)
FX_WCKI         equ $d00f14         ; w: the next entry (free backup RAM, hal/diag.s's
FX_WFR          equ $d00f16         ; b: the walk begun in this slot     fault registers)
FX_WIDLE        equ $d00f3c         ; l: (WALK_IDLE diagnostics, OVR_DIAG's RAM) slots without a walk
	ifnd FX_O1CHK
FX_O1CHK        equ 0               ; (diagnostics: fx_o1 checked against fx_objg)
	endif
	ifnd FX_O1
FX_O1           equ 1               ; one-piece objects' fast path (fx_o1)
	endif
	ifnd FX_HUDON
FX_HUDON        equ 1               ; the HUD on the fix layer
	endif
	ifne RES
FX_LMAX         equ 127             ; (hal/rs.s: no bullet pool, its records' room;
                                    ; an entry's index fits 7 bits)
	else
FX_LMAX         equ 96              ; pieces a list holds (the movies' most: 116, ~35
                                    ; pair bullets of them now in the bullet pool's
                                    ; records after the list: fxb_obj)
	endif
FX_NL           equ 5               ; lists
	ifnd FX_DELAY
FX_DELAY        equ 1               ; a conversion begun in slot k takes list k - FX_DELAY
                                    ; (1: measured, ground sprites locked to their tilemaps)
	endif

; walk charges, 16-cycle units (upper bounds)
FXU_CALL        equ 24              ; fx_walk's entry, exit, the pass dispatch
FXU_SLOT4       equ 8               ; four empty object slots (116 cycles)
FXU_OBJ         equ 64+64*RES       ; an object's set-up, its three tables' set-up and calls
                                    ; (hal/rs.s rs_obj: its signature, tags, links)
FXU_PIECE       equ 38+10*RES       ; a piece (the worst kind on screen, pass 1: ~596)
FXU_TAKES       equ 520             ; the HUD takes of a walk (FXH_N at most, measured ~744
                                    ; each)
FXU_PASS        equ 32              ; a pass ends, the next begins
FXU_GRP         equ 12              ; the sorted group's next object
FXU_SORT        equ 60              ; the group's sort: its count + 5 n^2 (n objects)
FXU_HUDC        equ 44              ; a HUD slot compared (unchanged: measured ~655)
FXU_HUD         equ 220             ; a HUD slot made and written (a 16-cell strip moved)
FXU_QFL         equ 72              ; and each queue entry it had to write at once (the queue
FXU_HPASS       equ 400+3*FX_HOV    ; the HUD pass entered (its slot checks, back-offs and end:
                                    ; up to ~390 units measured, 2026-10-17)
	ifnd FXU_HPRE
	ifne OVR_FIX
FXU_HPRE        equ 600             ; a strip is begun only with this much left (FXU_HUD+2*FXU_QFL
	else                            ; = 364 let the commit's walk rest overrun by ~5 lines, 2026-10-17)
FXU_HPRE        equ FXU_HUD+2*FXU_QFL
	endif
	endif
                                    ; full: fx_q_one, 2 x 16 cells ~1050 cycles; uncharged
                                    ; before: the commit's walk ran 4-6 lines over, 2026-10-17)
FX_QFLN         equ FXS+$6dc        ; w: those, this fx_hud_draw
FX_HSTRIP       equ 1250            ; cycles a queued strip takes to write in a flip (2 x 16
                                    ; cells + the queue's handling, ~1200; charged 960 / 900
                                    ; before: long flips ran 2-4 lines over, 2026-10-17)
FXU_HPEND       equ 200             ; the HUD objects pending looked for (130 slots)
FX_HPEND        equ FXS+$6de        ; b: (this walk) 0 not looked for, 1 none, 2 one pending
	ifnd FX_HOV
FX_HOV          equ 0               ; (2026-10-19) strips that overlap on the fix layer: the one
	endif                           ; under (taken later in the walk: the walk's first entry
                                    ; is drawn on top) yields - stays a sprite, its cells
                                    ; cleared - while the one above is seen (the demo's
                                    ; blinking credit digit over the 2P bombs: the digit's 2
                                    ; cells cut the bombs, its clear hollowed them; AUDIT
                                    ; s34).  A strip under one taken earlier in the walk is
                                    ; refused; fx_hud_ov, fx_hud_yref, the HUD pass's rounds.
FX_HYIELD       equ G_DX_LIST+$7c0  ; w: the yielding slots (bit per slot)
FX_HYTO         equ G_DX_LIST+$7c2  ; FXH_N b: per slot, the slot it yields to
FX_HYSEQ        equ G_DX_LIST+$7d0  ; FXH_N w: per slot, the walk number that last saw the
                                    ; slot it yields to (fx_hud_yref); FX_HYAGE walks on, the
                                    ; yield expires (the blink: on ~35 frames, off ~40)
FX_HYAGE        equ 64
FX_HSUS         equ G_DX_LIST+$7ea  ; w: (this walk) slots shown, not seen yet, under a strip
                                    ; taken: suspects - at its take, a suspect yields
FX_HOVRAN       equ G_DX_LIST+$7ec  ; b: fx_hud_ov went through the slots (the take's caller
                                    ; charges FXU_HOV / hal/fz.s FZU_HOV after it)
FX_HR1          equ G_DX_LIST+$7ed  ; b: (this walk) the HUD pass's round 1 done
FXU_HOV         equ 76              ; fx_hud_ov's slots, 16-cycle units (8 x ~130 + ~150)
FXU_HOV1        equ 30              ; the HUD pass's round 1 (fx_hud_yref, 8 slots looked at)
FXU_HOV0        equ 12              ; the pass's own test for it, every slot (~14 cycles each)

FXS             equ G_SPRRAM+$1000  ; state (sprite RAM the game leaves alone)
FX_AEND         equ FXS+0           ; l: the converted list's end (hal_spr_go: a0)
FX_BC8          equ FXS+4           ; w: 8 x its pieces
FX_PASS         equ FXS+6           ; w: 0 pass 1, 1 pass 2, 2 the group, 3 pass 3, 4 the
                                    ;    HUD's slots, 5 done
FX_OBJ          equ FXS+8           ; l: the next slot to look at (the passes in order)
FX_GI           equ FXS+12          ; w: the sorted group's / the HUD's next index
FX_GN           equ FXS+14          ; w: the sorted group's objects (-1: not sorted yet)
FX_SY           equ FXS+16
FX_SX           equ FXS+18
FX_HOK          equ FXS+21          ; b: the fix layer free for the HUD this walk
FX_SDONE        equ FXS+22          ; b: this slot's walk done (or skipped)
FX_CI           equ FXS+24          ; w: the buffer the conversion reads
FX_CL           equ FXS+26          ; l: its address
FX_OUT          equ FXS+30          ; l: the walk's next piece
FX_OUTE         equ FXS+34          ; l: its list's end
FX_MAGIC        equ FXS+38          ; l: FX_HSHD/FX_LN valid (the game's boot RAM test)
FX_RBA          equ FXS+42          ; l: the object's B/A tables' routine
FX_RC           equ FXS+46          ; l: its C table's
FX_W2BA         equ FXS+50          ; b: their w2 bytes
FX_W2C          equ FXS+51
FX_UNFIN        equ FXS+54          ; w: walks a slot did not finish (diagnostics)
FX_PHYS         equ FXS+56          ; 5 b: per slot mod 5 its list's buffer
FX_WP           equ FXS+62          ; w: the buffer the walk writes
FX_SORT         equ FXS+64          ; 16 x (key.w, object.l)
FX_LN           equ FXS+$180        ; 5 w: pieces per buffer
FX_KMOD         equ FXS+$18a        ; w: this slot's number mod 5 (its list)
FX_HSEEN        equ FXS+$18c        ; w: HUD slots taken this walk (bit per slot)
FX_HSAME        equ FXS+$18e        ; w: HUD slots taken unchanged (no drawing)
FX_HRAW         equ FXS+$190        ; FXH_N x 4 w: this walk's HUD strips (w0-w3)
FX_HSHD         equ G_DX_BUF0       ; FXH_N x FXH_SIZE: what the fix layer shows once
                                    ; the queue is written (the original's sprite-list
                                    ; buffers: unused without its builder)
FX_HMAGIC       equ G_DX_BUF0+$7f0  ; l: FX_HSHD and the queue valid
FXH_N           equ 13              ; slots: 0-7 the HUD's (lookup 0x3fc0 + 8 x slot),
                                    ; 8-12 "GAME OVER" (0x24cf, 0x24d7), "INSERT COINS!"
                                    ; (0x24ec), "CONTINUE ?" (0x24dd), its digit
                                    ; (0x24e2-0x24eb)
; The fix layer is written in the real vblank, with the sprites of the same list: the
; walk queues its writes (FX_HQ, each with its walk's number), the flip that shows a
; list's sprites writes the queue up to that list's number (fx_hud_apply).
FX_HQ           equ G_DX_LIST+$400  ; FXQ_N x FXQ_SIZE
FXQ_N           equ 12
FXQ_SIZE        equ 80
FXQ_SEQ         equ 0               ; w: the walk's number
FXQ_TYPE        equ 2               ; w: 1 write, 2 clear
FXQ_COL         equ 4               ; w column, w row, w cells per column
FXQ_C0          equ 16              ; 16 w: column 0's cells (a write)
FXQ_C1          equ 48              ; 16 w: column 1's
FX_QH           equ FXS+$690        ; w: the queue's oldest entry
FX_QN           equ FXS+$692        ; w: its entries
FX_WSEQ         equ FXS+$694        ; w: the walk's number (the slot it began in)
FX_LSEQ         equ FXS+$696        ; 5 w: per buffer its list's walk number
FX_QUPTO        equ FXS+$6a0        ; w: the queue to be written up to this walk number
FX_QDUE         equ FXS+$6a2        ; b: (a flip showed a list since)
FXH_RAW         equ 0               ; 4 w: the strip's words
FXH_COL         equ 8               ; w column, w row, w cells per column (0: none), w
                                    ; palette << 12
FXH_LUT         equ 16              ; 8 w: its lookup entries (one per tile)
FXH_C0          equ 32              ; 16 w: column 0 (palette << 12 | S tile)
FXH_C1          equ 64              ; 16 w: column 1
FXH_SIZE        equ 96              ; (to G_DX_BUF0+$4e0)
FX_LISTS        equ G_SPRRAM        ; the 5 lists (sprite RAM the game no longer writes:
                                    ; 0x000, 0x800, 0xc00, 0x1800, 0x1c00: 1KB each)

FXC	macro                           ; (FX_DIAG: steps of kind \1)
	ifne FX_DIAG
	addq.w  #1,FXS+$140+2*\1
	endif
	endm

; the lists' addresses
fx_ltab:
	dc.l    FX_LISTS,FX_LISTS+$800,FX_LISTS+$c00,FX_LISTS+$1800,FX_LISTS+$1c00

; after the game's boot RAM test (it overwrites sprite RAM): no lists, nothing shown on
; the fix layer.  Clobbers d0.
fx_magic:
	cmpi.l  #$46584853,FX_HMAGIC    ; (work RAM: the shadow, the queue)
	beq.s   .hm
	bsr.w   fx_hreset
.hm:	cmpi.l  #$46584853,FX_MAGIC
	beq.w   .m
	move.l  #$46584853,FX_MAGIC
	move.l  a0,-(sp)
	clr.l   FX_LN
	clr.l   FX_LN+4
	clr.l   FX_LN+8                 ; (and FX_KMOD)
	bsr.w   bp_reset
	ifne FUSED
	jsr     fz_reset                ; (hal/fz.s: no records, no pass)
	endif
	move.l  #$00010203,FX_PHYS      ; (each slot's list: its own buffer)
	move.b  #4,FX_PHYS+4
	bsr.w   fx_hreset
	moveq   #21-1,d0                ; (hal/tx.s: every row has content until blasted)
	lea     FX1_MASK,a0
.cm:	move.l  #-1,(a0)+
	dbra    d0,.cm
	move.l  #-1,FX1_PAT             ; (all counted shown until the first placement)
	st      FX1_DIRTY
	clr.l   FX1_PEND
	move.l  #-1,FX1_WIN             ; (any row)
	sf      FX_DELTA                ; (hal/dl.s)
	sf      FX_PON
	clr.w   FX_FLATE                ; (and FX_FNOH)
	if (RES=0)&(FUSED=0)
	jsr     dl_init
	endif
	move.w  #-1,FX_SBUF
	move.w  #-1,FX_CBUF
	clr.w   FX1_HN
	movea.l (sp)+,a0
.m:	rts

; hal_spr_end's replacement: a conversion begins in this slot (k): the list of slot
; k - FX_DELAY (its buffer: FX_PHYS).  a5 = its first entry.  Clobbers d0.
fx_start:
	bsr.w   fx_magic
	move.l  a1,-(sp)
	move.w  FX_KMOD,d0              ; (this slot's - FX_DELAY, mod 5)
	ifne FX_DELAY
	subq.w  #FX_DELAY,d0
	endif
	bpl.s   .k
	addq.w  #FX_NL,d0
.k:	lea     FX_PHYS,a1
	move.b  (a1,d0.w),d0
	ext.w   d0
	move.w  d0,FX_CI                ; (the buffer it reads)
	lea     FX_LN,a1
	add.w   d0,d0
	move.w  (a1,d0.w),d0            ; (bounded: the boot RAM test)
	cmpi.w  #FX_LMAX,d0
	bls.s   .n
	moveq   #0,d0
.n:	lsl.w   #3,d0
	move.w  d0,FX_BC8
	move.w  FX_CI,d0
	andi.w  #7,d0
	cmpi.w  #FX_NL,d0
	blo.s   .b
	moveq   #0,d0
.b:	add.w   d0,d0
	add.w   d0,d0
	lea     fx_ltab(pc),a1
	move.l  (a1,d0.w),d0
	move.l  d0,FX_CL
	movea.l d0,a5                   ; (hal_spr_go: a5 the next entry, up to FX_AEND)
	add.w   FX_BC8,d0
	move.l  d0,FX_AEND
	movea.l (sp)+,a1
	rts

	ifne WALK_IDLE
; Z set: the list this slot's conversion would take is the newest complete set's or
; the shown set's already (WALK_IDLE: a slot without a walk repeats the last list).
; Clobbers d0, a0.
fx_dupq:
	move.w  FX_KMOD,d0
	ifne FX_DELAY
	subq.w  #FX_DELAY,d0
	endif
	bpl.s   .k
	addq.w  #FX_NL,d0
.k:	lea     FX_PHYS,a0
	move.b  (a0,d0.w),d0
	ext.w   d0
	cmp.w   FX_CBUF,d0
	beq.s   .z
	cmp.w   FX_SBUF,d0
.z:	rts
	endif

; Z set when the list this slot's conversion (or update in place) would take is the one
; still being walked (the last slot's walk unfinished: its buffer is this slot's too):
; converting it now shows a set missing the objects not reached (one-frame dropouts,
; 2026-10-17).  Clobbers d0, a0.
	if LIST_GUARD|CONV_FIRST|WALK_IDLE
fx_listrdy:
	tst.b   FX_SDONE
	bne.s   .r                      ; (Z clear: ready)
	move.w  FX_KMOD,d0
	ifne FX_DELAY
	subq.w  #FX_DELAY,d0
	endif
	bpl.s   .k
	addq.w  #FX_NL,d0
.k:	lea     FX_PHYS,a0
	move.b  (a0,d0.w),d0
	ext.w   d0
	cmp.w   FX_WP,d0                ; the walk's buffer: not ready
.r:	rts
	endif

; slot start (hal_vid_prep): this slot's walk.  The last slot's walk unfinished (no
; time): it goes on, this slot's list is the same buffer (shown twice: a late frame,
; not a frame missing what it had not reached).  Else a new walk into a buffer that
; neither the conversion going on nor the one this slot begins (the last slot's list)
; reads.  Clobbers d0.
fx_snap_begin:
	bsr.w   fx_magic
	move.w  FX_KMOD,d0              ; this slot's number mod 5
	addq.w  #1,d0
	cmpi.w  #FX_NL,d0
	blo.s   .k
	moveq   #0,d0
.k:	move.w  d0,FX_KMOD
	movem.l d1/a0,-(sp)
	lea     FX_PHYS,a0
	tst.b   FX_SDONE
	bne.s   .new
	addq.w  #1,FX_UNFIN             ; (diagnostics)
	ifne FX_WCHK
	sf      FX_WFR
	endif
	move.b  FX_WP+1,(a0,d0.w)       ; unfinished: on with it
	bra.w   .x
.new:
	ifeq RES
	bsr.w   bp_poll                 ; (the bullet pool: on, off)
	endif
	move.w  d0,d1                   ; a buffer: not the last slot's list's, not the
	subq.w  #1,d1                   ; conversion's
	bpl.s   .p
	addq.w  #FX_NL,d1
.p:	move.b  (a0,d1.w),d1            ; (the last slot's list's buffer)
	ifne WALK_IDLE
	tst.b   HAL_SCH_BUSY            ; (experiment: the game still in its frame's logic
	beq.s   .fw                     ; (the timer began the slot): no new walk - the
	addq.l  #1,FX_WIDLE             ; objects are half updated; this slot's list is
	move.w  FX_KMOD,d0              ; the last one's again, as the original shows its
	move.b  d1,(a0,d0.w)            ; last list when its logic spans two vblanks)
	bra.w   .x
.fw:
	endif
	moveq   #FX_NL-1,d0
.f:	cmp.b   d1,d0
	beq.s   .fn
	cmp.w   FX_SBUF,d0              ; (hal/dl.s: the shown set's list)
	beq.s   .fn
	cmp.w   FX_CBUF,d0              ; (and the complete one's)
	beq.s   .fn
	ifeq RES
	tst.b   FX_PON                  ; (and a pending update's: a set completed after it
	beq.s   .fp                     ; took FX_CBUF, and its list was overwritten before
	cmp.w   DLP+D_BUF,d0            ; its flip - the set then shown with another list,
	beq.s   .fn                     ; its next update keeping heads by it, 2026-10-16)
.fp:
	endif
	tst.w   HAL_SPR_W
	bmi.s   .fy
	cmp.w   FX_CI,d0
	beq.s   .fn
.fy:	bra.s   .fz
.fn:	dbra    d0,.f
	ifeq RES
	addq.w  #1,FX_UNFIN             ; (none free - the last list, the shown, complete,
	move.w  FX_KMOD,d0              ; pending ones and the conversion's: this slot's
	move.b  d1,(a0,d0.w)            ; list the last one's again, no walk: a late frame;
	bra.w   .x                      ; buffer 0 taken was a pending update's list, its
	endif                           ; set shown with another, 2026-10-16)
	moveq   #0,d0                   ; (never: 5 buffers, 2 excluded)
.fz:	move.w  FX_KMOD,d1
	move.b  d0,(a0,d1.w)
	move.w  d0,FX_WP
	move.w  HAL_FRAMES+2,FX_WSEQ    ; (its walk's number: the fix layer's queue)
	move.w  d0,d1
	add.w   d1,d1
	lea     FX_LSEQ,a0
	move.w  HAL_FRAMES+2,(a0,d1.w)
	lea     FX_LN,a0
	add.w   d0,d0
	clr.w   (a0,d0.w)
	lea     FX_PBN,a0
	clr.w   (a0,d0.w)
	add.w   d0,d0
	lea     fx_ltab(pc),a0
	move.l  (a0,d0.w),d0
	move.l  d0,FX_OUT
	addi.l  #8*FX_LMAX,d0
	move.l  d0,FX_OUTE
	move.l  d0,FX_PBP               ; (the pool's records: after the list)
	addi.l  #8*BP_N,d0
	move.l  d0,FX_PBE
	sf      FX_SDONE
	ifne FX_WCHK
	tst.b   HAL_SCH_BUSY            ; (only walks of a waiting game: deterministic)
	seq     FX_WFR
	endif
	clr.w   FX_HSEEN                ; the walk from the top
	clr.w   FX_HSAME
	ifne FX_HOV
	clr.w   FX_HSUS
	sf      FX_HR1
	endif
	sf      FX_HPEND
	tst.w   HAL_FIXUSED
	seq     FX_HOK
	ifeq FX_HUDON
	sf      FX_HOK
	endif
	move.w  G_DX_SCRY,FX_SY
	move.w  G_DX_SCRX,FX_SX
	clr.w   FX_PASS
	move.l  #G_DX_OBJ1,FX_OBJ
	move.w  #-1,FX_GN
	ifne RES
	jsr     rs_wbegin               ; (hal/rs.s: its links to the walk before)
	endif
.x:	movem.l (sp)+,d1/a0
	rts

	ifne FX_WCHK
; the walk just done: if begun in this slot, its list's checksum (FX_WCK).  Clobbers
; d0-d3, a0-a1.
fx_wchk:
	tst.b   FX_WFR
	beq.s   .x
	move.w  FX_WP,d0
	add.w   d0,d0
	lea     FX_LN,a0
	move.w  (a0,d0.w),d1            ; pieces
	lea     FX_PBN,a0
	move.w  (a0,d0.w),d2            ; pool records
	add.w   d0,d0
	lea     fx_ltab(pc),a0
	movea.l (a0,d0.w),a0
	movea.l a0,a1
	adda.w  #8*FX_LMAX,a1
	moveq   #0,d3
	move.w  d1,d0
	bra.s   .l1
.l:	add.l   (a0)+,d3
	rol.l   #3,d3
	add.l   (a0)+,d3
	rol.l   #5,d3
.l1:	dbra    d0,.l
	move.w  d2,d0
	bra.s   .p1
.p:	add.l   (a1)+,d3
	rol.l   #3,d3
	add.l   (a1)+,d3
	rol.l   #5,d3
.p1:	dbra    d0,.p
	move.w  FX_WCKI,d0
	andi.w  #3,d0
	lsl.w   #3,d0
	lea     FX_WCK,a0
	adda.w  d0,a0
	move.w  FX_WSEQ,(a0)+
	lsl.w   #8,d1
	move.b  d2,d1
	move.w  d1,(a0)+
	move.l  d3,(a0)
	addq.w  #1,FX_WCKI
.x:	rts
	endif

; this slot's walk on, with the time the slot has left but d0 lines (and HAL_RESV).
; Z set: the walk is done (or none this slot).  Keeps all but d0.
fx_snap_step:
	tst.b   FX_SDONE
	bne.w   .z
	tst.b   HAL_OUT
	bne.w   .no
	movem.l d1-d7/a0-a6,-(sp)
	add.w   HAL_RESV,d0             ; lines left, less d0 + 2
	addq.w  #2,d0
	move.w  REG_LSPCMODE,d1
	lsr.w   #7,d1
	cmp.w   HAL_K0R,d1
	bhs.s   .p
	addi.w  #264,d1
.p:	add.w   d0,d1
	move.w  HAL_KDL,d6
	sub.w   d1,d6
	ble.w   .nz
	cmpi.w  #600,d6
	bls.s   .c
	move.w  #600,d6
.c:	mulu    #48,d6                  ; (48 units a line)
	move.w  #1,REG_VRAMMOD          ; (fx_hud_draw)
	if (OVR_DIAG=1)&(OVB_ON=0)
	tst.b   OVD_INC                 ; (diagnostics: the commit's walk: passes, units)
	beq.s   .d0
	move.w  FX_PASS,OVD_S
	move.w  d6,OVD_S+4
.d0:
	endif
	bsr.w   fx_walk
	if (OVR_DIAG=1)&(OVB_ON=0)
	tst.b   OVD_INC
	beq.s   .d1
	move.w  FX_PASS,OVD_S+2
	move.w  d6,OVD_S+6
.d1:
	endif
	move.w  FX_WP,d0                ; its pieces so far (its buffer)
	add.w   d0,d0
	add.w   d0,d0
	lea     fx_ltab(pc),a0
	move.l  FX_OUT,d1
	sub.l   (a0,d0.w),d1
	lsr.w   #3,d1
	lsr.w   #1,d0
	lea     FX_LN,a0
	move.w  d1,(a0,d0.w)
	add.w   d0,d0                   ; its pool records so far
	lea     fx_ltab(pc),a0
	move.l  FX_PBP,d1
	sub.l   (a0,d0.w),d1
	subi.l  #8*FX_LMAX,d1
	lsr.w   #3,d1
	lsr.w   #1,d0
	lea     FX_PBN,a0
	move.w  d1,(a0,d0.w)
	cmpi.w  #5,FX_PASS
	bne.w   .nz
	st      FX_SDONE
	ifne FX_WCHK
	bsr.w   fx_wchk
	endif
	movem.l (sp)+,d1-d7/a0-a6
.z:	move.w  #4,ccr
	rts
.nz:	movem.l (sp)+,d1-d7/a0-a6
.no:	move.w  #0,ccr
	rts

; ================================================================ the walk
; On from FX_PASS / FX_OBJ / FX_GI within d6 units (fx_snap_step).  Registers: a0
; object, a1 the list on (FX_OUT), a2 its end, a3 table, a4 piece, a5 zoom << 12 (type
; 0x2e objects), a6 the pass's end, d2/d3 scroll y/x, d4 pieces left - 1 (high: the
; table's routine), d5 the w2 byte (high byte: the object's), d6 units left.
; Clobbers all.
fx_walk:
	movea.l FX_OUT,a1
	movea.l FX_OUTE,a2
	move.w  FX_SY,d2
	move.w  FX_SX,d3
	subi.w  #FXU_CALL,d6
	tst.w   FX_PASS                 ; (pass 1 may still take the HUD)
	bne.s   .pass
	subi.w  #FXU_TAKES,d6
.pass:	tst.w   d6
	bmi.w   .x
	move.w  FX_PASS,d0
	add.w   d0,d0
	add.w   d0,d0
	jmp     .pt(pc,d0.w)
.pt:	bra.w   .lin
	bra.w   .lin
	bra.w   .grp
	bra.w   .lin
	bra.w   .hud
	bra.w   .x
.ends:	dc.l    G_DX_OBJ2,G_DX_OBJ3,G_DX_OBJ4,G_DX_OBJ5
.starts:dc.l    G_DX_OBJ2,G_DX_OBJ3,G_DX_OBJ4

	; the slots in order up to the pass's end (d0 = 4 x the pass)
.lin:	lea     .ends(pc),a6
	movea.l (a6,d0.w),a6
	movea.l FX_OBJ,a0
.s:	cmpa.l  a6,a0                   ; eight slots a turn (those past the end
	bhs.w   .pend                   ; are not taken)
	tst.b   (a0)
	bmi.s   .act
	tst.b   $60(a0)
	bmi.s   .a1
	tst.b   $c0(a0)
	bmi.s   .a2
	tst.b   $120(a0)
	bmi.s   .a3
	tst.b   $180(a0)
	bmi.s   .a4
	tst.b   $1e0(a0)
	bmi.s   .a5
	tst.b   $240(a0)
	bmi.s   .a6
	tst.b   $2a0(a0)
	bmi.s   .a7
	lea     $300(a0),a0
	subi.w  #2*FXU_SLOT4,d6
	bpl.s   .s
	move.l  a0,FX_OBJ
	bra.w   .x
.a7:	lea     $60(a0),a0
.a6:	lea     $60(a0),a0
.a5:	lea     $60(a0),a0
.a4:	lea     $60(a0),a0
.a3:	lea     $60(a0),a0
.a2:	lea     $60(a0),a0
.a1:	lea     $60(a0),a0
	subi.w  #2*FXU_SLOT4,d6
	cmpa.l  a6,a0
	bhs.w   .pend
.act:
	ifne RES
	jsr     rs_obj                  ; (hal/rs.s: the same as the last walk: copied)
	else
	bsr.w   fx_obj
	endif
	bcs.s   .bail
	cmpa.l  a2,a1
	bhs.s   .full
	lea     $60(a0),a0
	bra.s   .s
.bail:	move.l  a0,FX_OBJ               ; (this object again, next time)
	bra.w   .x
.full:	move.w  #4,FX_PASS              ; the list full: the HUD, then done
	clr.w   FX_GI
	bra.w   .pass
	; the pass done: the next
.pend:	subi.w  #FXU_PASS,d6
	move.w  FX_PASS,d0
	addq.w  #1,d0
	move.w  d0,FX_PASS
	cmpi.w  #4,d0
	bhs.s   .ph
	lsl.w   #2,d0
	lea     .starts-4(pc),a0
	move.l  (a0,d0.w),FX_OBJ
	bra.w   .pass
.ph:	clr.w   FX_GI
	bra.w   .pass

	; the group: in x order unless 0xff90e6 is set
.grp:	tst.w   G_DX_90E6
	bne.w   .lin
	tst.w   FX_GN
	bpl.s   .gs
	bsr.w   fx_sort                 ; (C set: no time for it)
	bcs.w   .x
	clr.w   FX_GI
.gs:	move.w  FX_GI,d0
	cmp.w   FX_GN,d0
	bhs.s   .pend
	subi.w  #FXU_GRP,d6
	bmi.w   .x
	move.w  d0,d1
	add.w   d1,d1
	add.w   d0,d1
	add.w   d1,d1
	lea     FX_SORT,a0
	movea.l 2(a0,d1.w),a0
	tst.b   (a0)
	bpl.s   .gn                     ; (gone since)
	ifne RES
	jsr     rs_obj
	else
	bsr.w   fx_obj
	endif
	bcs.w   .x
	cmpa.l  a2,a1
	bhs.w   .full
.gn:	addq.w  #1,FX_GI
	bra.s   .gs

	; the walk's end: the HUD's slots
.hud:	move.w  FX_GI,d0
	cmpi.w  #FXH_N,d0
	bhs.s   .hd
	ifne OVR_FIX
	tst.w   d0                      ; (the pass's skips and end, ~2000 cycles in all:
	bne.s   .hu                     ; charged when it is entered, 2026-10-17)
	subi.w  #FXU_HPASS,d6
	bmi.w   .x
.hu:
	endif
	ifne FX_HOV
	tst.w   d0                      ; (FX_HOV) with yields, once a walk, first: the
	bne.s   .h2                     ; yielding slots' sightings renewed and the ones
	ifeq FX_HOVCHG
	subi.w  #FXU_HOV0,d6            ; shown and not taken cleared, before the cells of
	endif
	tst.w   FX_HYIELD               ; the strips above them are written (fx_hud_round1)
	beq.s   .h2
	ifne FX_HOVCHG
	subi.w  #FXU_HOV0,d6            ; (FX_HOVCHG: charged with yields only)
	endif
	tst.b   FX_HR1
	bne.s   .h2
	bsr.w   fx_hud_round1
	st      FX_HR1
	moveq   #0,d0                   ; (the slot index again: round 1 clobbers d0)
.h2:
	endif
	move.w  FX_HSAME,d1             ; taken unchanged: nothing to do
	btst    d0,d1
	bne.s   .hn
	move.w  FX_HSEEN,d1             ; neither taken nor shown: nothing to do
	btst    d0,d1
	bne.s   .ho
	move.w  d0,d1
	lsl.w   #5,d1                   ; (x 96: FXH_SIZE)
	move.w  d1,d7
	add.w   d1,d1
	add.w   d7,d1
	lea     FX_HSHD+FXH_COL+4,a4
	tst.w   (a4,d1.w)
	bne.s   .ho
.hn:	addq.w  #1,FX_GI
	subq.w  #8,d6                   ; (~100 cycles)
	bra.s   .hud
.ho:	move.w  FX_HSEEN,d1             ; (shown, not taken: cleared - unless a HUD
	btst    d0,d1                   ; object is new, its handler not run yet)
	ifeq FUSED                      ; (hal/fz.s: the records are made after the handlers)
	bne.s   .hk
	bsr.w   fx_hud_pend
	beq.s   .hn
	endif
.hk:	cmpi.w  #FXU_HPRE,d6            ; (enough for the worst: a clear and a write, each
					; with the queue full; charged what it used)
	blt.w   .x
	addq.w  #1,FX_GI
	bsr.w   fx_hud_draw
	sub.w   d0,d6
	ifne FX_HOV
	bra.w   .hud
	else
	bra.s   .hud
	endif
.hd:	move.w  #5,FX_PASS
.x:	move.l  a1,FX_OUT
	rts

; Z set when a HUD/text object (type 2: lives, bombs and the score, 3: the PRESS
; START prompt) among the pass-1 slots is new - its active byte 0x01, its handler not
; run yet: the walk does not take it, but the original's builder (a task of its own,
; mid-frame) sees it after its handler made it 0x81.  The game respawning a player
; (0x1987e) makes the HUD object anew at a frame's end: its strips were cleared for one
; frame and written again (the HUD's blink, ~8 in 600000 frames, 2026-10-16).  Looked for
; once a walk.  Keeps all but d1 (charged in d6).
fx_hud_pend:
	tst.b   FX_HOK                  ; (the fix layer the tilemap text's: cleared)
	beq.s   .no
	tst.b   FX_HPEND
	bne.s   .k
	movem.l d0/a0,-(sp)
	subi.w  #FXU_HPEND,d6
	move.b  #1,FX_HPEND
	movea.l #G_DX_OBJ1,a0
	move.w  #(G_DX_OBJ2-G_DX_OBJ1)/$60-1,d0
.l:	cmpi.b  #1,(a0)
	bne.s   .n
	move.w  $16(a0),d1
	subq.w  #2,d1
	cmpi.w  #1,d1
	bhi.s   .n
	move.b  #2,FX_HPEND
	bra.s   .e
.n:	lea     $60(a0),a0
	dbra    d0,.l
.e:	movem.l (sp)+,d0/a0
.k:	cmpi.b  #2,FX_HPEND
	rts
.no:	moveq   #1,d1                   ; Z clear
	rts

; the group's sort (0xff42c0..0xff48c0): each active object before the first with a
; key (x + 0x8000) the same or higher, unsigned (the original's insertion), into
; FX_SORT, FX_GN.  Charged first (the count: FXU_SORT, then 5 n^2).  C set: no time.
; Clobbers d0, d1, d4, d5, a0, a3, a4, a5.
fx_sort:
	subi.w  #FXU_SORT,d6            ; (the count, charged first)
	bpl.s   .cn
	ori     #1,ccr
	rts
.cn:	movea.l #G_DX_OBJ3,a0           ; n: the active ones
	moveq   #0,d0
	moveq   #15,d1
.n:	tst.b   (a0)
	bpl.s   .n1
	addq.w  #1,d0
.n1:	lea     $60(a0),a0
	dbra    d1,.n
	move.w  d0,d1
	mulu    d0,d1
	move.w  d1,d0
	lsl.w   #2,d1
	add.w   d0,d1
	cmp.w   d1,d6
	bge.s   .go
	ori     #1,ccr
	rts
.go:	sub.w   d1,d6
	lea     FX_SORT,a4
	moveq   #0,d5                   ; entries
	movea.l #G_DX_OBJ3,a0
	moveq   #15,d4
.o:	tst.b   (a0)
	bpl.s   .on
	move.w  $10(a0),d0
	addi.w  #$8000,d0
	movea.l a4,a3                   ; first entry with a key >= d0 (unsigned)
	move.w  d5,d1
	bra.s   .c1
.c:	cmp.w   (a3),d0
	bls.s   .ins
	addq.l  #6,a3
.c1:	dbra    d1,.c
.ins:	move.w  d5,d1                   ; shift the rest up, from the end
	add.w   d1,d1
	add.w   d5,d1
	add.w   d1,d1
	lea     (a4,d1.w),a5
.sh:	cmpa.l  a3,a5
	bls.s   .put
	move.l  -4(a5),2(a5)
	move.w  -6(a5),(a5)
	subq.l  #6,a5
	bra.s   .sh
.put:	move.w  d0,(a3)
	move.l  a0,2(a3)
	addq.w  #1,d5
.on:	lea     $60(a0),a0
	dbra    d4,.o
	move.w  d5,FX_GN
	andi    #$fe,ccr
	rts

; ---------------------------------------------------------------- an object
; Object a0 (active): its tables B (b43 bit 7: the table at $44, b43 bits 0-3 + 1
; pieces), C (the table at $1a, b4 + 1), A (b43 bit 6: as B), charged first (bound:
; FXU_OBJ + FXU_PIECE per piece).  Per object: zoom (type 0x2e: the object's b1 for
; both), bit 5 (b19), flips (b42, or each piece's when 0), colour (b5 if its bit 7 is
; set: for B/A only when b43 bit 4 is clear), hence each table's routine and w2 byte
; (FX_RBA/FX_W2BA, FX_RC/FX_W2C).  C set: no time (nothing done).
; Clobbers d0, d1, d4, d5, d7, a3, a4, a5.
fx_obj:
	ifne FX_O1
	move.b  $43(a0),d1              ; B/A tables: the general way
	andi.b  #$c0,d1
	bne.w   fx_objg
	move.w  $16(a0),d0
	cmpi.w  #$18,d0                 ; (a pair bullet: fxb_obj)
	beq.w   fxb_obj
	cmpi.w  #$2e,d0                 ; (zoom from the object)
	beq.w   fx_objg
	tst.b   4(a0)                   ; one piece (most objects): fx_o1
	ifne FX_O1CHK
	beq.w   fx_o1chk
	else
	beq.w   fx_o1
	endif
	else
	cmpi.w  #$18,$16(a0)            ; (a pair bullet: fxb_obj)
	beq.w   fxb_obj
	endif
fx_objg:
	moveq   #0,d0                   ; the bound
	move.b  4(a0),d0
	addq.w  #1,d0
	move.b  $43(a0),d1
	moveq   #$f,d7
	and.b   d1,d7
	addq.w  #1,d7
	tst.b   d1
	bpl.s   .b1
	add.w   d7,d0
.b1:	btst    #6,d1
	beq.s   .b2
	add.w   d7,d0
.b2:	move.w  d0,d7                   ; x 34 (FXU_PIECE)
	lsl.w   #5,d0
	add.w   d7,d7
	add.w   d7,d0
	addi.w  #FXU_OBJ,d0
	cmp.w   d0,d6
	bge.s   .go
	ori     #1,ccr
	rts
.go:	sub.w   d0,d6
	FXC     0
	moveq   #0,d7                   ; the routine index (k2e 8, cobj 4, flips 2,
	moveq   #0,d5                   ; pass 1 1); d5: the w2 byte
	tst.w   FX_PASS
	bne.s   .k
	moveq   #1,d7
.k:	cmpi.w  #$2e,$16(a0)
	bne.s   .c
	moveq   #0,d0
	move.b  1(a0),d0
	ror.w   #4,d0
	andi.w  #$f000,d0
	movea.w d0,a5
	addq.w  #8,d7
.c:	tst.b   $19(a0)                 ; bit 5
	bpl.s   .p0
	btst    #0,$19(a0)
	beq.s   .p1
.p0:	ori.b   #$20,d5
.p1:	move.b  $2a(a0),d0              ; flips
	beq.s   .f0
	or.b    d0,d5
	bra.s   .f1
.f0:	addq.w  #2,d7
.f1:	move.w  d7,d0                   ; d0/d4: without the object's colour
	move.b  d5,d4
	move.b  5(a0),d1
	bpl.s   .nc
	andi.b  #$f,d1                  ; d7/d5: with it
	or.b    d1,d5
	addq.w  #4,d7
.nc:	lea     fx_emt(pc),a4
	lsl.w   #2,d7
	move.b  $43(a0),d1
	andi.b  #$c0,d1
	bne.s   .bt
	movea.l (a4,d7.w),a4            ; C only (most objects): straight on
	move.l  $1a(a0),d0
	bclr    #0,d0
	movea.l d0,a3
	moveq   #0,d4
	move.b  4(a0),d4
	jsr     (a4)
	andi    #$fe,ccr
	rts
.bt:	move.l  (a4,d7.w),FX_RC         ; C: with the colour (if any)
	move.b  d5,FX_W2C
	move.b  $43(a0),d1
	btst    #4,d1
	beq.s   .ba
	lsl.w   #2,d0                   ; B/A with b43 bit 4: without
	move.l  (a4,d0.w),FX_RBA
	move.b  d4,FX_W2BA
	bra.s   .t
.ba:	move.l  FX_RC,FX_RBA
	move.b  d5,FX_W2BA
.t:	tst.b   d1                      ; B
	bpl.s   .tc
	move.l  $44(a0),d0              ; (read while the game may be mid-frame: even)
	bclr    #0,d0
	movea.l d0,a3
	moveq   #$f,d4
	and.b   d1,d4
	move.b  FX_W2BA,d5
	movea.l FX_RBA,a4
	jsr     (a4)
.tc:	move.l  $1a(a0),d0              ; C
	bclr    #0,d0
	movea.l d0,a3
	moveq   #0,d4
	move.b  4(a0),d4
	move.b  FX_W2C,d5
	movea.l FX_RC,a4
	jsr     (a4)
	move.b  $43(a0),d1              ; A
	btst    #6,d1
	beq.s   .x
	move.l  $44(a0),d0
	bclr    #0,d0
	movea.l d0,a3
	moveq   #$f,d4
	and.b   d1,d4
	move.b  FX_W2BA,d5
	movea.l FX_RBA,a4
	jsr     (a4)
.x:	andi    #$fe,ccr
	rts
	ifne FX_O1
; ---------------------------------------------------------------- one-piece objects
; The C table only, one piece, no zoom from the object (87% of the objects walked): the
; set-up and the piece in one go (fx_o1_*: the EMIT body without its loop), charged
; as fx_objg would.  Same output as fx_objg + fx_em_*.
fx_o1:
	moveq   #FXU_OBJ+FXU_PIECE,d0
	cmp.w   d0,d6
	bge.s   .go
	ori     #1,ccr
	rts
.go:	sub.w   d0,d6
	FXC     0
	moveq   #0,d5                   ; d5: the w2 byte; d7: the routine (pass 1 2,
	moveq   #0,d7                   ; flips 4, cobj 8)
	tst.b   $19(a0)                 ; bit 5
	bpl.s   .p0
	btst    #0,$19(a0)
	beq.s   .p1
.p0:	moveq   #$20,d5
.p1:	move.b  $2a(a0),d0              ; flips
	beq.s   .f0
	or.b    d0,d5
	bra.s   .f1
.f0:	moveq   #4,d7
.f1:	move.b  5(a0),d1
	bpl.s   .nc
	andi.b  #$f,d1
	or.b    d1,d5
	addq.w  #8,d7
.nc:	tst.w   FX_PASS
	bne.s   .np
	addq.w  #2,d7
.np:	move.l  $1a(a0),d0
	bclr    #0,d0
	movea.l d0,a3
	move.w  .vt(pc,d7.w),d0
	jmp     .vt(pc,d0.w)
.vt:	dc.w    fx_o1_000-.vt,fx_o1_001-.vt,fx_o1_010-.vt,fx_o1_011-.vt
	dc.w    fx_o1_100-.vt,fx_o1_101-.vt,fx_o1_110-.vt,fx_o1_111-.vt

	ifne FX_O1CHK
; (diagnostics) fx_o1, then the general way into FX_CKB: the same entry?  FX_CKN
; objects compared, FX_CKX different (a HUD strip fx_o1 took is not compared).
FX_CKB          equ $d00f00         ; 8 b
FX_CKN          equ $d00f08         ; l
FX_CKX          equ $d00f0c         ; l
FX_CKA          equ $d00f10         ; l: where fx_o1 wrote
fx_o1chk:
	move.l  a1,FX_CKA
	bsr.w   fx_o1
	bcs.s   .x                      ; (no time: nothing done)
	movem.l d6/a1-a2,-(sp)
	lea     FX_CKB,a1
	lea     8(a1),a2
	move.w  #$7000,d6
	move.b  FX_HOK,-(sp)
	sf      FX_HOK
	bsr.w   fx_objg
	move.b  (sp)+,FX_HOK
	move.l  a1,d0                   ; the general way's entries (0 or 1)
	lea     FX_CKB,a1
	sub.l   a1,d0
	movem.l (sp)+,d6/a3-a4          ; a3: fx_o1's end, a4: the list's end
	movea.l a4,a2
	move.l  a3,d1
	sub.l   FX_CKA,d1
	addq.l  #1,FX_CKN
	cmp.l   d0,d1
	beq.s   .s
	tst.l   d1                      ; (fx_o1 took a HUD strip?)
	bne.s   .bad
	move.w  6(a1),d1
	cmpi.w  #$24cf,d1
	bhs.s   .ok
	bra.s   .bad
.s:	tst.l   d0
	beq.s   .ok
	movea.l FX_CKA,a4
	cmpm.l  (a1)+,(a4)+
	bne.s   .bad
	cmpm.l  (a1)+,(a4)+
	beq.s   .ok
.bad:	addq.l  #1,FX_CKX
.ok:	movea.l a3,a1
	andi    #$fe,ccr
.x:	rts
	endif

; \1 colour from the object (in d5), \2 flips from the piece, \3 pass 1.
EMIT1	macro
fx_o1_\1\2\3:
	move.w  $e(a0),d0               ; y
	add.w   4(a3),d0
	cmpi.w  #$fee0,d0
	bhs.s   .yv
	cmpi.w  #$e0,d0
	bhs.w   .n
.yv:	move.w  $10(a0),d1              ; x
	add.w   6(a3),d1
	cmpi.w  #$ff40,d1
	bhs.s   .xv
	cmpi.w  #$140,d1
	bhs.w   .n
.xv:	cmpa.l  a2,a1
	bhs.w   .n                      ; (the list full)
	movea.l (a3),a4
	btst    #0,3(a3)                ; (odd: the game is rewriting the object)
	bne.w   .n
	add.w   d2,d0                   ; w0 = y + scroll | zoomy << 12 | (a4)+0 << 8
	andi.w  #$1ff,d0
	cmpi.w  #224,d0
	blo.s   .vy
	moveq   #$e,d7
	and.b   (a4),d7
	lsl.w   #3,d7
	add.w   d0,d7
	cmpi.w  #512-16,d7
	bls.w   .n
.vy:	move.b  $a(a3),d7
	beq.s   .zy
	ror.w   #4,d7
	andi.w  #$f000,d7
	or.w    d7,d0
.zy:	move.w  (a4),d7
	andi.w  #$ff00,d7
	or.w    d7,d0
	move.w  d0,(a1)+
	add.w   d3,d1                   ; w1 = x + scroll | zoomx << 12 | (a4)+1 << 8
	andi.w  #$1ff,d1
	cmpi.w  #320,d1
	blo.s   .vx
	moveq   #$e,d7
	and.b   1(a4),d7
	lsl.w   #3,d7
	add.w   d1,d7
	cmpi.w  #512-16,d7
	bhi.s   .vx
	subq.l  #2,a1                   ; (w0 taken back)
	bra.w   .n
.vx:	move.b  $b(a3),d7
	beq.s   .zx
	ror.w   #4,d7
	andi.w  #$f000,d7
	or.w    d7,d1
.zx:	move.w  (a4),d7
	lsl.w   #8,d7
	or.w    d7,d1
	move.w  d1,(a1)+
	move.b  d5,d7                   ; w2 = colour | bit 5 | flips << 8 (| 0x1000)
	ifeq \1
	move.b  $c(a3),d1
	andi.b  #$f,d1
	or.b    d1,d7
	endif
	ifne \2
	move.b  8(a3),d1                ; bit 0 -> 7
	ror.b   #1,d1
	andi.b  #$80,d1
	or.b    d1,d7
	move.b  9(a3),d1                ; bits 1-0 -> 7-6
	ror.b   #2,d1
	andi.b  #$c0,d1
	or.b    d1,d7
	endif
	lsl.w   #8,d7
	ifne \3
	ori.w   #$1000,d7
	endif
	move.w  d7,(a1)+
	move.w  2(a4),d7                ; w3 = map (| 0x2000)
	ifne \3
	ori.w   #$2000,d7
	move.w  d7,(a1)+
	cmpi.w  #$24ec,d7               ; the HUD's, the game-over texts?
	bls.s   .t
	andi.w  #$3fc0,d7
	cmpi.w  #$3fc0,d7
	bne.s   .n
	bra.s   .h
.t:	cmpi.w  #$24cf,d7
	blo.s   .n
	beq.s   .h
	cmpi.w  #$24d7,d7
	beq.s   .h
	cmpi.w  #$24dd,d7
	beq.s   .h
	cmpi.w  #$24e2,d7
	blo.s   .n
.h:	tst.b   FX_HOK
	beq.s   .n
	bsr.w   fx_hud_take
	ifne FX_HOV
	move.w  sr,-(sp)                ; (FX_HOV) fx_hud_ov's slots charged after the fact
	tst.b   FX_HOVRAN
	beq.s   .nov\@
	sf      FX_HOVRAN
	subi.w  #FXU_HOV,d6
.nov\@:	move.w  (sp)+,sr
	endif
	bne.s   .n
	subq.l  #8,a1                   ; on the fix layer: not a sprite
	else
	move.w  d7,(a1)+
	endif
.n:	andi    #$fe,ccr
	rts
	endm

	EMIT1   0,0,0
	EMIT1   0,0,1
	EMIT1   0,1,0
	EMIT1   0,1,1
	EMIT1   1,0,0
	EMIT1   1,0,1
	EMIT1   1,1,0
	EMIT1   1,1,1
	endif

; ---------------------------------------------------------------- pair bullets
; The densest scenes' bullets (object type 0x18: 35 at once in the desert boss's
; attract scene) are one table of FXB_N in ROM (FXB_T0 on, FXB_TS apart; the builder
; checks them): two pieces of one 32x16 graphic, the upper one turned (flips 3) 16 lines
; above.  Such a bullet becomes one 32x32 entry (w2 low byte 0x80: hal/spr.s
; spr_go_bul draws both halves) instead of two pieces walked one by one: ~400 cycles
; instead of ~1470.  Anything else (another table, zoom, flips or colour from the
; object, behind tilemap 1, not pass 1, one half clipped) goes the general way.
FXB_T0          equ $52e4e
FXB_TS          equ $1c
FXB_N           equ 4
FXU_BUL         equ 26              ; walk units (~400 cycles)
fxb_obj:
	move.l  $1a(a0),d0
	subi.l  #FXB_T0,d0
	cmpi.l  #(FXB_N-1)*FXB_TS,d0
	bhi.w   fx_objg
	moveq   #3,d1                   ; (one of the tables: d0 = 28 k)
	and.w   d0,d1
	bne.w   fx_objg
	lsr.w   #2,d0
	lea     fxb_ok(pc),a3
	moveq   #0,d7
	move.b  (a3,d0.w),d7            ; (its w2, w3 in fxb_k: 4 k + 1)
	beq.w   fx_objg
	cmpi.b  #1,4(a0)                ; (two pieces, the C table only)
	bne.w   fx_objg
	move.b  $43(a0),d1
	andi.b  #$c0,d1
	bne.w   fx_objg
	tst.b   $2a(a0)                 ; (flips from the pieces)
	bne.w   fx_objg
	tst.b   5(a0)                   ; (colour from the pieces)
	bmi.w   fx_objg
	move.b  $19(a0),d1              ; (in front of tilemap 1)
	bpl.s   .f
	btst    #0,d1
	beq.w   fx_objg
.f:	tst.w   FX_PASS                 ; (pass 1)
	bne.w   fx_objg
	addq.w  #1,BP_SEEN              ; (the pool's policy)
	subi.w  #FXU_BUL,d6             ; time?
	bpl.s   .t
	addi.w  #FXU_BUL,d6
	ori     #1,ccr
	rts
.t:	cmpa.l  a2,a1                   ; (the list full: as the walk finds it)
	bhs.w   .x
	move.w  $e(a0),d0               ; the walk's clip, each half: y - 16 and y in
	addi.w  #288-16,d0              ; -288..223
	cmpi.w  #512,d0
	bhs.w   .tn
	cmpi.w  #512-16,d0
	bhs.w   fx_objg                 ; (the upper only: the general way)
	move.w  $10(a0),d1              ; x - 16 in -192..319
	addi.w  #192-16,d1
	cmpi.w  #512,d1
	bhs.w   .x                      ; (neither)
	move.w  $e(a0),d4               ; w0 = y - 16 + scroll | ysize 1
	add.w   d2,d4
	subi.w  #16,d4
	andi.w  #$1ff,d4
	cmpi.w  #224,d4                 ; (on the Neo screen: hal_spr_go draws no other)
	blo.s   .vy
	cmpi.w  #512-32,d4
	bls.s   .x
.vy:	ori.w   #$200,d4
	move.w  $10(a0),d5              ; w1 = x - 16 + scroll | xsize 1
	add.w   d3,d5
	subi.w  #16,d5
	andi.w  #$1ff,d5
	cmpi.w  #320,d5
	blo.s   .vx
	cmpi.w  #512-32,d5
	bls.s   .x
.vx:	ori.w   #$200,d5
	lea     fxb_k-1(pc),a3          ; w2 = (0x30 | colour) << 8 | 0x80, w3 = map |
	move.l  (a3,d7.w),d0            ; 0x2000 (the builder's, per table)
	cmpi.b  #2,BP_ST                ; the bullet pool on, room in its records?
	bne.s   .ls
	movea.l FX_PBP,a4
	cmpa.l  FX_PBE,a4
	bhs.s   .ls
	move.w  d4,(a4)+
	move.w  d5,(a4)+
	move.l  d0,(a4)+
	move.l  a4,FX_PBP
	bra.s   .x
.ls:	move.w  d4,(a1)+                ; else in the list (hal/spr.s spr_go_bul)
	move.w  d5,(a1)+
	move.l  d0,(a1)+
.x:	andi    #$fe,ccr
	rts
.tn:	addi.w  #16,d0                  ; the upper half out: the lower one in?
	cmpi.w  #512,d0
	blo.w   fx_objg
	bra.s   .x
fxb_ok:
	dc.b    1,0,0,0,0,0,0,5,0,0,0,0,0,0,9,0,0,0,0,0,0,13
	even
	include "fxb.inc"               ; (generated by the builder: fxb_k)

; ---------------------------------------------------------------- the bullet pool
; In the densest scenes the pair bullets (fxb_obj) skip the sets altogether: BP_N
; fixed slots of two columns at the top of the Neo's sprites (BP_LO..380, above every
; set: the bullets in front of all other sprites - the original has them behind the
; players' planes and shots in front of them, slots before theirs), written by the flip
; that shows a list (bp_apply, in the real vblank: each slot's SCB3 and SCB4, its tiles
; only when they change; the slots left over hidden).  Not converted, not double
; buffered: ~60 cycles a bullet instead of ~700, and their columns out of the ring.
; The pool takes the ring's top only while it is needed (bp_poll, each new walk): with
; BP_ONMIN pair bullets in a walk it is wanted (BP_ST 1: RING_TOP = BP_LO - the ring
; stops starting sets above it, a set begun at the top gets BP_LO height 0 as the column
; above its first one, bp_stop), on (2) once no set reaches above BP_LO (its columns
; written: heads 0, the others chained to them, full size); BP_OFFN walks without one:
; to be off (3), off once nothing is shown in it, no set begun at its bottom and none
; split (its columns chained again, RING_TOP = SPR_PT + 1).  Records: per list after
; its pieces (FX_LMAX on), 8 bytes: w0 (oy | 0x200), w1 (ox | 0x200), w2, w3.
BP_N            equ 32              ; slots (64 columns)
BP_LO           equ SPR_PT+1-2*BP_N ; their lowest column (slot k: BP_LO + 2k, + 1)
BP_ONMIN        equ 6
BP_OFFN         equ 240
FX_PBN          equ FXS+$200        ; 5 w: per buffer its pool records
BP_IDLE         equ FXS+$20c        ; w: walks without a pair bullet
BP_SHOWN        equ FXS+$20e        ; w: slots shown
BP_SEEN         equ FXS+$210        ; w: pair bullets in this walk
FX_PBP          equ FXS+$212        ; l: the walk's next record
FX_PBE          equ FXS+$216        ; l: its records' end
BP_KEY          equ FXS+$21a        ; BP_N x (w3, w2): each slot's tiles in VRAM
BP_NV           equ FXS+$2a0        ; w: (BP_SIZED) the pool's slots now (BP_N without)
BP_LOV          equ FXS+$2a2        ; w: their lowest column, SPR_PT + 1 - 2 x BP_NV
BP_DMAX         equ FXS+$2a4        ; w: the most pool pieces a walk had since the last sizing
BP_DCNT         equ FXS+$2a6        ; w: walks since
BP_WANT         equ FXS+$2a8        ; w: the size wanted at the next turn-on (0: from the demand)
BP_SIZEW        equ 64              ; walks between sizings while on (BP_SIZEONCE: never)
BP_SLOT         equ FXS+$2b0        ; (BP_STABLE) 255 b: per object index its slot + 1 (0: none)
BP_OWNR         equ FXS+$3b0        ; BP_N b: per slot its object index + 1 (0: free)
BP_SEENM        equ FXS+$3d0        ; l: the slots the flip's records own (bit per slot)
BP_QMAX         equ FXS+$3d4        ; w: the most pool pieces a walk had in the shrink window
BP_QCNT         equ FXS+$3d6        ; w: the window's walks
BP_GROW         equ FXS+$3d8        ; w: a grow pending: the size wanted (0: none)
BP_OWNM         equ FXS+$3dc        ; l: the slots owned (a mask)
BP_SHRW         equ 200             ; walks of a shrink window
	ifnd BP_SIZEONCE
BP_SIZEONCE     equ 0
	endif
	if BP_KEY+4*BP_N>FXS+$2a0
	fail "bullet pool keys"
	endif
	ifeq RES
	if 8*(FX_LMAX+BP_N)>$400
	fail "bullet pool records"
	endif
	endif

; (fx_magic: the sprite RAM lost) no records; every slot's tiles to be written.
; Keeps all.
bp_reset:
	movem.l d0/a0,-(sp)
	lea     FX_PBN,a0
	clr.l   (a0)+
	clr.l   (a0)+
	clr.w   (a0)
	clr.w   BP_IDLE
	clr.w   BP_SEEN
	move.w  #BP_N,BP_SHOWN          ; (all hidden at the next flip)
	ifne BP_SIZED
	move.w  #BP_N,BP_NV
	move.w  #BP_LO,BP_LOV
	clr.w   BP_DMAX
	clr.w   BP_DCNT
	clr.w   BP_WANT
	endif
	ifne BP_STABLE
	bsr.w   bp_stclr
	endif
	lea     BP_KEY,a0
	moveq   #BP_N-1,d0
.k:	move.l  #-1,(a0)+
	dbra    d0,.k
	movem.l (sp)+,d0/a0
	rts

	ifne BP_STABLE
; (BP_STABLE) no slot owned, no object mapped, the windows fresh.  Clobbers d0, a0.
bp_stclr:
	lea     BP_SLOT,a0
	move.w  #(255+BP_N+3)/4-1,d0
.c:	clr.l   (a0)+
	dbra    d0,.c
	clr.l   BP_SEENM
	clr.l   BP_OWNM
	clr.w   BP_QMAX
	clr.w   BP_QCNT
	clr.w   BP_GROW
	rts

; (BP_STABLE) d1 = a column -> Z set when no set reaches it or above (the ring's next start
; and every set's start below it); as bp_poll's turn-on test.  Clobbers d0, d2, a0.
bp_clear:
	cmp.w   HAL_SPR_GNEXT,d1
	blo.s   .no
	moveq   #0,d0
	move.b  HAL_SPR_ORDN,d0
	bra.s   .c
.l:	lea     HAL_SPR_ORD,a0
	moveq   #0,d2
	move.b  (a0,d0.w),d2
	add.w   d2,d2
	lea     HAL_SPR_START,a0
	cmp.w   (a0,d2.w),d1
	blo.s   .no
.c:	dbra    d0,.l
	moveq   #0,d0
	rts
.no:	moveq   #1,d0
	rts

; (BP_STABLE) an object's index from its slot: (address - G_DX_OBJ1) >> 5 -> 0..254
bp_kidx:
BPK	set     0
	rept    255
	dc.b    BPK,BPK,BPK
BPK	set     BPK+1
	endr
	even
	endif

; A new walk: the last one's pair bullets decide.  Keeps all.
bp_poll:
	movem.l d0-d2/a0-a1,-(sp)
	move.w  BP_SEEN,d1
	clr.w   BP_SEEN
	ifne BP_SIZED
	cmp.w   BP_DMAX,d1              ; (BP_SIZED) the demand seen since the last sizing
	bls.s   .dm
	move.w  d1,BP_DMAX
.dm:	addq.w  #1,BP_DCNT
	endif
	moveq   #0,d0
	move.b  BP_ST,d0
	add.w   d0,d0
	move.w  .t(pc,d0.w),d0
	jmp     .t(pc,d0.w)
.t:	dc.w    .s0-.t,.s1-.t,.s2-.t,.s3-.t
.s0:	cmpi.w  #BP_ONMIN,d1            ; off: wanted?
	blo.w   .x
	move.b  #1,BP_ST
	clr.w   BP_IDLE
	ifne BP_SIZED
	move.w  BP_WANT,d0              ; the size: wanted by a resize, else the demand + 2,
	bne.s   .sz                     ; by eights, 8..BP_N
	move.w  d1,d0
	addq.w  #2,d0
.sz:	clr.w   BP_WANT
	bsr.w   bp_size
	move.w  d0,BP_NV
	add.w   d0,d0
	neg.w   d0
	addi.w  #SPR_PT+1,d0
	move.w  d0,BP_LOV
	clr.w   BP_DMAX
	clr.w   BP_DCNT
	else
	move.w  #BP_LO,d0
	endif
	bsr.w   bp_top
	bra.w   .x
.s1:	bsr.w   bp_idle                 ; wanted: still?
	bne.s   .s1a
	move.b  #3,BP_ST
	bra.w   .x
.s1a:	tst.b   HAL_SPR_SPS             ; on once no set reaches above its bottom
	bpl.w   .x
	ifne BP_SIZED
	move.w  BP_LOV,d1
	cmp.w   HAL_SPR_GNEXT,d1
	blo.w   .x
	else
	cmpi.w  #BP_LO,HAL_SPR_GNEXT
	bhi.w   .x
	endif
	moveq   #0,d0
	move.b  HAL_SPR_ORDN,d0
	bra.s   .s1c
.s1l:	lea     HAL_SPR_ORD,a0
	moveq   #0,d2
	move.b  (a0,d0.w),d2
	add.w   d2,d2
	lea     HAL_SPR_START,a0
	ifne BP_SIZED
	cmp.w   (a0,d2.w),d1
	blo.w   .x
	else
	cmpi.w  #BP_LO,(a0,d2.w)
	bhi.w   .x
	endif
.s1c:	dbra    d0,.s1l
	lea     REG_VRAMRW,a1           ; its columns: full size; SCB3 heads 0, the
	move.w  #1,REG_VRAMMOD          ; others chained to them
	ifne BP_SIZED
	move.w  BP_LOV,d0
	addi.w  #SCB2,d0
	move.w  d0,REG_VRAMADDR
	move.w  BP_NV,d0
	add.w   d0,d0
	subq.w  #1,d0
	else
	move.w  #SCB2+BP_LO,REG_VRAMADDR
	move.w  #2*BP_N-1,d0
	endif
.i2:	move.w  #$0fff,(a1)
	dbra    d0,.i2
	ifne BP_SIZED
	move.w  BP_LOV,d0
	addi.w  #SCB3,d0
	move.w  d0,REG_VRAMADDR
	move.w  BP_NV,d0
	subq.w  #1,d0
	else
	move.w  #SCB3+BP_LO,REG_VRAMADDR
	moveq   #BP_N-1,d0
	endif
.i3:	move.w  #0,(a1)
	nop
	move.w  #$40,(a1)
	dbra    d0,.i3
	clr.w   BP_SHOWN
	lea     BP_KEY,a0
	moveq   #BP_N-1,d0
.ik:	move.l  #-1,(a0)+
	dbra    d0,.ik
	ifne BP_STABLE
	bsr.w   bp_stclr
	endif
	st      BP_INIT
	move.b  #2,BP_ST
	ifne BP_SIZED
	move.w  BP_LOV,d0
	subq.w  #1,d0
	else
	move.w  #BP_LO-1,d0             ; (the ring writes below it from now on)
	endif
	bsr.w   bp_own
	bra.w   .x
.s2:
	ifne BP_STABLE
	; (BP_STABLE) grow: the demand over the size -> the size for it wanted (BP_GROW), the ring
	; told to start no set above the new bottom (bp_top), and once no set reaches it the new
	; columns chained, the slots cleared, the bottom and RING_PT moved.  Shrink: after BP_SHRW
	; walks the window's most, rounded, under the size by a step or more, the slots above it
	; free, no set split or begun at the bottom: the lowest columns chained back to the ring.
	move.w  BP_GROW,d0
	bne.s   .g2
	cmp.w   BP_NV,d1
	ifne BP_STABLE
	bls.w   .shr
	else
	bls.s   .shr
	endif
	move.w  d1,d0
	addq.w  #2,d0
	bsr.w   bp_size
	cmp.w   BP_NV,d0
	ifne BP_STABLE
	bls.w   .shr
	else
	bls.s   .shr
	endif
	move.w  d0,BP_GROW
	add.w   d0,d0
	neg.w   d0
	addi.w  #SPR_PT+1,d0
	bsr.w   bp_top
.g2:	move.w  BP_GROW,d0
	add.w   d0,d0
	neg.w   d0
	addi.w  #SPR_PT+1,d0            ; the new bottom
	move.w  d0,d1
	bsr.w   bp_clear
	bne.w   .x
	lea     REG_VRAMRW,a1           ; the new columns: full size, heads 0 / chained
	move.w  #1,REG_VRAMMOD
	move.w  d1,d0
	addi.w  #SCB2,d0
	move.w  d0,REG_VRAMADDR
	move.w  BP_LOV,d0
	sub.w   d1,d0
	subq.w  #1,d0
.gi2:	move.w  #$0fff,(a1)
	dbra    d0,.gi2
	move.w  d1,d0
	addi.w  #SCB3,d0
	move.w  d0,REG_VRAMADDR
	move.w  BP_LOV,d0
	sub.w   d1,d0
	lsr.w   #1,d0
	subq.w  #1,d0
.gi3:	move.w  #0,(a1)
	nop
	move.w  #$40,(a1)
	dbra    d0,.gi3
	move.w  BP_NV,d0                ; the new slots: no owner, no key
	lea     BP_OWNR,a0
.go:	cmp.w   BP_GROW,d0
	bhs.s   .gd
	clr.b   (a0,d0.w)
	move.w  d0,d2
	lsl.w   #2,d2
	lea     BP_KEY,a1
	move.l  #-1,(a1,d2.w)
	addq.w  #1,d0
	bra.s   .go
.gd:	move.w  BP_GROW,BP_NV
	move.w  d1,BP_LOV
	clr.w   BP_GROW
	clr.w   BP_QMAX
	clr.w   BP_QCNT
	move.w  d1,d0
	subq.w  #1,d0
	bsr.w   bp_own
	bra.w   .x
.shr:	cmp.w   BP_QMAX,d1
	bls.s   .sq
	move.w  d1,BP_QMAX
.sq:	addq.w  #1,BP_QCNT
	cmpi.w  #BP_SHRW,BP_QCNT
	ifne BP_STABLE
	blo.w   .s2i
	else
	blo.s   .s2i
	endif
	move.w  BP_QMAX,d0
	addq.w  #2,d0
	bsr.w   bp_size
	clr.w   BP_QMAX
	clr.w   BP_QCNT
	cmp.w   BP_NV,d0
	ifne BP_STABLE
	bhs.w   .s2i
	else
	bhs.s   .s2i
	endif
	lea     BP_OWNR,a0              ; the slots to release free?
	move.w  d0,d2
.sc:	cmp.w   BP_NV,d2
	bhs.s   .sf
	tst.b   (a0,d2.w)
	bne.s   .sr
	addq.w  #1,d2
	bra.s   .sc
.sr:	move.w  #BP_SHRW-16,BP_QCNT     ; (not yet: again soon)
	ifne BP_STABLE
	bra.w   .s2i
	else
	bra.s   .s2i
	endif
.sf:	tst.b   HAL_SPR_SPS             ; no set split, none begun at the bottom
	bpl.s   .sr
	move.w  BP_LOV,d1
	move.w  d0,-(sp)
	moveq   #0,d0
	move.b  HAL_SPR_ORDN,d0
	bra.s   .sb
.sl:	lea     HAL_SPR_ORD,a0
	moveq   #0,d2
	move.b  (a0,d0.w),d2
	add.w   d2,d2
	lea     HAL_SPR_START,a0
	cmp.w   (a0,d2.w),d1
	beq.s   .sn
.sb:	dbra    d0,.sl
	move.w  (sp)+,d0
	lea     REG_VRAMRW,a1           ; the lowest columns chained back to the ring
	move.w  #1,REG_VRAMMOD
	move.w  d1,d2
	addi.w  #SCB3,d2
	move.w  d2,REG_VRAMADDR
	move.w  BP_NV,d2
	sub.w   d0,d2
	add.w   d2,d2
	subq.w  #1,d2
.so3:	move.w  #$40,(a1)
	dbra    d2,.so3
	move.w  d0,BP_NV
	add.w   d0,d0
	neg.w   d0
	addi.w  #SPR_PT+1,d0
	move.w  d0,BP_LOV
	subq.w  #1,d0
	bsr.w   bp_own
	bra.s   .s2i
.sn:	move.w  (sp)+,d0
	ifne BP_STABLE
	bra.w   .sr
	else
	bra.s   .sr
	endif
	endif
	ifne BP_SIZED&(BP_SIZEONCE=0)&(BP_STABLE=0)
	cmpi.w  #BP_SIZEW,BP_DCNT       ; on: every BP_SIZEW walks the size against the demand
	blo.s   .s2i                    ; seen - unlike: off, then on at the new size
	move.w  BP_DMAX,d0
	addq.w  #2,d0
	bsr.w   bp_size
	clr.w   BP_DMAX
	clr.w   BP_DCNT
	cmp.w   BP_NV,d0
	beq.s   .s2i
	move.w  d0,BP_WANT
	move.b  #3,BP_ST
	bra.w   .x
	endif
.s2i:	bsr.w   bp_idle                 ; on: still wanted?
	bne.w   .x
	move.b  #3,BP_ST
	bra.w   .x
.s3:
	ifne BP_SIZED
	tst.w   BP_WANT                 ; (a resize: all the way off first)
	bne.s   .s3o
	endif
	cmpi.w  #BP_ONMIN,d1            ; to be off: wanted again?
	blo.s   .s3o
	clr.w   BP_IDLE
	move.b  #1,BP_ST
	tst.b   BP_INIT
	beq.w   .x
	move.b  #2,BP_ST
	bra.w   .x
.s3o:	tst.w   BP_SHOWN                ; off once nothing is shown in it, no set split,
	bne.w   .x                      ; none begun at its bottom (its columns may be
	tst.b   HAL_SPR_SPS             ; chained again)
	bpl.w   .x
	ifne BP_SIZED
	move.w  BP_LOV,d1
	endif
	moveq   #0,d0
	move.b  HAL_SPR_ORDN,d0
	bra.s   .s3c
.s3l:	lea     HAL_SPR_ORD,a0
	moveq   #0,d2
	move.b  (a0,d0.w),d2
	add.w   d2,d2
	lea     HAL_SPR_START,a0
	ifne BP_SIZED
	cmp.w   (a0,d2.w),d1
	beq.w   .x
	else
	cmpi.w  #BP_LO,(a0,d2.w)
	beq.w   .x
	endif
.s3c:	dbra    d0,.s3l
	lea     REG_VRAMRW,a1
	move.w  #1,REG_VRAMMOD
	ifne BP_SIZED
	move.w  BP_LOV,d0
	addi.w  #SCB3,d0
	move.w  d0,REG_VRAMADDR
	move.w  BP_NV,d0
	add.w   d0,d0
	subq.w  #1,d0
	else
	move.w  #SCB3+BP_LO,REG_VRAMADDR
	move.w  #2*BP_N-1,d0
	endif
.o3:	move.w  #$40,(a1)
	dbra    d0,.o3
	sf      BP_INIT
	sf      BP_ST
	move.w  #SPR_PT+1,d0
	bsr.s   bp_top
	move.w  #SPR_PT,d0
	bsr.s   bp_own
.x:	movem.l (sp)+,d0-d2/a0-a1
	rts
	ifne BP_SIZED
; (BP_SIZED) d0 = pieces wanted -> d0 = the pool's size for them: by eights, 8..BP_N.
bp_size:
	addq.w  #7,d0
	andi.w  #$fff8,d0
	cmpi.w  #BP_N,d0
	bls.s   .c
	move.w  #BP_N,d0
.c:	cmpi.w  #8,d0
	bhs.s   .x
	moveq   #8,d0
.x:	rts
	endif

; d1 = this walk's pair bullets: BP_IDLE on; Z set: BP_OFFN walks without.
bp_idle:
	tst.w   d1
	beq.s   .n
	clr.w   BP_IDLE
	moveq   #1,d0                   ; (Z clear)
	rts
.n:	addq.w  #1,BP_IDLE
	moveq   #1,d0
	cmpi.w  #BP_OFFN,BP_IDLE
	blo.s   .x
	moveq   #0,d0                   ; (Z set)
.x:	rts
; RING_TOP = d0, where the ring's sets may start (and RING_TPM).  Keeps all.
bp_top:
	move.w  d0,RING_TOP
	subq.w  #1,d0
	move.w  d0,RING_TPM
	addq.w  #1,d0
	rts
; RING_PT = d0, the ring's highest column it owns, writes in (and RING_S3T): moved only
; when the pool's columns become its own or the ring's again (a set begun at the old top
; may still be in the ring while the pool is wanted: its tail and chains are the ring's
; to write - left alone, it hung on a shown set, 2026-10-15).  Keeps all.
bp_own:
	move.w  d0,RING_PT
	addi.w  #SCB3,d0
	move.w  d0,RING_S3T
	subi.w  #SCB3,d0
	rts

; (hal/spr.s hal_spr_begin, .rst) a set begins at d0 (the column above its first
; one): at the top while the pool is wanted but its columns are not its own yet - the
; column above, BP_LO, height 0 (chained with the free ones, it would carry them on the
; set's top).  Keeps all.
bp_stop:
	tst.b   BP_INIT
	bne.s   .x
	cmp.w   RING_TOP,d0
	bne.s   .x
	cmpi.w  #SPR_PT,d0
	bhi.s   .x
	move.w  d0,-(sp)
	addi.w  #SCB3,d0
	move.w  d0,REG_VRAMADDR
	move.w  #0,REG_VRAMRW
	move.w  (sp)+,d0
.x:	rts

; d0 = a list's buffer: its pool records' writing time, cycles (long; 0: pool off).
; Keeps all but d0.
bp_cost:
	tst.b   BP_INIT
	beq.s   .z
	move.l  a0,-(sp)
	andi.w  #7,d0
	add.w   d0,d0
	ifne FUSED
	lea     FZ_PBN,a0               ; (hal/fz.s: d0 the set)
	else
	lea     FX_PBN,a0
	endif
	move.w  (a0,d0.w),d0
	ifne BP_STABLE
	mulu    #350,d0                 ; (~250 a record placed, ~600 with its tiles, which
	addi.l  #800,d0                 ; change in ~8% of the frames: AUDIT 44)
	else
	mulu    #300,d0                 ; (~300 a bullet whose tiles change)
	addi.l  #400,d0
	endif
	move.l  (sp)+,a0
	rts
.z:	moveq   #0,d0
	rts

; In the real vblank, the flip that shows list d0 (a buffer): its pair bullets in the
; pool's slots.  Keeps all.
bp_apply:
	tst.b   BP_INIT
	beq.w   .xx
	movem.l d0-d7/a0-a5,-(sp)
	andi.w  #7,d0
	move.w  d0,d1
	add.w   d1,d1
	ifne FUSED
	lea     FZ_PBN,a0               ; (hal/fz.s: d0 the set, its records at FZ_POOL)
	else
	lea     FX_PBN,a0
	endif
	move.w  (a0,d1.w),d6            ; its records
	ifne BP_SIZED
	cmp.w   BP_NV,d6
	else
	cmpi.w  #BP_N,d6
	endif
	bls.s   .n
	moveq   #0,d6                   ; (the boot RAM test: none)
.n:
	ifne FUSED
	lsl.w   #7,d1
	lea     FZ_POOL,a0
	adda.w  d1,a0
	else
	add.w   d1,d1
	lea     fx_ltab(pc),a0
	movea.l (a0,d1.w),a0
	lea     8*FX_LMAX(a0),a0        ; a0 = the records
	endif
	lea     REG_VRAMADDR,a1
	lea     REG_VRAMRW,a2
	lea     BP_KEY,a3
	lea     G_SPRLUT,a5
	move.w  #1,REG_VRAMMOD
	ifne BP_STABLE
	bra.w   bp_apply_st
	endif
	ifne BP_SIZED
	move.w  BP_LOV,d7               ; this slot's head column
	else
	move.w  #BP_LO,d7               ; this slot's head column
	endif
	move.w  d6,d5                   ; (slots shown now)
	bra.w   .c
.l:	move.w  (a0)+,d1                ; SCB3 = (496 - oy) << 7 | 2
	ifne BP_SHOTS
	movea.w d1,a4                   ; (BP_SHOTS: w0 kept - the generic kind's rows)
	endif
	neg.w   d1
	lsl.w   #7,d1
	ifne BP_SHOTS
	btst    #6,3(a0)                ; (BP_SHOTS) the generic kind: its own height (w2 low byte)
	beq.s   .h2
	move.w  a4,d2
	lsr.w   #8,d2
	lsr.w   #1,d2
	andi.w  #7,d2
	addq.w  #1,d2
	add.w   d2,d1
	addi.w  #(496<<7),d1
	bra.s   .h3
.h2:
	endif
	addi.w  #(496<<7)+2,d1
.h3:	move.w  d7,d2
	addi.w  #SCB3,d2
	move.w  d2,(a1)
	move.w  d1,(a2)
	move.w  (a0)+,d1                ; SCB4 = ox << 7
	ifne BP_SHOTS
	move.w  d1,d0                   ; (w1's bits 9-11: the generic kind's columns)
	endif
	lsl.w   #7,d1
	addi.w  #SCB4-SCB3,d2
	move.w  d2,(a1)
	move.w  d1,(a2)
	move.w  (a0)+,d3                ; w2
	move.w  (a0)+,d4                ; w3
	cmp.w   (a3)+,d4                ; its tiles there already?
	bne.s   .tw
	cmp.w   (a3)+,d3
	beq.s   .tn
	subq.l  #2,a3
.tw:	subq.l  #2,a3
	move.w  d4,(a3)+
	move.w  d3,(a3)+
	ifne BP_SHOTS
	btst    #6,d3                   ; (BP_SHOTS) the generic kind
	bne.w   .gk
	endif
	move.w  d3,d1                   ; attributes: the lower row, the upper (flips 3)
	andi.w  #$1f00,d1
	addi.w  #NPAL_SPR<<8,d1
	move.w  d1,d2
	addq.w  #3,d2
	andi.w  #$3fff,d4               ; tiles 0 and 1 of the lookup run
	add.w   d4,d4
	move.w  (a5,d4.w),d3
	andi.w  #$7fff,d3
	move.w  2(a5,d4.w),d4
	andi.w  #$7fff,d4
	move.w  d7,d0                   ; column 0: tile 1 turned, tile 0
	lsl.w   #6,d0
	move.w  d0,(a1)
	move.w  d4,(a2)
	nop
	move.w  d2,(a2)
	nop
	move.w  d3,(a2)
	nop
	move.w  d1,(a2)
	addi.w  #64,d0                  ; column 1: tile 0 turned, tile 1
	move.w  d0,(a1)
	move.w  d3,(a2)
	nop
	move.w  d2,(a2)
	nop
	move.w  d4,(a2)
	nop
	move.w  d1,(a2)
.tn:	addq.w  #2,d7
.c:	dbra    d6,.l
	ifne BP_SHOTS
	bra.w   .hid
	; (BP_SHOTS) a generic piece: rows = w0 bits 9-11 + 1 (a4), columns = w1's (d0) + 1;
	; the tiles of the lookup run map + row * columns + column, the flips of w2 (bit 15
	; y, 14 x: the rows / columns reversed, the attribute's bits 1 / 0), the slot's
	; second column blank when the piece is one column wide.  ~200 cycles.
.gk:	movem.l d5-d7,-(sp)
	move.w  d3,d1                   ; attributes: palette | flips
	andi.w  #$1f00,d1
	addi.w  #NPAL_SPR<<8,d1
	move.w  d3,d2
	rol.w   #2,d2
	andi.w  #3,d2                   ; bit 0 = w2 bit 14 (x), bit 1 = w2 bit 15 (y)
	or.w    d2,d1
	move.w  a4,d5
	lsr.w   #8,d5
	lsr.w   #1,d5
	andi.w  #7,d5                   ; rows - 1
	lsr.w   #8,d0
	lsr.w   #1,d0
	andi.w  #7,d0                   ; columns - 1
	andi.w  #$3fff,d4
	add.w   d4,d4
	lea     (a5,d4.w),a4            ; the lookup run
	move.w  d7,d6
	lsl.w   #6,d6                   ; SCB1 of column 0
	moveq   #0,d7                   ; the column
.gc:	move.w  d6,(a1)
	moveq   #0,d4                   ; the row
.gr:	cmp.w   d0,d7
	bhi.s   .gb
	move.w  d4,d2                   ; the source row (reversed with flip y)
	btst    #1,d1
	beq.s   .gy
	move.w  d5,d2
	sub.w   d4,d2
.gy:	move.w  d2,d3
	mulu    d0,d2
	add.w   d3,d2                   ; row * columns
	move.w  d7,d3                   ; the source column (reversed with flip x)
	btst    #0,d1
	beq.s   .gx
	move.w  d0,d3
	sub.w   d7,d3
.gx:	add.w   d3,d2
	add.w   d2,d2
	move.w  (a4,d2.w),d2
	andi.w  #$7fff,d2
	move.w  d2,(a2)
	nop
	move.w  d1,(a2)
	bra.s   .gn
.gb:	move.w  #BLANK_TILE,(a2)        ; (the second column of a one-column piece)
	nop
	move.w  #0,(a2)
.gn:	addq.w  #1,d4
	cmp.w   d5,d4
	bls.s   .gr
	addi.w  #64,d6
	addq.w  #1,d7
	cmpi.w  #1,d7
	bls.s   .gc
	movem.l (sp)+,d5-d7
	bra.w   .tn
.hid:
	endif
	move.w  BP_SHOWN,d6             ; the slots no longer used: hidden
	ifne BP_SIZED
	cmp.w   BP_NV,d6
	bls.s   .hb
	move.w  BP_NV,d6
	else
	cmpi.w  #BP_N,d6
	bls.s   .hb
	moveq   #BP_N,d6
	endif
.hb:	sub.w   d5,d6
	ble.s   .h
	subq.w  #1,d6
.hh:	move.w  d7,d2
	addi.w  #SCB3,d2
	move.w  d2,(a1)
	move.w  #0,(a2)
	addq.w  #2,d7
	dbra    d6,.hh
.h:	move.w  d5,BP_SHOWN
	movem.l (sp)+,d0-d7/a0-a5
.xx:	rts

	ifne BP_STABLE
; (BP_STABLE) bp_apply's records (a0, d6 of them; a1/a2 the VRAM ports, a3 BP_KEY, a5 the
; lookup RAM) placed by object: w0's high nibble | w1's high nibble = the object's index
; (fz_bul, fz_pshot).  1: the records with a slot mark it seen; 2: owned slots not seen are
; freed and hidden (SCB3 0); 3: the records without a slot take the lowest free one (its key
; cleared); 4: each record's slot gets its SCB3/SCB4 and, when its key changed, its tiles
; (the pair kind as bp_apply, the generic kind's columns and rows).  Slot s = columns
; SPR_PT - 1 - 2s (the head) and SPR_PT - 2s.
bp_apply_st:
	move.l  a6,-(sp)                ; (the flip's set state)
	moveq   #0,d5                   ; the slots seen (a mask)
	clr.w   BP_SHOWN
	movea.l a0,a4
	lea     BP_SLOT,a6
	lea     BP_OWNR,a0
	subq.w  #1,d6
	bmi.w   .p5
	; one pass over the records: the slot the object has, else the lowest free one (an
	; owned slot not in this list is freed only below: the demand's slack covers it);
	; its SCB3/SCB4, its tiles when the key changed; the slot marked seen
.p4l:	move.w  2(a4),d1                ; the object's index: SCB4's low 7 bits, w2's bit 7
	andi.w  #$7f,d1
	btst    #7,5(a4)
	beq.s   .i0
	addi.w  #$80,d1
.i0:	moveq   #0,d7
	move.b  (a6,d1.w),d7            ; its slot + 1
	bne.s   .have
	move.l  BP_OWNM,d2              ; the lowest free slot
	moveq   #1,d3
	move.w  BP_NV,d0
	lsl.l   d0,d3
	subq.l  #1,d3                   ; (the slots there)
	not.l   d2
	and.l   d3,d2
	beq.w   .p4n                    ; (none free: the record is not shown)
.af:	btst    d7,d2
	bne.s   .at
	addq.w  #1,d7
	bra.s   .af
.at:	move.l  BP_OWNM,d3
	bset    d7,d3
	move.l  d3,BP_OWNM
	move.w  d1,d3
	addq.w  #1,d3
	move.b  d3,(a0,d7.w)            ; the slot's owner
	move.w  d7,d2
	lsl.w   #2,d2
	move.l  #-1,(a3,d2.w)           ; its key: none
	addq.w  #1,d7
	move.b  d7,(a6,d1.w)            ; the object's slot
.have:	subq.w  #1,d7                   ; the slot
	bset    d7,d5
	addq.w  #1,BP_SHOWN
	move.w  d7,d0
	add.w   d0,d0
	neg.w   d0
	addi.w  #SCB3+SPR_PT-1,d0       ; its head's SCB3, SCB4 (the record's w0, w1)
	move.w  d0,(a1)
	move.w  (a4),(a2)
	addi.w  #SCB4-SCB3,d0
	move.w  d0,(a1)
	move.w  2(a4),d1
	andi.w  #$ff80,d1
	move.w  d1,(a2)
	move.l  4(a4),d3                ; w2:w3, the key
	move.w  d7,d2
	lsl.w   #2,d2
	cmp.l   (a3,d2.w),d3            ; its tiles there already?
	beq.w   .p4n
	move.l  d3,(a3,d2.w)
	move.w  d3,d4                   ; w3
	swap    d3                      ; w2
	move.w  d7,d0
	add.w   d0,d0
	neg.w   d0
	addi.w  #SPR_PT-1,d0
	lsl.w   #6,d0                   ; the head column's SCB1
	btst    #6,d3
	bne.s   .gk
	move.w  d3,d1                   ; the pair kind: as bp_apply (w2's high byte the
	andi.w  #$ff00,d1               ; attribute)
	move.w  d1,d2
	addq.w  #3,d2
	andi.w  #$3fff,d4
	add.w   d4,d4
	move.w  (a5,d4.w),d3
	andi.w  #$7fff,d3
	move.w  2(a5,d4.w),d4
	andi.w  #$7fff,d4
	move.w  d0,(a1)
	move.w  d4,(a2)
	nop
	move.w  d2,(a2)
	nop
	move.w  d3,(a2)
	nop
	move.w  d1,(a2)
	addi.w  #64,d0
	move.w  d0,(a1)
	move.w  d3,(a2)
	nop
	move.w  d2,(a2)
	nop
	move.w  d4,(a2)
	nop
	move.w  d1,(a2)
	bra.w   .p4n
	; the generic kind (at most 2 x 2 tiles, row-major in the lookup run; w2 the attribute
	; with bit 2 = columns - 1, bit 6 the kind, bit 7 the index's; w0's low bits the rows):
	; column 0's rows, then column 1's (blank when the record has one)
.gk:	move.w  d6,-(sp)
	move.w  d3,d1                   ; the attribute: the palette, the flips (bits 1, 0)
	andi.w  #$ff03,d1
	andi.w  #$3fff,d4
	add.w   d4,d4
	lea     (a5,d4.w),a6            ; the lookup run
	moveq   #0,d4
	btst    #2,d3
	beq.s   .ck
	moveq   #1,d4                   ; columns - 1 (the run's width - 1: index = row << it)
.ck:	move.w  (a4),d3
	andi.w  #$3f,d3
	subq.w  #1,d3                   ; rows - 1
	moveq   #0,d7                   ; column 0's source column: the last when flipped
	btst    #0,d1
	beq.s   .fx
	move.w  d4,d7
.fx:	moveq   #0,d2                   ; row 0's source row: the last when flipped
	btst    #1,d1
	beq.s   .fy
	move.w  d3,d2
.fy:	move.w  d0,(a1)                 ; column 0
	move.w  d2,d6
	lsl.w   d4,d6
	add.w   d7,d6
	add.w   d6,d6
	move.w  (a6,d6.w),d6
	andi.w  #$7fff,d6
	move.w  d6,(a2)
	nop
	move.w  d1,(a2)
	tst.w   d3
	beq.s   .c1
	move.w  d3,d6                   ; row 1's source row: the other
	sub.w   d2,d6
	lsl.w   d4,d6
	add.w   d7,d6
	add.w   d6,d6
	move.w  (a6,d6.w),d6
	andi.w  #$7fff,d6
	nop
	move.w  d6,(a2)
	nop
	move.w  d1,(a2)
.c1:	addi.w  #64,d0                  ; column 1
	move.w  d0,(a1)
	tst.w   d4
	beq.s   .blank
	sub.w   d7,d4                   ; its source column: the other
	move.w  d4,d7
	move.w  d2,d6
	add.w   d6,d6                   ; (the width 2)
	add.w   d7,d6
	add.w   d6,d6
	move.w  (a6,d6.w),d6
	andi.w  #$7fff,d6
	move.w  d6,(a2)
	nop
	move.w  d1,(a2)
	tst.w   d3
	beq.s   .gx
	move.w  d3,d6
	sub.w   d2,d6
	add.w   d6,d6
	add.w   d7,d6
	add.w   d6,d6
	move.w  (a6,d6.w),d6
	andi.w  #$7fff,d6
	nop
	move.w  d6,(a2)
	nop
	move.w  d1,(a2)
	bra.s   .gx
.blank:	move.w  #BLANK_TILE,(a2)
	nop
	move.w  #0,(a2)
	tst.w   d3
	beq.s   .gx
	nop
	move.w  #BLANK_TILE,(a2)
	nop
	move.w  #0,(a2)
.gx:	move.w  (sp)+,d6
	lea     BP_SLOT,a6
.p4n:	addq.l  #8,a4
	dbra    d6,.p4l
	; the owned slots not seen: freed, hidden
.p5:	move.l  BP_OWNM,d3
	move.l  d3,d4
	eor.l   d5,d4                   ; (the seen are owned)
	beq.s   .p5d
	moveq   #0,d2
.p5l:	btst    d2,d4
	beq.s   .p5n
	bclr    d2,d3
	moveq   #0,d1
	move.b  (a0,d2.w),d1
	clr.b   (a0,d2.w)
	subq.w  #1,d1
	clr.b   (a6,d1.w)
	move.w  d2,d1
	add.w   d1,d1
	neg.w   d1
	addi.w  #SCB3+SPR_PT-1,d1
	move.w  d1,(a1)
	move.w  #0,(a2)
	move.w  d2,d1
	lsl.w   #2,d1
	move.l  #-1,(a3,d1.w)
	bclr    d2,d4
	tst.l   d4
	beq.s   .p5d
.p5n:	addq.w  #1,d2
	bra.s   .p5l
.p5d:	move.l  d3,BP_OWNM
	movea.l (sp)+,a6
	movem.l (sp)+,d0-d7/a0-a5
	rts

; a4 = a pool record -> d1 = its object's index (w0's high nibble | w1's).  Keeps the rest.
bp_kof:
	move.w  (a4),d1
	lsr.w   #8,d1
	andi.w  #$f0,d1
	move.b  3(a4),d2
	lsr.b   #4,d2
	or.b    d2,d1
	rts
	endif

fx_emt:
	dc.l    fx_em_0000,fx_em_0001,fx_em_0010,fx_em_0011
	dc.l    fx_em_0100,fx_em_0101,fx_em_0110,fx_em_0111
	dc.l    fx_em_1000,fx_em_1001,fx_em_1010,fx_em_1011
	dc.l    fx_em_1100,fx_em_1101,fx_em_1110,fx_em_1111

; d4 + 1 pieces of table a3 (14 bytes each: piece l, dy, dx, flipx, flipy, zoomy,
; zoomx, colour) for object a0: each on screen (y + dy in 0xfee0.. or ..0xdf, x + dx
; in 0xff40.. or ..0x13f) -> its four words at a1 (none once a1 = a2: the list full).
; \1 zoom from the object (a5), \2 colour from the object (in d5), \3 flips from the
; piece, \4 pass 1 (w2 | 0x1000, w3 | 0x2000; the HUD's strips: fx_hud_take).
; Clobbers d0, d1, d4 (low), d7, a3, a4.
EMIT	macro
fx_em_\1\2\3\4:
.p:	move.w  $e(a0),d0               ; y
	add.w   4(a3),d0
	cmpi.w  #$fee0,d0
	bhs.s   .yv
	cmpi.w  #$e0,d0
	bhs.w   .n
.yv:	move.w  $10(a0),d1              ; x
	add.w   6(a3),d1
	cmpi.w  #$ff40,d1
	bhs.s   .xv
	cmpi.w  #$140,d1
	bhs.w   .n
.xv:	cmpa.l  a2,a1
	bhs.w   .f                      ; (the list full)
	movea.l (a3),a4
	btst    #0,3(a3)                ; (odd: the game is rewriting the object - the walk
	bne.w   .n                      ; interrupts it - skipped: else an address error,
					; the game's handler resets it, 2026-10-14)
	add.w   d2,d0                   ; w0 = y + scroll | zoomy << 12 | (a4)+0 << 8
	andi.w  #$1ff,d0
	cmpi.w  #224,d0                 ; on the Neo screen (hal_spr_go draws no other):
	blo.s   .vy                     ; oy < 224 or oy + 16 rows > 512
	moveq   #$e,d7
	and.b   (a4),d7
	lsl.w   #3,d7
	add.w   d0,d7
	cmpi.w  #512-16,d7
	bls.w   .n
.vy:
	ifne \1
	move.w  a5,d7
	or.w    d7,d0
	else
	move.b  $a(a3),d7               ; (0: most pieces)
	beq.s   .zy
	ror.w   #4,d7
	andi.w  #$f000,d7
	or.w    d7,d0
.zy:
	endif
	move.w  (a4),d7
	andi.w  #$ff00,d7
	or.w    d7,d0
	move.w  d0,(a1)+
	add.w   d3,d1                   ; w1 = x + scroll | zoomx << 12 | (a4)+1 << 8
	andi.w  #$1ff,d1
	cmpi.w  #320,d1                 ; (the same in x)
	blo.s   .vx
	moveq   #$e,d7
	and.b   1(a4),d7
	lsl.w   #3,d7
	add.w   d1,d7
	cmpi.w  #512-16,d7
	bhi.s   .vx
	subq.l  #2,a1                   ; (w0 taken back)
	bra.w   .n
.vx:
	ifne \1
	move.w  a5,d7
	or.w    d7,d1
	else
	move.b  $b(a3),d7
	beq.s   .zx
	ror.w   #4,d7
	andi.w  #$f000,d7
	or.w    d7,d1
.zx:
	endif
	move.w  (a4),d7
	lsl.w   #8,d7
	or.w    d7,d1
	move.w  d1,(a1)+
	move.b  d5,d7                   ; w2 = colour | bit 5 | flips << 8 (| 0x1000)
	ifeq \2
	move.b  $c(a3),d1
	andi.b  #$f,d1
	or.b    d1,d7
	endif
	ifne \3
	move.b  8(a3),d1                ; bit 0 -> 7
	ror.b   #1,d1
	andi.b  #$80,d1
	or.b    d1,d7
	move.b  9(a3),d1                ; bits 1-0 -> 7-6
	ror.b   #2,d1
	andi.b  #$c0,d1
	or.b    d1,d7
	endif
	lsl.w   #8,d7
	ifne \4
	ori.w   #$1000,d7
	endif
	move.w  d7,(a1)+
	move.w  2(a4),d7                ; w3 = map (| 0x2000)
	ifne \4
	ori.w   #$2000,d7
	move.w  d7,(a1)+
	cmpi.w  #$24ec,d7               ; the HUD's, the game-over texts?
	bls.s   .t
	andi.w  #$3fc0,d7
	cmpi.w  #$3fc0,d7
	bne.s   .n
	bra.s   .h
.t:	cmpi.w  #$24cf,d7
	blo.s   .n
	beq.s   .h
	cmpi.w  #$24d7,d7
	beq.s   .h
	cmpi.w  #$24dd,d7
	beq.s   .h
	cmpi.w  #$24e2,d7               ; (the digits, "INSERT COINS!")
	blo.s   .n
.h:	tst.b   FX_HOK
	beq.s   .n
	bsr.w   fx_hud_take
	ifne FX_HOV
	move.w  sr,-(sp)                ; (FX_HOV) fx_hud_ov's slots charged after the fact
	tst.b   FX_HOVRAN
	beq.s   .nov\@
	sf      FX_HOVRAN
	subi.w  #FXU_HOV,d6
.nov\@:	move.w  (sp)+,sr
	endif
	bne.s   .n
	subq.l  #8,a1                   ; on the fix layer: not a sprite
	else
	move.w  d7,(a1)+
	endif
.n:	lea     14(a3),a3
	dbra    d4,.p
.f:	rts
	endm

	EMIT    0,0,0,0
	EMIT    0,0,0,1
	EMIT    0,0,1,0
	EMIT    0,0,1,1
	EMIT    0,1,0,0
	EMIT    0,1,0,1
	EMIT    0,1,1,0
	EMIT    0,1,1,1
	EMIT    1,0,0,0
	EMIT    1,0,0,1
	EMIT    1,0,1,0
	EMIT    1,0,1,1
	EMIT    1,1,0,0
	EMIT    1,1,0,1
	EMIT    1,1,1,0
	EMIT    1,1,1,1

; ---------------------------------------------------------------- the HUD
; The piece just written (-8(a1)) is the HUD's (lookup 0x3fc0-0x3fff): its slot (map
; bits 3-5, one strip a slot a walk) keeps its words (FX_HRAW) if the fix layer can show
; it (unzoomed, one column, unflipped, colour 0x10/0x11/0x14/0x15, 8-pixel aligned, on
; screen, its lookup run not wrapping).  Z set: taken.  Clobbers d0, d1, d7, a4.
fx_hud_take:
	bsr.w   fx_hud_slot
	ifne FX_HOV
	move.w  FX_HYIELD,d0            ; yielding to a strip above it: a sprite, while the
	btst    d1,d0                   ; yield is fresh
	beq.s   .ny
	move.w  d1,d0
	add.w   d0,d0
	lea     FX_HYSEQ,a4
	move.w  FX_WSEQ,d7
	sub.w   (a4,d0.w),d7
	cmpi.w  #FX_HYAGE,d7
	bls.w   .no
	move.w  FX_HYIELD,d0            ; expired
	bclr    d1,d0
	move.w  d0,FX_HYIELD
.ny:	move.w  FX_HSUS,d0              ; under a strip taken earlier this walk: yields
	btst    d1,d0
	beq.s   .ns
	move.w  FX_HYIELD,d0
	bset    d1,d0
	move.w  d0,FX_HYIELD
	move.w  d1,d0
	add.w   d0,d0
	lea     FX_HYSEQ,a4
	move.w  FX_WSEQ,(a4,d0.w)
	bra.w   .no
.ns:
	endif
	move.w  FX_HSEEN,d0
	btst    d1,d0
	bne.w   .no                     ; (one a walk)
	move.w  d1,d0                   ; shown, with the same words and entries?
	lsl.w   #5,d0                   ; (x 96: FXH_SIZE)
	move.w  d0,d7
	add.w   d0,d0
	add.w   d7,d0
	lea     FX_HSHD,a4
	adda.w  d0,a4
	tst.w   FXH_COL+4(a4)
	beq.s   .full
	move.l  -8(a1),d7
	cmp.l   FXH_RAW(a4),d7
	bne.s   .full
	move.l  -4(a1),d7
	cmp.l   FXH_RAW+4(a4),d7
	bne.s   .full
	move.l  a3,-(sp)
	lea     G_SPRLUT,a3
	move.w  -2(a1),d0
	andi.w  #$3fff,d0
	add.w   d0,d0
	adda.w  d0,a3
	lea     FXH_LUT(a4),a4
	move.w  -8(a1),d0               ; ysize: entries - 1
	rol.w   #7,d0
	andi.w  #7,d0
.lc:	cmpm.w  (a3)+,(a4)+
	dbne    d0,.lc
	movea.l (sp)+,a3
	bne.s   .full
	move.w  FX_HSEEN,d0             ; unchanged: taken, nothing to draw
	bset    d1,d0
	move.w  d0,FX_HSEEN
	move.w  FX_HSAME,d0
	bset    d1,d0
	move.w  d0,FX_HSAME
	move.w  #4,ccr
	rts
.full:	movem.w -8(a1),d0-d1            ; w0, w1
	move.w  d0,d7
	andi.w  #$f007,d7               ; zoomy, y 8-aligned
	ifne FX_HOV
	bne.w   .no
	else
	bne.s   .no
	endif
	move.w  d1,d7
	andi.w  #$fe07,d7               ; zoomx, xsize, x 8-aligned
	bne.s   .no
	andi.w  #$1ff,d1
	cmpi.w  #320-16,d1
	bhi.s   .no
	move.w  d0,d1                   ; y + 16 rows <= 224
	rol.w   #7,d1
	andi.w  #7,d1
	addq.w  #1,d1
	lsl.w   #4,d1
	andi.w  #$1ff,d0
	add.w   d0,d1
	cmpi.w  #224,d1
	bhi.s   .no
	move.w  -4(a1),d7               ; w2: flips, colour 0x10 + 0, 1, 4, 5
	andi.w  #$da00,d7
	cmpi.w  #$1000,d7
	bne.s   .no
	move.w  -8(a1),d1               ; the run: map + ysize <= 0x3fff
	rol.w   #7,d1
	andi.w  #7,d1
	move.w  -2(a1),d7
	andi.w  #$3fff,d7
	add.w   d1,d7
	cmpi.w  #$3fff,d7
	bhi.s   .no
	bsr.w   fx_hud_slot
	ifne FX_HOV
	bsr.w   fx_hud_ov               ; (new or changed) over or under another strip?
	bne.s   .no
	endif
	move.w  FX_HSEEN,d7
	bset    d1,d7
	move.w  d7,FX_HSEEN
	lsl.w   #3,d1
	lea     FX_HRAW,a4
	adda.w  d1,a4
	move.l  -8(a1),(a4)+
	move.l  -4(a1),(a4)
	move.w  #4,ccr                  ; Z set
	rts
.no:	move.w  #0,ccr
	rts

	ifne FX_HOV
; (FX_HOV) The strip at -8(a1) (slot d1, new or changed, about to be taken) against the
; strips on the fix layer: the shadow's shown ones, the ones taken earlier in this walk
; (new: their words in FX_HRAW).  Both are 2 fix columns wide: they overlap when their
; columns are within 1 and their rows meet.  One taken earlier in the walk is above this
; one (the walk's first entry is drawn on top: hal/fz.s): this strip is a sprite, under
; its cells.  One shown but not seen yet is under this one (later in the walk), or gone:
; it yields (FX_HYIELD, FX_HYTO = this slot, FX_HYSEQ = now) - refused when its turn
; comes, its cells cleared in this walk's HUD pass before this strip's are written
; (fx_walk .hud's two rounds) - and this strip is taken.  A yielding slot is no obstacle
; (cleared this walk).  Z set: take it.  Keeps d1, a1; clobbers d0, d7, a4.
fx_hud_ov:
	movem.l d2-d6/a2,-(sp)
	move.w  d1,d0                   ; shown at the same place and size (its content
	lsl.w   #5,d0                   ; changed): nothing new to meet
	move.w  d0,d7
	add.w   d0,d0
	add.w   d7,d0
	lea     FX_HSHD,a4
	adda.w  d0,a4
	tst.w   FXH_COL+4(a4)
	beq.s   .go
	move.l  -8(a1),d0
	cmp.l   FXH_RAW(a4),d0
	bne.s   .go
	moveq   #0,d0
	bra.w   .x
.go:	cmpi.w  #8,d1                   ; (the texts, 8-12, meet nothing: the screen's middle)
	bhs.w   .x
	st      FX_HOVRAN
	move.w  -6(a1),d2               ; column
	andi.w  #$1ff,d2
	lsr.w   #3,d2
	move.w  -8(a1),d3               ; row, row end
	move.w  d3,d4
	andi.w  #$1ff,d3
	lsr.w   #3,d3
	addq.w  #2,d3
	rol.w   #7,d4
	andi.w  #7,d4
	addq.w  #1,d4
	add.w   d4,d4
	add.w   d3,d4
	lea     FX_HSHD,a4
	lea     FX_HRAW,a2
	moveq   #0,d6
.l:	cmp.w   d1,d6
	beq.w   .n
	move.w  FX_HYIELD,d0
	btst    d6,d0
	bne.w   .n
	tst.w   FXH_COL+4(a4)
	beq.w   .raw
	move.w  FXH_COL(a4),d0          ; columns within 1 (first: most strips are in the
	sub.w   d2,d0                   ; other band)
	addq.w  #1,d0
	cmpi.w  #2,d0
	bhi.w   .n
	move.w  FXH_COL+2(a4),d5
	move.w  FXH_COL+4(a4),d7
	add.w   d5,d7
	bra.w   .c
.raw:	move.w  FX_HSEEN,d0
	btst    d6,d0
	beq.w   .n
	move.w  2(a2),d0
	andi.w  #$1ff,d0
	lsr.w   #3,d0
	sub.w   d2,d0
	addq.w  #1,d0
	cmpi.w  #2,d0
	bhi.w   .n
	move.w  (a2),d5
	move.w  d5,d7
	andi.w  #$1ff,d5
	lsr.w   #3,d5
	addq.w  #2,d5
	rol.w   #7,d7
	andi.w  #7,d7
	addq.w  #1,d7
	add.w   d7,d7
	add.w   d5,d7
.c:	cmp.w   d4,d5                   ; rows meet
	bhs.w   .n
	cmp.w   d3,d7
	bls.w   .n
	move.w  FX_HSEEN,d0             ; taken earlier this walk: above this one, which
	btst    d6,d0                   ; stays a sprite
	bne.w   .ov
	move.l  a4,-(sp)                ; shown, not seen yet: under this one (later in the
	move.w  FX_HSUS,d0              ; walk: at its take it yields), or gone (cleared
	bset    d6,d0                   ; this walk)
	move.w  d0,FX_HSUS
	lea     FX_HYTO,a4
	move.b  d1,(a4,d6.w)
	movea.l (sp)+,a4
	bra.w   .n
.ov:	moveq   #1,d0                   ; (Z clear: a sprite this walk)
	bra.w   .x
.n:	lea     FXH_SIZE(a4),a4
	addq.l  #8,a2
	addq.w  #1,d6
	cmpi.w  #8,d6
	blo.w   .l
	moveq   #0,d0                   ; (Z set: clear)
.x:	movem.l (sp)+,d2-d6/a2
	rts

; (FX_HOV) The HUD pass begins: each yielding slot whose strip above was seen this walk
; has its sighting renewed.  Keeps every register.
fx_hud_yref:
	movem.l d0-d3/a2/a4,-(sp)
	move.w  FX_HYIELD,d1
	move.w  FX_HSEEN,d3
	lea     FX_HYTO,a4
	lea     FX_HYSEQ,a2
	moveq   #0,d2
.l:	btst    d2,d1
	beq.s   .n
	moveq   #0,d0
	move.b  (a4,d2.w),d0            ; the slot above: seen this walk?
	btst    d0,d3
	beq.s   .n
	move.w  d2,d0
	add.w   d0,d0
	move.w  FX_WSEQ,(a2,d0.w)
.n:	addq.w  #1,d2
	cmpi.w  #FXH_N,d2
	blo.s   .l
	movem.l (sp)+,d0-d3/a2/a4
	rts

; (FX_HOV) The HUD pass's round 1: the yielding slots' sightings renewed (fx_hud_yref),
; each one shown and not taken this walk cleared (fx_hud_draw's .gone) - before the
; pass writes the strips above them.  d6 charged.  Clobbers d0, d1, d7, a4.
fx_hud_round1:
	bsr.w   fx_hud_yref
	subi.w  #FXU_HOV1,d6
	movem.l d2/d3,-(sp)
	move.w  FX_HYIELD,d2
	move.w  FX_HSEEN,d3
	moveq   #0,d1
.l:	btst    d1,d2
	beq.s   .n
	btst    d1,d3
	bne.s   .n
	move.w  d1,d0
	lsl.w   #5,d0                   ; (x 96: FXH_SIZE)
	move.w  d0,d7
	add.w   d0,d0
	add.w   d7,d0
	lea     FX_HSHD+FXH_COL+4,a4
	tst.w   (a4,d0.w)
	beq.s   .n
	move.w  d1,d0
	bsr.w   fx_hud_draw
	sub.w   d0,d6
.n:	addq.w  #1,d1
	cmpi.w  #8,d1
	blo.s   .l
	movem.l (sp)+,d2/d3
	rts
	endif

; The piece just written (-8(a1)): d1 = its HUD slot (map 0x3fc0-0x3fff: bits 3-5;
; 0x24cf 8, 0x24d7 9, 0x24ec 10, 0x24dd 11, 0x24e2-0x24eb 12).
fx_hud_slot:
	move.w  -2(a1),d1
	cmpi.w  #$24ec,d1
	bhi.s   .h
	beq.s   .c
	cmpi.w  #$24e2,d1
	bhs.s   .dg
	cmpi.w  #$24dd,d1
	beq.s   .ct
	cmpi.w  #$24d7,d1
	beq.s   .o
	moveq   #8,d1
	rts
.o:	moveq   #9,d1
	rts
.c:	moveq   #10,d1
	rts
.ct:	moveq   #11,d1
	rts
.dg:	moveq   #12,d1
	rts
.h:	lsr.w   #3,d1
	andi.w  #7,d1
	rts

; HUD slot d0 at the walk's end: its strip (FX_HRAW) where the fix layer does not show
; it already (FX_HSHD: the same words and lookup entries: ~300 cycles), else made into
; cells (HUD_STAB: four S tiles per tile; tile 0 or one not in the S ROM: blank) and
; written (REG_VRAMMOD = 1, the writes >= 12 cycles apart; cleared first only where it
; moved); what is shown cleared if it is gone (or the fix layer is the tilemap text's
; now).  d0 = the 16-cycle units used.  Keeps d1-d7, a0-a6.
fx_hud_draw:
	movem.l d1-d5/a0-a5,-(sp)
	ifne FZ_PD&FZ_HC
	move.w  d0,FZ_HDS               ; (hal/fz.s: the HUD cache's slot)
	endif
	clr.w   FX_QFLN
	moveq   #FXU_HUDC,d5
	move.w  d0,d4
	lsl.w   #5,d0                   ; (x 96: FXH_SIZE)
	move.w  d0,d1
	add.w   d0,d0
	add.w   d1,d0
	lea     FX_HSHD,a1
	adda.w  d0,a1
	lea     REG_VRAMRW,a3
	tst.b   FX_HOK
	beq.w   .gone
	move.w  FX_HSEEN,d0
	btst    d4,d0
	beq.w   .gone
	lsl.w   #3,d4
	lea     FX_HRAW,a0
	adda.w  d4,a0
	move.w  (a0),d1                 ; tiles - 1: ysize
	rol.w   #7,d1
	andi.w  #7,d1
	lea     G_SPRLUT,a2             ; its lookup entries
	move.w  6(a0),d0
	andi.w  #$3fff,d0
	add.w   d0,d0
	adda.w  d0,a2
	tst.w   FXH_COL+4(a1)           ; the same words and entries as shown?
	beq.s   .chg
	move.l  (a0),d0
	cmp.l   FXH_RAW(a1),d0
	bne.s   .chg
	move.l  4(a0),d0
	cmp.l   FXH_RAW+4(a1),d0
	bne.s   .chg
	movea.l a2,a5
	lea     FXH_LUT(a1),a4
	move.w  d1,d0
.lc:	cmpm.w  (a5)+,(a4)+
	dbne    d0,.lc
	beq.w   .x                      ; (unchanged)
.chg:	move.w  #FXU_HUD,d5             ; changed: column, row, cells per column
	move.w  2(a0),d2
	andi.w  #$1ff,d2
	lsr.w   #3,d2
	move.w  (a0),d3
	andi.w  #$1ff,d3
	lsr.w   #3,d3
	addq.w  #2,d3                   ; (fix rows 2..29 on screen)
	move.w  d1,d4
	addq.w  #1,d4
	add.w   d4,d4
	cmp.w   FXH_COL(a1),d2          ; elsewhere: what is shown cleared first
	bne.s   .mv
	cmp.w   FXH_COL+2(a1),d3
	bne.s   .mv
	cmp.w   FXH_COL+4(a1),d4
	beq.s   .st
.mv:	movem.w d1-d4,-(sp)
	bsr.w   .clr
	movem.w (sp)+,d1-d4
.st:	move.l  (a0),FXH_RAW(a1)        ; the words, place, size, palette
	move.l  4(a0),FXH_RAW+4(a1)
	move.w  d2,FXH_COL(a1)
	move.w  d3,FXH_COL+2(a1)
	move.w  d4,FXH_COL+4(a1)
	moveq   #4,d2                   ; fix palette 4 + colour bit 0 + 2 x bit 2
	btst    #0,4(a0)
	beq.s   .c0
	addq.w  #1,d2
.c0:	btst    #2,4(a0)
	beq.s   .c2
	addq.w  #2,d2
.c2:	ror.w   #4,d2
	move.w  d2,FXH_COL+6(a1)
	lea     FXH_LUT(a1),a4          ; the entries and the cells
	lea     FXH_C0(a1),a0
	move.l  a3,d3                   ; (the VRAM port)
	lea     FXH_C1(a1),a3
	lea     HUD_STAB,a5
	move.w  d1,d4
.r:	move.w  (a2)+,d0
	move.w  d0,(a4)+
	andi.w  #$7fff,d0
	beq.s   .bl
	subi.w  #HUD_T0,d0
	cmpi.w  #HUD_TN,d0
	bhs.s   .bl                     ; (not in the S ROM: blank)
	lsl.w   #3,d0
	move.l  (a5,d0.w),d1            ; top left, top right
	move.l  4(a5,d0.w),d0           ; bottom left, bottom right
	cmpi.l  #$ffff0000,d1
	bhs.s   .bl
	or.w    d2,d1
	or.w    d2,d0
	swap    d1
	swap    d0
	or.w    d2,d1
	or.w    d2,d0
	move.w  d1,(a0)+
	move.w  d0,(a0)+
	swap    d1
	swap    d0
	move.w  d1,(a3)+
	move.w  d0,(a3)+
	dbra    d4,.r
	bra.s   .mk
.bl:	move.w  d2,(a0)+                ; blank
	move.w  d2,(a0)+
	move.w  d2,(a3)+
	move.w  d2,(a3)+
	dbra    d4,.r
.mk:	movea.l d3,a3
	moveq   #1,d0                   ; (queued: written with this list's sprites)
	bsr.w   fx_q_put
	bra.s   .x
.gone:	bsr.s   .clr
.x:
	ifne FZ_PD&FZ_HC
	move.w  FZ_HDS,d1               ; (hal/fz.s: the slot shown as last taken, or not)
	move.w  d1,d2
	lsl.w   #5,d2                   ; (x 96: its strip)
	move.w  d2,d0
	add.w   d2,d2
	add.w   d0,d2
	lea     FX_HSHD,a0
	adda.w  d2,a0
	move.w  FZ_HCOK,d2
	bclr    d1,d2
	tst.w   FXH_COL+4(a0)
	beq.s   .hc
	bset    d1,d2
.hc:	move.w  d2,FZ_HCOK
	addq.w  #4,d5                   ; (this: ~60 cycles, in the units returned)
	endif
	move.w  FX_QFLN,d0              ; (the queue entries written at once)
	mulu    #FXU_QFL,d0
	add.w   d5,d0
	movem.l (sp)+,d1-d5/a0-a5
	rts
	; what FX_HSHD a1 shows: cleared (queued).  Clobbers d0-d2.
.clr:	tst.w   FXH_COL+4(a1)
	beq.s   .cx
	move.w  #FXU_HUD,d5
	moveq   #2,d0
	bsr.w   fx_q_put
	clr.w   FXH_COL+4(a1)
.cx:	rts

; Queue a write (d0 = 1: shadow a1's place and cells) or a clear (2: its place) for the
; walk's list; the queue full, its oldest entry is written now.  Keeps all but d0.
fx_q_put:
	movem.l d1-d2/a0/a2,-(sp)
	move.w  d0,d2
	cmpi.w  #FXQ_N,FX_QN
	blo.s   .r
	bsr.w   fx_q_one
	addq.w  #1,FX_QFLN
.r:	move.w  FX_QH,d0                ; the entry after the last
	add.w   FX_QN,d0
	cmpi.w  #FXQ_N,d0
	blo.s   .i
	subi.w  #FXQ_N,d0
.i:	mulu    #FXQ_SIZE,d0
	lea     FX_HQ,a2
	adda.w  d0,a2
	move.w  FX_WSEQ,(a2)+
	move.w  d2,(a2)+
	move.l  FXH_COL(a1),(a2)+       ; column, row
	move.w  FXH_COL+4(a1),(a2)+     ; cells per column
	cmpi.w  #1,d2
	bne.s   .n
	lea     FXH_C0(a1),a0           ; (both columns' cells: 64 bytes)
	lea     FXQ_C0-FXQ_COL-6(a2),a2
	moveq   #16-1,d1
.c:	move.l  (a0)+,(a2)+
	dbra    d1,.c
.n:	addq.w  #1,FX_QN
	movem.l (sp)+,d1-d2/a0/a2
	rts

; The queue's oldest entry to the fix layer (not while the tilemap text has it: then
; dropped).  Keeps all but d0.
fx_q_one:
	movem.l d1-d2/a2-a3,-(sp)
	move.w  FX_QH,d0
	mulu    #FXQ_SIZE,d0
	lea     FX_HQ,a2
	adda.w  d0,a2
	tst.w   HAL_FIXUSED
	bne.s   .d
	move.w  #1,REG_VRAMMOD
	lea     REG_VRAMRW,a3
	move.w  FXQ_COL(a2),d0          ; its first cell
	lsl.w   #5,d0
	add.w   FXQ_COL+2(a2),d0
	addi.w  #FIXMAP,d0
	move.w  FXQ_COL+4(a2),d1        ; cells per column
	beq.s   .d
	subq.w  #1,d1
	cmpi.w  #1,FXQ_TYPE(a2)
	bne.s   .k
	move.w  d0,-2(a3)               ; a write: both columns
	lea     FXQ_C0(a2),a2
	move.w  d1,d2
.w0:	move.w  (a2)+,(a3)              ; (12 + 10 cycles apart)
	dbra    d2,.w0
	addi.w  #32,d0
	move.w  d0,-2(a3)
	move.w  FX_QH,d2                ; (column 1's cells)
	mulu    #FXQ_SIZE,d2
	lea     FX_HQ+FXQ_C1,a2
	adda.w  d2,a2
.w1:	move.w  (a2)+,(a3)
	dbra    d1,.w1
	bra.s   .d
.k:	move.w  d0,-2(a3)               ; a clear
	move.w  d1,d2
.k0:	move.w  #0,(a3)
	dbra    d2,.k0
	addi.w  #32,d0
	move.w  d0,-2(a3)
.k1:	move.w  #0,(a3)
	dbra    d1,.k1
.d:	move.w  FX_QH,d0                ; dequeued
	addq.w  #1,d0
	cmpi.w  #FXQ_N,d0
	blo.s   .h
	moveq   #0,d0
.h:	move.w  d0,FX_QH
	subq.w  #1,FX_QN
	movem.l (sp)+,d1-d2/a2-a3
	rts

; A flip shows the sprites of list buffer d0: the queue written up to its walk's
; number, while the time lasts (the rest at the next flip).  Keeps every register.
fx_hud_apply:
	movem.l d0/a0,-(sp)             ; (noted: written at the commit's end,
	add.w   d0,d0                   ; fx_hud_flush - still before the picture)
	ifne FUSED
	lea     FZ_SEQ,a0               ; (hal/fz.s: d0 the set)
	else
	lea     FX_LSEQ,a0
	endif
	move.w  (a0,d0.w),FX_QUPTO
	st      FX_QDUE
	movem.l (sp)+,d0/a0
	rts
; The queue up to FX_QUPTO, while the time lasts.  Keeps every register.
fx_hud_flush:
	tst.b   FX_QDUE
	beq.s   .z
	movem.l d0-d2/a0,-(sp)
	move.w  FX_QUPTO,d1
.q:	tst.w   FX_QN
	beq.s   .xd
	move.w  FX_QH,d0
	mulu    #FXQ_SIZE,d0
	lea     FX_HQ,a0
	move.w  (a0,d0.w),d2            ; the oldest's number: up to the list's?
	sub.w   d1,d2
	tst.w   d2                      ; (frame numbers wrap: the sign only)
	bgt.s   .xd
	moveq   #2,d0                   ; (an entry: <= ~800 cycles)
	jsr     hal_late_n
	bne.s   .x
	bsr.w   fx_q_one
	bra.s   .q
.xd:	sf      FX_QDUE                 ; (all of it written)
.x:	movem.l (sp)+,d0-d2/a0
.z:	rts

; d0 = list buffer -> d0 = the queue's entries up to its walk's number (a flip that
; shows its sprites writes them with it: its time counts them).  Keeps all but d0.
fx_hud_count:
	movem.l d1-d3/a0,-(sp)
	add.w   d0,d0
	ifne FUSED
	lea     FZ_SEQ,a0               ; (hal/fz.s: d0 the set)
	else
	lea     FX_LSEQ,a0
	endif
	move.w  (a0,d0.w),d1            ; its number
	moveq   #0,d0
	move.w  FX_QN,d3
	move.w  FX_QH,d2
	bra.s   .e
.l:	movem.w d2,-(sp)
	mulu    #FXQ_SIZE,d2
	lea     FX_HQ,a0
	move.w  (a0,d2.w),d2
	sub.w   d1,d2
	tst.w   d2                      ; (frame numbers wrap: the sign only)
	movem.w (sp)+,d2                ; (keeps the flags)
	bgt.s   .x                      ; (in order: the rest are later)
	addq.w  #1,d0
	addq.w  #1,d2
	cmpi.w  #FXQ_N,d2
	blo.s   .e
	moveq   #0,d2
.e:	dbra    d3,.l
.x:	movem.l (sp)+,d1-d3/a0
	rts

; d0 = list buffer whose sprites a flip shows now: the queue up to its walk's number
; written (counted in the flip's time: no check).  Keeps every register.
fx_hud_flushall:
	movem.l d0-d2/a0,-(sp)
	add.w   d0,d0
	ifne FUSED
	lea     FZ_SEQ,a0               ; (hal/fz.s: d0 the set)
	else
	lea     FX_LSEQ,a0
	endif
	move.w  (a0,d0.w),d1
.q:	tst.w   FX_QN
	beq.s   .x
	move.w  FX_QH,d0
	mulu    #FXQ_SIZE,d0
	lea     FX_HQ,a0
	move.w  (a0,d0.w),d2
	sub.w   d1,d2
	tst.w   d2                      ; (frame numbers wrap: the sign only)
	bgt.s   .x
	bsr.w   fx_q_one
	bra.s   .q
.x:	sf      FX_QDUE
	movem.l (sp)+,d0-d2/a0
	rts

; The shadow (nothing shown) and the queue (empty) after the game's boot RAM test.
; Clobbers d0.
fx_hreset:
	move.l  a0,-(sp)
	moveq   #FXH_N-1,d0
	lea     FX_HSHD+FXH_COL+4,a0
.c:	clr.w   (a0)
	lea     FXH_SIZE(a0),a0
	dbra    d0,.c
	ifne FZ_PD
	clr.w   FZ_HCOK                 ; (hal/fz.s: no strip shown: the HUD cache's slots
	endif                           ; untrusted - stale bits kept the 1P label away after
					; a game start on the MiSTer, 2026-10-18)
	clr.w   FX_QH
	clr.w   FX_QN
	ifne FX_HOV
	clr.w   FX_HYIELD
	clr.w   FX_HSUS
	sf      FX_HOVRAN
	sf      FX_HR1
	endif
	move.l  #$46584853,FX_HMAGIC
	movea.l (sp)+,a0
	rts
