; Not cycle-exact (AEROFGT_DIRECT=1): two of the game's object-slot loops, faster.
;
; Both spend most of their time on slots with nothing to do; these scan eight slots a
; turn and hand every slot that has something to do to the original code, so the game
; does exactly what it did (same registers wherever its own code runs or returns).  The
; time they free is the game's frame ending earlier: idle time the HAL's slot gets.
;
; 1. The main object loop (0x1996a..0x199aa: every slot 0x1010c0..0x107060, a non-zero
;    first byte -> its type's handler at 0x19976): jmp gx_upd at 0x1996a, the handler's
;    return path (0x199a0: adda, cmpa, bcs) jmp gx_updn.  Out of the loop (0x199ac, the
;    frame's end: the task switch at 0xaee saves every register) d0 is what the
;    original left: its last slot's byte if that slot was empty.
; 2. The collision scan (0x2a18c..0x2a1b4: D7 + 1 slots from A2, each with (b0 & 0x31)
;    = 1 tested against object A0 by 0x2a1f6/0x2a26a): jmp gx_col at 0x2a18c, its
;    continuation (0x2a1b0: adda, dbra) jmp gx_coln.  A candidate goes on at 0x2a198
;    with d0 as the original's (b0 & 0x31) - 1 = 0; the end at 0x2a1b8 (clr.l d0,
;    C clear) with A2 past the slots and D7 = -1, as the original.  A slot with b0 bit
;    0 clear is never a candidate (btst first).

GX_UPD_END      equ $107060

; ---------------------------------------------------------------- 1
gx_upd:
	ifne GX_BAND
	addq.w  #1,GXB_PASS             ; (7: a new pass - the collision index is stale)
	endif
	movea.l #$1010c0,a0             ; (the original's first instruction)
	bra.s   gx_upds
gx_updn:
	lea     $60(a0),a0              ; (the original's adda: the next slot)
gx_upds:
	cmpa.l  #GX_UPD_END-7*$60,a0    ; eight slots a turn while eight are left
	bhs.s   .t
	tst.b   (a0)
	bne.s   .o
	tst.b   $60(a0)
	bne.s   .o1
	tst.b   $c0(a0)
	bne.s   .o2
	tst.b   $120(a0)
	bne.s   .o3
	tst.b   $180(a0)
	bne.s   .o4
	tst.b   $1e0(a0)
	bne.s   .o5
	tst.b   $240(a0)
	bne.s   .o6
	tst.b   $2a0(a0)
	bne.s   .o7
	lea     $300(a0),a0
	bra.s   gx_upds
.o7:	lea     $60(a0),a0
.o6:	lea     $60(a0),a0
.o5:	lea     $60(a0),a0
.o4:	lea     $60(a0),a0
.o3:	lea     $60(a0),a0
.o2:	lea     $60(a0),a0
.o1:	lea     $60(a0),a0
.o:	move.b  (a0),d0                 ; (as the original: then its handler)
	jmp     $19976
.t:	cmpa.l  #GX_UPD_END,a0          ; the last ones, one a turn
	bhs.s   .x
	move.b  (a0),d0
	bne.s   .o
	lea     $60(a0),a0
	bra.s   .t
.x:	jmp     $199ac                  ; (d0: as the original's: the last slot always goes
	                                ; through .t, which loads it)

; ---------------------------------------------------------------- 2
; X matters: the game's random numbers (0x2a602) use roxl, and X leaves this loop as
; the original's last subq.w #1,d0 left it (or the hit checks, after a candidate):
; the continuation counts with dbra (no flags), an end after a slot rejected by its
; bit 0 does that slot's subq again.
gx_col:
	bra.s   gx_cols
gx_coln:
	lea     $60(a2),a2              ; (the original's adda, dbra)
	dbra    d7,gx_cols
	jmp     $2a1b8                  ; (X: the last op's, as the original's)
gx_cols:
	cmpi.w  #7,d7                   ; eight slots a turn while eight are left
	blt.w   .t
	tst.b   (a2)
	bne.s   .c
	tst.b   $60(a2)
	bne.s   .c1
	tst.b   $c0(a2)
	bne.s   .c2
	tst.b   $120(a2)
	bne.s   .c3
	tst.b   $180(a2)
	bne.s   .c4
	tst.b   $1e0(a2)
	bne.s   .c5
	tst.b   $240(a2)
	bne.s   .c6
	tst.b   $2a0(a2)
	bne.s   .c7
	lea     $300(a2),a2
	subq.w  #8,d7
	bra.s   gx_cols
.c7:	lea     $60(a2),a2
	subq.w  #1,d7
.c6:	lea     $60(a2),a2
	subq.w  #1,d7
.c5:	lea     $60(a2),a2
	subq.w  #1,d7
.c4:	lea     $60(a2),a2
	subq.w  #1,d7
.c3:	lea     $60(a2),a2
	subq.w  #1,d7
.c2:	lea     $60(a2),a2
	subq.w  #1,d7
.c1:	lea     $60(a2),a2
	subq.w  #1,d7
.c:	move.b  (a2),d0                 ; bit 0 set: the original's test (and its X)
	andi.w  #$31,d0
	subq.w  #1,d0
	bne.w   gx_coln
	ifne GX_XPRE
	; (4) the overlap test's own x compares first (0x2a1f6's first sixteen instructions,
	; the same registers): no x overlap -> on at 0x2a1a0 as the failed test leaves it
	; (d0, d1, d3 as below, C clear so the bcs at 0x2a19c is not taken, X untouched by
	; either); else into the test's y block (0x2a22c) with the return address the bsr at
	; 0x2a198 would have pushed.  93% of the calls failed on x (catalog: 3.97M calls,
	; 311k reached y).  GX_VERIFY: a failed pre-test runs the whole test too, a C set
	; counted in HAL_GX_MISS.
	move.w  80(a0),d0
	move.w  84(a2),d1
	move.w  (a3),d3
	eori.w  #$8000,d3
	cmp.w   d0,d1
	bcs.s   .xf
	cmp.w   d3,d1
	bcs.s   .xf
	move.w  84(a0),d0
	move.w  80(a2),d1
	move.w  4(a3),d3
	eori.w  #$8000,d3
	cmp.w   d1,d0
	bcs.s   .xf
	cmp.w   d1,d3
	bcs.s   .xf
	pea     $2a19c
	jmp     $2a22c
.xf:
	ifne GX_VERIFY
	jsr     $2a1f6
	bcc.s   .xv
	addq.l  #1,HAL_GX_MISS
.xv:
	endif
	jmp     $2a1a0
	else
	jmp     $2a198                  ; (a candidate: d0.w = 0)
	endif
.t:	tst.w   d7                      ; the last ones, one a turn
	bmi.s   .x
	tst.b   (a2)
	bne.s   .c
	lea     $60(a2),a2
	subq.w  #1,d7
	bra.s   .t
.x:	move.b  -$60(a2),d0             ; (the last slot, rejected by bit 0: its X)
	andi.w  #$31,d0
	subq.w  #1,d0
	jmp     $2a1b8                  ; (A2 past the slots, D7 = -1)

; 3. The same scan's twin at 0x2a088..0x2a0b0 (its candidates on at 0x2a094, its end
;    0x2a0b4: rts, CCR and X as the original's last op left them): jmp gx_col2 there,
;    its continuation (0x2a0ac) jmp gx_col2n.  (~20% of the game's time in the densest
;    attract scene, 2026-10-15.)
gx_col2:
	bra.s   gx_col2s
gx_col2n:
	lea     $60(a2),a2              ; (the original's adda, dbra)
	dbra    d7,gx_col2s
	jmp     $2a0b4                  ; (X: the last op's, as the original's)
gx_col2s:
	cmpi.w  #7,d7                   ; eight slots a turn while eight are left
	blt.w   .t
	tst.b   (a2)
	bne.s   .c
	tst.b   $60(a2)
	bne.s   .c1
	tst.b   $c0(a2)
	bne.s   .c2
	tst.b   $120(a2)
	bne.s   .c3
	tst.b   $180(a2)
	bne.s   .c4
	tst.b   $1e0(a2)
	bne.s   .c5
	tst.b   $240(a2)
	bne.s   .c6
	tst.b   $2a0(a2)
	bne.s   .c7
	lea     $300(a2),a2
	subq.w  #8,d7
	bra.s   gx_col2s
.c7:	lea     $60(a2),a2
	subq.w  #1,d7
.c6:	lea     $60(a2),a2
	subq.w  #1,d7
.c5:	lea     $60(a2),a2
	subq.w  #1,d7
.c4:	lea     $60(a2),a2
	subq.w  #1,d7
.c3:	lea     $60(a2),a2
	subq.w  #1,d7
.c2:	lea     $60(a2),a2
	subq.w  #1,d7
.c1:	lea     $60(a2),a2
	subq.w  #1,d7
.c:	move.b  (a2),d0                 ; bit 0 set: the original's test (and its X)
	andi.w  #$31,d0
	subq.w  #1,d0
	bne.w   gx_col2n
	jmp     $2a094                  ; (a candidate: d0.w = 0)
.t:	tst.w   d7                      ; the last ones, one a turn
	bmi.s   .x
	tst.b   (a2)
	bne.s   .c
	lea     $60(a2),a2
	subq.w  #1,d7
	bra.s   .t
.x:	move.b  -$60(a2),d0             ; (the last slot, rejected by bit 0: its X)
	andi.w  #$31,d0
	subq.w  #1,d0
	jmp     $2a0b4                  ; (A2 past the slots, D7 = -1)


	ifne GX_SCAN
; ---------------------------------------------------------------- 6 (GX_SCAN)
; shot_collide (0x2a142: a0 the shot, d2 its damage, a3 the playfield bounds; three
; pool scans 0x2a166/74/82 through the loop at 0x2a18c; a hit ends the whole thing
; through 0x2a1c0 with C set): the same from here (jmp at 0x2a142; the loop at 0x2a18c
; stays gx_col's for the bomb pieces' entry 0x2a0e8).  Faster in two ways, both exact:
;   * the overlap test's x block (0x2a1f6, the first sixteen instructions, 93% of the
;     tests end there) compares the candidate's x range against the shot's AND the
;     playfield's: max/min of those once a call (d4 = the left bound, d5 = the right),
;     two compares a candidate with their loads instead of four.  The registers the
;     failed block leaves (d1 the candidate's word, d3 the playfield's) are set the same
;     (d6 = the playfield's two words); d0 is dead (the loop's next slot or the end's
;     clr.l).  The second hitbox (76(a2): 0x2a26a, 92/88) the same way.
;   * a slot that is active but no target ((b0 & $31) != 1: every enemy bullet) costs
;     the original's six instructions' worth, not the eight-slot scanner's round trip
;     (gx_col: 82 cycles against 52).  Empty slots as gx_col.
; Out as the original: a hit through 0x2a1c0's own code (d0, C set; its rts comes back
; to the bsr); the end with d0 = 0, C clear, a2 past the slots, d7 = -1 and X = the last
; slot's subq (0x2a1b8's own code).  d4-d6 saved on the game's stack (the overlap tests
; and the hit code read none of it).  GX_VERIFY: a failed cheap test runs the original
; test too (a C set, or d1/d3 unlike its, counted in HAL_GX_MISS).
	ifne GX_VERIFY
