; Not cycle-exact (AEROFGT_DIRECT=1): sprites of the last list that the next one has
; again keep their Neo columns (the newest set updated in place).
;
; Most of a list is the last one again (the same tiles, moved or not); in the dense
; scenes two sets of a list do not fit the ring's 338 columns.  So a new list is
; matched against the ring's newest set's (the base: shown, or complete with its flip
; to come): its entries in order, each looked for among the base's next DL_LOOK
; entries not passed yet (sizes, zoom, attributes, tiles: positions aside).  A match
; with a head keeps it (its new SCB3 and SCB4 written at the flip: DA_HV, DA_HX); the
; rest is converted below the set's last column, behind every kept one, and the base's
; heads not kept are hidden at the flip (their columns idle until the set is
; reclaimed).  Draw order (the higher column on top, entry 0 the front): a kept sprite
; may lie under no new one before it, and the kept ones keep the list's order (their
; columns falling), so it is converted again instead when one of its cells (32
; pixels) is covered by an entry before it that is not kept (DL_NCOV), or its column
; is above a kept one's before it (DLR_MINC).  (Model, 2026-10-14, the attract and
; movie7 lists: the dense attract scenes' drop frames 238 -> ~200, dropped columns
; ~27500 -> ~18300 against keeping the list's first entries only.)
;   * dl_try / dl_step (a new conversion, hal_spr_work): the matching, DL_STEP entries
;     per time check, across calls in the slot; then dl_fin: the rules for an update
;     and its arrays: the kept heads move to the set's first head slots (a shown set
;     is only hidden whole and reclaimed by address: their order does not matter), the
;     others' SCB3 addresses go to DA_HIDE; the conversion skips the kept entries
;     (hal_spr_go: their table values) and appends its heads after the kept ones
;     (HAL_SPR_W = the base, FX_DELTA 1, FX_DHOFF).
;   * done (hal_spr_work .fin): FX_DELTA 2; dl_flip, from FX_DRDY on, writes it all.
; A base not shown yet (its own flip shows its heads in their slots) or with an update
; pending (whose flip writes its slots) keeps its slots: only its heads in their order
; may be kept then, all of them (DLR_ID).
; Entry tables (DL_TABS): per entry of a set's list its head slot ($fe: none - out of
; view or dropped; $ff: converted, the slot given lazily: the converted entries' heads
; come in entry order after the kept ones, dl_tget).  Each set owns one; an update
; another, its list's, which is the set's from the update's flip on.

DL_SETS         equ G_SPRRAM+$510   ; per set 64 bytes:
DL_NOD          equ 0               ;   b: no update from it (head slots ran out)
DL_TABI         equ 1               ;   b: its entry table
DL_DEAD         equ 3               ;   b: heads hidden by updates (their columns idle)
DL_SRC          equ 64*3            ; 3 w after the sets: per set its list's buffer
DL_WHY          equ G_SPRRAM+$5e0   ; (diagnostics) w: why the last try failed
DL_WHYN         equ G_SPRRAM+$5e2   ; w per reason (1-14): tries it failed
DL_HXN          equ 80              ; heads kept at most
DL_HIDEN        equ 96              ; heads hidden at most
DL_LOOK         equ 8               ; base entries an entry is looked for among
DL_STEP         equ 4               ; entries matched per time check
DL_STEPL        equ 8               ; its lines (~1400 cycles an entry at most)
DL_SLACK        equ 16              ; columns the ring keeps spare for a list's growth
; an update in place: its state block (C: the one converting, or done waiting behind P;
; P: done, waiting for its flip)
D_ST            equ 0               ; b: C: 1 converting, 2 done (behind P); P: 1 on
D_KEPT          equ 2               ; w: heads kept (the first slots)
D_BUF           equ 4               ; w: its list's buffer
D_HOFF          equ 6               ; w: the set's heads x 2 after it
D_BASE          equ 8               ; w: the set updated
D_RDY           equ 10              ; w: the first slot it may be shown in
D_HIDE          equ 12              ; w: heads to hide (D_ARR+DA_HIDE)
D_ARR           equ 14              ; l: its arrays
D_TAB           equ 18              ; w: its list's entry table
D_SIZE          equ 20
DA_HV           equ 0               ; per kept head: SCB3
DA_HX           equ 2*DL_HXN        ; per kept head: SCB4
DA_HIDE         equ 4*DL_HXN        ; SCB3 addresses of the heads to hide
	if DA_HIDE+2*DL_HIDEN>$200
	fail "update arrays too large"
	endif
DL_ARR0         equ G_DX_LIST       ; (the original's sprite-list builder's work area:
DL_ARR1         equ G_DX_LIST+$200  ; unused without it)
DL_KS           equ G_SPRRAM+$600   ; 80 b: per kept head (list order) its base slot
DL_NCOV         equ G_SPRRAM+$650   ; 7 w: per cell row, the cells covered by entries
                                    ; not kept (a bit per cell column)
DL_USED         equ G_SPRRAM+$6ec   ; 16 b: base slots kept (a bit each)
DL_TA           equ G_SPRRAM+$700   ; 80 w: (dl_fin) kept heads' SCB3 addresses
DL_TABS         equ G_DX_BUF0+$4e0  ; DL_NTAB entry tables of DL_TSZ bytes (fx.s: the
DL_NTAB         equ 5               ; fix layer's shadow ends at +$4e0, its magic at
DL_TSZ          equ 132             ; +$7f0)
T_FIN           equ 128             ; b: entries with their slots given up to here
T_NXT           equ 129             ; b: the next slot
T_OK            equ 130             ; b: valid
T_N             equ 131             ; b: the list's entries it covers (a list still being
                                    ; walked grows after: its later entries none, else
                                    ; their stale slots were kept, 2026-10-16)
	if DL_NTAB*DL_TSZ>$7f0-$4e0
	fail "entry tables too large"
	endif
DLC             equ FXS+$620
DLP             equ FXS+$640
FX_DELTA        equ DLC+D_ST
FX_DHOFF        equ DLC+D_HOFF
FX_DRDY         equ DLC+D_RDY
FX_PON          equ DLP+D_ST
FX_PRDY         equ DLP+D_RDY
FX_SBUF         equ FXS+$660        ; w: the shown set's list's buffer (-1: none)
FX_CBUF         equ FXS+$662        ; w: the newest complete / pending list's buffer
DL_BH2          equ FXS+$664        ; w: (dl_try) the base's heads x 2
DL_BP           equ FXS+$666        ; b: (dl_try) the base has an update pending
DLR_ON          equ FXS+$667        ; b: a matching going on (dl_step)
DLR_SLOT        equ FXS+$668        ; w: its slot
DLR_BASE        equ FXS+$66a        ; w: its base
DLR_N           equ FXS+$66c        ; w: the new list's entries
DLR_E           equ FXS+$66e        ; w: entries matched
DLR_J           equ FXS+$670        ; w: base entries passed
DLR_H           equ FXS+$672        ; w: heads kept
DLR_LIM         equ FXS+$674        ; w: this step's end
DLR_A2          equ FXS+$676        ; l: the base list
DLR_A3          equ FXS+$67a        ; l: the new list's next entry
DLR_A0          equ FXS+$67e        ; l: next HV
DLR_A1          equ FXS+$682        ; l: next HX
DLR_A4          equ FXS+$686        ; l: the base's entry table
DLR_OFF         equ FXS+$68a        ; w: kept heads out of view
DLR_K           equ FXS+$68c        ; w: kept heads' columns
FX_FLATE        equ FXS+$68e        ; b: flips deferred in a row (hal/spr.s .defer)
FX_FNOH         equ FXS+$68f        ; b: this flip leaves its list's text to the queue
DLR_R           equ FXS+$6a4        ; w: the columns of the entries not kept
DLR_NB          equ FXS+$6a6        ; w: the base list's entries
DLR_CT          equ FXS+$6a8        ; l: the new list's entry table
FX_KTAB         equ FXS+$6ac        ; l: the conversion's entry table (dl_skip, the
                                    ; update's kept entries: hal_spr_go)
DLR_PH          equ FXS+$6b0        ; l: a pending update's DA_HV (its kept heads)
DLR_F1          equ FXS+$6b4        ; w: the first entry not kept (-1: none yet)
DLR_ID          equ FXS+$6b6        ; b: the base's slots stay (only its own order)
DLR_DONE        equ FXS+$6b7        ; b: all entries matched (dl_fin to do)
DLR_VIEW        equ FXS+$6b8        ; b: the entry in view
DLR_BW          equ FXS+$6ba        ; l: its w0, w1 sizes and zoom
DLR_CM          equ FXS+$6be        ; w: its cells: a bit per cell column
DLR_CY0         equ FXS+$6c0        ; w: its first cell row
DLR_CY1         equ FXS+$6c2        ; w: its last
DLR_PK          equ FXS+$6c6        ; w: a pending update's kept heads (else 0)
DLR_CX0         equ FXS+$6c8        ; w: its first cell column
DLR_CX1         equ FXS+$6ca        ; w: its last
DLR_MINC        equ FXS+$6cc        ; w: the lowest column kept so far
DLR_NV          equ FXS+$6ce        ; b: an entry not kept in view so far
DLR_PRESS       equ FXS+$6cf        ; b: the ring short of columns: match it all
DLR_RS          equ FXS+$6d0        ; w: the entries from here on not kept (dl_fin)
DLR_SEND        equ FXS+$6d2        ; l: the base's entries looked among: their end
DLR_PERM        equ FXS+$6d6        ; b: a kept head not in its slot already
	ifnd DL_CW
DL_CW           equ 0               ; (experiment: in-place updates limited by idle columns)
	endif
	ifnd DL_CWS
DL_CWS          equ 16              ; (idle columns allowed besides the 1/4)
	endif
	ifnd DL_OFF
DL_OFF          equ 0               ; (experiment: 1 = no updates in place)
	endif
