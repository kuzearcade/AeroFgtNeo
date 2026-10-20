; Not cycle-exact (AEROFGT_DIRECT=1, RES=1): resident sprites (prototype).
;
; Most of a list's pieces are the shown list's again, from the same object, with the
; same tiles (attract storm 96%, gameplay 80%: work/native/redund.py), often at the same
; place (zoomed ones too: the same zoom, the same shrink).  So a piece keeps the Neo columns it was converted into for as long as its
; object draws it the same way: only the new ones are converted (into free columns,
; hidden until the flip), a kept one that moved gets its head's SCB3 and SCB4 rewritten
; at the flip, and the shown ones no piece kept are hidden there.  No set is double
; buffered, no ring: the pool SPR_PB..SPR_PT holds one frame's pieces and the new ones.
;
; The walk (rs_obj, in place of fx_obj): per object slot a signature of what its
; pieces come from (position, tables, counts, colour, flips, zoom, type: RS_SIG, at
; (object - 0xff0000) / 4) and where its entries went in that walk's list.  An object
; the same as in the walk before (same scroll, same HUD use) gets that list's entries
; copied; each entry gets a link to the walk before's entry of the same object and
; ordinal (RS_LNK: $80 + i the same entry i, i an entry to compare with, $ff none).
;
; Match (rs_match): when the shown list (S) is the one the list in work (P) links to,
; the links say it all: the same entry (checked: the same words) keeps its columns, a
; linked one is compared (kept when its attribute words are the same but the position,
; tiles the game does not change under it: rs_lutb); else everything is new.
;
; Columns: a free column has SCB3 0 (height 0, not chained) and SCB2 full size; a placed
; piece gets its columns' SCB3 when it is placed (head 0, the others chained: hidden),
; its head at the flip; a hidden one gets SCB3 0 in all its columns (and SCB2 back if it
; was zoomed) at that flip, and its columns are free again.  RS_COLM: per column, in use.
; Draw order (higher column on top, the list's first entry the front): a new piece goes
; to the free run nearest its share of the pool by list position (prototype: overlaps
; are not checked, kept pieces never move).
;
; Phases (hal_spr_work, budgeted, resumable; HAL_SPR_ST/RDY/W of set 0 as the ring's,
; for hal/sched.s): match, convert (hal_spr_go over the list: kept ones skipped, a new
; one into its columns: RS_PC0), complete (waits for its flip).  One list at a time:
; the next begins after the flip.
;
; Memory (all of it unused in RES builds: the ring's sets 1-2, hal/dl.s's arrays, the
; original builder's buffers, the sprite RAM gap, the game's RAM gap 0xff9a90-0xffb8ff);
; the game's boot RAM test wipes it: three magic words, rs_reset when one is gone.

RS_NSLOT        equ 258                 ; object slots 0xff0000..0xff60c0
RS_TAG0         equ G_DX_LIST           ; per list buffer 0-3: 128 w (entry: object slot)
RS_TAG4         equ G_DX_BUF0+$4e0      ; buffer 4's (to +$5e0)
RS_C0A          equ G_DX_BUF0+$5e0      ; 128 w: per entry its columns' end + flags
RS_C0B          equ G_DX_BUF0+$6e0      ; (to +$7e0; FX_HMAGIC at +$7f0)
RS_OBJA         equ G_SPRRAM+$400       ; RS_NSLOT w: first entry << 8 | entries
RS_V            equ G_SPRRAM+$608       ; variables (to $800)
RS_OBJB         equ G_SPRBUF+SS_SIZE    ; (the ring's sets 1, 2)
RS_COLM         equ RS_OBJB+2*RS_NSLOT  ; 382 b: per column (0..380) in use
RS_MAG2         equ RS_COLM+382         ; l
RS_GAP          equ $100000+$ff9aa0-$fef000     ; (the game's RAM gap, Neo address)
RS_SIGSZ        equ 24                  ; (at (object - 0xff0000) / 4: no multiply)
RS_SIG          equ RS_GAP              ; RS_NSLOT x RS_SIGSZ
RS_LNK0         equ RS_SIG+RS_NSLOT*RS_SIGSZ    ; per list buffer 128 b
RS_MAG3         equ RS_LNK0+5*128       ; l
	if RS_MAG2+4>G_SPRBUF+3*SS_SIZE
	fail "hal/rs.s: column map past the sets"
	endif
	if RS_MAG3+4>$100000+$ffb900-$fef000
	fail "hal/rs.s: the gap's tables run into G_SLIPLOG"
	endif
	if FX_LMAX>127
	fail "hal/rs.s: lists longer than 7-bit links"
	endif

; signature (RS_SIG, per slot)
SG_YX           equ 0                   ; l: $e, $10
SG_TAB          equ 4                   ; l: $1a
SG_T44          equ 8                   ; l: $44 (b43 bits 6, 7)
SG_B4           equ 12                  ; w: $4, $5
SG_TYPE         equ 14                  ; w: $16
SG_B19          equ 16
SG_B2A          equ 17
SG_B43          equ 18
SG_B1           equ 19
SG_SEQ          equ 20                  ; w: its walk (number)
SG_FIRST        equ 22                  ; b: its first entry in that walk's list
SG_NF           equ 23                  ; b: its entries (bits 0-6); bit 7: never copied
                                        ; (HUD takes, a table in RAM, tiles that change
                                        ; under it: rs_lutb)

RS_MAGIC        equ RS_V+0              ; l
RS_PH           equ RS_V+4              ; w: 0 none, 1 match, 2 convert, 3 complete
RS_PI           equ RS_V+6              ; w: match: next entry
RS_PN           equ RS_V+8              ; w: P (the list in work) entries
RS_SN           equ RS_V+10             ; w: S (shown) entries
RS_PC0          equ RS_V+12             ; l: P's column table
RS_SC0          equ RS_V+16             ; l: S's
RS_POBJ         equ RS_V+20             ; l: P's slot table
RS_SOBJ         equ RS_V+24             ; l: S's
RS_PTAG         equ RS_V+28             ; l: P's tags
RS_STAG         equ RS_V+32             ; l: S's
RS_SLIST        equ RS_V+36             ; l: S's list
RS_CUR          equ RS_V+40             ; w: match: the object (slot; -1 none)
RS_SI           equ RS_V+42             ; w: match: its S entry for the next ordinal
RS_SE           equ RS_V+44             ; w: match: its S entries' end
RS_PF           equ RS_V+46             ; w: match: its first P entry
RS_STEP         equ RS_V+48             ; w: placement: 256 x pool / (entries + 1)
RS_NEWN         equ RS_V+50             ; w: P: new ones placed
RS_MVN          equ RS_V+52             ; w: P: kept ones moved
RS_KN           equ RS_V+54             ; w: P: kept
RS_DN           equ RS_V+56             ; w: P: dropped (no room)
RS_PBUF         equ RS_V+58             ; w: P's list buffer
RS_SPRES        equ RS_V+60             ; w: S entries with columns
RS_A1           equ RS_V+62             ; l: (rs_obj) the list before the object
RS_NKEPT        equ RS_V+66             ; l: (diagnostics) entries kept
RS_NNEW         equ RS_V+70             ; l: placed
RS_NDROP        equ RS_V+74             ; l: no room
RS_NMOVED       equ RS_V+78             ; l: kept and moved
RS_NFAST        equ RS_V+82             ; l: lists matched by their links
RS_NSLOW        equ RS_V+86             ; l: the slow way
RS_NBADL        equ RS_W+74             ; l: (diagnostics) "same" links that were not
RS_FAST         equ RS_V+90             ; b: P matched by its links
RS_POBJOK       equ RS_V+91             ; b: P's slot table made
RS_SOBJOK       equ RS_V+92             ; b: S's
RS_PREVOK       equ RS_V+93             ; b: (walk) the walk before is linked to
RS_IDOK         equ RS_V+94             ; b: (walk) its entries may be copied
RS_MV           equ RS_V+96             ; 128 b: P's moved ones
RS_W            equ RS_V+224            ; the walk's state:
RS_WLIST        equ RS_W+0              ; l: its list
RS_WTAG         equ RS_W+4              ; l: its tags
RS_WLNK         equ RS_W+8              ; l: its links
RS_WPLIST       equ RS_W+12             ; l: the walk before's list
RS_WPTAG        equ RS_W+58             ; l: its tags
RS_WCNT         equ RS_W+62             ; w: walks begun (their numbers)
RS_BSEQ         equ RS_W+64             ; 5 w: per list buffer its walk's number
RS_CBUF         equ RS_W+16             ; w: the last walk begun: its buffer (-1 none)
RS_CSEQ         equ RS_W+18             ; w: its number
RS_CSY          equ RS_W+20             ; w: its scroll
RS_CSX          equ RS_W+22
RS_CHOK         equ RS_W+24             ; b: its FX_HOK
RS_SLOT         equ RS_W+26             ; w: (rs_obj) the object's slot
RS_LFC          equ RS_W+28             ; w: (rs_obj) its entries in the walk before: first
                                        ; << 8 | entries (0: none)
RS_HS           equ RS_W+30             ; w: (rs_obj) FX_HSEEN before it
RS_LNKB         equ RS_W+32             ; 5 w: per list buffer the buffer it links to (-1)
RS_LNKS         equ RS_W+42             ; 5 w: and that list's walk number
RS_PSEQ         equ RS_W+52             ; w: (walk) the walk before's number (RS_WCNT)
RS_WSEQ         equ RS_W+54             ; w: this walk's
RS_LUTD         equ RS_W+56             ; b: the lookup RAM loaded (rs_lutld)
RS_NOKEEP       equ RS_W+57             ; b: P keeps nothing (loaded since S was made)
	if RS_W+78>G_SPRRAM+$800
	fail "hal/rs.s: variables"
	endif
RS_MAGICV       equ $52455331

; column table (per list entry): its run's end column (bits 0-8), columns - 1 (9-11),
; zoomed (12: SCB2 to restore), and
C_KEPT          equ $8000               ; (P) kept
C_TAKEN         equ $4000               ; (S) kept by P
C_NONE          equ $ffff               ; no columns (dropped)
C_RUN           equ $1fff               ; (the run: end, columns, zoomed)

; walk charges (16-cycle units)
FXU_RSG         equ 40                  ; an object's signature checked (charged first)
FXU_RSK         equ 16                  ; an object copied: its set-up
FXU_RSE         equ 6                   ; and per entry

rs_lnkt:
	dc.l    RS_LNK0,RS_LNK0+128,RS_LNK0+256,RS_LNK0+384,RS_LNK0+512

; ================================================================ the walk
; (fx_snap_begin) a new walk into FX_WP: its entries link to the walk begun before it
; (complete: a new walk begins only then), its list's link noted.  Keeps all.
rs_wbegin:
	movem.l d0-d2/a0,-(sp)
	bsr.w   rs_check
	sf      RS_PREVOK
	sf      RS_IDOK
	move.w  #-2,RS_PSEQ             ; (no walk before: no signature matches)
	move.w  FX_WP,d2
	add.w   d2,d2                   ; (2 x this buffer)
	lea     RS_LNKB,a0
	move.w  #-1,(a0,d2.w)
	move.w  RS_CBUF,d0
	cmpi.w  #FX_NL,d0
	bhs.s   .np                     ; (none, or not kept: -1)
	cmp.w   FX_WP,d0
	beq.s   .np
	move.w  d0,(a0,d2.w)
	lea     RS_LNKS,a0
	move.w  RS_CSEQ,(a0,d2.w)
	st      RS_PREVOK
	move.w  RS_CSEQ,RS_PSEQ
	add.w   d0,d0
	add.w   d0,d0
	lea     fx_ltab,a0
	move.l  (a0,d0.w),RS_WPLIST
	move.w  FX_SY,d1                ; copies only with the same scroll, the same HUD use
	cmp.w   RS_CSY,d1
	bne.s   .np
	move.w  FX_SX,d1
	cmp.w   RS_CSX,d1
	bne.s   .np
	move.b  FX_HOK,d1
	cmp.b   RS_CHOK,d1
	bne.s   .np
	st      RS_IDOK
.np:	addq.w  #1,RS_WCNT              ; this walk (its own number: HAL_FRAMES may not
	move.w  FX_WP,d0                ; move from one walk to the next)
	move.w  d0,RS_CBUF
	move.w  RS_WCNT,RS_CSEQ
	move.w  RS_WCNT,RS_WSEQ
	add.w   d0,d0
	lea     RS_BSEQ,a0
	move.w  RS_WCNT,(a0,d0.w)
	lsr.w   #1,d0
	move.w  FX_SY,RS_CSY
	move.w  FX_SX,RS_CSX
	move.b  FX_HOK,RS_CHOK
	add.w   d0,d0
	add.w   d0,d0
	lea     fx_ltab,a0
	move.l  (a0,d0.w),RS_WLIST
	lea     rs_lnkt(pc),a0
	move.l  (a0,d0.w),RS_WLNK
	movem.l (sp)+,d0-d2/a0
	rts

; (fx_walk) object a0, as fx_obj (a1 the list on, a2 its end, d6 units left; C set: no
; time, nothing done): the same as in the walk before (its fields, its position, the
; scroll), its entries copied from that walk's list; else fx_obj, its signature kept
; (only its position when the rest is the same).  Its entries' links.  Clobbers d0,
; d1, d4, d5, d7, a3, a4, a5 (fx_obj's).
rs_obj:
	subi.w  #FXU_RSG,d6             ; (the check, charged first)
	bpl.s   .g0
	addi.w  #FXU_RSG,d6
	ori     #1,ccr
	rts
.g0:	move.l  a0,d0
	subi.l  #G_DX_OBJ1,d0
	lsr.l   #2,d0                   ; its signature: 96 bytes an object, 24 a signature
	cmpi.l  #RS_NSLOT*RS_SIGSZ,d0
	bhs.w   .plain
	lea     RS_SIG,a5
	adda.w  d0,a5
	moveq   #0,d4                   ; (made again: all of its signature)
	moveq   #0,d7                   ; its entries in the walk before (none)
	move.w  SG_SEQ(a5),d0           ; walked in the walk before?
	cmp.w   RS_PSEQ,d0
	bne.w   .gen
	move.w  SG_FIRST(a5),d7         ; (its first entry << 8 | entries, never copied)
	move.l  $1a(a0),d0              ; the same but its position?
	cmp.l   SG_TAB(a5),d0
	bne.w   .gen
	move.w  4(a0),d0
	cmp.w   SG_B4(a5),d0
	bne.w   .gen
	move.w  $16(a0),d0
	cmp.w   SG_TYPE(a5),d0
	bne.w   .gen
	move.b  $19(a0),d0
	cmp.b   SG_B19(a5),d0
	bne.w   .gen
	move.b  $2a(a0),d0
	cmp.b   SG_B2A(a5),d0
	bne.w   .gen
	move.b  1(a0),d0
	cmp.b   SG_B1(a5),d0
	bne.w   .gen
	move.b  $43(a0),d0
	cmp.b   SG_B43(a5),d0
	bne.w   .gen
	andi.b  #$c0,d0
	beq.s   .p
	move.l  $44(a0),d0
	cmp.l   SG_T44(a5),d0
	bne.w   .gen
.p:	moveq   #1,d4                   ; (made again: its position only)
	move.l  $e(a0),d0
	cmp.l   SG_YX(a5),d0
	bne.w   .gen
	tst.b   RS_IDOK                 ; (the same scroll)
	beq.w   .gen
	tst.b   d7                      ; (never copied)
	bmi.w   .gen
	; the same: its entries again (room in the list, in time?)
	moveq   #$7f,d1
	and.w   d7,d1                   ; entries
	move.w  d7,d4
	lsr.w   #8,d4                   ; the first
	move.w  d4,d0
	add.w   d1,d0
	cmpi.w  #FX_LMAX,d0             ; (bounded)
	bhi.w   .gen
	move.w  d1,d0
	lsl.w   #3,d0
	lea     (a1,d0.w),a3
	cmpa.l  a2,a3
	bhi.w   .gen
	move.w  d1,d0                   ; charge: FXU_RSK + 6 per entry
	add.w   d0,d0
	move.w  d0,d5
	add.w   d0,d0
	add.w   d5,d0
	addi.w  #FXU_RSK,d0
	sub.w   d0,d6
	bpl.s   .ct
	add.w   d0,d6
	ori     #1,ccr
	rts
.ct:	move.l  a1,d0                   ; this list's entry j
	sub.l   RS_WLIST,d0
	lsr.w   #3,d0
	move.w  RS_WSEQ,SG_SEQ(a5)      ; (its signature: in this walk, at j)
	move.b  d0,SG_FIRST(a5)
	tst.w   d1
	beq.s   .cx
	movea.l RS_WLNK,a4
	adda.w  d0,a4
	move.w  d4,d5                   ; links: $80 + the walk before's entry
	ori.b   #$80,d5
	lsl.w   #3,d4
	movea.l RS_WPLIST,a3
	adda.w  d4,a3
	subq.w  #1,d1
.cp:	move.l  (a3)+,(a1)+
	move.l  (a3)+,(a1)+
	move.b  d5,(a4)+
	addq.b  #1,d5
	dbra    d1,.cp
.cx:	andi    #$fe,ccr
	rts
.plain:	jmp     fx_obj                  ; (not a slot: no signature, no links)
	; made again
.gen:	move.w  FX_HSEEN,-(sp)          ; (HUD takes by it: never copied)
	movem.l d4/d7/a1/a5,-(sp)
	jsr     fx_obj
	movem.l (sp)+,d4/d7/a3/a5       ; (keep the flags: a3 its first entry)
	movem.w (sp)+,d5
	bcs.w   .gx
	move.l  $e(a0),SG_YX(a5)        ; its signature
	move.w  RS_WSEQ,SG_SEQ(a5)
	tst.w   d4
	bne.s   .gp                     ; (the rest the same)
	move.l  $1a(a0),SG_TAB(a5)
	move.l  $44(a0),SG_T44(a5)
	move.w  4(a0),SG_B4(a5)
	move.w  $16(a0),SG_TYPE(a5)
	move.b  $19(a0),SG_B19(a5)
	move.b  $2a(a0),SG_B2A(a5)
	move.b  $43(a0),SG_B43(a5)
	move.b  1(a0),SG_B1(a5)
.gp:	moveq   #0,d4                   ; never copied: HUD takes, a table in RAM (the
	cmp.w   FX_HSEEN,d5             ; object rewrites it: its pieces change under the
	bne.s   .h1                     ; same pointer), tiles that change under an entry
	cmpi.l  #$80000,$1a(a0)
	bhs.s   .h1
	move.b  $43(a0),d0
	andi.b  #$c0,d0
	beq.s   .h0
	cmpi.l  #$80000,$44(a0)
	blo.s   .h0
.h1:	move.w  #$80,d4
.h0:	move.l  a3,d1                   ; its first entry j0, entries
	sub.l   RS_WLIST,d1
	lsr.w   #3,d1
	move.b  d1,SG_FIRST(a5)
	move.l  a1,d0
	sub.l   a3,d0
	lsr.w   #3,d0
	beq.s   .gf
	move.l  a6,-(sp)                ; (the walk's: borrowed for rs_lutb)
	lea     rs_lutb,a6
	movea.l RS_WLNK,a4              ; links: the walk before's entry of the same
	adda.w  d1,a4                   ; ordinal (to compare), else none
	moveq   #$7f,d1
	and.w   d7,d1                   ; the walk before's entries
	lsr.w   #8,d7                   ; its first
	move.w  d0,-(sp)
	subq.w  #1,d0
.tl:	moveq   #-1,d5
	tst.w   d1
	beq.s   .tn
	subq.w  #1,d1
	move.b  d7,d5
	addq.w  #1,d7
.tn:	move.b  d5,(a4)+
	move.w  6(a3),d5                ; (tiles that change without it?)
	lsr.w   #6,d5
	andi.w  #$ff,d5
	tst.b   (a6,d5.w)
	beq.s   .th
	move.w  #$80,d4
.th:	addq.l  #8,a3
	dbra    d0,.tl
	move.w  (sp)+,d0
	movea.l (sp)+,a6
.gf:	or.w    d4,d0
	move.b  d0,SG_NF(a5)
	andi    #$fe,ccr
.gx:	rts

; Per 64 lookup entries (w3 bits 6-13, an entry's first tile): 1 if an entry starting
; there may show tiles the game changes in the lookup RAM without changing the entry
; (measured, movie7 and attract: the HUD 0x3fc0-0x3fff, 0x2fec-0x2ffd, 0x3800-0x3880;
; runs up to 64 tiles): never kept, its object never copied.
rs_lutb:
	dc.b    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	dc.b    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	dc.b    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	dc.b    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	dc.b    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	dc.b    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1
	dc.b    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1
	dc.b    1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1

; (the game's lookup RAM loader, 0x2bbca: movea.l #lookup,a2 -> jsr here) a scene's
; lookup RAM: what is kept shows old tiles - the next list keeps nothing.
rs_lutld:
	movea.l #G_SPRLUT,a2
	st      RS_LUTD
	rts

; ================================================================ init
rs_init:
	move.w  #-1,HAL_SPR_SHOWN
	move.w  #-1,HAL_SPR_W
	clr.l   HAL_SPR_ST
	clr.l   HAL_SPR_MIX
	sf      HAL_SPR_DONE
	clr.l   HAL_SPR_RA5
	clr.l   HAL_SPR_BLK             ; (and HAL_SPR_INQ)
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
; (and when a magic word is gone: the boot RAM test) every pool column free, nothing
; shown, nothing in work, no walk to link to.  Keeps all.
rs_reset:
	movem.l d0-d1/a0/a3,-(sp)
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
	lea     RS_COLM,a0
	move.w  #382/2-1,d1
.c:	clr.w   (a0)+
	dbra    d1,.c
	lea     RS_V,a0
	move.w  #(RS_W+78-RS_V)/2-1,d1
.v:	clr.w   (a0)+
	dbra    d1,.v
	lea     RS_SIG+SG_SEQ,a0        ; (no signature of the walk before)
	move.w  #RS_NSLOT-1,d1
.g:	move.w  #$ffff,(a0)
	sf      SG_NF-SG_SEQ(a0)
	lea     RS_SIGSZ(a0),a0
	dbra    d1,.g
	move.l  #RS_C0A,RS_PC0
	move.l  #RS_C0B,RS_SC0
	move.w  #-1,RS_CUR
	move.w  #-1,RS_CBUF
	lea     RS_LNKB,a0
	moveq   #4,d1
.l:	move.w  #-1,(a0)+
	dbra    d1,.l
	move.l  #RS_MAGICV,RS_MAGIC
	move.l  #RS_MAGICV,RS_MAG2
	move.l  #RS_MAGICV,RS_MAG3
	move.w  #-1,HAL_SPR_W
	clr.l   HAL_SPR_RA5
	sf      HAL_SPR_ST
	move.w  #-1,FX_SBUF
	move.w  #-1,FX_CBUF
	movem.l (sp)+,d0-d1/a0/a3
	rts

; Z clear: the state was gone (reset now).  Keeps all.
rs_check:
	cmpi.l  #RS_MAGICV,RS_MAGIC
	bne.s   .r
	cmpi.l  #RS_MAGICV,RS_MAG2
	bne.s   .r
	cmpi.l  #RS_MAGICV,RS_MAG3
	bne.s   .r
	rts
.r:	bsr.w   rs_reset
	move.w  #0,ccr
	rts

; ================================================================ slot start
rs_slot:
	sf      HAL_SPR_DONE
	tst.w   HAL_SPR_W
	bmi.s   .x
	bset    #0,HAL_SPR_MIX          ; (a conversion carried into this slot)
	addq.l  #1,HAL_SPR_CARRY
.x:	rts

; ================================================================ work
; As the ring's: while the budget lasts (HAL_SPR_RES lines left to the rest), the list
; in work on, else (none, none begun in this slot, nothing waiting for its flip) this
; slot's list begun.  Z set: nothing left to do now; Z clear: the budget stopped it.
rs_work:
	tst.b   HAL_OUT
	bne.w   .no
	jsr     hal_spr_klim
	addq.w  #3,d0
	tst.w   HAL_SPR_TAILU
	beq.s   .nt
	addq.w  #(SPR_TAIL*16+767)/768,d0
.nt:	bgt.w   .no
	bsr.w   rs_check
	tst.w   HAL_SPR_W
	bpl.s   .go
	tst.b   HAL_SPR_DONE
	bne.s   .ok
	tst.b   HAL_SPR_ST              ; (complete: waits for its flip)
	bne.s   .ok
	jsr     hal_spr_left
	addi.w  #BEGIN_LINES+SCAN_LINES,d0
	tst.w   HAL_SPR_TAILU
	beq.s   .bt
	addq.w  #(SPR_TAIL*16+767)/768,d0
.bt:	bgt.s   .no
	bsr.w   rs_begin
.go:	cmpi.w  #1,RS_PH
	bne.s   .cv
	bsr.w   rs_match
	bne.s   .no
.cv:	tst.w   RS_NEWN                 ; (all kept: nothing to convert)
	beq.s   .fin
	moveq   #0,d0
	jsr     hal_spr_set
	movea.l HAL_SPR_RA5,a5
	jsr     hal_spr_go
	bne.s   .no
.fin:	bsr.w   rs_fin
.ok:	moveq   #0,d0                   ; Z set
	rts
.no:	tst.b   HAL_BG_EARLY
	bne.s   .no1
	st      HAL_OUT
.no1:	moveq   #1,d0                   ; Z clear
	rts

; This slot's list (fx_start: list k - FX_DELAY) in work: set 0 converting.  Matched by
; its links if they lead to the shown list.
rs_begin:
	jsr     fx_start                ; (a5, FX_CI, FX_CL, FX_AEND, FX_BC8)
	st      HAL_SPR_DONE
	move.b  #2,HAL_SPR_ST
	clr.w   HAL_SPR_W
	sf      HAL_SPR_MIX
	move.w  HAL_FRAMES+2,d1         ; shown from the next slot on
	addq.w  #1,d1
	move.w  d1,HAL_SPR_RDY
	move.w  FX_CI,RS_PBUF
	move.w  FX_BC8,d0
	lsr.w   #3,d0
	move.w  d0,RS_PN
	move.l  #SPR_POOL*256,d1
	addq.w  #1,d0
	divu    d0,d1
	bvc.s   .st
	moveq   #0,d1
.st:	move.w  d1,RS_STEP
	clr.w   RS_PI
	clr.w   RS_NEWN
	clr.w   RS_MVN
	clr.w   RS_KN
	clr.w   RS_DN
	move.w  #-1,RS_CUR
	clr.w   RS_SI
	clr.w   RS_SE
	move.w  FX_CI,d0
	add.w   d0,d0
	add.w   d0,d0
	move.b  RS_LUTD,RS_NOKEEP       ; (the lookup RAM loaded since: nothing kept)
	sf      RS_LUTD
	sf      RS_FAST                 ; its links lead to S (the list, its walk)?
	lsr.w   #1,d0
	lea     RS_LNKB,a0
	move.w  (a0,d0.w),d1
	bmi.s   .sl
	cmp.w   FX_SBUF,d1
	bne.s   .sl
	lea     RS_LNKS,a0
	move.w  (a0,d0.w),d2
	add.w   d1,d1
	lea     RS_BSEQ,a0
	cmp.w   (a0,d1.w),d2
	bne.s   .sl
	st      RS_FAST
	addq.l  #1,RS_NFAST
.sl:	moveq   #0,d0                   ; set 0 for hal_spr_go: no heads yet, its columns
	jsr     hal_spr_set             ; per entry (SS_HNEXT), never short (SS_HMIN)
	clr.w   SS_HOFF(a6)
	clr.w   SS_ZN(a6)
	sf      SS_PRIO(a6)
	move.w  #SPR_PB,SS_HMIN(a6)
	move.w  #SPR_PT+1,SS_HNEXT(a6)
	move.l  FX_CL,HAL_SPR_RA5
	move.w  #1,RS_PH
	rts

; Complete: waits for its flip.
rs_fin:
	move.b  #1,HAL_SPR_ST
	move.w  #-1,HAL_SPR_W
	move.w  RS_PBUF,FX_CBUF
	move.w  #3,RS_PH
	rts

; ---------------------------------------------------------------- match
; P's entries from RS_PI on: kept or placed.  Z set: all done; Z clear: out of time
; (on from RS_PI).  Clobbers all.
RS_LINES        equ 4                   ; lines a time check's entries may take (2 compared,
                                        ; or 1 the slow way: <= ~2k cycles; a placement checks
                                        ; its own)
rs_match:
	move.w  #1,REG_VRAMMOD
	tst.b   RS_FAST
	bne.s   rs_mfast
	st      RS_NOKEEP               ; (not linked to S: all of it new)
	addq.l  #1,RS_NSLOW
	st      RS_FAST
rs_mfast:
; By the links.  Registers: a0 P entry, a2 P column table entry, a3 S list, a4 S column
; table, a5 P link, d7 entry, d6 entries.
	move.w  RS_PI,d7
	move.w  RS_PN,d6
	movea.l FX_CL,a0
	move.w  d7,d0
	lsl.w   #3,d0
	adda.w  d0,a0
	movea.l RS_PC0,a2
	adda.w  d7,a2
	adda.w  d7,a2
	move.w  RS_PBUF,d0
	add.w   d0,d0
	add.w   d0,d0
	lea     rs_lnkt(pc),a5
	movea.l (a5,d0.w),a5
	adda.w  d7,a5
	movea.l RS_SLIST,a3
	movea.l RS_SC0,a4
.e:	cmp.w   d6,d7
	bhs.w   .done
	moveq   #1,d0                   ; (time: every 2 entries)
	and.w   d7,d0
	bne.s   .nt
	jsr     hal_spr_left
	addq.w  #RS_LINES,d0
	bgt.w   .stop
.nt:	moveq   #0,d0
	move.b  (a5)+,d0
	cmpi.b  #$ff,d0
	beq.w   .new
	bclr    #7,d0
	beq.s   .cmp
	tst.b   RS_NOKEEP
	bne.w   .new
	cmp.w   RS_SN,d0                ; the same entry: its columns
	bhs.w   .new
	move.w  d0,d3
	lsl.w   #3,d3                   ; (the same words: checked)
	lea     (a3,d3.w),a6
	move.l  (a0),d1
	cmp.l   (a6)+,d1
	bne.s   .cmd
	move.l  4(a0),d1
	cmp.l   (a6),d1
	bne.s   .cmd
	add.w   d0,d0
	move.w  (a4,d0.w),d1
	cmpi.w  #C_NONE,d1
	beq.w   .new
	ori.w   #C_TAKEN,(a4,d0.w)
	andi.w  #C_RUN,d1
	ori.w   #C_KEPT,d1
	move.w  d1,(a2)+
	addq.w  #1,RS_KN
	addq.w  #1,d7
	addq.l  #8,a0
	bra.w   .e
.cmd:	addq.l  #1,RS_NBADL             ; (diagnostics: a link not the same after all)
.cmp:	cmp.w   RS_SN,d0                ; compared with S's entry d0
	bhs.w   .new
	move.w  d0,d3
	bsr.w   rs_cmp
	bne.s   .new
	addq.w  #1,d7
	addq.l  #8,a0
	bra.w   .e
.new:	bsr.w   rs_place
	cmpi.w  #C_LATER,d0
	beq.s   .lat
	move.w  d0,(a2)+
	addq.w  #1,d7
	addq.l  #8,a0
	bra.w   .e
.lat:	subq.l  #1,a5                   ; (this entry again)
	bra.w   .stop
.done:
	bra.w   rs_mdone
.stop:	move.w  d7,RS_PI
	moveq   #1,d0                   ; Z clear
	rts

; P's entry a0 (d7) and S's entry d3: kept (its column table entry written at a2+, S's
; taken; moved: noted) - Z set; else Z clear.  Clobbers d0, d1, d5, a6.
rs_cmp:
	tst.b   RS_NOKEEP
	bne.w   .no
	move.w  6(a0),d5                ; (tiles that change without it: rs_lutb)
	lsr.w   #6,d5
	andi.w  #$ff,d5
	lea     rs_lutb,a6
	tst.b   (a6,d5.w)
	bne.w   .no
	move.w  d3,d1
	add.w   d1,d1
	move.w  (a4,d1.w),d0            ; S's columns
	cmpi.w  #C_NONE,d0
	beq.w   .no
	lsl.w   #2,d1
	lea     (a3,d1.w),a6
	move.l  4(a0),d1                ; w2, w3
	cmp.l   4(a6),d1
	bne.w   .no
	move.l  (a0),d1                 ; w0, w1: zoom, sizes
	move.l  (a6),d5
	eor.l   d1,d5
	andi.l  #$fe00fe00,d5
	bne.w   .no
	move.w  d3,d1                   ; kept: its columns, S's taken
	add.w   d1,d1
	ori.w   #C_TAKEN,(a4,d1.w)
	andi.w  #C_RUN,d0
	ori.w   #C_KEPT,d0
	move.w  d0,(a2)+
	addq.w  #1,RS_KN
	move.l  (a0),d1                 ; moved?
	cmp.l   (a6),d1
	beq.s   .k
	move.w  RS_MVN,d1
	lea     RS_MV,a6
	move.b  d7,(a6,d1.w)
	addq.w  #1,RS_MVN
.k:	moveq   #0,d0                   ; Z set
	rts
.no:	moveq   #1,d0                   ; Z clear
	rts

; (both ways) P matched: on to its conversion.  Z set.
rs_mdone:
	moveq   #0,d0
	move.w  RS_KN,d0
	add.l   d0,RS_NKEPT
	move.w  RS_NEWN,d0
	add.l   d0,RS_NNEW
	move.w  RS_MVN,d0
	add.l   d0,RS_NMOVED
	move.w  RS_DN,d0
	add.l   d0,RS_NDROP
	move.w  #2,RS_PH
	move.w  RS_PN,RS_PI
	moveq   #0,d0                   ; Z set
	rts

; Columns for P's entry a0 (d7 of d6): the free run nearest its share of the pool by
; list position (front: the top) within RS_NEAR columns, else the lowest anywhere; SCB3
; of its chained columns written (its head stays 0: hidden until the flip).  d0 = its
; end column; C_NONE: no room, or no head slot left (dropped); C_LATER: no time for the
; search now (nothing done).  Keeps all but d0, d1, a6.
RS_NEAR         equ 64
C_LATER         equ $fffe
rs_place:
	movem.l d2-d5,-(sp)
	cmpi.w  #SS_MAXHEAD,RS_NEWN
	bhs.w   .no
	jsr     hal_spr_left            ; (time: the near search, ~4.6 lines at most)
	addq.w  #5,d0
	bgt.w   .later
	move.w  2(a0),d5                ; n: xsize + 1
	rol.w   #7,d5
	andi.w  #7,d5
	addq.w  #1,d5
	move.w  d6,d1                   ; target: SPR_PB + pool (entries - this) /
	sub.w   d7,d1                   ; (entries + 1) - n / 2
	mulu    RS_STEP,d1
	lsr.l   #8,d1
	addi.w  #SPR_PB,d1
	move.w  d5,d0
	lsr.w   #1,d0
	sub.w   d0,d1
	cmpi.w  #SPR_PB,d1
	bge.s   .t1
	move.w  #SPR_PB,d1
.t1:	move.w  #SPR_PT+1,d0
	sub.w   d5,d0
	cmp.w   d0,d1
	ble.s   .t2
	move.w  d0,d1
.t2:	lea     RS_COLM,a6
	; down: the highest free run of n whose top is at most target + n - 1, its first
	; column not below target - RS_NEAR
	move.w  d1,d2
	add.w   d5,d2
	subq.w  #1,d2
	move.w  d1,d0
	subi.w  #RS_NEAR,d0
	cmpi.w  #SPR_PB,d0
	bge.s   .d0
	move.w  #SPR_PB,d0
.d0:	moveq   #0,d3                   ; free so far
	moveq   #-1,d4                  ; found (none)
.dn:	cmp.w   d0,d2
	blt.s   .dx
	tst.b   (a6,d2.w)
	bne.s   .db
	addq.w  #1,d3
	cmp.w   d5,d3
	beq.s   .df
	subq.w  #1,d2
	bra.s   .dn
.db:	moveq   #0,d3
	subq.w  #1,d2
	bra.s   .dn
.df:	move.w  d2,d4                   ; its first column
	cmp.w   d1,d4
	beq.w   .got                    ; (right there)
.dx:	; up: the lowest free run of n from target on, nearer than the one below
	move.w  d1,d0                   ; (its first column at most target + RS_NEAR, or
	addi.w  #RS_NEAR,d0             ; nearer than the one below)
	tst.w   d4
	bmi.s   .u0
	move.w  d1,d0
	add.w   d1,d0
	sub.w   d4,d0                   ; target + (target - below)
.u0:	add.w   d5,d0
	subq.w  #1,d0                   ; (its last column)
	cmpi.w  #SPR_PT,d0
	ble.s   .u1
	move.w  #SPR_PT,d0
.u1:	move.w  d1,d2
	moveq   #0,d3
.up:	cmp.w   d0,d2
	bgt.s   .ux
	tst.b   (a6,d2.w)
	bne.s   .ub
	addq.w  #1,d3
	cmp.w   d5,d3
	beq.s   .uf
	addq.w  #1,d2
	bra.s   .up
.ub:	moveq   #0,d3
	addq.w  #1,d2
	bra.s   .up
.uf:	sub.w   d5,d2                   ; its first column
	addq.w  #1,d2
	move.w  d2,d4
	bra.s   .got
.ux:	tst.w   d4
	bpl.s   .got
	; none near: the lowest free run anywhere (time: ~12 lines at most)
	jsr     hal_spr_left
	addi.w  #12,d0
	bgt.w   .later
	move.w  #SPR_PB,d2
	moveq   #0,d3
.an:	cmpi.w  #SPR_PT,d2
	bgt.s   .no
	tst.b   (a6,d2.w)
	bne.s   .ab
	addq.w  #1,d3
	cmp.w   d5,d3
	beq.s   .af
	addq.w  #1,d2
	bra.s   .an
.ab:	moveq   #0,d3
	addq.w  #1,d2
	bra.s   .an
.af:	sub.w   d5,d2
	addq.w  #1,d2
	move.w  d2,d4
.got:	move.w  d4,d0                   ; columns d4 .. d4 + n - 1: in use, chained
	move.w  d5,d1
	subq.w  #1,d1
.m:	st      (a6,d0.w)
	addq.w  #1,d0
	dbra    d1,.m
	move.w  d5,d1
	subq.w  #2,d1
	bmi.s   .one
	move.w  d4,d0
	addi.w  #SCB3+1,d0
	move.w  d0,REG_VRAMADDR
	moveq   #$40,d0
.ch:	move.w  d0,REG_VRAMRW           ; (>= 12 cycles apart: the loop)
	dbra    d1,.ch
.one:	move.w  d5,d0                   ; its run: end column, columns - 1, zoomed
	subq.w  #1,d0
	lsl.w   #8,d0
	add.w   d0,d0
	add.w   d4,d0
	add.w   d5,d0
	move.w  (a0),d1
	or.w    2(a0),d1
	cmpi.w  #$1000,d1
	blo.s   .nz
	bset    #12,d0
.nz:	addq.w  #1,RS_NEWN
	movem.l (sp)+,d2-d5
	rts
.no:	addq.w  #1,RS_DN
	addq.l  #1,HAL_SPR_DROP
	bset    #1,HAL_SPR_MIX          ; (a slip when shown)
	move.w  #C_NONE,d0
	movem.l (sp)+,d2-d5
	rts
.later:	move.w  #C_LATER,d0
	movem.l (sp)+,d2-d5
	rts

; ================================================================ flip
; Inside the real vblank: the complete list shown (its new heads, its moved kept ones,
; the shown ones not kept hidden), as the ring's flip times it; none (or no time): the
; old one stays (a slip).
rs_flip:
	bsr.w   rs_check
	cmpi.b  #1,HAL_SPR_ST
	bne.w   .none
	move.w  HAL_SPR_RDY,d1
	sub.w   HAL_FRAMES+2,d1         ; (frame numbers wrap: the sign of the difference)
	tst.w   d1
	bgt.w   .none
	; time: ~40 cycles a word written (heads, moved x 2, hidden x their columns + 2)
	move.w  RS_NEWN,d0
	move.w  RS_MVN,d1
	add.w   d1,d1
	add.w   d1,d0
	move.w  RS_SPRES,d1
	sub.w   RS_KN,d1
	bpl.s   .h0
	moveq   #0,d1
.h0:	mulu    #6,d1
	add.w   d1,d0
	mulu    #40,d0
	addi.l  #600+767,d0
	divu    #768,d0
	move.w  d0,-(sp)                ; (hal/fx.s: its list's fix-layer text with it)
	move.w  RS_PBUF,d0
	jsr     fx_hud_count
	move.w  d0,d1
	lsr.w   #2,d1
	add.w   d1,d0
	add.w   (sp),d0
	sf      FX_FNOH
	jsr     hal_late_n
	beq.s   .fit
	cmpi.b  #2,FX_FLATE
	blo.s   .nft
	st      FX_FNOH
	move.w  (sp),d0
	jsr     hal_late_n
	beq.s   .fit
.nft:	addq.l  #2,sp
	bra.w   .defer
.fit:	addq.l  #2,sp
	lea     REG_VRAMRW,a3
	lea     REG_VRAMADDR,a4
	move.w  #1,REG_VRAMMOD
	moveq   #0,d0                   ; the new ones' heads (set 0's)
	jsr     hal_spr_set
	lea     SS_HADR(a6),a0
	lea     SS_HVAL(a6),a1
	move.w  SS_HOFF(a6),d2
	add.w   d2,d2
	lea     .se(pc),a2
	suba.w  d2,a2
	jmp     (a2)
	rept SS_MAXHEAD
	move.w  (a0)+,(a4)
	move.w  (a1)+,(a3)
	endr
.se:	movea.l FX_CL,a0                ; the moved kept ones: head SCB3, SCB4
	movea.l RS_PC0,a1
	lea     spr_zh,a5
	lea     RS_MV,a2
	move.w  RS_MVN,d7
	bra.s   .m1
.m:	moveq   #0,d0
	move.b  (a2)+,d0
	move.w  d0,d1
	add.w   d1,d1
	move.w  (a1,d1.w),d3            ; its run
	move.w  d3,d6
	lsr.w   #8,d6
	lsr.w   #1,d6
	andi.w  #7,d6                   ; columns - 1
	andi.w  #$1ff,d3
	sub.w   d6,d3
	subq.w  #1,d3                   ; its first column
	lsl.w   #2,d1
	movem.w (a0,d1.w),d4-d5         ; w0, w1
	move.w  d4,d6                   ; SCB3 = (496 - oy) << 7 | height (spr_zh: the
	rol.w   #7,d6                   ; rows the vertical shrink shows; ysize + 1
	andi.w  #$7f,d6                 ; unzoomed)
	move.b  (a5,d6.w),d6
	neg.w   d4
	addi.w  #496,d4
	lsl.w   #7,d4
	or.w    d6,d4
	move.w  d3,d0
	addi.w  #SCB3,d0
	move.w  d0,(a4)
	move.w  d4,(a3)
	addi.w  #SCB4-SCB3,d0
	move.w  d0,(a4)
	lsl.w   #7,d5                   ; SCB4 = ox << 7
	move.w  d5,(a3)
.m1:	dbra    d7,.m
	movea.l RS_SLIST,a0             ; the shown ones not kept: hidden, columns free
	movea.l RS_SC0,a1
	lea     RS_COLM,a2
	move.w  RS_SN,d7
	cmpi.w  #FX_LMAX,d7             ; (bounded: the boot RAM test)
	bls.s   .h1
	moveq   #0,d7
	bra.s   .h1
.h:	move.w  (a1)+,d3
	cmpi.w  #C_NONE,d3
	beq.s   .hn
	btst    #14,d3                  ; (C_TAKEN)
	bne.s   .hn
	move.w  d3,d5                   ; its run: columns - 1
	lsr.w   #8,d5
	lsr.w   #1,d5
	andi.w  #7,d5
	move.w  d3,-(sp)                ; (zoomed: bit 12)
	andi.w  #$1ff,d3
	sub.w   d5,d3
	subq.w  #1,d3                   ; its first column
	move.w  (sp)+,d4
	cmpi.w  #SPR_PB,d3
	blt.s   .hn
	move.w  d3,d0
	add.w   d5,d0
	cmpi.w  #SPR_PT,d0
	bgt.s   .hn
	move.w  d3,d0
	addi.w  #SCB3,d0
	move.w  d0,(a4)
	moveq   #0,d1
	move.w  d5,d6
.hz:	move.w  d1,(a3)                 ; head and chain: 0
	clr.b   (a2,d3.w)
	addq.w  #1,d3
	dbra    d6,.hz
	btst    #12,d4                  ; zoomed: SCB2 back to full size
	beq.s   .hn
	sub.w   d5,d3
	subq.w  #1,d3
	addi.w  #SCB2,d3
	move.w  d3,(a4)
	move.w  #$0fff,d1
	move.w  d5,d6
.hs:	move.w  d1,(a3)
	nop
	dbra    d6,.hs
.hn:	addq.l  #8,a0
.h1:	dbra    d7,.h
	move.l  RS_PC0,d0               ; P is shown: S
	move.l  RS_SC0,RS_PC0
	move.l  d0,RS_SC0
	move.l  FX_CL,RS_SLIST
	move.w  RS_PN,d0
	move.w  d0,RS_SN
	sub.w   RS_DN,d0
	move.w  d0,RS_SPRES
	clr.w   RS_PH
	sf      HAL_SPR_ST
	clr.w   HAL_SPR_SHOWN
	move.w  RS_PBUF,FX_SBUF
	move.w  #-1,FX_CBUF
	move.w  RS_PBUF,d0              ; (hal/fx.s: the fix layer with these sprites)
	jsr     fx_flip_hud
	move.b  HAL_SPR_MIX,d0
	btst    #1,d0                   ; sprites dropped?
	beq.s   .nd
	addq.l  #1,HAL_SPR_DROPN
	bset    #2,HAL_SLIP+1
.nd:	btst    #0,d0                   ; converted over more than its slot?
	beq.s   .ex
	addq.l  #1,HAL_SPR_MIXN
	bset    #2,HAL_SLIP+1
.ex:	rts
.defer:	addq.l  #1,HAL_SPR_LATE         ; no time to flip: it waits
	addq.w  #1,HAL_SPR_DBGD
	cmpi.b  #2,FX_FLATE
	bhs.s   .df
	addq.b  #1,FX_FLATE
.df:	bset    #2,HAL_SLIP+1
	rts
.none:	addq.l  #1,HAL_SPR_LATE         ; nothing complete to show
	bset    #2,HAL_SLIP+1
	rts