GXS_D1          equ $d00f10         ; (GX_VERIFY: OVR_DIAG's RAM, not together)
GXS_D3          equ $d00f12
GXSV	macro                           ; (\1: 84 the first hitbox's test, 92 the second's)
	jsr     gxsv\1
	endm
	else
GXSV	macro
	endm
	endif
gx_scan:
	movem.l d4-d6,-(sp)
	movea.l #$50858,a3              ; (the original's: the bounds table)
	move.w  #$178,d0
	movea.l 0(a3,d0.w),a3
	move.w  4(a3),d6                ; d6 = the right bound << 16 | the left (both ^ $8000)
	eori.w  #$8000,d6
	swap    d6
	move.w  (a3),d6
	eori.w  #$8000,d6
	move.w  80(a0),d4               ; d4 = max(the shot's left, the playfield's)
	cmp.w   d6,d4
	bhs.s   .a
	move.w  d6,d4
.a:	move.w  84(a0),d5               ; d5 = min(the shot's right, the playfield's)
	swap    d6
	cmp.w   d6,d5
	bls.s   .b
	move.w  d6,d5
.b:	swap    d6
	ifne GX_BAND
	cmpa.l  #GXB_SHLO,a0            ; a shot of the shot region: the index (7)
	bcs.s   gx_scanp
	cmpa.l  #GXB_SHHI,a0
	bcs.w   gx_band
gx_scanp:                               ; (7: the slots scanned, d4-d6 on the stack)
	endif
	movea.l #$1019c0,a2             ; (0x2a166)
	move.w  #$17,d7
	bsr.s   .pool
	bcs.s   .x
	movea.l #$1040c0,a2             ; (0x2a174)
	move.w  #$f,d7
	bsr.s   .pool
	bcs.s   .x
	movea.l #$1052c0,a2             ; (0x2a182)
	move.w  #$2f,d7
	bsr.s   .pool
.x:	movem.l (sp)+,d4-d6
	rts
	; the slots a2, d7 + 1 of them: eight a turn while eight are left, a candidate
	; ((b0 & $31) = 1) tested, the end as 0x2a1b8
.pool:	cmpi.w  #7,d7
	blt.w   .t
	move.b  (a2),d0
	beq.s   .e0
	andi.w  #$31,d0
	subq.w  #1,d0
	beq.w   .cand
.e0:	move.b  $60(a2),d0
	beq.s   .e1
	andi.w  #$31,d0
	subq.w  #1,d0
	beq.w   .c1
.e1:	move.b  $c0(a2),d0
	beq.s   .e2
	andi.w  #$31,d0
	subq.w  #1,d0
	beq.s   .c2
.e2:	move.b  $120(a2),d0
	beq.s   .e3
	andi.w  #$31,d0
	subq.w  #1,d0
	beq.s   .c3
.e3:	move.b  $180(a2),d0
	beq.s   .e4
	andi.w  #$31,d0
	subq.w  #1,d0
	beq.s   .c4
.e4:	move.b  $1e0(a2),d0
	beq.s   .e5
	andi.w  #$31,d0
	subq.w  #1,d0
	beq.s   .c5
.e5:	move.b  $240(a2),d0
	beq.s   .e6
	andi.w  #$31,d0
	subq.w  #1,d0
	beq.s   .c6
.e6:	move.b  $2a0(a2),d0
	beq.s   .e7
	andi.w  #$31,d0
	subq.w  #1,d0
	beq.s   .c7
.e7:	lea     $300(a2),a2
	subq.w  #8,d7
	bra.w   .pool
.c7:	lea     $60(a2),a2
	subq.w  #1,d7
.c6:	lea     $60(a2),a2
	subq.w  #1,d7
.c5:	lea     $60(a2),a2
	subq.w  #1,d7
.c4:	lea     $60(a2),a2
	subq.w  #1,d7
.c3:	lea     $60(a2),a2
	subq.w  #1,d7
.c2:	lea     $60(a2),a2
	subq.w  #1,d7
.c1:	lea     $60(a2),a2
	subq.w  #1,d7
	; a candidate (d0 = 0, X clear as its subq left it): the x block's compares
.cand:	move.w  84(a2),d1
	cmp.w   d4,d1
	bcs.s   .f1
	move.w  80(a2),d1
	cmp.w   d1,d5
	bcs.s   .f2
	pea     .r1(pc)
	jmp     $2a22c                  ; the test's y block, its rts back here with C
.r1:	bcs.s   .hit
	bra.s   .second
.f1:	move.w  d6,d3                   ; (as the block's first compares leave d1, d3)
	GXSV    84
	bra.s   .second
.f2:	swap    d6                      ; (as its last two)
	move.w  d6,d3
	swap    d6
	GXSV    84
.second:
	tst.b   76(a2)                  ; (0x2a1a0) the second hitbox: 0x2a26a the same way
	beq.s   .next
	move.w  92(a2),d1
	cmp.w   d4,d1
	bcs.s   .g1
	move.w  88(a2),d1
	cmp.w   d1,d5
	bcs.s   .g2
	pea     .r2(pc)
	jmp     $2a2a0                  ; its y block
.r2:	bcs.s   .hit
	bra.s   .next
.g1:	move.w  d6,d3
	GXSV    92
	bra.s   .next
.g2:	swap    d6
	move.w  d6,d3
	swap    d6
	GXSV    92
.next:	lea     $60(a2),a2              ; (0x2a1b0)
	dbra    d7,.pool
	bra.s   .end
.hit:	jmp     $2a1c0                  ; (its rts: back to the bsr, C set)
.t:	tst.w   d7                      ; the last ones, one a turn
	bmi.s   .end
	move.b  (a2),d0
	beq.s   .tn
	andi.w  #$31,d0
	subq.w  #1,d0
	beq.w   .cand
.tn:	lea     $60(a2),a2
	subq.w  #1,d7
	bra.s   .t
.end:	move.b  -$60(a2),d0             ; (the last slot's subq: its X)
	andi.w  #$31,d0
	subq.w  #1,d0
	jmp     $2a1b8                  ; (clr.l d0, C clear, rts: back to the bsr)
	ifne GX_VERIFY
; (GX_VERIFY) after a failed cheap test: the original test must fail too and leave the
; same d1 and d3 (else HAL_GX_MISS).  Keeps everything but the flags.
gxsv84:	movem.l d0-d3,-(sp)
	move.w  d1,GXS_D1
	move.w  d3,GXS_D3
	jsr     $2a1f6
	bra.s   gxsv
gxsv92:	movem.l d0-d3,-(sp)
	move.w  d1,GXS_D1
	move.w  d3,GXS_D3
	jsr     $2a26a
gxsv:	bcs.s   .m
	cmp.w   GXS_D1,d1
	bne.s   .m
	cmp.w   GXS_D3,d3
	beq.s   .k
.m:	addq.l  #1,HAL_GX_MISS
.k:	movem.l (sp)+,d0-d3
	rts
	endif

	ifne GX_BAND
; ---------------------------------------------------------------- 7 (GX_BAND)
; AUDIT 43, the collision index: shot_collide's shots (a0 in the shot region,
; 0x1022c0..0x1040c0, between the first target pool and the second) visit only the
; targets near them.  The main object loop runs the region's slots in one stretch, after
; the first pool's handlers and before the others': between two of its calls nothing
; moves, spawns or arms a target (traced over 4 x 57k frames of every nation, the arcade:
; work/play/fh/gxtrace.lua - the one change is a target the hit code took, bit 5: the
; candidacy is tested again at the visit).  So the index is built at the pass's first
; call from the region (gx_upd counts the passes) and kept for the pass; calls from
; elsewhere (the bomb pieces, objects in the pools) scan the slots as gx_scan does.
;   The index: the targets ((b0 & $31) = 1) of the three pools in slot order, each with
; its x extent - the least and the largest of its x words (80/84, and 88/92 with 76 set).
; A target whose extent misses the shot's clipped range (d4/d5, as gx_scan's: max < d4
; or min > d5, either order) cannot pass the x block of either hitbox, and a failed x
; block has no side effect but d1/d3: skipping it is what the original's would have done.
; (AUDIT 43's x bands, built: an entry in ~2.8 band lists cost the build ~600 cycles a
; target, more than the bands saved the shots - the extent compare is ~50 cycles a
; skipped entry.)  More than GXB_CAP targets: the pass's calls scan (gx_scanp).
;   Out as the original: a hit through 0x2a1c0 with a2 the slot and d7 its pool count
; left (the dbra's: gx_bd7); no hit: d0 = 0, C clear, a2 past the last pool, d7 = -1, X
; the last slot's subq (as gx_scan), and d1/d3 as the slots' last target left them - the
; last one tested here, or (skipped) its failed x block's (its second hitbox's with 76
; set), computed; none: as they came.  GX_VERIFY: a side-effect-free scan of every slot
; with the original tests (0x2a1f6, 0x2a26a) first; its hit slot, or its d1/d3, compared
; (HAL_GX_MISS).
GXB_BASE        equ $10fc40         ; the index: the idle stack's deep end, after G_TRAMP's 48
                                    ; bytes (the stack's live top < 64 bytes; no write to
                                    ; 0x10fc30..0x10fdaf after the boot in 3 x 40k frames:
                                    ; work/play/fh/ramfree.lua WATCH)
GXB_SHLO        equ $1022c0         ; the shot region
GXB_SHHI        equ $1040c0
GXB_PASS        equ GXB_BASE        ; w: the main loop's passes (gx_upd)
GXB_BUILT       equ GXB_BASE+2      ; w: the pass the index is for, + 1
GXB_END         equ GXB_BASE+4      ; l: the list's end
GXB_OVF         equ GXB_BASE+8      ; b: more targets than GXB_CAP: this pass scans
GXB_LIST        equ GXB_BASE+10     ; GXB_CAP x (min w, max w, index x 4 w)
GXB_CAP         equ 56
GXB_LEND        equ GXB_LIST+GXB_CAP*6   ; (0x10fd9a)
GXB_VHIT        equ $d00f00         ; (GX_VERIFY, OVR_DIAG's RAM: not together) l: the
GXB_VD1         equ $d00f04         ; reference's hit slot (0: none); w: its d1, d3
GXB_VD3         equ $d00f06
GXB_NQ          equ $d00f08         ; l: indexed calls
GXB_NBUILD      equ $d00f0c         ; l: builds
GXB_NOVF        equ $d00f14         ; l: calls scanned for a full list
GXB_NVIS        equ $d00f18         ; l: entries in range (tested again)

; (entered from gx_scan with d4-d6 on the stack, d4/d5/d6 and a3 set)
gx_band:
	movem.l a1/a4-a6,-(sp)
	move.w  GXB_PASS,d0
	addq.w  #1,d0
	cmp.w   GXB_BUILT,d0
	beq.s   .ok
	bsr.w   gx_bbuild
.ok:	tst.b   GXB_OVF
	bne.s   .full
	ifne GX_VERIFY
	bsr.w   gx_bref
	addq.l  #1,GXB_NQ
	endif
	bsr.s   .q
	movem.l (sp)+,a1/a4-a6
	movem.l (sp)+,d4-d6
	rts
.full:	movem.l (sp)+,a1/a4-a6          ; (too many targets: gx_scan's scan)
	ifne GX_VERIFY
	addq.l  #1,GXB_NOVF
	endif
	bra.w   gx_scanp
	; the targets in slot order: those whose extent meets [d4, d5] tested
.q:	lea     GXB_LIST,a1
	movea.l GXB_END,a4
	lea     gx_bslot,a6
	suba.l  a5,a5                   ; a5: the last target tested
.v:	cmpa.l  a4,a1
	bcc.w   .end
	cmp.w   (a1)+,d5                ; its least x word over the range's right: skipped
	bcs.s   .s4
	cmp.w   (a1)+,d4                ; its largest under the range's left: skipped
	bhi.s   .s2
	move.w  (a1)+,d0
	movea.l 0(a6,d0.w),a2
	ifne GX_VERIFY
	addq.l  #1,GXB_NVIS
	endif
	move.b  (a2),d0                 ; still a target? (a hit this pass may have taken it)
	andi.w  #$31,d0
	subq.w  #1,d0
	bne.w   .v
	movea.l a2,a5
	move.w  84(a2),d1               ; (as gx_scan's .cand)
	cmp.w   d4,d1
	bcs.s   .f1
	move.w  80(a2),d1
	cmp.w   d1,d5
	bcs.s   .f2
	pea     .r1(pc)
	jmp     $2a22c                  ; the test's y block
.r1:	bcs.s   .hit
	bra.s   .sec
.s4:	addq.l  #4,a1
	bra.w   .v
.s2:	addq.l  #2,a1
	bra.w   .v
.f1:	move.w  d6,d3
	bra.s   .sec
.f2:	swap    d6
	move.w  d6,d3
	swap    d6
.sec:	tst.b   76(a2)                  ; the second hitbox
	beq.w   .v
	move.w  92(a2),d1
	cmp.w   d4,d1
	bcs.s   .g1
	move.w  88(a2),d1
	cmp.w   d1,d5
	bcs.s   .g2
	pea     .r2(pc)
	jmp     $2a2a0
.r2:	bcs.s   .hit
	bra.w   .v
.g1:	move.w  d6,d3
	bra.w   .v
.g2:	swap    d6
	move.w  d6,d3
	swap    d6
	bra.w   .v
	; a hit: d7 as the pool scan's dbra left it (a word: its high word stays the
	; caller's), then the original's hit code (its rts back to .q's bsr, C set)
.hit:	move.w  -2(a1),d0
	lsr.w   #1,d0
	lea     gx_bd7,a6
	move.w  0(a6,d0.w),d7
	ifne GX_VERIFY
	cmpa.l  GXB_VHIT,a2
	beq.s   .hv
	addq.l  #1,HAL_GX_MISS
.hv:
	endif
	jmp     $2a1c0
	; no hit: d1/d3 as the slots' last target left them
.end:	lea     GXB_LIST,a1             ; the last target: the list from its end
.e1:	cmpa.l  a1,a4
	bls.s   .e3                     ; (none: d1/d3 as they came)
	move.w  -(a4),d0
	subq.l  #4,a4
	movea.l 0(a6,d0.w),a2
	move.b  (a2),d0
	andi.w  #$31,d0
	subq.w  #1,d0
	bne.s   .e1
	cmpa.l  a5,a2
	beq.s   .e3                     ; (tested here: as the test left them)
	moveq   #84,d0                  ; skipped: its x block failed, the second hitbox's
	tst.b   76(a2)                  ; with 76 set
	beq.s   .e2
	moveq   #92,d0
.e2:	move.w  0(a2,d0.w),d1           ; the right word below the left bound: d1, d3 as the
	cmp.w   d4,d1                   ; block's first compares leave them
	bcs.s   .e4
	move.w  -4(a2,d0.w),d1          ; else its left word over the right bound: its last
	swap    d6                      ; two
	move.w  d6,d3
	swap    d6
	bra.s   .e3
.e4:	move.w  d6,d3
.e3:
	ifne GX_VERIFY
	tst.l   GXB_VHIT
	bne.s   .em
	cmp.w   GXB_VD1,d1
	bne.s   .em
	cmp.w   GXB_VD3,d3
	beq.s   .ek
.em:	addq.l  #1,HAL_GX_MISS
.ek:
	endif
	movea.l #$1052c0+$30*$60,a2     ; (past the last pool)
	move.w  #-1,d7
	move.b  -$60(a2),d0             ; (the last slot's subq: its X)
	andi.w  #$31,d0
	subq.w  #1,d0
	jmp     $2a1b8                  ; (clr.l d0, C clear, rts: back to .q's bsr)

; the index for this pass (d1/d3 kept: they leave as they came when no target is tested)
GXBS	macro                           ; (\1: the slot's offset from 0x1019c0, \2 its index)
	move.b  \1(a2),d0
	beq.s   .s\@
	andi.b  #$31,d0
	subq.b  #1,d0
	bne.s   .s\@
	move.w  #\2*4,d2
	bsr.w   gx_bcand
.s\@:
	endm
gx_bbuild:
	movem.l d1-d3/a1-a2/a4,-(sp)
	ifne GX_VERIFY
	addq.l  #1,GXB_NBUILD
	endif
	move.w  GXB_PASS,d0
	addq.w  #1,d0
	move.w  d0,GXB_BUILT
	clr.b   GXB_OVF
	lea     GXB_LIST,a4             ; a4: the list's end
	movea.l #$1019c0,a2
GXI	set     0
	rept    $18
	GXBS    GXI*$60,GXI
GXI	set     GXI+1
	endr
	rept    $10
	GXBS    $1040c0-$1019c0+(GXI-$18)*$60,GXI
GXI	set     GXI+1
	endr
	rept    $30
	GXBS    $1052c0-$1019c0+(GXI-$28)*$60,GXI
GXI	set     GXI+1
	endr
	move.l  a4,GXB_END
	movem.l (sp)+,d1-d3/a1-a2/a4
	rts
; a target (d2 its index x 4): its extent and index at a4
gx_bcand:
	cmpa.l  #GXB_LEND,a4
	bcc.s   .ov
	lea     gx_bslot,a1
	movea.l 0(a1,d2.w),a1
	move.w  80(a1),d1               ; d1 = its least x word, d3 the largest
	move.w  84(a1),d3
	cmp.w   d1,d3
	bcc.s   .a1
	exg     d1,d3
.a1:	tst.b   76(a1)
	beq.s   .a6
	move.w  88(a1),d0
	cmp.w   d1,d0
	bcc.s   .a3
	move.w  d0,d1
.a3:	cmp.w   d3,d0
	bls.s   .a4
	move.w  d0,d3
.a4:	move.w  92(a1),d0
	cmp.w   d1,d0
	bcc.s   .a5
	move.w  d0,d1
.a5:	cmp.w   d3,d0
	bls.s   .a6
	move.w  d0,d3
.a6:	move.w  d1,(a4)+
	move.w  d3,(a4)+
	move.w  d2,(a4)+
	rts
.ov:	st      GXB_OVF
	rts

; the slots of the list's indexes, in order, and the pool scan's d7 at each
gx_bslot:
GXI	set     0
	rept    $18
	dc.l    $1019c0+GXI*$60
GXI	set     GXI+1
	endr
GXI	set     0
	rept    $10
	dc.l    $1040c0+GXI*$60
GXI	set     GXI+1
	endr
GXI	set     0
	rept    $30
	dc.l    $1052c0+GXI*$60
GXI	set     GXI+1
	endr
gx_bd7:
GXI	set     0
	rept    $18
	dc.w    $17-GXI
GXI	set     GXI+1
	endr
GXI	set     0
	rept    $10
	dc.w    $f-GXI
GXI	set     GXI+1
	endr
GXI	set     0
	rept    $30
	dc.w    $2f-GXI
GXI	set     GXI+1
	endr

	ifne GX_VERIFY
; (GX_VERIFY) the reference: every slot in order with the original tests, no side effects
; (the hit code not run): its hit slot or 0, and d1/d3 as it leaves them.  Keeps all.
gx_bref:
	movem.l d0-d3/d7/a2,-(sp)
	clr.l   GXB_VHIT
	movea.l #$1019c0,a2
	move.w  #$17,d7
	bsr.s   .pool
	bcs.s   .x
	movea.l #$1040c0,a2
	moveq   #$f,d7
	bsr.s   .pool
	bcs.s   .x
	movea.l #$1052c0,a2
	moveq   #$2f,d7
	bsr.s   .pool
.x:	move.w  d1,GXB_VD1
	move.w  d3,GXB_VD3
	movem.l (sp)+,d0-d3/d7/a2
	rts
.pool:	move.b  (a2),d0
	andi.w  #$31,d0
	subq.w  #1,d0
	bne.s   .n
	jsr     $2a1f6
	bcs.s   .h
	tst.b   76(a2)
	beq.s   .n
	jsr     $2a26a
	bcs.s   .h
.n:	lea     $60(a2),a2
	dbra    d7,.pool
	andi.b  #$fe,ccr
	rts
.h:	move.l  a2,GXB_VHIT
	ori.b   #1,ccr
	rts
	endif
	endif
	endif

	ifne GX_CULLK
; ---------------------------------------------------------------- 8 (GX_CULLK)
; obj_cull_outside_rect's entry 0x2b2d4 (lea $2b326(pc),a2; nop; then 0x2b2da: the object
; a0's y/x against the rect at a2, both ^ $8000, the object cleared outside it) - 2.7M of
; its 3.6M calls in a playthrough, ~200 cycles each, 6.5k a dense frame (AUDIT 46): the
; ROM rect's words ^ $8000 as immediates (GXC_R0..3, tools/aerofgt2neo.py from the ROM):
; ~48 cycles less a call.  Out as the original on every exit: a2 = $2b326; d0 = y ^ $8000,
; d3/d4 = the rect's first pair ^ $8000 and d1 = x raw when the y test fails; else d1 =
; x ^ $8000 and d3/d4 the second pair; the flags of the last compare (inside), or the
; clr.b's (outside); X untouched by either.  GX_VERIFY: the original first (its result
; kept, the slot's byte put back), then this, the registers, the flags and the byte
; compared (HAL_GX_MISS).
	ifne GX_VERIFY
GXK_B0          equ $d00f20         ; (GX_VERIFY, OVR_DIAG's RAM: not together) b: the byte
GXK_R           equ $d00f22         ; 5 w: d0, d1, d3, d4 and the SR after the original
GXK_B1          equ $d00f2c         ; b: the slot's byte after it
	endif
gx_cull:
	ifne GX_VERIFY
	move.b  (a0),GXK_B0
	lea     $2b326,a2
	jsr     $2b2da
	move.w  sr,GXK_R+8
	movem.w d0-d1/d3-d4,GXK_R
	move.b  (a0),GXK_B1
	move.b  GXK_B0,(a0)
	bsr.s   .k
	move.w  sr,-(sp)
	move.l  d2,-(sp)                ; (d2 the caller's: kept)
	cmpa.l  #$2b326,a2
	bne.s   .m
	cmp.w   GXK_R,d0
	bne.s   .m
	cmp.w   GXK_R+2,d1
	bne.s   .m
	cmp.w   GXK_R+4,d3
	bne.s   .m
	cmp.w   GXK_R+6,d4
	bne.s   .m
	move.b  GXK_B1,d2
	cmp.b   (a0),d2
	bne.s   .m
	move.w  4(sp),d2
	cmp.w   GXK_R+8,d2
	beq.s   .ok
.m:	addq.l  #1,HAL_GX_MISS
.ok:	move.l  (sp)+,d2
	move.w  (sp)+,sr
	rts
	endif
.k:	lea     $2b326,a2
	move.w  14(a0),d0
	move.w  16(a0),d1
	move.w  #GXC_R0,d3
	move.w  #GXC_R2,d4
	eori.w  #$8000,d0
	cmp.w   d3,d0
	bcs.s   .out
	cmp.w   d0,d4
	bcs.s   .out
	move.w  #GXC_R1,d3
	move.w  #GXC_R3,d4
	eori.w  #$8000,d1
	cmp.w   d3,d1
	bcs.s   .out
	cmp.w   d1,d4
	bcs.s   .out
	rts
.out:	clr.b   (a0)                    ; (0x2b322)
	rts
	endif

	ifne NOEXPL
; Test switch (AEROFGT_NOEXPL=1): the explosions' handlers (object types 0x09 and 0x20,
; table 0x199ba) -> this: the object is gone at once (as the loop's own clear, 0x1999c).
gx_noexpl:
	clr.b   (a0)
	rts
	endif

	ifne GX_VEL
; ---------------------------------------------------------------- 5 (GX_VEL)
; obj_move_dir_speed's velocity (0x2b950: d2/d3 = speed d0 x the direction table's
; (dy, dx) at 0x2b976 + 4 (d1 & $1f), two muls.w): the products from a table instead
; (at GXV_AT, tools/aerofgt2neo.py, from the ROM's own table: a slot per |speed| of
; the set the game uses, 32 directions x 8 bytes, negated for a negative speed); a speed outside it the original's way
; (0x2b956).  Out as the original: d0 kept, d1 = (dir & $1f) << 2 with its lsl the last
; X, d2/d3 the 32-bit products, a2 = 0x2b976, N/Z of d3, V/C clear.  jmp gx_vel at
; 0x2b950 (its tst.w d0, beq); the zero case at 0x2b970.  GX_VERIFY: the original's
; products compared (HAL_GX_MISS), the speeds outside the table counted (GXV_OUT) and
; the largest seen kept (GXV_BIG): OVR_DIAG's RAM, not together.
GXV_OUT         equ $d00f00         ; (GX_VERIFY) l: speeds outside the table
GXV_BIG         equ $d00f04         ; w: the largest |speed|
GXV_MISS        equ $d00f08         ; l: products unlike the original's
GXV_CALLS       equ $d00f0c         ; l: calls with a speed
GXV_HIST        equ $d0fe00         ; 256 w: calls per |speed| (the sprite RAM's last 512 bytes)
gx_vel:
	tst.w   d0
	bne.s   .nz
	jmp     $2b970
.nz:
	ifne GX_VERIFY
	addq.l  #1,GXV_CALLS
	move.w  d0,d2
	bpl.s   .vp
	neg.w   d2
.vp:	cmp.w   GXV_BIG,d2
	bls.s   .vb
	move.w  d2,GXV_BIG
.vb:	cmpi.w  #255,d2
	bhi.s   .vh
	add.w   d2,d2
	lea     GXV_HIST,a2
	addq.w  #1,(a2,d2.w)
.vh:
	endif
	move.w  d0,d2
	bpl.s   .ap
	neg.w   d2                      ; |speed|
.ap:	cmpi.w  #GXV_MAPN-1,d2
	bhi.s   .out
	lea     GXV_AT,a2               ; (tools/aerofgt2neo.py: the |speed| -> slot map,
	moveq   #0,d3                   ; then the slots' 32 x 8 bytes)
	move.b  (a2,d2.w),d3
	cmpi.w  #$ff,d3
	beq.s   .out
	lsl.w   #8,d3
	lea     GXV_AT+GXV_MAPN,a2      ; the slot
	adda.w  d3,a2
	move.w  d1,d3
	andi.w  #$1f,d3
	lsl.w   #3,d3                   ; the direction's 8 bytes
	move.l  (a2,d3.w),d2
	move.l  4(a2,d3.w),d3
	tst.w   d0
	bpl.s   .pos
	neg.l   d2                      ; (muls of the negated speed: the negated products)
	neg.l   d3
.pos:
	ifne GX_VERIFY
	movem.l d2-d3,-(sp)
	jsr     $2b956                  ; the original's (d1 masked and shifted, a2 set)
	cmp.l   (sp)+,d2
	bne.s   .vm
	cmp.l   (sp)+,d3
	beq.s   .vk
	subq.l  #4,sp
.vm:	addq.l  #4,sp
	addq.l  #1,GXV_MISS
.vk:	rts
	endif
	lea     $2b976,a2
	andi.w  #$1f,d1
	lsl.w   #2,d1
	tst.l   d3
	rts
.out:
	ifne GX_VERIFY
	addq.l  #1,GXV_OUT
	endif
	jmp     $2b956
	endif