;   (DL_OOO, DIRECT: out of order) a new entry may keep any unused base entry of its
;   shape, attributes and tiles (a hash of the base list's, DL_HASH/DL_NEXT): the one
;   with the highest column that keeps the draw order where it matters - its column below
;   every kept one before it over its cells (DL_MINC), and not under a new one before it
;   (DL_NCOV); the base list's order no longer matters (2026-10-16: kept columns of the
;   split scenes' lists ~17 in order -> ~60% out of order).
;   (DL_SPLIT) a split base (the ring's only set, shown) keeps its runs; the entries not
;   kept go into the hole between them, below the top run (which grows down: SPJ, as a
;   set begun there would), above the lower run: so a kept one of the lower run may lie
;   under a new one before it, one of the top run not; and a new one may not lie under a
;   kept one of the lower run before it (DL_LCOV): those are converted again too
;   (dl_odem, from their recorded cells; the order between the new ones is the
;   conversion's).  A split base is matched only when a new set of its list would not
;   fit the hole (else it goes there as usual).
;   Both OFF (2026-10-16, work/catalog/AUDIT.md section 13): correct (every commit's kept
;   pairs and every shown sprite's columns checked: bot movies 8, 9), but the whole list
;   matched costs ~1000 cycles an entry: for every base movie7's late frames 575 ->
;   1330; for a split base only, its dense scenes leave a slot time for ~20 of ~65
;   entries, so no split base was ever updated (bot movie 8, 60k frames) - it needs a
;   much cheaper match (e.g. keys and cells made by the walk).
	ifnd DL_OOO
DL_OOO          equ 0               ; (off: see above)
	endif
	ifnd DL_SPLIT
DL_SPLIT        equ 0
	endif
	ifnd DL_OOOALL
DL_OOOALL       equ 0               ; (1: out of order for every base, not only a split one)
	endif
	if DL_SPLIT&(1-DL_OOO)
	fail "DL_SPLIT needs DL_OOO"
	endif
DL_MINC         equ G_SPRRAM+$65e   ; 70 b: per cell (10 x 7) the lowest kept column so
                                    ; far ((column - DL_C0) / 2: $ff none)
DL_LCOV         equ G_SPRRAM+$6a4   ; 7 w: per cell row, cells with a kept one of the
                                    ; lower run (DL_SPLIT)
DL_HASH         equ G_SPRRAM+$6b2   ; 32 b: per hash (w3 & 31) the base entries' chain
DL_NEXT         equ G_SPRRAM+$7a0   ; FX_LMAX b: per base entry the next in its chain
DL_BSL          equ G_DX_BUF0+$774  ; FX_LMAX b: per base entry its head slot ($fe: none
                                    ; or kept already)
DL_DMSK         equ DL_TA           ; 7 w: (dl_odem) the cells demoted over
DL_LKC          equ DL_TA+16        ; DL_LKMAX x 4 b: per kept one of the lower run (in
DL_LKMAX        equ 36              ; entry order): entry, CY0 << 4 | CY1, w CM
	if DL_LKC+4*DL_LKMAX>DL_TA+160
	fail "DL_LKC"
	endif
	if DL_HASH+32>DL_USED
	fail "DL_HASH"
	endif
	if DL_NEXT+FX_LMAX>G_SPRRAM+$800
	fail "DL_NEXT"
	endif
	if DL_BSL+FX_LMAX>FX_HMAGIC
	fail "DL_BSL"
	endif
DL_C0           equ 40
DL_CMAX         equ 16              ; candidates looked at at most
DL_OSTEP        equ 2               ; entries matched per time check
DL_OSTEPL       equ 8               ; its lines (~1600 cycles an entry at most, the index:
                                    ; ~100 a base entry)
DL_ISTEP        equ 16              ; base entries indexed per time check
DLR_HOLE        equ FXS+$6e0        ; b: the base split: new entries into its hole
DL_HOLEC        equ FXS+$6e1        ; b: the converting update goes into the hole
DLR_OOO         equ FXS+$6e2        ; b: the matching out of order
DLR_PH0         equ FXS+$6e3        ; b: the base list indexed
DLR_BJ          equ FXS+$6e4        ; w: base entries indexed so far
DLR_BNXT        equ FXS+$6e6        ; w: (the index) the next head slot given lazily
DLR_ROOM        equ FXS+$6e8        ; w: the columns the entries not kept may take
DLR_SPG         equ FXS+$6ea        ; w: the guard (the lower run below it)
DLR_CELL        equ FXS+$6ec        ; b: the entry has cells on screen
DLR_LKN         equ FXS+$6ee        ; w: DL_LKC records
DLR_EI          equ FXS+$6f0        ; w: the entry matched (dl_oent)
DL_FAILS        equ FXS+$6d8        ; b: tries failed in a row
DL_SKIPN        equ FXS+$6d9        ; b: tries still skipped (the back-off)
DL_BOFF         equ FXS+$6da        ; b: (DL_EXPB) the next back-off's length
	ifnd DL_EXPB
DL_EXPB         equ 1               ; back-offs in a row double (to DL_BOMAX), a success
	endif                           ; resets them (dense scenes: tries ~5% successful,
DL_BOMAX        equ 64              ; each failed one a whole matching, 2026-10-17)
DL_FAILMAX      equ 3               ; dense scenes (the ring split, most entries new):
DL_BACKOFF      equ 8               ; tries cost ~9k cycles a frame and never succeed -
                                    ; after DL_FAILMAX failures in a row DL_BACKOFF
                                    ; are skipped (2026-10-15)
DLR_PRESSC      equ 153             ; base columns over which (two sets ~ the ring)
DL_OFFY         equ 300             ; y of a kept head out of view (lines 300-427)

; a1 = the DL record of set \1.  Clobbers d0.
DLREC	macro
	move.w  \1,d0
	lsl.w   #6,d0
	lea     DL_SETS,a1
	adda.w  d0,a1
	endm

RSTUB	macro
.r\1:	move.w  #\1,DL_WHY
	addq.w  #1,DL_WHYN+2*\1
	bra.w   .no
	endm

; (hal/fx.s, the sprite RAM lost: the boot RAM test) no updates, each set its own
; table.  Keeps every register.
dl_init:
	movem.l d0/a0-a1,-(sp)
	lea     DL_SETS,a1
	moveq   #0,d0
.s:	st      DL_NOD(a1)
	move.b  d0,DL_TABI(a1)
	sf      DL_DEAD(a1)
	lea     64(a1),a1
	addq.w  #1,d0
	cmpi.w  #NSPRSETS,d0
	blo.s   .s
	moveq   #DL_NTAB-1,d0
.t:	bsr.s   dl_tab
	sf      T_OK(a0)
	dbra    d0,.t
	sf      DLR_ON
	sf      DL_FAILS
	sf      DL_SKIPN
	ifne DL_EXPB
	sf      DL_BOFF
	endif
	sf      DL_HOLEC
	ifne SPR_SHARE
	sf      SH_ON
	endif
	ifne SPR_SHARE2
	sf      SH2_ON
	endif
	movem.l (sp)+,d0/a0-a1
	rts

; a0 = entry table d0.  Keeps every register but a0.
dl_tab:
	move.w  d0,-(sp)
	lsl.w   #2,d0                   ; (x DL_TSZ: 132 = 128 + 4)
	lea     DL_TABS,a0
	adda.w  d0,a0
	lsl.w   #5,d0
	adda.w  d0,a0
	move.w  (sp)+,d0
	rts
	if DL_TSZ!=132
	fail "dl_tab: DL_TSZ"
	endif

; d0 = an entry table no set owns, nor the pending update.  Clobbers d1, a0.
dl_talloc:
	moveq   #0,d0
.c:	lea     DL_SETS,a0
	moveq   #NSPRSETS-1,d1
.s:	cmp.b   DL_TABI(a0),d0
	beq.s   .n
	lea     64(a0),a0
	dbra    d1,.s
	tst.b   FX_PON
	beq.s   .x
	cmp.w   DLP+D_TAB,d0
	bne.s   .x
.n:	addq.w  #1,d0
	bra.s   .c
.x:	rts

; A conversion begins for set d0: its list FX_CI's, its table every entry converted.
; Keeps every register.
dl_begin:
	movem.l d0-d1/a0-a1,-(sp)
	DLREC   d0
	sf      DL_NOD(a1)
	sf      DL_DEAD(a1)
	moveq   #0,d0
	move.b  DL_TABI(a1),d0
	bsr.s   dl_tab
	move.l  a0,FX_KTAB
	clr.w   T_FIN(a0)               ; (and T_NXT)
	st      T_OK(a0)
	move.w  FX_BC8,d0
	lsr.w   #3,d0
	move.b  d0,T_N(a0)
	moveq   #-1,d0                  ; (the list's entries: FX_BC8, fx_start)
	move.w  FX_BC8,d1
	addi.w  #31,d1
	lsr.w   #5,d1
	bra.s   .fc
.f:	move.l  d0,(a0)+
.fc:	dbra    d1,.f
	move.w  2(sp),d0
	add.w   d0,d0
	lea     DL_SETS+DL_SRC,a1
	move.w  FX_CI,(a1,d0.w)
	movem.l (sp)+,d0-d1/a0-a1
	rts

; The entry at a5 has no head (out of view: hal_spr_go .off; dropped: .hdrop).  Keeps
; every register but CCR.
dl_skip:
dl_drop:
	movem.l d0/a1,-(sp)
	move.l  a5,d0                   ; (a5 past it)
	sub.l   FX_CL,d0
	lsr.w   #3,d0
	subq.w  #1,d0                   ; its number
	cmpi.w  #128,d0
	bhs.s   .x
	movea.l FX_KTAB,a1
	move.b  #$fe,(a1,d0.w)
.x:	movem.l (sp)+,d0/a1
	rts

; The head slots ran out (hal_spr_go .nsl), or the set began again (.rst): its table
; no use, no update from the set.  Keeps every register.
dl_nod:
	movem.l d0/a1,-(sp)
	movea.l FX_KTAB,a1
	sf      T_OK(a1)
	DLREC   HAL_SPR_W
	st      DL_NOD(a1)
	movem.l (sp)+,d0/a1
	rts

; d0 = entry d0 (< 128) of the base's table (a4): its head slot, $fe none.  Its
; converted entries before it get theirs first.  Keeps every register but d0.
dl_tget:
	cmp.b   T_FIN(a4),d0
	blo.s   .r
	movem.l d2-d3,-(sp)
	moveq   #0,d2
	move.b  T_FIN(a4),d2
	move.b  T_NXT(a4),d3
.f:	cmpi.b  #$ff,(a4,d2.w)
	bne.s   .n
	move.b  d3,(a4,d2.w)
	addq.b  #1,d3
.n:	addq.w  #1,d2
	cmp.w   d0,d2
	bls.s   .f
	move.b  d2,T_FIN(a4)
	move.b  d3,T_NXT(a4)
	movem.l (sp)+,d2-d3
.r:	move.b  (a4,d0.w),d0
	rts

; d0 = the columns of the entry at a3.  Keeps every register but d0.
dl_cols:
	move.w  2(a3),d0
	rol.w   #7,d0
	andi.w  #7,d0
	addq.w  #1,d0
	rts

; The cells (32 pixels) of the entry at a3 on screen: DLR_CM, DLR_CX0/1, DLR_CY0/1; Z
; set: none.  Clobbers d0, d4.
dl_cells:
	move.w  2(a3),d0                ; x .. x1
	andi.w  #$1ff,d0
	cmpi.w  #320,d0
	blo.s   .x
	subi.w  #512,d0
.x:	bsr.s   dl_cols
	move.w  d0,d4
	move.w  2(a3),d0
	andi.w  #$1ff,d0
	cmpi.w  #320,d0
	blo.s   .xx
	subi.w  #512,d0
.xx:	lsl.w   #4,d4
	add.w   d0,d4
	subq.w  #1,d4
	tst.w   d0
	bpl.s   .x0
	moveq   #0,d0
.x0:	cmpi.w  #319,d4
	ble.s   .x1
	move.w  #319,d4
.x1:	cmp.w   d4,d0
	bgt.s   .z
	lsr.w   #5,d0
	lsr.w   #5,d4
	move.w  d0,DLR_CX0
	move.w  d4,DLR_CX1
	move.l  d1,-(sp)
	moveq   #2,d1                   ; (2 << x1) - (1 << x0)
	lsl.w   d4,d1
	moveq   #1,d4
	lsl.w   d0,d4
	sub.w   d4,d1
	move.w  d1,DLR_CM
	move.l  (sp)+,d1
	move.w  (a3),d0                 ; y .. y1
	andi.w  #$1ff,d0
	cmpi.w  #224,d0
	blo.s   .y
	subi.w  #512,d0
.y:	move.w  (a3),d4
	rol.w   #7,d4
	andi.w  #7,d4
	addq.w  #1,d4
	lsl.w   #4,d4
	add.w   d0,d4
	subq.w  #1,d4
	tst.w   d0
	bpl.s   .y0
	moveq   #0,d0
.y0:	cmpi.w  #223,d4
	ble.s   .y1
	move.w  #223,d4
.y1:	cmp.w   d4,d0
	bgt.s   .z
	lsr.w   #5,d0
	lsr.w   #5,d4
	move.w  d0,DLR_CY0
	move.w  d4,DLR_CY1
	moveq   #1,d0                   ; Z clear
	rts
.z:	moveq   #0,d0                   ; Z set
	rts

; Z clear when a cell of the entry (dl_cells) is covered by an entry not kept before
; it.  Clobbers d0, d4.
dl_ncov:
	movem.l d1/a5,-(sp)
	lea     DL_NCOV,a5
	move.w  DLR_CY0,d0
	move.w  DLR_CY1,d4
	sub.w   d0,d4
	add.w   d0,d0
	adda.w  d0,a5
	move.w  DLR_CM,d0
.r:	move.w  (a5)+,d1
	and.w   d0,d1
	dbne    d4,.r
	movem.l (sp)+,d1/a5             ; (keeps the flags)
	rts

; The entry's cells (dl_cells) covered by one not kept.  Clobbers d0, d4.
dl_ncovset:
	move.l  a5,-(sp)
	lea     DL_NCOV,a5
	move.w  DLR_CY0,d0
	move.w  DLR_CY1,d4
	sub.w   d0,d4
	add.w   d0,d0
	adda.w  d0,a5
	move.w  DLR_CM,d0
.r:	or.w    d0,(a5)+
	dbra    d4,.r
	movea.l (sp)+,a5
	rts

; d0 = 0: no update in place (a new set as usual), 1: begun (HAL_SPR_W, HAL_SPR_RA5 set:
; convert it), 2: no time now.  Clobbers d0-d7, a0-a6.
dl_try:
	ifne DL_OFF
	moveq   #0,d0                   ; (experiment: no updates in place)
	rts
	endif
	tst.b   DL_SKIPN                ; (backing off)
	beq.s   .tt
	ifne DL_SPLIT
	bsr.w   dl_hready               ; (but not from a split base's hole: dense scenes
	bne.s   .tt                     ; back off from their other tries, and the moment
	endif                           ; the hole is free was skipped, 2026-10-16)
	subq.b  #1,DL_SKIPN
	moveq   #0,d0
	rts
.tt:
	jsr     hal_spr_klim            ; (its set-up: ~1500 cycles)
	ifne DL_GATE
	move.w  d0,d2                   ; only with time to spare before the real vblank
	move.w  FX_KMOD,d0              ; for the slot's other work: the walk (~0.8 lines
	ifne FX_DELAY
	subq.w  #FX_DELAY,d0            ; a piece), the conversion if the try fails (~0.65)
	endif
	bpl.s   .g1                     ; and the matching itself (up to ~1.3 a piece), by
	addq.w  #FX_NL,d0               ; the pieces of the list it would match
.g1:	lea     FX_PHYS,a0
	move.b  (a0,d0.w),d0
	ext.w   d0
	add.w   d0,d0
	lea     FX_LN,a0
	move.w  (a0,d0.w),d1
	move.w  d1,d0
	add.w   d1,d1
	add.w   d0,d1                   ; 3 lines a piece
	addi.w  #DL_GATE,d1             ; + the fixed share
	add.w   d1,d2
	ble.s   .g2
	addq.l  #1,DL_GATEN
	moveq   #0,d0                   ; (a new set as usual; not a failure: no back-off)
	rts
.g2:	move.w  d2,d0
	endif
	addq.w  #3,d0
	tst.w   HAL_SPR_TAILU
	beq.s   .t0
	addq.w  #3,d0
.t0:	tst.w   d0
	ble.s   .t1
	moveq   #2,d0
	rts
.t1:	moveq   #0,d0                   ; the base: the ring's newest set, shown or
	move.b  HAL_SPR_ORDN,d0         ; complete
	beq.w   .r1
	lea     HAL_SPR_ORD,a0
	moveq   #0,d7
	move.b  -1(a0,d0.w),d7
	lea     HAL_SPR_ST,a0
	move.b  (a0,d7.w),d0
	cmpi.b  #3,d0
	beq.s   .b
	cmpi.b  #1,d0
	bne.w   .r2
.b:	sf      DLR_HOLE
	tst.b   HAL_SPR_SPS             ; (no split set)
	ifeq DL_SPLIT
	bpl.w   .r3
	else
	bmi.s   .b1
	cmp.b   HAL_SPR_SPS,d7          ; (DL_SPLIT: it, shown, the ring's only set - the
	bne.w   .r3                     ; hole free; till then no failure for the back-off:
	cmpi.b  #1,HAL_SPR_ORDN         ; its flip comes, the older set is reclaimed, and
	bne.w   .r3w                    ; the next try must not be skipped)
	cmpi.b  #3,d0
	bne.w   .r3w
	st      DLR_HOLE
.b1:
	endif
	tst.b   FX_DELTA
	bne.w   .r4
	sf      DL_BP                   ; a pending update of it: on top of that one
	move.l  #DL_ARR0,DLC+D_ARR      ; (and the other arrays)
	tst.b   FX_PON
	beq.s   .np
	cmp.w   DLP+D_BASE,d7
	bne.w   .r4
	st      DL_BP
	cmpi.l  #DL_ARR0,DLP+D_ARR
	bne.s   .np
	move.l  #DL_ARR1,DLC+D_ARR
.np:	DLREC   d7
	tst.b   DL_NOD(a1)
	bne.w   .r5
	movea.l a1,a5                   ; a5 = its DL record
	move.w  d7,d0
	jsr     hal_spr_set
	move.w  SS_HOFF(a6),DL_BH2      ; its heads (x 2), list's buffer, entry table
	move.w  d7,d0
	add.w   d0,d0
	lea     DL_SETS+DL_SRC,a0
	move.w  (a0,d0.w),d6
	moveq   #0,d0
	move.b  DL_TABI(a5),d0
	clr.l   DLR_PH
	clr.w   DLR_PK
	tst.b   DL_BP
	beq.s   .nb
	move.w  DLP+D_HOFF,DL_BH2
	move.w  DLP+D_BUF,d6
	move.w  DLP+D_TAB,d0
	move.l  DLP+D_ARR,DLR_PH        ; (its kept heads' SCB3: their heights)
	move.w  DLP+D_KEPT,DLR_PK
.nb:	cmp.w   FX_SBUF,d6              ; (kept by the walk?)
	beq.s   .bk
	cmp.w   FX_CBUF,d6
	bne.w   .r7
.bk:	bsr.w   dl_tab
	tst.b   T_OK(a0)
	beq.w   .r5
	move.l  a0,DLR_A4
	bsr.w   dl_talloc               ; the new list's table
	move.w  d0,DLC+D_TAB
	bsr.w   dl_tab
	move.l  a0,DLR_CT
	jsr     fx_start                ; the new list: FX_CL, FX_BC8, FX_CI
	lea     FX_LN,a0
	move.w  d6,d0
	add.w   d0,d0
	move.w  (a0,d0.w),d5            ; the base list's entries
	beq.w   .r8
	cmpi.w  #FX_LMAX,d5
	bhi.w   .r8
	movea.l DLR_A4,a0               ; (no more than its table covers)
	moveq   #0,d0
	move.b  T_N(a0),d0
	cmp.w   d0,d5
	bls.s   .nb1
	move.w  d0,d5
	tst.w   d5
	beq.w   .r8
.nb1:	move.w  d5,DLR_NB
	move.w  FX_BC8,d4
	lsr.w   #3,d4                   ; the new list's
	beq.w   .r8
	move.w  d4,DLR_N
	ifne DL_SPLIT
	tst.b   DLR_HOLE                ; (a split base: only when a new set of the list
	beq.s   .nh0                    ; would not fit the hole - else it goes there as
	movea.l FX_CL,a0                ; usual: the whole list matched out of order costs
	moveq   #4,d1                   ; ~1000 cycles an entry, on every try movie7's late
	move.w  d4,d2                   ; frames 575 -> ~1000; its columns: ~40 an entry)
	subq.w  #1,d2
.ns:	move.w  2(a0),d0
	rol.w   #7,d0
	andi.w  #7,d0
	addq.w  #1,d0
	add.w   d0,d1
	addq.l  #8,a0
	dbra    d2,.ns
	move.w  HAL_SPR_SPJ,d0
	sub.w   HAL_SPR_SPG,d0
	subq.w  #1,d0
	cmp.w   d0,d1
	bls.w   .r3w
.nh0:
	endif
	sf      DLR_ID                  ; the base not shown, or an update of it pending:
	tst.b   DL_BP                   ; its slots stay
	bne.s   .id
	lea     HAL_SPR_ST,a0
	cmpi.b  #3,(a0,d7.w)
	beq.s   .ni
.id:	st      DLR_ID
	tst.b   DLR_HOLE                ; (a split base: out of order only)
	bne.w   .r3
.ni:	lea     fx_ltab,a0
	move.w  d6,d0
	add.w   d0,d0
	add.w   d0,d0
	move.l  (a0,d0.w),DLR_A2
	move.l  FX_CL,DLR_A3
	movea.l DLC+D_ARR,a0
	move.l  a0,DLR_A0
	lea     DA_HX(a0),a0
	move.l  a0,DLR_A1
	clr.w   DLR_E
	clr.w   DLR_J
	clr.w   DLR_H
	clr.w   DLR_OFF
	clr.w   DLR_K
	clr.w   DLR_R
	move.w  #-1,DLR_F1
	lea     DL_NCOV,a0              ; no cell covered, no kept head anywhere, no base
	clr.l   (a0)+                   ; slot kept
	clr.l   (a0)+
	clr.l   (a0)+
	clr.w   (a0)
	move.w  #$ffff,DLR_MINC
	sf      DLR_NV
	sf      DLR_PERM
	move.w  DLR_N,DLR_RS
	move.w  d7,d0                   ; the ring short of columns (the base about half
	add.w   d0,d0                   ; of it)?  Else the matching ends at the first
	lea     HAL_SPR_START,a0        ; entry not kept (the cheap update: its first
	move.w  (a0,d0.w),d1            ; entries kept, ~1/3 of the time)
	lea     HAL_SPR_END,a0
	sub.w   (a0,d0.w),d1
	cmpi.w  #DLR_PRESSC,d1
	shi     DLR_PRESS
	lea     DL_USED,a0
	clr.l   (a0)+
	clr.l   (a0)+
	clr.l   (a0)+
	clr.l   (a0)
	move.w  d7,DLR_BASE
	move.w  HAL_FRAMES+2,DLR_SLOT
	sf      DLR_DONE
	st      DLR_ON
	ifne DL_OOO
	sf      DLR_OOO
	tst.b   DLR_ID
	bne.s   .oi
	ifeq DL_OOOALL
	tst.b   DLR_HOLE                ; (out of order only into a split base's hole: the
	beq.s   .oi                     ; whole list matched costs ~1000 cycles an entry -
	endif                           ; for every base, movie7's late frames 575 -> 1330)
	bsr.w   dl_oinit
.oi:
	endif
	bra.w   dl_step
	RSTUB   1
	RSTUB   2
	RSTUB   3
	RSTUB   4
	RSTUB   5
	RSTUB   7
	RSTUB   8
.no:	bra.w   dl_stopno
	ifne DL_SPLIT
.r3w:	move.w  #3,DL_WHY
	addq.w  #1,DL_WHYN+2*3
	moveq   #0,d0
	rts
	endif

	ifne DL_SPLIT
; Z clear when the ring's only set is split and shown (its hole free).  Clobbers d0, a0.
dl_hready:
	cmpi.b  #1,HAL_SPR_ORDN
	bne.s   .n
	move.b  HAL_SPR_SPS,d0
	bmi.s   .n
	cmp.b   HAL_SPR_ORD,d0
	bne.s   .n
	ext.w   d0
	lea     HAL_SPR_ST,a0
	cmpi.b  #3,(a0,d0.w)
	bne.s   .n
	moveq   #1,d0                   ; Z clear
	rts
.n:	moveq   #0,d0                   ; Z set
	rts
	endif

	ifne DL_OOO
; dl_try: the matching out of order set up (the base d7, a1 its DL record).  Clobbers
; d0-d1, a0.
dl_oinit:
	st      DLR_OOO
	sf      DLR_PH0
	clr.w   DLR_BJ
	movea.l DLR_A4,a0
	moveq   #0,d0
	move.b  T_NXT(a0),d0
	move.w  d0,DLR_BNXT
	moveq   #-1,d0
	lea     DL_HASH,a0
	rept 8
	move.l  d0,(a0)+
	endr
	lea     DL_MINC,a0
	rept 17
	move.l  d0,(a0)+
	endr
	move.w  d0,(a0)
	lea     DL_LCOV,a0
	moveq   #0,d0
	move.l  d0,(a0)+
	move.l  d0,(a0)+
	move.l  d0,(a0)+
	move.w  d0,(a0)
	clr.w   DLR_LKN
	move.w  d7,d0                   ; room: below the set's end, or the hole
	add.w   d0,d0
	lea     HAL_SPR_END,a0
	move.w  (a0,d0.w),d1
	subi.w  #SPR_PB,d1
	move.w  #SPR_PB,DLR_SPG
	tst.b   DLR_HOLE
	beq.s   .r
	move.w  HAL_SPR_SPJ,d1
	sub.w   HAL_SPR_SPG,d1
	subq.w  #1,d1
	move.w  HAL_SPR_SPG,DLR_SPG
.r:	move.w  d1,DLR_ROOM
	rts
	endif

; The matching on: d0 as dl_try.  Clobbers d0-d7, a0-a6.
dl_step:
	move.w  HAL_FRAMES+2,d0         ; (the same slot, the base still the newest set,
	cmp.w   DLR_SLOT,d0             ; shown or complete, no update converting, the
	ifeq DL_SPLIT                   ; pending one as it was)
	bne.w   dl_stopno
	else
	beq.s   .sl
	sf      DLR_ON                  ; (an earlier slot's matching: a new try - else the
	bra.w   dl_try                  ; set began then, the split base's hole moment lost)
.sl:
	endif
	tst.b   FX_DELTA
	bne.w   dl_stopno
	move.w  DLR_BASE,d7
	moveq   #0,d0
	move.b  HAL_SPR_ORDN,d0
	beq.w   dl_stopno
	lea     HAL_SPR_ORD,a0
	cmp.b   -1(a0,d0.w),d7
	bne.w   dl_stopno
	lea     HAL_SPR_ST,a0
	move.b  (a0,d7.w),d0
	cmpi.b  #3,d0
	beq.s   .s3
	cmpi.b  #1,d0
	bne.w   dl_stopno
.s3:	tst.b   DL_BP
	beq.s   .p0
	tst.b   FX_PON
	beq.w   dl_stopno
	bra.s   .ok
.p0:	tst.b   FX_PON
	beq.s   .ok
	cmp.w   DLP+D_BASE,d7
	beq.w   dl_stopno
.ok:	move.w  d7,d0
	jsr     hal_spr_set
	ifne DL_OOO
	tst.b   DLR_OOO
	bne.w   dl_ostep
	endif
	tst.b   DLR_DONE
	bne.w   dl_fin
	move.w  DLR_N,d5
	move.w  DLR_E,d3
	move.w  DLR_J,d2
	move.w  DLR_H,d1
	movea.l DLR_A2,a2
	movea.l DLR_A3,a3
	movea.l DLR_A0,a0
	movea.l DLR_A1,a1
	movea.l DLR_A4,a4
dl_chunk:
	cmp.w   d5,d3                   ; (all matched)
	bhs.w   .end
	move.w  d2,-(sp)                ; time for DL_STEP more
	jsr     hal_spr_klim
	addq.w  #DL_STEPL,d0
	tst.w   HAL_SPR_TAILU
	beq.s   .tu
	addq.w  #3,d0
.tu:	movem.w (sp)+,d2                ; (keeps the flags of a tst: test again)
	tst.w   d0
	ble.s   .go
	bsr.w   dl_save                 ; no: on in a later call
	moveq   #2,d0
	rts
.go:	move.w  d3,d0
	addq.w  #DL_STEP,d0
	cmp.w   d5,d0
	bls.s   .l
	move.w  d5,d0
.l:	move.w  d0,DLR_LIM
.k:	; in view (as hal_spr_go decides)?
	sf      DLR_VIEW
	move.w  (a3),d0
	andi.w  #$1ff,d0
	cmpi.w  #224,d0
	blo.s   .vy
	move.w  (a3),d4
	andi.w  #$0e00,d4
	lsr.w   #5,d4
	add.w   d0,d4
	cmpi.w  #512-16,d4
	bls.s   .vd
.vy:	move.w  2(a3),d0
	andi.w  #$1ff,d0
	cmpi.w  #320,d0
	blo.s   .vi
	move.w  2(a3),d4
	andi.w  #$0e00,d4
	lsr.w   #5,d4
	add.w   d0,d4
	cmpi.w  #512-16,d4
	bls.s   .vd
.vi:	st      DLR_VIEW
.vd:	; looked for among the base's next DL_LOOK entries
	move.w  d2,d4
	addq.w  #DL_LOOK,d4
	cmp.w   DLR_NB,d4
	bls.s   .le
	move.w  DLR_NB,d4
.le:	lsl.w   #3,d4
	lea     (a2,d4.w),a5
	move.l  a5,DLR_SEND
	move.w  d2,d0
	lsl.w   #3,d0
	lea     (a2,d0.w),a5
.s:	cmpa.l  DLR_SEND,a5
	bhs.w   .new
	move.l  4(a5),d0                ; w2, w3
	cmp.l   4(a3),d0
	bne.s   .sn
	move.l  (a5),d6                 ; w0, w1: sizes and zoom
	move.l  (a3),d0
	eor.l   d6,d0
	andi.l  #$fe00fe00,d0
	beq.s   .fd
.sn:	addq.l  #8,a5
	bra.s   .s
.fd:	move.l  a5,d6
	sub.l   a2,d6
	lsr.w   #3,d6                   ; t
	move.w  d6,d2                   ; found: the base passed up to it
	addq.w  #1,d2
	move.w  d6,d0
	cmp.b   T_FIN(a4),d0            ; its head slot
	bhs.s   .tg
	move.b  (a4,d0.w),d0
	bra.s   .tgd
.tg:	bsr.w   dl_tget
.tgd:
	cmpi.w  #$fe,d0
	bhs.w   .new                    ; (none: out of view or dropped then)
	cmpi.w  #DL_HXN,d1
	bhs.w   .dem                    ; (no room for more kept heads)
	tst.b   DLR_ID
	beq.s   .ip
	cmp.w   d1,d0                   ; (the base's slots stay: its next only)
	bne.w   .dem
.ip:	move.w  d0,d6                   ; d6 = its base slot
	tst.b   DLR_VIEW
	beq.s   .kp                     ; (out of view: no order)
	tst.b   DLR_NV
	beq.s   .nc
	bsr.w   dl_cells
	beq.s   .nc
	tst.b   DLR_NV                  ; under a new one before it?
	beq.s   .nc
	bsr.w   dl_ncov
	bne.w   .dem
.nc:	move.w  d6,d0                   ; in front of the kept ones before it (their
	add.w   d0,d0                   ; columns higher)?
	move.w  SS_HADR(a6,d0.w),d0
	cmp.w   DLR_MINC,d0
	bhs.w   .dem
	move.w  d0,DLR_MINC
.kp:	cmp.w   d1,d6                   ; kept (another slot: moved in dl_fin)
	beq.s   .ks
	st      DLR_PERM
.ks:	lea     DL_KS,a5
	move.b  d6,(a5,d1.w)
	move.w  d6,d0
	lsr.w   #3,d0
	lea     DL_USED,a5
	bset    d6,(a5,d0.w)
	movea.l DLR_CT,a5
	move.b  d1,(a5,d3.w)            ; (its slot after the flip)
	bsr.w   dl_cols
	add.w   d0,DLR_K
	move.w  d6,d0                   ; head: SCB3 = (496 - oy) << 7 | its height
	add.w   d0,d0
	cmp.w   DLR_PK,d6               ; (a pending update's kept head: its height there)
	bhs.s   .hs
	movea.l DLR_PH,a5
	bra.s   .hh
.hs:	lea     SS_HVAL(a6),a5
.hh:	moveq   #$3f,d4
	and.w   (a5,d0.w),d4
	tst.b   DLR_VIEW
	beq.s   .ho
	move.w  (a3),d0
	neg.w   d0
	addi.w  #496,d0
	lsl.w   #7,d0
	add.w   d4,d0
	move.w  d0,(a0)+
	move.w  2(a3),d0                ; SCB4: ox << 7
	lsl.w   #7,d0
	move.w  d0,(a1)+
	bra.s   .hn
.ho:	addi.w  #((496-DL_OFFY)&511)<<7,d4      ; out of view now: below the screen
	addq.w  #1,DLR_OFF
	move.w  d4,(a0)+
	addq.l  #2,a1
.hn:	addq.w  #1,d1
	bra.s   .nx
.dem:	tst.b   DLR_ID                  ; a base head not kept (its slots stay: all must
	bne.w   dl_abort                ; be kept - none now)
.new:	move.w  d2,d0                   ; (the base's entries passed but not kept: more
	sub.w   d1,d0                   ; than 1/4 of its heads + 8 - no update)
	move.w  DL_BH2,d4
	lsr.w   #3,d4
	addq.w  #8,d4
	cmp.w   d4,d0
	bhi.w   dl_abort
	movea.l DLR_CT,a5               ; not kept: converted
	st      (a5,d3.w)
	tst.w   DLR_F1
	bpl.s   .f1
	move.w  d3,DLR_F1
.f1:	tst.b   DLR_PRESS               ; (the cheap update: the rest not kept either)
	bne.s   .f2
	bsr.w   dl_cols
	add.w   d0,DLR_R
	addq.w  #1,d3
	addq.l  #8,a3
	move.w  d3,DLR_RS
	bra.w   .end
.f2:	tst.b   DLR_VIEW
	beq.s   .nx
	bsr.w   dl_cols
	add.w   d0,DLR_R
	bsr.w   dl_cells
	beq.s   .nx
	bsr.w   dl_ncovset
	st      DLR_NV
.nx:	addq.l  #8,a3
	addq.w  #1,d3
	cmp.w   DLR_LIM,d3
	blo.w   .k
	bra.w   dl_chunk
.end:	st      DLR_DONE
	bsr.w   dl_save
	bra.w   dl_fin

	ifne DL_OOO
; The matching out of order (dl_step, a6 the base's state, d7 the base): the base list
; indexed, then DL_OSTEP entries per time check; all matched: dl_ofin.  d0 as dl_try.
; Clobbers d0-d7, a0-a6.
dl_ostep:
	tst.b   DLR_DONE
	bne.w   dl_ofin
	move.w  DLR_N,d5
	move.w  DLR_E,d3
	move.w  DLR_H,d1
	movea.l DLR_A2,a2
	movea.l DLR_A3,a3
.ch:	jsr     hal_spr_klim            ; time for DL_OSTEP more?
	addq.w  #DL_OSTEPL,d0
	tst.w   HAL_SPR_TAILU
	beq.s   .tu
	addq.w  #3,d0
.tu:	tst.w   d0
	ble.s   .go
	bsr.s   dl_osave                ; no: on in a later call
	moveq   #2,d0
	rts
.go:	tst.b   DLR_PH0
	bne.s   .m
	bsr.w   dl_oindex
	bne.s   .ch
	st      DLR_PH0
	bra.s   .ch
.m:	cmp.w   d5,d3
	bhs.s   .end
	move.w  d3,d0
	addq.w  #DL_OSTEP,d0
	cmp.w   d5,d0
	bls.s   .l
	move.w  d5,d0
.l:	move.w  d0,DLR_LIM
.k:	bsr.w   dl_oent
	bmi.w   dl_stopno               ; (DL_WHY 16: no room, 17: no time for dl_odem)
	addq.l  #8,a3
	addq.w  #1,d3
	cmp.w   DLR_LIM,d3
	blo.s   .k
	bra.s   .ch
.end:	st      DLR_DONE
	bsr.s   dl_osave
	bra.w   dl_ofin
dl_osave:
	move.w  d3,DLR_E
	move.w  d1,DLR_H
	move.l  a3,DLR_A3
	rts

; DL_ISTEP more base entries (a2 its list) indexed: per entry its head slot (the entry
; table's, as dl_tget gives them) in DL_BSL, those with one chained by hash.  Z set:
; all.  Keeps d1, d3, d5, d7, a2, a3, a6.
dl_oindex:
	movem.l d1/d3,-(sp)
	movea.l DLR_A4,a4
	moveq   #0,d2
	move.b  T_FIN(a4),d2
	move.w  DL_BH2,d6
	lsr.w   #1,d6                   ; its heads
	lea     DL_BSL,a1
	lea     DL_HASH,a5
	lea     DL_NEXT,a0
	move.w  DLR_BJ,d3
	move.w  d3,d4
	addi.w  #DL_ISTEP,d4
	cmp.w   DLR_NB,d4
	bls.s   .c
	move.w  DLR_NB,d4
	bra.s   .c
.l:	moveq   #0,d0
	move.b  (a4,d3.w),d0
	cmp.w   d2,d3                   ; (given already)
	blo.s   .g
	cmpi.b  #$ff,d0                 ; (converted: the next slot)
	bne.s   .g
	move.w  DLR_BNXT,d0
	addq.w  #1,DLR_BNXT
.g:	cmp.w   d6,d0
	bhs.s   .no                     ; ($fe: none)
	move.b  d0,(a1,d3.w)
	move.w  d3,d0
	lsl.w   #3,d0
	moveq   #$1f,d1
	and.b   7(a2,d0.w),d1
	move.b  (a5,d1.w),(a0,d3.w)
	move.b  d3,(a5,d1.w)
	bra.s   .n
.no:	move.b  #$fe,(a1,d3.w)
.n:	addq.w  #1,d3
.c:	cmp.w   d4,d3
	blo.s   .l
	move.w  d3,DLR_BJ
	movem.l (sp)+,d1/d3
	move.w  DLR_BJ,d0
	cmp.w   DLR_NB,d0               ; (Z: all)
	rts

; New entry d3 at a3 (d1 heads kept so far, in/out): kept (DLR_CT: its base slot) or
; converted ($ff).  N set: no update (no room, or no time for dl_odem).  Keeps d3, d5,
; d7, a2, a3, a6.
dl_oent:
	movem.l d3/d5/d7,-(sp)
	move.w  d3,DLR_EI
	sf      DLR_VIEW
	sf      DLR_CELL
	move.w  #$ff,d6                 ; d6: the floor ($ff: none), d2: under a new one
	moveq   #0,d2
	bsr.w   dl_vis
	beq.s   .nv
	st      DLR_VIEW
	bsr.w   dl_cells
	beq.s   .nv
	st      DLR_CELL
	bsr.w   dl_ofloor
	bsr.w   dl_ncov
	sne     d2
.nv:	move.l  (a3),d0                 ; its sizes and zoom
	andi.l  #$fe00fe00,d0
	move.l  d0,DLR_BW
	moveq   #$1f,d0                 ; its chain
	and.b   7(a3),d0
	lea     DL_HASH,a0
	moveq   #0,d4
	move.b  (a0,d0.w),d4
	lea     DL_NEXT,a0
	lea     DL_BSL,a1
	moveq   #-1,d5                  ; d5: the best base entry, d7 its column
	moveq   #-1,d7
	moveq   #DL_CMAX-1,d3
.cl:	cmpi.b  #$ff,d4
	beq.w   .ce
	moveq   #0,d0
	move.b  (a1,d4.w),d0
	cmpi.b  #$fe,d0                 ; (no head, or kept already)
	bhs.s   .cn
	move.w  d4,d0
	lsl.w   #3,d0
	lea     (a2,d0.w),a4
	move.l  4(a4),d0                ; w2, w3
	cmp.l   4(a3),d0
	bne.s   .cn
	move.l  (a4),d0
	andi.l  #$fe00fe00,d0
	cmp.l   DLR_BW,d0
	bne.s   .cn
	moveq   #0,d0                   ; its column
	move.b  (a1,d4.w),d0
	add.w   d0,d0
	move.w  SS_HADR(a6,d0.w),d0
	subi.w  #SCB3,d0
	tst.b   DLR_CELL
	beq.s   .ok                     ; (no cells: no order)
	movea.w d0,a5
	subi.w  #DL_C0,d0
	lsr.w   #1,d0
	cmp.w   d6,d0                   ; (under a kept one before it)
	bhs.s   .cn
	move.w  a5,d0
	ifne DL_SPLIT
	tst.b   DLR_HOLE                ; (the lower run's: no more than DL_LKMAX kept, their
	beq.s   .lk                     ; cells recorded for dl_odem)
	cmp.w   DLR_SPG,d0
	bhs.s   .lk
	cmpi.w  #DL_LKMAX,DLR_LKN
	bhs.s   .cn
.lk:
	endif
	tst.b   d2
	beq.s   .ok
	tst.b   DLR_HOLE                ; (under a new one before it: in the lower run only)
	beq.s   .cn
	cmp.w   DLR_SPG,d0
	bhs.s   .cn
.ok:	cmp.w   d7,d0                   ; (the highest column)
	ble.s   .cn
	move.w  d0,d7
	move.w  d4,d5
.cn:	move.b  (a0,d4.w),d4
	dbra    d3,.cl
.ce:	movea.l DLR_CT,a5
	move.w  2(sp),d0                ; (the entry's number)
	tst.w   d5
	bmi.s   .new
	cmpi.w  #DL_HXN,d1
	bhs.s   .new
	move.b  (a1,d5.w),(a5,d0.w)     ; kept: its base slot
	move.b  #$fe,(a1,d5.w)
	addq.w  #1,d1
	tst.b   DLR_CELL
	beq.s   .x
	move.w  d7,d0
	bsr.w   dl_ominc
	bra.s   .x
.new:	st      (a5,d0.w)
	tst.b   DLR_VIEW
	beq.s   .x
	bsr.w   dl_cols
	add.w   d0,DLR_R
	move.w  DLR_R,d0
	cmp.w   DLR_ROOM,d0
	bhi.s   .ar                     ; (no room for them)
	tst.b   DLR_CELL
	beq.s   .x
	ifne DL_SPLIT
	tst.b   DLR_HOLE
	beq.s   .ns
	bsr.w   dl_olcov                ; under a kept one of the lower run before it?
	beq.s   .ns
	bsr.w   dl_ncovset
	move.w  2(sp),d0
	bsr.w   dl_odem                 ; (those new too)
	bmi.s   .ab
	bra.s   .x
	endif
.ns:	bsr.w   dl_ncovset
.x:	movem.l (sp)+,d3/d5/d7
	moveq   #0,d0                   ; (N clear)
	rts
.ar:	move.w  #16,DL_WHY              ; (no room)
	bra.s   .ax
.ab:	move.w  #17,DL_WHY              ; (dl_odem: no room, or no time)
.ax:	movem.l (sp)+,d3/d5/d7
	moveq   #-1,d0                  ; N set
	rts

; d6 = the lowest kept column ((column - DL_C0) / 2) over the entry's cells (dl_cells),
; $ff none.  Clobbers d0, d4, a0, a1.
dl_ofloor:
	move.l  d2,-(sp)
	lea     DL_MINC,a0
	move.w  DLR_CY0,d0
	move.w  d0,d4
	lsl.w   #2,d4
	add.w   d0,d4
	add.w   d4,d4                   ; (x 10)
	add.w   DLR_CX0,d4
	adda.w  d4,a0
	move.w  DLR_CY1,d2
	sub.w   d0,d2
	move.w  DLR_CX1,d0
	sub.w   DLR_CX0,d0
	move.w  #$ff,d6
.r:	movea.l a0,a1
	move.w  d0,d4
.c:	cmp.b   (a1)+,d6
	bls.s   .k
	move.b  -1(a1),d6
.k:	dbra    d4,.c
	lea     10(a0),a0
	dbra    d2,.r
	move.l  (sp)+,d2
	rts

; Kept at column d0 over the entry's cells (dl_cells): DL_MINC, and DL_LCOV if in the
; lower run (DL_SPLIT).  Clobbers d0, d2, d4, a0, a1.
dl_ominc:
	move.w  d0,-(sp)
	subi.w  #DL_C0,d0
	lsr.w   #1,d0
	lea     DL_MINC,a0
	move.w  DLR_CY0,d2
	move.w  d2,d4
	lsl.w   #2,d4
	add.w   d2,d4
	add.w   d4,d4
	add.w   DLR_CX0,d4
	adda.w  d4,a0
	move.w  DLR_CY1,d2
	sub.w   DLR_CY0,d2
.r:	movea.l a0,a1
	move.w  DLR_CX1,d4
	sub.w   DLR_CX0,d4
.c:	cmp.b   (a1)+,d0
	bhs.s   .k
	move.b  d0,-1(a1)
.k:	dbra    d4,.c
	lea     10(a0),a0
	dbra    d2,.r
	move.w  (sp)+,d0
	ifne DL_SPLIT
	tst.b   DLR_HOLE
	beq.s   .x
	cmp.w   DLR_SPG,d0
	bhs.s   .x
	move.w  DLR_LKN,d0              ; (its record)
	addq.w  #1,DLR_LKN
	lsl.w   #2,d0
	lea     DL_LKC,a0
	adda.w  d0,a0
	move.b  DLR_EI+1,(a0)+
	move.b  DLR_CY0+1,d0
	lsl.b   #4,d0
	or.b    DLR_CY1+1,d0
	move.b  d0,(a0)+
	move.w  DLR_CM,(a0)
	lea     DL_LCOV,a0
	bra.w   dl_cset
	endif
.x:	rts

	ifne DL_SPLIT
; Z clear when a cell of the entry (dl_cells) has a kept one of the lower run.  Clobbers
; d0, d4.
dl_olcov:
	move.l  a5,-(sp)
	lea     DL_LCOV,a5
	bsr.s   dl_ctst
	movem.l (sp)+,a5                ; (keeps the flags)
	rts
; DLR_CM over the entry's rows of the cell rows at a0 (or).  Clobbers d0, d4, a0.
dl_cset:
	move.w  DLR_CY0,d0
	move.w  DLR_CY1,d4
	sub.w   d0,d4
	add.w   d0,d0
	adda.w  d0,a0
	move.w  DLR_CM,d0
.r:	or.w    d0,(a0)+
	dbra    d4,.r
	rts
; Z clear when a cell of the entry (dl_cells) is set in the cell rows at a5.  Clobbers
; d0, d4, a5.
dl_ctst:
	movem.l d1,-(sp)
	move.w  DLR_CY0,d0
	move.w  DLR_CY1,d4
	sub.w   d0,d4
	add.w   d0,d0
	adda.w  d0,a5
	move.w  DLR_CM,d0
.r:	move.w  (a5)+,d1
	and.w   d0,d1
	dbne    d4,.r
	movem.l (sp)+,d1                ; (keeps the flags)
	rts

; New entry d0 (its cells in DLR_C*, DL_NCOV marked) under a kept one of the lower run
; before it: the kept ones of the lower run before it over its cells, and over theirs
; (on to the front), converted too (DLR_CT $ff, d1 one less, their columns to DLR_R) -
; from their records (DL_LKC, ~70 cycles each).  N set: no room.  Clobbers d0, d2, d4,
; d6, a0, a1, a4, a5.
dl_odem:
	lea     DL_DMSK,a0
	moveq   #0,d0
	move.l  d0,(a0)+
	move.l  d0,(a0)+
	move.l  d0,(a0)+
	move.w  d0,(a0)
	lea     DL_DMSK,a0
	bsr.s   dl_cset
	move.w  DLR_LKN,d6
	lsl.w   #2,d6
	lea     DL_LKC,a4
	adda.w  d6,a4                   ; (the last record first: on to the front)
	lsr.w   #2,d6
	bra.w   .c
.l:	subq.l  #4,a4
	moveq   #0,d2
	move.b  (a4),d2                 ; its entry: still kept?
	movea.l DLR_CT,a5
	cmpi.b  #$fe,(a5,d2.w)
	bhs.s   .c
	moveq   #0,d0
	move.b  1(a4),d0
	move.w  d0,d4
	lsr.w   #4,d0
	move.w  d0,DLR_CY0
	andi.w  #$f,d4
	move.w  d4,DLR_CY1
	move.w  2(a4),DLR_CM
	lea     DL_DMSK,a5
	bsr.w   dl_ctst                 ; over the cells demoted?
	beq.s   .c
	movea.l DLR_CT,a5
	st      (a5,d2.w)
	subq.w  #1,d1
	move.l  a3,-(sp)
	movea.l FX_CL,a3
	lsl.w   #3,d2
	adda.w  d2,a3
	bsr.w   dl_cols
	movea.l (sp)+,a3
	add.w   d0,DLR_R
	move.w  DLR_R,d0
	cmp.w   DLR_ROOM,d0
	bhi.s   .no
	bsr.w   dl_ncovset
	lea     DL_DMSK,a0
	bsr.w   dl_cset
.c:	dbra    d6,.l
	moveq   #0,d0
	rts
.no:	moveq   #-1,d0
	rts
	endif

; All matched out of order: the kept ones' arrays (DL_KS, DL_USED, DA_HV/DA_HX in the
; new list's order, their new slots in DLR_CT), DLR_K, DLR_OFF, DLR_F1, DLR_PERM, then
; dl_fin (its time counted here: this is not done twice).  d0 as dl_try.
dl_ofin:
	move.w  DLR_N,d0                ; time: ~130 cycles an entry + dl_fin's
	mulu    #130,d0
	move.w  DL_BH2,d1
	lsr.w   #1,d1
	mulu    #90,d1
	add.l   d1,d0
	addi.l  #1000+767,d0
	divu    #768,d0
	move.w  d0,-(sp)
	jsr     hal_spr_klim
	add.w   (sp)+,d0
	tst.w   HAL_SPR_TAILU
	beq.s   .tu
	addq.w  #3,d0
.tu:	tst.w   d0
	ble.s   .go
	moveq   #2,d0                   ; (on in a later call)
	rts
.go:	movea.l DLR_CT,a5
	movea.l FX_CL,a3
	movea.l DLC+D_ARR,a0
	lea     DA_HX(a0),a1
	lea     DL_KS,a4
	clr.w   DLR_K
	clr.w   DLR_OFF
	sf      DLR_PERM
	move.w  #-1,DLR_F1
	moveq   #0,d1                   ; kept
	moveq   #0,d3                   ; the entry
	bra.w   .c
.l:	moveq   #0,d6
	move.b  (a5,d3.w),d6            ; its base slot, or $ff
	cmpi.w  #$fe,d6
	bhs.s   .nk
	move.b  d6,(a4,d1.w)
	move.w  d6,d0
	lsr.w   #3,d0
	lea     DL_USED,a2
	bset    d6,(a2,d0.w)
	move.b  d1,(a5,d3.w)            ; (its slot after the flip)
	cmp.w   d1,d6
	beq.s   .p
	st      DLR_PERM
.p:	bsr.w   dl_cols
	add.w   d0,DLR_K
	bsr.w   dl_vis
	sne     d2
	move.w  d6,d0                   ; head: SCB3 = (496 - oy) << 7 | its height
	add.w   d0,d0
	cmp.w   DLR_PK,d6               ; (a pending update's kept head: its height there)
	bhs.s   .hs
	movea.l DLR_PH,a2
	bra.s   .hh
.hs:	lea     SS_HVAL(a6),a2
.hh:	moveq   #$3f,d4
	and.w   (a2,d0.w),d4
	tst.b   d2
	beq.s   .ho
	move.w  (a3),d0
	neg.w   d0
	addi.w  #496,d0
	lsl.w   #7,d0
	add.w   d4,d0
	move.w  d0,(a0)+
	move.w  2(a3),d0                ; SCB4: ox << 7
	lsl.w   #7,d0
	move.w  d0,(a1)+
	bra.s   .hn
.ho:	addi.w  #((496-DL_OFFY)&511)<<7,d4      ; out of view now: below the screen
	addq.w  #1,DLR_OFF
	move.w  d4,(a0)+
	addq.l  #2,a1
.hn:	addq.w  #1,d1
	bra.s   .nx
.nk:	tst.w   DLR_F1
	bpl.s   .nx
	move.w  d3,DLR_F1
.nx:	addq.l  #8,a3
	addq.w  #1,d3
.c:	cmp.w   DLR_N,d3
	blo.w   .l
	move.w  d1,DLR_H
	move.w  DLR_N,DLR_RS
	bra.w   dl_fin_go
	endif

; The matching's registers kept for a later call.
dl_save:
	move.w  d3,DLR_E
	move.w  d2,DLR_J
	move.w  d1,DLR_H
	move.l  a3,DLR_A3
	move.l  a0,DLR_A0
	move.l  a1,DLR_A1
	rts

; All matched (a6 = the base's state, d7 the base): the update's rules, its arrays, its
; conversion begun.  d0 as dl_try.  Clobbers d0-d7, a0-a6.
dl_fin:
	move.w  DL_BH2,d0               ; time: ~150 cycles a base head, ~100 an entry not
	lsr.w   #1,d0                   ; kept after the cheap update's end, + ~1000
	mulu    #90,d0
	move.w  DLR_N,d1
	sub.w   DLR_RS,d1
	mulu    #100,d1
	add.l   d1,d0
	addi.l  #1000+767,d0
	divu    #768,d0
	move.w  d0,-(sp)
	jsr     hal_spr_klim
	add.w   (sp)+,d0
	tst.w   HAL_SPR_TAILU
	beq.s   .tu
	addq.w  #3,d0
.tu:	tst.w   d0
	ble.s   .go
	moveq   #2,d0                   ; (on in a later call)
	rts
.go:
dl_fin_go:
	sf      DLR_ON
	movea.l DLR_CT,a0               ; (the cheap update's rest: not kept)
	movea.l FX_CL,a3
	move.w  DLR_RS,d0
	move.w  d0,d1
	lsl.w   #3,d1
	adda.w  d1,a3
	move.w  DLR_R,d2
	bra.s   .rc
.rl:	st      (a0,d0.w)
	move.w  2(a3),d1
	rol.w   #7,d1
	andi.w  #7,d1
	addq.w  #1,d1
	add.w   d1,d2
	addq.l  #8,a3
	addq.w  #1,d0
.rc:	cmp.w   DLR_N,d0
	blo.s   .rl
	move.w  d2,DLR_R
	move.w  DLR_H,d1                ; d1 = heads kept
	beq.w   .r13
	move.w  DL_BH2,d0
	lsr.w   #1,d0                   ; the base's heads
	cmp.w   d0,d1
	bhi.w   .r9
	move.w  d0,d4
	sub.w   d1,d4                   ; d4 = its heads not kept (hidden)
	beq.s   .ka
	tst.b   DLR_ID                  ; (its slots stay: all kept)
	bne.w   .r10
	ifne DL_SPLIT
	tst.b   DLR_HOLE                ; (a split base: the hole's room the only limit -
	bne.s   .hn                     ; else a new set, in that room, drops)
	endif
	move.w  d4,d2                   ; and 3/4 of its heads kept
	lsl.w   #2,d2
	cmp.w   d0,d2
	bhi.w   .r11
	ifne DL_SPLIT
.hn:
	endif
	cmpi.w  #DL_HIDEN,d4
	bhi.w   .r12
.ka:
	ifne DL_SPLIT
	tst.b   DLR_HOLE                ; (the hole's room)
	beq.s   .kn
	move.w  DLR_R,d6
	cmp.w   DLR_ROOM,d6
	bhi.w   .r6
	bra.w   .gk
.kn:
	endif
	DLREC   d7
	moveq   #0,d0                   ; columns idle in the set after it: no more than
	move.b  DL_DEAD(a1),d0          ; 1/4 of its kept heads' (else a new set: the
	add.w   d4,d0                   ; ring gets them back)
	add.w   DLR_OFF,d0
	lsl.w   #2,d0
	cmp.w   d1,d0
	bhi.w   .r14
	; the set grows by the entries not kept (below its end; the columns of the heads
	; hidden idle until it is reclaimed): only with room for them there (else its back
	; sprites drop), and with the ring left room for a new set of the list after it
	; (else the next list that is not an update finds none: growing sets filled the
	; ring and dropped the city's buildings, 2026-10-14) - unless that is so already
	move.w  DLR_R,d6
	move.w  d7,d0
	add.w   d0,d0
	lea     HAL_SPR_END,a0
	move.w  (a0,d0.w),d5            ; (the next free column)
	lea     HAL_SPR_START,a0
	move.w  (a0,d0.w),d0
	sub.w   d5,d0                   ; d0 = its columns now
	ifne DL_CW
	move.w  d0,d2                   ; (DL_CW: its idle columns - hidden heads', out of
	sub.w   DLR_K,d2                ; view - no more than 1/4 of what it shows after
	lsl.w   #2,d2                   ; the update + DL_CWS: else a new set, compact)
	move.w  DLR_K,d3
	add.w   d6,d3
	addi.w  #4*DL_CWS,d3
	cmp.w   d3,d2
	bhi.w   .r6
	endif
	subi.w  #SPR_PB,d5              ; room below it
	cmp.w   d5,d6
	bhi.w   .r6
	add.w   DLR_K,d0
	add.w   d6,d0                   ; + a new set of the list
	cmpi.w  #SPR_POOL-DL_SLACK,d0
	bhi.s   .gk                     ; (no room for that already)
	add.w   d6,d0
	cmpi.w  #SPR_POOL-DL_SLACK,d0
	bhi.w   .r6
.gk:	; the base's heads not kept: hidden at the flip
	movea.l DLC+D_ARR,a2
	lea     DA_HIDE(a2),a2
	lea     SS_HADR(a6),a0
	lea     DL_USED,a1
	move.w  DL_BH2,d2
	lsr.w   #1,d2
	moveq   #0,d0
	bra.s   .uc
.ul:	move.w  d0,d3
	lsr.w   #3,d3
	moveq   #7,d5
	and.w   d0,d5
	bne.s   .ub
	cmpi.b  #$ff,(a1,d3.w)          ; (eight kept: on)
	bne.s   .ub
	addq.w  #8,d0
	lea     16(a0),a0
	bra.s   .uc
.ub:	btst    d0,(a1,d3.w)
	bne.s   .un
	move.w  (a0),(a2)+
.un:	addq.l  #2,a0
	addq.w  #1,d0
.uc:	cmp.w   d2,d0
	blo.s   .ul
	; the kept heads to the first slots, in the new list's order (its slots stay:
	; there already)
	tst.b   DLR_PERM                ; (in their slots already: as they are)
	beq.s   .np
	lea     DL_KS,a1
	lea     DL_TA,a2
	lea     SS_HADR(a6),a0
	move.w  d1,d2
	subq.w  #1,d2
.p1:	moveq   #0,d0
	move.b  (a1)+,d0
	add.w   d0,d0
	move.w  (a0,d0.w),(a2)+
	dbra    d2,.p1
	lea     DL_TA,a2
	move.w  d1,d2
	subq.w  #1,d2
.p2:	move.w  (a2)+,(a0)+
	dbra    d2,.p2
.np:	move.w  d4,DLC+D_HIDE
	move.w  d1,DLC+D_KEPT
	move.w  d1,d0
	add.w   d0,d0
	move.w  d0,DLC+D_HOFF
	move.w  d7,DLC+D_BASE
	move.w  FX_CI,DLC+D_BUF
	movea.l DLR_CT,a0               ; its table: the converted entries' slots after
	clr.b   T_FIN(a0)               ; the kept ones
	move.b  d1,T_NXT(a0)
	st      T_OK(a0)
	move.b  DLR_N+1,T_N(a0)
	move.l  a0,FX_KTAB
	move.b  #1,FX_DELTA             ; converted in the base from the first entry not
	move.w  d7,HAL_SPR_W            ; kept (the kept ones skipped: hal_spr_go)
	st      HAL_SPR_DONE
	move.w  HAL_FRAMES+2,d1         ; shown from the next slot on
	addq.w  #1,d1
	move.w  d1,FX_DRDY
	move.w  DLR_F1,d0
	bpl.s   .f1
	move.w  DLR_N,d0                ; (none: nothing to convert)
.f1:	movea.l FX_CL,a0                ; (hal_spr_go: a5 the entry itself)
	lsl.w   #3,d0
	adda.w  d0,a0
	move.l  a0,HAL_SPR_RA5
	move.l  FX_CL,HAL_SPR_LEND
	addq.l  #1,HAL_SPR_DELTAN
	sf      DL_FAILS
	ifne DL_EXPB
	sf      DL_BOFF
	endif
	ifne DL_SPLIT
	tst.b   DLR_HOLE                ; (into the hole: from the top run's end down to
	beq.s   .nh                     ; the guard - hal_spr_lim; hal/spr.s .hoff moves
	st      DL_HOLEC                ; SPJ, dl_done gives the set its end back)
	move.w  HAL_SPR_SPJ,SS_HNEXT(a6)
.nh:
	endif
	moveq   #1,d0
	rts
.no:	moveq   #0,d0
	rts
	RSTUB   6
	RSTUB   9
	RSTUB   10
	RSTUB   11
	RSTUB   12
	RSTUB   13
	RSTUB   14
dl_stopno:
	sf      DLR_ON
	addq.b  #1,DL_FAILS             ; (the back-off)
	cmpi.b  #DL_FAILMAX,DL_FAILS
	blo.s   .b
	sf      DL_FAILS
	ifne DL_EXPB
	move.b  DL_BOFF,d0              ; (0: none in a row yet)
	bne.s   .e
	moveq   #DL_BACKOFF,d0
.e:	move.b  d0,DL_SKIPN
	add.b   d0,d0
	cmpi.b  #DL_BOMAX,d0
	bls.s   .e2
	moveq   #DL_BOMAX,d0
.e2:	move.b  d0,DL_BOFF
	else
	move.b  #DL_BACKOFF,DL_SKIPN
	endif
.b:
	moveq   #0,d0
	rts
dl_abort:
	move.w  #15,DL_WHY              ; (diagnostics: no use going on)
	bra.s   dl_stopno

	ifne SPR_SHARE
; Back-suffix sharing (SPR_SHARE, 2026-10-16).  In the dense scenes the ring is split:
; the shown set S has its top run at the top and its lower run at SPR_PB, the hole
; between them free; the next set N, begun in the hole, needs a few more columns than it
; has (two sets of a dense list do not fit 338) and drops its back entries.  But the back
; entries of N's list are mostly S's again (the ground's buildings, moved): N takes S's
; lower run over for them - from the list's back, in order (SH_LOOK on in S), each the
; same shape, zoom, attributes and tiles as an S entry of the lower run - converting only
; the entries before that suffix into the hole.  At N's flip (sh_flip, after S's heads
; are hidden) the shared heads get N's positions and become N's: N is the hole and the
; lower run (one run: the guard SPG inside it, 0), S its top run only, the ring not split.
; The shared sprites lie below every one N converts, as its back entries must, and in
; S's order, which is N's.  Nothing new begins and no update before N's flip (SH_ON).
SH_ON           equ FXS+$6f2        ; b: N shares S's lower run (till its flip)
SH_SET          equ FXS+$6f3        ; b: N
SH_N            equ FXS+$6f4        ; w: its entries shared
SH_END          equ FXS+$6f6        ; w: S's end (the lower run's)
SH_HL           equ FXS+$6f8        ; w: S's heads in its lower run
SH_CNT          equ FXS+$6fc        ; l: (diagnostics) shares flipped
SH_ARR          equ DL_ARR0         ; SH_MAX x 8 b: per shared one (from the list's back)
SH_MAX          equ 80              ; its head's SCB3 address, its SCB3 and SCB4 in N, its
                                    ; N entry, its S slot (DL_ARR0-1: no update meanwhile)
SH_TOP          equ FXS+$6fa        ; w: S's heads in its top run (its first ones)
SH_MARK         equ DL_TA           ; SS_MAXHEAD b: S's slots shared
SH_LOOK         equ 8               ; S entries looked at for each N entry
SH_LINES        equ 16              ; (~60 cycles an S entry, ~250 an N entry shared)
SH_SLACK        equ 4               ; (N's start: columns spare)
	if 8*SH_MAX>$400
	fail "SH_ARR"
	endif
	if SS_MAXHEAD>160
	fail "SH_MARK"
	endif

; hal_spr_work, set d7 (N, a6 its state) just begun, a5 its list's first entry: does it
; share the shown split set's lower run?  Keeps all.
sh_match:
	movem.l d0-d7/a0-a6,-(sp)
	tst.b   SH_ON
	bne.w   .x
	move.b  HAL_SPR_SPS,d6          ; d6 = S: split, the ring's oldest, shown; N the
	bmi.w   .x                      ; newest, begun at the hole's top; no update
	ext.w   d6
	cmpi.b  #2,HAL_SPR_ORDN
	bne.w   .x
	cmp.b   HAL_SPR_ORD,d6
	bne.w   .x
	cmp.b   HAL_SPR_ORD+1,d7
	bne.w   .x
	lea     HAL_SPR_ST,a0
	cmpi.b  #3,(a0,d6.w)
	bne.w   .x
	tst.b   FX_PON
	bne.w   .x
	tst.b   FX_DELTA
	bne.w   .x
	move.w  d7,d0
	add.w   d0,d0
	lea     HAL_SPR_START,a0
	move.w  (a0,d0.w),d0
	cmp.w   HAL_SPR_SPJ,d0
	bne.w   .x
	movea.l FX_CL,a0                ; only when N's list does not fit the hole (else it
	moveq   #SH_SLACK,d1            ; goes there as usual: N anchored low and nothing
	move.w  FX_BC8,d2               ; new before its flip delayed the light scenes'
	lsr.w   #3,d2                   ; next sets: movie7's late frames 543 -> 843)
	bra.s   .gc
.ga:	move.w  2(a0),d0
	rol.w   #7,d0
	andi.w  #7,d0
	addq.w  #1,d0
	add.w   d0,d1
	addq.l  #8,a0
.gc:	dbra    d2,.ga
	move.w  HAL_SPR_SPJ,d0
	sub.w   HAL_SPR_SPG,d0
	subq.w  #1,d0
	cmp.w   d0,d1
	bls.w   .x
	jsr     hal_spr_klim            ; (time)
	addi.w  #SH_LINES,d0
	tst.w   HAL_SPR_TAILU
	beq.s   .tu
	addq.w  #3,d0
.tu:	tst.w   d0
	bgt.w   .x
	DLREC   d6                      ; S's table, its list (kept by the walk)
	moveq   #0,d0
	move.b  DL_TABI(a1),d0
	bsr.w   dl_tab
	tst.b   T_OK(a0)
	beq.w   .x
	movea.l a0,a4
	move.w  d6,d0
	add.w   d0,d0
	lea     DL_SETS+DL_SRC,a0
	move.w  (a0,d0.w),d0
	cmp.w   FX_SBUF,d0
	bne.w   .x
	cmpi.w  #FX_NL,d0
	bhs.w   .x
	add.w   d0,d0
	lea     FX_LN,a0
	move.w  (a0,d0.w),d5            ; d5 = its entries (no more than its table covers)
	add.w   d0,d0
	lea     fx_ltab,a0
	movea.l (a0,d0.w),a2            ; a2 = S's list
	moveq   #0,d0
	move.b  T_N(a4),d0
	cmp.w   d0,d5
	bls.s   .nb
	move.w  d0,d5
.nb:	tst.w   d5
	beq.w   .x
	cmpi.w  #FX_LMAX,d5
	bhi.w   .x
	move.w  d6,d0
	jsr     hal_spr_set
	movea.l a6,a5                   ; a5 = S's state
	lea     DL_BSL,a1               ; per S entry its head slot ($fe none: dl_tget's)
	moveq   #0,d2
	move.b  T_FIN(a4),d2
	moveq   #0,d3
	move.b  T_NXT(a4),d3
	move.w  SS_HOFF(a5),d4
	lsr.w   #1,d4
	moveq   #0,d1
.sl:	moveq   #0,d0
	move.b  (a4,d1.w),d0
	cmp.w   d2,d1
	blo.s   .sg
	cmpi.b  #$ff,d0
	bne.s   .sg
	move.w  d3,d0
	addq.w  #1,d3
.sg:	cmp.w   d4,d0
	blo.s   .ss
	move.w  #$fe,d0
.ss:	move.b  d0,(a1,d1.w)
	addq.w  #1,d1
	cmp.w   d5,d1
	blo.s   .sl
	move.w  HAL_SPR_SPG,d2          ; d2: the guard's SCB3 address (the lower run below)
	addi.w  #SCB3,d2
	lea     SS_HADR(a5),a0          ; S's heads in its lower run (after all of its top
	moveq   #0,d1                   ; run's: its order)
	move.w  d4,d0
	bra.s   .hc
.hl:	cmp.w   (a0)+,d2
	bls.s   .ht
	addq.w  #1,d1
	bra.s   .hc
.ht:	tst.w   d1
	bne.w   .x
.hc:	dbra    d0,.hl
	move.w  d1,SH_HL
	move.w  d4,d0
	sub.w   d1,d0
	move.w  d0,SH_TOP
	movea.l FX_KTAB,a6              ; a6: N's table
	movea.l FX_CL,a3                ; N's entries from its back (a3 past it)
	move.w  FX_BC8,d0
	adda.w  d0,a3
	lsr.w   #3,d0
	move.w  d0,d7                   ; d7: entries left
	move.w  d5,d1                   ; d1: S entries left (before the last shared one's)
	moveq   #0,d3                   ; d3: shared
	lea     SH_ARR,a0
.ni:	subq.w  #1,d7
	bmi.w   .done
	subq.l  #8,a3
	bsr.w   dl_vis                  ; (out of view: no columns, on)
	bne.s   .iv
	move.b  #$fe,(a6,d7.w)
	bra.s   .ni
.iv:	move.l  (a3),d5
	andi.l  #$fe00fe00,d5
	move.w  d1,d4
	moveq   #SH_LOOK-1,d6
.cl:	subq.w  #1,d4
	bmi.s   .done
	moveq   #0,d0
	move.b  (a1,d4.w),d0
	cmpi.w  #$fe,d0
	bhs.s   .cn
	add.w   d0,d0
	cmp.w   SS_HADR(a5,d0.w),d2     ; (in the lower run)
	bls.s   .cn
	move.w  d4,d0
	lsl.w   #3,d0
	lea     (a2,d0.w),a4
	move.l  4(a4),d0
	cmp.l   4(a3),d0
	bne.s   .cn
	move.l  (a4),d0
	andi.l  #$fe00fe00,d0
	cmp.l   d5,d0
	beq.s   .fd
.cn:	dbra    d6,.cl
	bra.s   .done                   ; (none: the suffix ends)
.fd:	moveq   #0,d0                   ; shared: S entry d4
	move.b  (a1,d4.w),d0
	add.w   d0,d0
	move.w  SS_HADR(a5,d0.w),(a0)+
	lea     SS_HVAL(a5),a4          ; (displacements over 127: not indexed)
	moveq   #$3f,d6
	and.w   (a4,d0.w),d6
	move.w  (a3),d0                 ; SCB3 = (496 - oy) << 7 | its height
	neg.w   d0
	addi.w  #496,d0
	lsl.w   #7,d0
	add.w   d6,d0
	move.w  d0,(a0)+
	move.w  2(a3),d0                ; SCB4 = ox << 7
	lsl.w   #7,d0
	move.w  d0,(a0)+
	move.b  d7,(a0)+                ; (its N entry, its S slot)
	move.b  (a1,d4.w),(a0)+
	move.w  d4,d1
	addq.w  #1,d3
	cmpi.w  #SH_MAX,d3
	blo.w   .ni
	subq.w  #1,d7
.done:	addq.w  #1,d7                   ; d7: the shared suffix's first entry
	tst.w   d3
	beq.w   .x
	move.w  d7,d0                   ; (N's heads: no more than its slots)
	add.w   d3,d0
	cmpi.w  #SS_MAXHEAD,d0
	bhi.w   .x
	move.w  d7,d0                   ; N converted up to the suffix only
	lsl.w   #3,d0
	movea.l FX_CL,a0
	adda.w  d0,a0
	move.l  a0,FX_AEND
	movea.l FX_CL,a0                ; and starting as low as that part needs: else the
	moveq   #SH_SLACK,d1            ; hole's columns it leaves idle were N's after its
	move.w  d7,d2                   ; flip, the next set short of them (drops x 100)
	bra.s   .sc
.sa:	move.w  2(a0),d0
	rol.w   #7,d0
	andi.w  #7,d0
	addq.w  #1,d0
	add.w   d0,d1
	addq.l  #8,a0
.sc:	dbra    d2,.sa
	add.w   HAL_SPR_SPG,d1
	addq.w  #1,d1                   ; (its start: the column above its first)
	cmp.w   HAL_SPR_SPJ,d1
	bhs.s   .ns
	moveq   #0,d0
	move.b  31(sp),d0
	move.w  d0,d2
	add.w   d2,d2
	lea     HAL_SPR_START,a0
	move.w  d1,(a0,d2.w)
	jsr     hal_spr_set
	move.w  d1,SS_HNEXT(a6)
	addi.w  #SCB3,d1                ; (its start column height 0: the hole's columns
	move.w  #1,REG_VRAMMOD          ; above it hang off it)
	move.w  d1,REG_VRAMADDR
	move.w  #0,REG_VRAMRW
.ns:	moveq   #0,d0                   ; the shared heads: N's first slots (its table's
	move.b  31(sp),d0               ; slots for them; its converted ones after them),
	jsr     hal_spr_set             ; shown by N's flip; out of S's list (its hide)
	movea.l FX_KTAB,a4
	lea     SH_MARK,a0
	moveq   #SS_MAXHEAD/4-1,d0
.mc:	clr.l   (a0)+
	dbra    d0,.mc
	lea     SH_ARR,a0
	lea     SH_MARK,a1
	move.w  d3,d2                   ; d2: the slot (the last record: the first entry)
	move.w  d3,d0
	add.w   d0,d0
	move.w  d0,SS_HOFF(a6)
	move.b  d3,T_NXT(a4)
	lea     SS_HVAL(a6),a2
.rc:	subq.w  #1,d2
	moveq   #0,d0
	move.b  6(a0),d0
	move.b  d2,(a4,d0.w)
	move.w  d2,d0
	add.w   d0,d0
	move.w  (a0),SS_HADR(a6,d0.w)
	move.w  2(a0),(a2,d0.w)
	moveq   #0,d0
	move.b  7(a0),d0
	st      (a1,d0.w)
	addq.l  #8,a0
	tst.w   d2
	bne.s   .rc
	lea     SS_HADR(a5),a0          ; S's list without them
	lea     SS_HVAL(a5),a2
	movea.l a0,a3
	movea.l a2,a4
	move.w  SS_HOFF(a5),d0
	lsr.w   #1,d0
	moveq   #0,d1                   ; (its slot)
	moveq   #0,d2                   ; (its heads left)
	bra.s   .ck
.cl2:	tst.b   (a1,d1.w)
	bne.s   .cs
	move.w  (a0),(a3)+
	move.w  (a2),(a4)+
	addq.w  #1,d2
.cs:	addq.l  #2,a0
	addq.l  #2,a2
	addq.w  #1,d1
.ck:	dbra    d0,.cl2
	add.w   d2,d2
	move.w  d2,SS_HOFF(a5)
	move.w  d3,SH_N
	move.b  31(sp),SH_SET           ; (d7 on entry: N)
	move.b  HAL_SPR_SPS,d0
	ext.w   d0
	add.w   d0,d0
	lea     HAL_SPR_END,a0
	move.w  (a0,d0.w),SH_END
	st      SH_ON
.x:	movem.l (sp)+,d0-d7/a0-a6
	rts

; ring_spr_flip: another set shown than N (never: nothing new begins before N's flip):
; the shared heads (S's, out of its list) hidden too.  Keeps all.
sh_drop:
	movem.l d0/d3/a0,-(sp)
	sf      SH_ON
	move.w  SH_N,d3
	lea     SH_ARR,a0
	moveq   #0,d0
	subq.w  #1,d3
.h:	move.w  (a0),REG_VRAMADDR
	move.w  d0,REG_VRAMRW
	addq.l  #8,a0
	dbra    d3,.h
	movem.l (sp)+,d0/d3/a0
	rts

; ring_spr_flip, N shown and S's heads hidden (a5 N's state, a6 S's, a3/a4 the VRAM data
; and address ports): the shared heads with N's positions and N's from now on; S its top
; run only (its heads, zoomed columns), N down to the lower run's end, the ring not split;
; N's columns all chained again at its reclaim (the guard, S's other lower-run heads: 0).
; Keeps all.
sh_flip:
	movem.l d0-d7/a0-a6,-(sp)
	sf      SH_ON
	move.w  SH_N,d3                 ; the shared heads' x (their SCB3 shown with N's)
	lea     SH_ARR,a0
	subq.w  #1,d3
.w:	move.w  (a0),d0
	addi.w  #SCB4-SCB3,d0
	move.w  d0,(a4)
	move.w  4(a0),(a3)
	addq.l  #8,a0
	dbra    d3,.w
	move.w  SH_TOP,d0               ; S: its top run's heads only (the lower run's it
	add.w   d0,d0                   ; did not share hidden with it)
	move.w  d0,SS_HOFF(a6)
	move.w  HAL_SPR_SPG,d2          ; zoomed sprites of the lower run: N's
	move.w  SS_ZN(a6),d0
	cmpi.w  #ZL_MAX,d0
	bhi.s   .zall
	lea     SS_ZL(a6),a0
	movea.l a0,a1
	moveq   #0,d1
	bra.s   .zc
.zl:	move.w  (a0)+,d4
	move.w  (a0)+,d5
	cmp.w   d2,d4
	bhs.s   .zs
	move.w  SS_ZN(a5),d6
	cmpi.w  #ZL_MAX,d6
	bhs.s   .zf
	add.w   d6,d6
	add.w   d6,d6
	move.w  d4,SS_ZL(a5,d6.w)
	move.w  d5,SS_ZL+2(a5,d6.w)
	addq.w  #1,SS_ZN(a5)
	bra.s   .zc
.zf:	move.w  #ZL_MAX+1,SS_ZN(a5)
	bra.s   .zc
.zs:	move.w  d4,(a1)+
	move.w  d5,(a1)+
	addq.w  #1,d1
.zc:	dbra    d0,.zl
	move.w  d1,SS_ZN(a6)
	bra.s   .zd
.zall:	move.w  #ZL_MAX+1,SS_ZN(a5)     ; (S's all: N's all too)
.zd:	move.b  HAL_SPR_SPS,d0          ; the ring
	ext.w   d0
	add.w   d0,d0
	lea     HAL_SPR_END,a0
	move.w  HAL_SPR_SPJ,(a0,d0.w)
	moveq   #0,d1
	move.b  SH_SET,d1
	move.w  d1,d0
	add.w   d0,d0
	move.w  SH_END,(a0,d0.w)
	move.w  SH_END,SS_HNEXT(a5)     ; (an update of N goes on below it: else into the
	move.w  SH_END,HAL_SPR_GNEXT    ; lower run, over its sprites)
	st      HAL_SPR_SPS
	move.w  SH_HL,d2                ; (N's dead heads: at least 1 - its columns all
	sub.w   SH_N,d2                 ; chained again at its reclaim, the guard too)
	bgt.s   .d0
	moveq   #1,d2
.d0:	DLREC   d1
	cmpi.w  #255,d2
	bls.s   .d1
	move.w  #255,d2
.d1:	add.b   d2,DL_DEAD(a1)
	bcc.s   .d2
	st      DL_DEAD(a1)
.d2:	addq.l  #1,SH_CNT
	movem.l (sp)+,d0-d7/a0-a6
	rts
	endif

	ifne SPR_SHARE2
; Taking the shown set's back over (SPR_SHARE2, 2026-10-17; the mirror of SPR_SHARE).  A
; set X begun at the ring's top reaches the tail (the shown set S, the ring's only other
; set) with nothing complete: it would split, its rest converted below S, short of
; columns in the dense scenes (two lists > 338).  But its rest - the list's back, the
; ground's buildings - is mostly S's back again, moved (the drop probe: the whole rest in
; 80% of these drops).  When all of it is (in order, SH2_LOOK on in S, the same shape,
; attributes and tiles, no zoom), X takes those sprites of S over: their heads appended
; to X's (X's positions, shown by X's flip), out of S's list (not hidden by S's hide);
; X is complete at once.  At X's flip (sh2_flip, after S's hide) their x is written,
; and X takes S's whole run over: X's run from its start down to S's end, S's other
; columns idle in it (S's hide made their heads 0; X's reclaim chains them all again,
; DL_DEAD), S left with no heads and no run (its reclaim touches nothing).  Draw order:
; S's columns are below all of X's top run, and in S's order, which is X's.  Nothing
; new begins before X's flip (SH2_ON).
SH2_ON          equ FXS+$760        ; b: X takes S's back over (till its flip)
SH2_SET         equ FXS+$761        ; b: X
SH2_S           equ FXS+$762        ; b: S
SH2_N           equ FXS+$764        ; w: sprites taken over
SH2_CNT         equ FXS+$768        ; l: (diagnostics) flips that took them
SH2_SPG         equ FXS+$76c        ; w: X's guard then: the column above the highest
                                    ; one taken (X's lower run: S's end .. below it)
SH2_SPJ         equ FXS+$76e        ; w: X's top run's lowest column
SH2_ARR         equ DL_ARR0         ; SH2_MAX x 8 b (from the list's back): the head's SCB3
SH2_MAX         equ 80              ; address, its SCB3 and SCB4 in X, X's entry, S's slot
SH2_MARK        equ DL_TA           ; SS_MAXHEAD b: S's slots taken
SH2_LOOK        equ 8               ; S entries looked at for each X entry
SH2_ECY         equ 520             ; cycles an entry of the rest (matched and taken)
SH2_C0          equ 2600            ; and the rest of it (S's slots, its list)
	ifnd SH2_LOW
SH2_LOW         equ 16              ; only with S's end this close to SPR_PB: else X's lower
	endif                           ; run cut the free ring in two (drops x 2-100, 2026-10-17)
	if 8*SH2_MAX>$400
	fail "SH2_ARR"
	endif
	if SS_MAXHEAD>160
	fail "SH2_MARK"
	endif

; hal_spr_go .spl: X (HAL_SPR_W, a6 its state) at the tail, a5 past its entry there
; (the rest: a5 - 8 .. a0), a4 its next head slot.  Z clear: taken over (a4 past X's
; heads now); Z set: not (nothing changed).  Keeps all but a4.
sh2_try:
	movem.l d0-d7/a0-a6,-(sp)       ; (a0 32, a4 48, a5 52, a6 56)
	tst.b   SH2_ON
	bne.w   .no
	tst.b   FX_DELTA
	bne.w   .no
	tst.b   FX_PON
	bne.w   .no
	ifne SPR_SHARE
	tst.b   SH_ON
	bne.w   .no
	endif
	cmpi.b  #2,HAL_SPR_ORDN         ; the ring: S (shown), X
	bne.w   .no
	move.w  HAL_SPR_W,d7
	cmp.b   HAL_SPR_ORD+1,d7
	bne.w   .no
	moveq   #0,d6
	move.b  HAL_SPR_ORD,d6
	cmp.w   HAL_SPR_SHOWN,d6
	bne.w   .no
	lea     HAL_SPR_ST,a1
	cmpi.b  #3,(a1,d6.w)
	bne.w   .no
	move.w  d6,d0                   ; (S ends near SPR_PB)
	add.w   d0,d0
	lea     HAL_SPR_END,a1
	cmpi.w  #SPR_PB+SH2_LOW,(a1,d0.w)
	bhi.w   .no
	lea     -8(a5),a3               ; a3: the rest's first entry
	move.l  a0,d0                   ; time: its entries
	sub.l   a3,d0
	lsr.l   #3,d0
	cmpi.w  #SH2_MAX,d0
	bhi.w   .no
	mulu    #SH2_ECY,d0
	addi.l  #SH2_C0+767,d0
	divu    #768,d0
	move.w  d0,d1
	jsr     hal_spr_klim            ; (d0: lines over the stop)
	add.w   d1,d0
	tst.w   HAL_SPR_TAILU
	beq.s   .tu
	addq.w  #3,d0
.tu:	tst.w   d0
	bgt.w   .no
	move.l  a6,d5                   ; S's state: a5 (X's: 56(sp))
	move.w  d6,d0
	jsr     hal_spr_set
	movea.l a6,a5
	movea.l d5,a6
	cmpi.w  #ZL_MAX,SS_ZN(a5)       ; (its zoomed columns listed: its reclaim restores
	bhi.w   .no                     ; those only, never X's)
	DLREC   d6                      ; S's table, its list (kept by the walk)
	moveq   #0,d0
	move.b  DL_TABI(a1),d0
	bsr.w   dl_tab
	tst.b   T_OK(a0)
	beq.w   .no
	movea.l a0,a4
	move.w  d6,d0
	add.w   d0,d0
	lea     DL_SETS+DL_SRC,a0
	move.w  (a0,d0.w),d0
	cmp.w   FX_SBUF,d0
	bne.w   .no
	cmpi.w  #FX_NL,d0
	bhs.w   .no
	add.w   d0,d0
	lea     FX_LN,a0
	move.w  (a0,d0.w),d5            ; d5 = its entries (no more than its table covers)
	add.w   d0,d0
	lea     fx_ltab,a0
	movea.l (a0,d0.w),a2            ; a2 = S's list
	moveq   #0,d0
	move.b  T_N(a4),d0
	cmp.w   d0,d5
	bls.s   .nb
	move.w  d0,d5
.nb:	tst.w   d5
	beq.w   .no
	cmpi.w  #FX_LMAX,d5
	bhi.w   .no
	lea     DL_BSL,a1               ; per S entry its head slot ($fe none: dl_tget's)
	moveq   #0,d2
	move.b  T_FIN(a4),d2
	moveq   #0,d3
	move.b  T_NXT(a4),d3
	move.w  SS_HOFF(a5),d4
	lsr.w   #1,d4
	moveq   #0,d1
.sl:	moveq   #0,d0
	move.b  (a4,d1.w),d0
	cmp.w   d2,d1
	blo.s   .sg
	cmpi.b  #$ff,d0
	bne.s   .sg
	move.w  d3,d0
	addq.w  #1,d3
.sg:	cmp.w   d4,d0
	blo.s   .ss
	move.w  #$fe,d0
.ss:	move.b  d0,(a1,d1.w)
	addq.w  #1,d1
	cmp.w   d5,d1
	blo.s   .sl
	; the rest from its back, each among S's next SH2_LOOK entries from its back
	movea.l a3,a0                   ; a0: the rest's first entry; a3 from its end
	movea.l 32(sp),a3
	lea     SS_HVAL(a5),a6          ; (displacements over 127: not indexed)
	move.w  d5,d1                   ; d1: S entries left (before the last taken)
	moveq   #0,d3                   ; d3: taken
	lea     SH2_ARR,a4
.ni:	cmpa.l  a0,a3
	bls.w   .md
	subq.l  #8,a3
	bsr.w   dl_vis                  ; (out of view: no columns, none needed)
	beq.s   .ni
	move.w  (a3),d0                 ; (zoomed: no)
	or.w    2(a3),d0
	cmpi.w  #$1000,d0
	bhs.w   .no
	move.l  (a3),d5
	andi.l  #$fe00fe00,d5
	move.w  d1,d4
	moveq   #SH2_LOOK-1,d6
.cl:	subq.w  #1,d4
	bmi.w   .no
	moveq   #0,d0
	move.b  (a1,d4.w),d0
	cmpi.w  #$fe,d0
	bhs.s   .cn
	move.w  d4,d0
	lsl.w   #3,d0
	move.l  4(a2,d0.w),d2
	cmp.l   4(a3),d2
	bne.s   .cn
	move.l  (a2,d0.w),d2
	andi.l  #$fe00fe00,d2
	cmp.l   d5,d2
	beq.s   .fd
.cn:	dbra    d6,.cl
	bra.w   .no                     ; (not there: all or nothing)
.fd:	moveq   #0,d0                   ; taken: S entry d4
	move.b  (a1,d4.w),d0
	add.w   d0,d0
	move.w  SS_HADR(a5,d0.w),(a4)+
	moveq   #$3f,d2
	and.w   (a6,d0.w),d2
	move.w  (a3),d0                 ; SCB3 = (496 - oy) << 7 | its height
	neg.w   d0
	addi.w  #496,d0
	lsl.w   #7,d0
	add.w   d2,d0
	move.w  d0,(a4)+
	move.w  2(a3),d0                ; SCB4 = ox << 7
	lsl.w   #7,d0
	move.w  d0,(a4)+
	move.l  a3,d0                   ; (its X entry, its S slot)
	sub.l   FX_CL,d0
	lsr.w   #3,d0
	move.b  d0,(a4)+
	move.b  (a1,d4.w),(a4)+
	move.w  d4,d1
	addq.w  #1,d3
	cmpi.w  #SH2_MAX,d3
	blo.w   .ni
	bra.w   .no
.md:	tst.w   d3
	beq.w   .no
	movea.l 56(sp),a6               ; X: its heads so far + these, no more than its slots
	move.l  48(sp),d0
	sub.l   a6,d0
	subi.l  #SS_HADR,d0
	lsr.l   #1,d0
	move.w  d0,d2                   ; d2: X's heads so far (its next slot)
	add.w   d3,d0
	cmpi.w  #SS_MAXHEAD,d0
	bhi.w   .no
	; taken: X's table (the rest's entries none, but those: their slots after X's
	; converted ones, in entry order), its heads, S's list without them
	movea.l FX_KTAB,a1
	move.l  a0,d0                   ; the rest's first entry .. the list's end: $fe
	sub.l   FX_CL,d0
	lsr.w   #3,d0
	move.l  32(sp),d1
	sub.l   FX_CL,d1
	lsr.w   #3,d1
	bra.s   .fc
.fl:	move.b  #$fe,(a1,d0.w)
	addq.w  #1,d0
.fc:	cmp.w   d1,d0
	blo.s   .fl
	lea     SH2_MARK,a0
	moveq   #SS_MAXHEAD/4-1,d0
.mc:	clr.l   (a0)+
	dbra    d0,.mc
	lea     SH2_ARR,a0
	lea     SH2_MARK,a2
	movea.l 48(sp),a4               ; X's next head slot
	lea     SS_HVAL-SS_HADR(a4),a3  ; (and its SCB3 value)
	move.w  d3,d1                   ; the last record is the rest's first entry
	mulu    #8,d1
	adda.w  d1,a0
	move.w  d3,d1
	subq.w  #1,d1
.rc:	subq.l  #8,a0
	moveq   #0,d0
	move.b  6(a0),d0                ; X entry: slot d2
	move.b  d2,(a1,d0.w)
	addq.w  #1,d2
	move.w  (a0),(a4)+
	move.w  2(a0),(a3)+
	move.b  7(a0),d0                ; S's slot taken
	st      (a2,d0.w)
	dbra    d1,.rc
	move.l  a4,48(sp)               ; (a4 on return)
	move.w  SS_HNEXT(a6),SH2_SPJ    ; X split at its flip: its top run, and a lower
	lea     SH2_ARR,a0              ; run up to the highest column taken
	movea.l FX_CL,a1
	moveq   #0,d4
	move.w  d3,d1
	subq.w  #1,d1
.tp:	move.w  (a0),d0                 ; its head's column + its columns - 1
	subi.w  #SCB3,d0
	moveq   #0,d2
	move.b  6(a0),d2
	lsl.w   #3,d2
	move.w  2(a1,d2.w),d2
	rol.w   #7,d2
	andi.w  #7,d2
	add.w   d2,d0
	cmp.w   d4,d0
	bls.s   .tq
	move.w  d0,d4
.tq:	addq.l  #8,a0
	dbra    d1,.tp
	addq.w  #1,d4
	move.w  d4,SH2_SPG
	lea     SS_HADR(a5),a0          ; S's list without them
	lea     SS_HVAL(a5),a1
	movea.l a0,a3
	movea.l a1,a4
	move.w  SS_HOFF(a5),d0
	lsr.w   #1,d0
	moveq   #0,d1                   ; (its slot)
	moveq   #0,d2                   ; (its heads left)
	bra.s   .ck
.c2:	tst.b   (a2,d1.w)
	bne.s   .cs
	move.w  (a0),(a3)+
	move.w  (a1),(a4)+
	addq.w  #1,d2
.cs:	addq.l  #2,a0
	addq.l  #2,a1
	addq.w  #1,d1
.ck:	dbra    d0,.c2
	add.w   d2,d2
	move.w  d2,SS_HOFF(a5)
	move.w  d3,SH2_N
	move.b  d7,SH2_SET
	move.b  HAL_SPR_ORD,SH2_S
	st      SH2_ON
	movem.l (sp)+,d0-d7/a0-a6
	andi    #$fb,ccr                ; Z clear
	rts
.no:	movem.l (sp)+,d0-d7/a0-a6
	ori     #4,ccr                  ; Z set
	rts

; ring_spr_flip, X shown and S hidden (a5 X's state, a6 S's, a3/a4 the VRAM data and
; address ports): the taken heads' x; X split - its top run, and a lower run from S's
; end up to below its guard (SH2_SPG, height 0), S's other heads there idle in it (X's
; reclaim chains them again, DL_DEAD); S keeps its heads above the guard and ends there
; (its reclaim frees that: the hole, as after a split).  Keeps all.
sh2_flip:
	movem.l d0-d4/a0-a2,-(sp)
	sf      SH2_ON
	move.w  SH2_N,d3
	lea     SH2_ARR,a0
	subq.w  #1,d3
.w:	move.w  (a0),d0
	addi.w  #SCB4-SCB3,d0
	move.w  d0,(a4)
	move.w  4(a0),(a3)
	addq.l  #8,a0
	dbra    d3,.w
	move.w  SH2_SPG,d4              ; the guard: 0
	move.w  d4,d0
	addi.w  #SCB3,d0
	move.w  d0,(a4)
	move.w  #0,(a3)
	lea     SS_HADR(a6),a0          ; S: its heads above the guard only (hidden:
	movea.l a0,a2                   ; their values unused)
	move.w  SS_HOFF(a6),d0
	lsr.w   #1,d0
	moveq   #0,d2                   ; (heads kept)
	moveq   #1,d3                   ; (X's idle ones: + the guard's column)
	addi.w  #SCB3,d4
	bra.s   .kc
.kl:	cmp.w   (a0),d4
	blo.s   .kk
	addq.w  #1,d3
	bra.s   .kn
.kk:	move.w  (a0),(a2)+
	addq.w  #1,d2
.kn:	addq.l  #2,a0
.kc:	dbra    d0,.kl
	add.w   d2,d2
	move.w  d2,SS_HOFF(a6)
	moveq   #0,d1
	move.b  SH2_S,d1
	add.w   d1,d1
	moveq   #0,d2
	move.b  SH2_SET,d2
	add.w   d2,d2
	lea     HAL_SPR_END,a0
	move.w  (a0,d1.w),d0            ; X: down to S's end
	move.w  d0,(a0,d2.w)
	move.w  d0,SS_HNEXT(a5)
	move.w  d0,HAL_SPR_GNEXT
	move.w  SH2_SPG,d0              ; S: ends above the guard
	addq.w  #1,d0
	move.w  d0,(a0,d1.w)
	move.b  SH2_SET,HAL_SPR_SPS     ; X split
	move.w  SH2_SPJ,HAL_SPR_SPJ
	move.w  SH2_SPG,HAL_SPR_SPG
	moveq   #0,d0
	move.b  SH2_SET,d0
	DLREC   d0
	cmpi.w  #255,d3
	bls.s   .d1
	move.w  #255,d3
.d1:	add.b   d3,DL_DEAD(a1)
	bcc.s   .d2
	st      DL_DEAD(a1)
.d2:	addq.l  #1,SH2_CNT
	movem.l (sp)+,d0-d4/a0-a2
	rts

; ring_spr_flip: another set shown than X (never: nothing new begins before X's
; flip): the taken heads (out of S's list) hidden too.  Keeps all.
sh2_drop:
	movem.l d0/d3/a0,-(sp)
	sf      SH2_ON
	move.w  SH2_N,d3
	lea     SH2_ARR,a0
	moveq   #0,d0
	subq.w  #1,d3
.h:	move.w  (a0),REG_VRAMADDR
	move.w  d0,REG_VRAMRW
	addq.l  #8,a0
	dbra    d3,.h
	movem.l (sp)+,d0/d3/a0
	rts
	endif

; A flip writes its list's text strips with its sprites (fx_hud_flushall), its time
; counted; once flips were deferred twice in a row (FX_FLATE) one that does not fit with
; them goes without (FX_FNOH): the commit's fx_hud_flush writes them, while its time
; lasts - a flip that never fit its text stalled the sprites for good (an update's flip,
; 11 strips queued, 2026-10-14).
; The flip done (d0 = its list's buffer): its text written now, or (FX_FNOH) noted for
; the commit's fx_hud_flush.  Keeps all.
fx_flip_hud:
	sf      FX_FLATE
	tst.b   FX_FNOH
	bne.s   .q
	jmp     fx_hud_flushall
.q:	jmp     fx_hud_apply

; dl_vis keeping d4.
dl_vis2:
	move.w  d4,-(sp)
	bsr.s   dl_vis
	movem.w (sp)+,d4                ; (keeps the flags)
	rts
; a3 = an entry (w0, w1): Z clear when in view (as hal_spr_go decides).  Clobbers d0,
; d4.
dl_vis:
	move.w  (a3),d0
	andi.w  #$1ff,d0
	cmpi.w  #224,d0
	blo.s   .y
	move.w  (a3),d4
	andi.w  #$0e00,d4
	lsr.w   #5,d4
	add.w   d0,d4
	cmpi.w  #512-16,d4
	bls.s   .o
.y:	move.w  2(a3),d0
	andi.w  #$1ff,d0
	cmpi.w  #320,d0
	blo.s   .v
	move.w  2(a3),d4
	andi.w  #$0e00,d4
	lsr.w   #5,d4
	add.w   d0,d4
	cmpi.w  #512-16,d4
	bls.s   .o
.v:	moveq   #1,d0                   ; Z clear
	rts
.o:	moveq   #0,d0                   ; Z set
	rts

; The finished update in place's end (hal_spr_work .fin): pending (P) if none is, else
; it waits behind it (C done).  Its list kept by the walk from now on.  Keeps a6.
dl_done:
	ifne DL_SPLIT
	tst.b   DL_HOLEC
	beq.s   .h
	sf      DL_HOLEC
	movem.l d0/a0,-(sp)
	move.w  DLC+D_BASE,d0
	add.w   d0,d0
	lea     HAL_SPR_END,a0
	move.w  (a0,d0.w),SS_HNEXT(a6)
	movem.l (sp)+,d0/a0
.h:
	endif
	move.w  DLC+D_BUF,FX_CBUF
	tst.b   FX_PON
	bne.s   dl_behind
dl_promote:
	movem.l d0/a0-a1,-(sp)
	lea     DLC,a0
	lea     DLP,a1
	moveq   #D_SIZE/2-1,d0
.c:	move.w  (a0)+,(a1)+
	dbra    d0,.c
	st      FX_PON
	sf      FX_DELTA
	movem.l (sp)+,d0/a0-a1
	rts
dl_behind:
	move.b  #2,FX_DELTA
	rts

; The flip of the pending update (P, from its D_RDY on): the base's heads not kept
; hidden, the kept ones with their new SCB3/SCB4, the new ones; the base shown (the
; one shown so far hidden if it was another: the base was complete and its own flip
; never came).  Then a done one behind it pending.  Z clear: no time (it waits).
dl_flip:
	move.w  DLP+D_BASE,d0
	jsr     hal_spr_set
	move.w  DLP+D_HOFF,d1
	lsr.w   #1,d1                   ; heads
	move.w  DLP+D_KEPT,d2
	move.w  d2,d0                   ; time: 40 cycles a head, 60 more a kept one,
	mulu    #60,d0                  ; 30 a hidden one, + 48 x heads of a set hidden
	move.w  d1,d3
	mulu    #40,d3
	add.l   d3,d0
	move.w  DLP+D_HIDE,d3
	mulu    #30,d3
	add.l   d3,d0
	move.w  HAL_SPR_SHOWN,d3
	cmp.w   DLP+D_BASE,d3
	beq.s   .t
	addi.l  #48*SS_MAXHEAD,d0
.t:	move.l  d0,-(sp)                ; (hal/fx.s: its list's pair bullets in the pool)
	move.w  DLP+D_BUF,d0
	jsr     bp_cost
	add.l   (sp)+,d0
	move.l  d0,-(sp)                ; (hal/fx.s: its list's fix-layer text with it,
	sf      FX_FNOH                 ; FX_HSTRIP cycles a strip)
	move.w  DLP+D_BUF,d0
	jsr     fx_hud_count
	mulu    #FX_HSTRIP,d0
	add.l   (sp),d0
	addi.l  #800+767,d0
	divu    #768,d0
	jsr     hal_late_n
	beq.s   .ok
	cmpi.b  #2,FX_FLATE             ; (fx_flip_hud: deferred twice: without it)
	blo.s   .lt
	st      FX_FNOH
	move.l  (sp),d0
	addi.l  #800+767,d0
	divu    #768,d0
	jsr     hal_late_n
	beq.s   .ok
.lt:	addq.l  #4,sp
	bra.w   .late
.ok:	addq.l  #4,sp
	lea     REG_VRAMRW,a3
	lea     REG_VRAMADDR,a4
	movea.l DLP+D_ARR,a1            ; the base's heads not kept: hidden
	lea     DA_HIDE(a1),a0
	move.w  DLP+D_HIDE,d3
	moveq   #0,d0
	bra.s   .dc
.dl:	move.w  (a0)+,(a4)
	move.w  d0,(a3)
.dc:	dbra    d3,.dl
	lea     SS_HADR(a6),a0
	lea     DA_HX(a1),a2            ; (a1: DA_HV)
	lea     SS_HVAL(a6),a5
	sub.w   d2,d1                   ; the new heads
	subq.w  #1,d2
	bmi.s   .n
.k:	move.w  (a0),(a4)               ; a kept head: SCB3, SCB4
	move.w  (a1),(a3)
	move.w  (a1)+,(a5)+             ; (its value from now on)
	move.w  (a0)+,d0
	addi.w  #SCB4-SCB3,d0
	move.w  d0,(a4)
	move.w  (a2)+,(a3)
	dbra    d2,.k
.n:	subq.w  #1,d1
	bmi.s   .e
.w:	move.w  (a0)+,(a4)              ; a new head: SCB3 (its x was written)
	move.w  (a5)+,(a3)
	dbra    d1,.w
.e:	move.w  DLP+D_HOFF,SS_HOFF(a6)  ; (an update converting on top counts its own)
	move.w  HAL_SPR_SHOWN,d0        ; another set shown so far: hidden, freed
	move.w  DLP+D_BASE,d1
	cmp.w   d1,d0
	beq.s   .s
	lea     HAL_SPR_ST,a5
	tst.w   d0
	bmi.s   .h
	clr.b   (a5,d0.w)
	jsr     hal_spr_set
	lea     SS_HADR(a6),a0
	move.w  SS_HOFF(a6),d2
	lsr.w   #1,d2
	moveq   #0,d3
	bra.s   .hc
.hl:	move.w  (a0)+,(a4)
	move.w  d3,(a3)
.hc:	dbra    d2,.hl
.h:	move.w  d1,HAL_SPR_SHOWN
	move.b  #3,(a5,d1.w)
.s:	move.w  DLP+D_BASE,d0           ; (its heads hidden: idle columns from now on)
	DLREC   d0
	move.w  DLP+D_HIDE,d0
	add.b   d0,DL_DEAD(a1)
	bcc.s   .sd
	st      DL_DEAD(a1)
.sd:	moveq   #0,d2                   ; (its list's table now the set's)
	move.b  DL_TABI(a1),d2
	move.b  DLP+D_TAB+1,DL_TABI(a1)
	move.w  d2,DLP+D_TAB
	sf      FX_PON
	lea     HAL_SPR_RDY,a1          ; the set's age now its list's; complete sets
	move.w  DLP+D_BASE,d0           ; older than that: never shown (one shown after
	add.w   d0,d0                   ; this would go back in time, and the oldest in
	move.w  FX_PRDY,d3              ; the ring kept shown stops its reclaim: nothing
	move.w  d3,(a1,d0.w)            ; new converted, 2026-10-14; newer ones stay)
	lea     HAL_SPR_ST,a0
	moveq   #NSPRSETS-1,d0
	moveq   #2*(NSPRSETS-1),d2
.o:	cmpi.b  #1,(a0,d0.w)
	bne.s   .on
	move.w  (a1,d2.w),d1
	sub.w   d3,d1
	tst.w   d1                      ; (frame numbers wrap: the sign only)
	bge.s   .on
	clr.b   (a0,d0.w)
	jsr     spr_cut                 ; (hal/spr.s: its chain cut off)
.on:	subq.w  #2,d2
	dbra    d0,.o
	move.w  DLP+D_BUF,FX_SBUF       ; (its list now the shown set's)
	move.w  DLP+D_BASE,d0
	add.w   d0,d0
	lea     DL_SETS+DL_SRC,a0
	move.w  DLP+D_BUF,(a0,d0.w)
	move.w  DLP+D_BUF,d0            ; (hal/fx.s: the fix layer with these sprites,
	bsr.w   fx_flip_hud             ; in this vblank)
	jsr     bp_apply                ; (and its pair bullets in the pool)
	cmpi.b  #2,FX_DELTA             ; one done behind it: pending now
	bne.s   .z
	bsr.w   dl_promote
.z:	moveq   #0,d0                   ; Z set
	rts
.late:	moveq   #1,d0
	rts
