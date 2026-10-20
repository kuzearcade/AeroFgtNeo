; Not cycle-exact (AEROFGT_DIRECT=1, FUSED=1): fused direct conversion (AUDIT.md 24).
;
; Two halves instead of the walk's list and hal_spr_go's decode of it:
;   * fz_build, in game time, where the game's own sprite-list builder ran (0x2bee0
;     jumps here, back to 0x2bfaa; hal/dx.s's conventions: d2/d3 kept): one 16-byte
;     record per active object, in the builder's order (pass 1, pass 2, the group
;     sorted by x, pass 3), into a free record buffer; the header gets the count and
;     the stamp (HAL_FRAMES when complete).  No pieces, no clipping.  A logic frame
;     that overruns its vblank builds no records for it: the set shown stays, as the
;     arcade's handler copies no new list then.
;   * the pass (fz_go, hal_spr_go's place in hal_spr_work, budgeted the same way):
;     the due buffer (stamp + 2 = this slot: shown at + 3, as list k was converted in
;     slot k + 1 and shown at k + 2 before) in the list's order - the records from the
;     first, the tables B, C, A, the pieces from the first (hal_spr_go went up the
;     walk's list: the first entry gets the highest columns, on top) -, each piece
;     clipped and composed as
;     hal/fx.s's EMIT did (the four words in d2-d5) and dispatched into the generated
;     shape routine (sprfast.inc), which allocates the columns and writes them.  The
;     ring, the flip, the reclaim, the drop/split/restart paths are hal/spr.s's.  The
;     HUD take (fix layer) and the pair bullets (the pool or a 2x2 entry) as before.
;
; Record (FZ_RSZ bytes, one per TABLE in the builder's order: B, C, A of each object, so
; the pass has no per-object state): +0 l the table ($44 or $1a); +4 l its piece routine
; (fz_em_*, chosen here from the object: zoom from the object (type $2e), colour from the
; object (b5 bit 7, not for B/A with b43 bit 4), flips from the pieces (b2a = 0), pass 1;
; fz_bul for a pair bullet); +8 w y ($e), +10 w x ($10); +12 w the w2 byte as fx_objg
; composes it (bit 5 from b19, flips from b2a, the colour nibble when it is the object's;
; a pair bullet: its fxb_ok value) | the record's charge << 8 (FZU_TAB + FZU_PIECE x
; pieces, 16-cycle units); +14 b the zoom nibble (b1) << 4; +15 b pieces - 1.  The
; buffer ends with a terminator record (routine fz_toh, one piece, no charge).
; Pass state (resumable at any piece): FZ_REC the record, FZ_PH its phase, a5 the piece
; (the last one done; fz_next steps up first), FZ_LEFT the pieces not done yet in the
; table, a0 the table's piece routine (fz_em_*); a budget stop inside a shape routine
; (spr_go_late) steps back one piece.  Registers as hal_spr_go: a2 lookup RAM, a3 VRAM
; data port, a4 next head, a6 set state, d7 credit (high) / $7fff (low); (sp) = the
; head slots' end.

FZ_NB           equ 3               ; record buffers
FZ_NREC         equ 80              ; records each (the playthrough's most: 77 objects)
FZ_RSZ          equ 16
FZB_N           equ 0               ; w: records
FZB_STAMP       equ 2               ; w: HAL_FRAMES (low) when complete
FZB_ST          equ 4               ; b: 0 free, 1 complete, 2 in the pass, 3 being built
FZB_OVF         equ 5               ; b: objects left out (more than FZ_NREC)
FZB_COLS        equ 6               ; w: (FZ_ANCHSUM) the records' columns, unclipped (fz_anch)
FZB_MAGIC       equ 8               ; l
FZB_SEQ         equ 12              ; l: the build's number (FZ_BLD; fz_due: of two complete
                                    ; buffers with one stamp the later build is the one)
FZB_REC         equ 16
FZ_BSZ          equ FZB_REC+(FZ_NREC+1)*FZ_RSZ   ; (+ the terminator record: fz_toh)
FZ_MAGICV       equ $465a4253
; the buffers, the pool records and the state: the sprite RAM the walk's lists and
; hal/dl.s had (neither runs; hal/tm.s has +$400..$510, hal/fx.s FXS +$1000..)
FZ_B0           equ G_SPRRAM+$510
FZ_B1           equ FZ_B0+FZ_BSZ
FZ_B2           equ G_SPRRAM+$1800
	if (FZ_B1+FZ_BSZ>G_SPRRAM+$1000)|(FZ_B2+FZ_BSZ>G_SPRRAM+$2000)
	fail "hal/fz.s: the record buffers do not fit"
	endif
FZ_POOL         equ G_SPRRAM        ; 3 x BP_N x 8: per set its pool records
FZ_V            equ G_SPRRAM+$300   ; the state (wiped with FX_MAGIC: fz_reset)
	if FZ_POOL+3*8*BP_N>FZ_V
	fail "hal/fz.s: the pool records run into the state"
	endif
FZ_REC          equ FZ_V+0          ; l: the pass's record
FZ_RTN          equ FZ_V+4          ; l: its table's piece routine
FZ_RECS         equ FZ_V+8          ; l: its buffer's first record
FZ_RECE         equ FZ_V+76         ; l: past its last
FZ_PBUF         equ FZ_V+12         ; l: its buffer
FZ_DUE          equ FZ_V+16         ; l: the buffer due (fz_due)
FZ_PBP          equ FZ_V+20         ; l: the pass's next pool record
FZ_PBE          equ FZ_V+24         ; l: their end
FZ_LEFT         equ FZ_V+28         ; w: pieces not done yet in the table
FZ_PH           equ FZ_V+30         ; b: 0 the records, -1 the HUD pass
FZ_Y            equ FZ_V+32         ; w: the record's y (and x: one long)
FZ_X            equ FZ_V+34
FZ_W2           equ FZ_V+36         ; w: the table's w2 byte
FZ_ZOOM         equ FZ_V+38         ; w: the object's zoom << 12
FZ_SY           equ FZ_V+40         ; w: the scroll offsets (G_DX_SCRY, G_DX_SCRX)
FZ_SX           equ FZ_V+42
FZ_WORDS        equ FZ_V+44         ; 4 w: an entry's words (fx_hud_take, the zoom path)
FZ_SEQ          equ FZ_V+52         ; 3 w: per set its pass's number (the HUD queue)
FZ_PBN          equ FZ_V+58         ; 3 w: per set its pool records
FZ_SKIP         equ FZ_V+64         ; w: builds without a free buffer (diagnostics)
FZ_NDUE         equ FZ_V+66         ; w: due buffers dropped unconverted (diagnostics)
FZ_BLD          equ FZ_V+68         ; l: builds
FZ_PASSN        equ FZ_V+72         ; l: passes begun
FZ_D0           equ FZ_V+80         ; (FZ_DIAG) l: fz_next entries
FZ_D1           equ FZ_V+84         ; l: stops at a table's charge
FZ_D2           equ FZ_V+88         ; l: stops at the HUD pass's start (no time)
FZ_D3           equ FZ_V+92         ; l: stops with the HUD pass unfinished
FZ_D4           equ FZ_V+96         ; l: stops in a shape routine (spr_go_late)
FZ_D5           equ FZ_V+100        ; l: passes completed
FZ_D6           equ FZ_V+104        ; l: fz_nsl (head slots out)
FZ_DW           equ FZ_V+108        ; 4 w: the entry dispatched (work/play/fh/entries.lua)
FZ_T0           equ FZ_V+116        ; w: (FZ_DIAG) the line counter at a timed step's start
FZ_TMAX         equ FZ_V+118        ; w: the longest pass run in a commit's tail (lines)
FZ_TPHM         equ FZ_V+120        ; b: FZ_PH then
FZ_TN           equ FZ_V+122        ; w: pass runs in commit tails
FZ_TSUM         equ FZ_V+124        ; l: their lines
FZ_RMAX         equ FZ_V+128        ; w: the longest hal_spr_reclaim (lines)
FZ_BMAX         equ FZ_V+130        ; w: the longest hal_spr_begin + fz_begin (lines)
FZ_T1           equ FZ_V+132        ; w: the line counter at the HUD pass's start
FZ_HMAX         equ FZ_V+134        ; w: the longest HUD pass in a commit's tail (lines)
FZ_HD6          equ FZ_V+136        ; w: the units it was given then
FZ_HD6A         equ FZ_V+138        ; w: the units it had left then
FZ_HD6T         equ FZ_V+140        ; w: (the units given, this HUD pass)
; (FUSED=2: the game-time pass, below)
FZ_OBJ          equ FZ_V+144        ; l: the pass's next object slot
FZ_OEND         equ FZ_V+148        ; l: the pass's end
FZ_PASS         equ FZ_V+152        ; w: 0 pass 1, 1 pass 2, 2 the group, 3 pass 3, 4 done
FZ_GI           equ FZ_V+154        ; w: the group's next index
FZ_GN           equ FZ_V+156        ; w: the group's objects (-1: not sorted yet)
FZ_P1           equ FZ_V+158        ; w: 1 in pass 1 (the routine index's bit 0)
FZ_CONT         equ FZ_V+160        ; l: where a table's end goes on (fz_next)
FZ_HEND         equ FZ_V+164        ; l: the head slots' end
FZ_SR           equ FZ_V+168        ; w: the game's SR (back after a piece's VRAM writes)
FZ_GTSET        equ FZ_V+170        ; w: the set in work (-1: none)
FZ_RTC          equ FZ_V+172        ; l: the object's C routine
FZ_RTB          equ FZ_V+176        ; l: its B/A routine
FZ_W2C          equ FZ_V+180        ; w: its C w2 byte
FZ_W2B          equ FZ_V+182        ; w: its B/A w2 byte
FZ_CUR          equ FZ_V+184        ; l: the object
FZ_GTSKIP       equ FZ_V+188        ; l: builds skipped (no free set)
FZ_GTN          equ FZ_V+192        ; l: builds
FZ_GTLATE       equ FZ_V+196        ; l: builds begun after their slot (shown a frame later)
FZ_GTWAIT       equ FZ_V+200        ; b: the pass waits at the ring's tail for the flip
FZ_GTCTX        equ FZ_V+201        ; b: the pass runs in the slot (resumed), not the game
FZ_WA4          equ FZ_V+204        ; l: its a4 (next head) at the wait
FZ_WA5          equ FZ_V+208        ; l: its a5 (the piece)
FZ_WAITN        equ FZ_V+212        ; l: waits
FZ_WSTALE       equ FZ_V+216        ; l: waits the round went on from (the set as it was)
FZ_VEND         equ FZ_V+224
FZ_HX           equ FZ_V+144        ; (FZ_DIAG, FUSED=1: the game-time pass's words above are
                                    ; free) 8 w: the HUD cache prologue's exits (hccnt3.lua)
FZ_NDUP         equ FZ_V+228        ; w: complete buffers superseded by a later round's
                                    ; in the same frame (fz_build; diagnostics)
; (FZ_PD) the HUD pieces' cache: per HUD slot the key of the record whose piece last took
; it (y, x, w2, zoom, table, the lookup RAM's generation); a HUD piece whose slot holds
; its record's key and is shown is taken unchanged without the take (FZPD \5)
FZ_HKEY         equ G_SPRRAM+$1d20  ; 13 x 16: l y|x, l w2|zoom, l table, w generation
FZ_HCOK         equ G_SPRRAM+$1df0  ; w: slots shown as last taken (fx_hud_draw)
FZ_LUTGEN       equ G_SPRRAM+$1df2  ; w: lookup RAM loads (fz_lutld)
FZ_HDS          equ G_SPRRAM+$1df4  ; w: fx_hud_draw's slot
                                    ; ($400-$502 is hal/tm.s's TM_DIRTY/TM_ALL/TM_ANY; the
                                    ; records end at $1d20, GX_VERIFY's GXV_HIST at $1e00)
	ifnd FZ_SHOW
FZ_SHOW         equ 1               ; the set shown FZ_SHOW slots after its round's (1: one
	endif                           ; frame before the arcade; 0: two, the ring's sets two
                                    ; at a time; tools/aerofgt2neo.py shortens the scroll
                                    ; FIFO by 2 - FZ_SHOW stages to match)
FZ_SORT         equ G_SPRRAM+$510   ; 16 x (key.w, object.l): the group in x order
	ifnd FZ_DIAG
FZ_DIAG         equ 0
	endif
	ifnd FZ_ANCHSUM
FZ_ANCHSUM      equ 0               ; (fz_build sums the records' columns into FZB_COLS: fz_anch
	endif                           ; reads one word instead of walking up to ANLN pieces.  Off:
                                    ; the sums cost the builder 3.2-3.9k cycles a dense frame
                                    ; (split profiles de55b2/nf55b2, 2026-10-19) and the walk
                                    ; they replace cost 0.6-0.9k)
	ifnd FZ_FASTCHG
FZ_FASTCHG      equ 1               ; (a fast record is charged only when its piece is clipped:
	endif                           ; the shape routine's charge keeps PRE_MAX for the way to it)
	ifnd FZ_RC
FZ_RC           equ 0               ; (fz_rec: a 32-entry cache of fast-record templates by table,
	endif                           ; pass and front bit, filled by the general fast path: off -
                                    ; the matched profiles had the builder slower with it, the
                                    ; probe on every miss costing more than the hits gave, fz53;
                                    ; not with FZ_FINAL)
	ifnd FZ_FINAL
FZ_FINAL        equ FZ_FASTCHG      ; (fz_rec: a fast record whose piece is on the screen whole -
	endif                           ; 0 <= y < 224, 0 <= x < 320, the scroll words zero - holds
                                    ; w0 and w1 final, the flag $fe: fz_fastv dispatches it with
                                    ; no screen test; the scroll words G_DX_SCRX/Y are set once
                                    ; at boot from the table at 0xf68, zero in both halves)
	ifne FZ_RC&FZ_FINAL
	fail "FZ_RC and FZ_FINAL: not together (the template's y/x)"
	endif
	ifne FZ_FINAL&(FZ_FASTCHG=0)
	fail "FZ_FINAL wants FZ_FASTCHG"
	endif
	ifnd FZU_FASTV
FZU_FASTV       equ 16              ; (fz_fastv's credit: FZU_FASTX + the screen tests it skips,
	endif                           ; ~160 cycles)
FZ_FYM          equ FZ_V+220        ; w: (FZ_FINAL) the build's y bound, 224 (the scroll words
                                    ; zero) or 0 (no final records)
	ifnd FZ_TPL
FZ_TPL          equ 0               ; (fz_rec: a one-piece descriptor's fast record from its ROM
	endif                           ; template - tools/aerofgt2neo.py writes one per descriptor
                                    ; at FZ_TPL_AT, its index in the descriptor's first word,
                                    ; bits 0-12 (the flags move to bits 14 and 13: FZD_FD/FH):
                                    ; +0 l spr_fast_jt's entry for the piece's sizes
                                    ; and zoom, in front, no flips, +4 w y, +6 w x, +8 l the
                                    ; piece's colour | flips << 24 | the map, +12 w w0's high
                                    ; byte << 8 | w1's, +14 w w1's << 8 - no descriptor tests,
                                    ; no word composition, no shape index: ~130 cycles less a
                                    ; record, 2026-10-19)
	ifnd FZ_TPLCHK
FZ_TPLCHK       equ 0               ; (1: the templates in shadow mode - the record built the
	endif                           ; general fast way after the template's, compared with it:
                                    ; FZ_TPLBAD mismatches, FZ_TPLHIT compares, FZ_TPLMISS one-
                                    ; piece records without a template)
	ifne FZ_TPL&(FZ_FINAL=0)
	fail "FZ_TPL wants FZ_FINAL"
	endif
	ifne FZ_TPL&FZ_RC
	fail "FZ_TPL and FZ_RC: not together"
	endif
	ifne FZ_TPL&FZ_ANCHSUM
	fail "FZ_TPL and FZ_ANCHSUM: not together (the template holds no column count)"
	endif
	ifne FZ_TPLCHK&(FZ_TPL=0)
	fail "FZ_TPLCHK wants FZ_TPL"
	endif
	ifne BP_SHOTS&((FZ_TPL=0)|FZ_TPLCHK)
	fail "BP_SHOTS wants FZ_TPL, not FZ_TPLCHK"
	endif
FZ_TPL_AT       equ $7b470          ; the templates (the free ROM after the game's, to $80000:
                                    ; 1,208 x 16; tools/aerofgt2neo.py FZ_TPL_AT)
	ifne FZ_TPL
FZD_FD          equ 6               ; a descriptor's first byte: bit 6 a descriptor, bit 5 a HUD
FZD_FH          equ 5               ; piece (bits 0-4 the template index's high bits; a raw
	else                            ; table's first byte is 0: its pointer's high word < 8)
FZD_FD          equ 0               ; bit 0 a descriptor, bit 1 a HUD piece (the word's low byte
FZD_FH          equ 1               ; the pointer's, unread)
	endif
FZ_PSN          equ FZ_V+248        ; b: (BP_SHOTS) the descriptor at hand is a poolable shot piece
FZ_PBL          equ FZ_V+252        ; l: (BP_SIZED) the pool records' room at the pool's size
FZ_TPLE         equ FZ_V+240        ; b: (FZ_TPLCHK) the record at hand came from a template
FZ_TPLMISS      equ FZ_V+242        ; w: (FZ_TPLCHK) one-piece fast records without a template
FZ_TPLBAD       equ FZ_V+244        ; w: (FZ_TPLCHK) templates unlike the general path's record
FZ_TPLHIT       equ FZ_V+246        ; w: (FZ_TPLCHK) compares
	ifnd FZ_RCCHK
FZ_RCCHK        equ 0               ; (1: the cache in shadow mode - every record built the general
	endif                           ; way, a hit's template compared with it: FZ_RCBAD counts
                                    ; mismatches, FZ_RCHIT hits)
FZ_RC_AT        equ G_SPRRAM+$1e00  ; 32 x 16: l table | b w2 byte | b routine flags | w w2 | w w3 |
FZ_RC_MASK      equ $1f0            ; w w0/w1 high bytes | l shape routine (hashed by (table << 3) &
                                    ; FZ_RC_MASK; GX_VERIFY's GXV_HIST: not together)
FZ_RCE          equ FZ_V+240        ; l: (FZ_RCCHK) the entry hit, 0 none
FZ_RCBAD        equ FZ_V+244        ; w: (FZ_RCCHK) templates unlike the general path's record
FZ_RCHIT        equ FZ_V+246        ; w: (FZ_RCCHK) hits
	ifnd FZ_HCX
FZ_HCX          equ 0               ; (FZ_DIAG: the HUD cache prologue's exit counters, FZ_HX /
	endif                           ; hccnt3.lua; off: the diagnostic build fits the ROM's room)
FZD	macro
	ifne FZ_DIAG
	addq.l  #1,\1
	endif
	endm
	if FZ_VEND>G_SPRRAM+$400
	fail "hal/fz.s: the state runs into hal/tm.s"
	endif
fz_btab:
	dc.l    FZ_B0,FZ_B1,FZ_B2

; ---------------------------------------------------------------- the object half
; 0x2bee0 (the builder's entry): the active objects' records into a free buffer.
fz_build:
	movem.l d2-d3,-(sp)
	lea     fz_btab(pc),a3
	moveq   #FZ_NB-1,d0
.fb:	movea.l (a3)+,a2
	tst.b   FZB_ST(a2)
	beq.s   .got
	dbra    d0,.fb
	addq.w  #1,FZ_SKIP              ; (none free: no records this frame)
	bra.w   .out
.got:	move.b  #3,FZB_ST(a2)
	sf      FZB_OVF(a2)
	ifne FZ_ANCHSUM
	clr.w   FZB_COLS(a2)
	endif
	ifne FZ_FINAL
	move.w  #224,d0                 ; (final records only with the scroll words zero -
	tst.l   G_DX_SCRX               ; SCRX, SCRY: always, but for the service screens'
	beq.s   .sz                     ; tables; else every fast record clips in fz_fast)
	moveq   #0,d0
.sz:	move.w  d0,FZ_FYM
	endif
	lea     FZB_REC(a2),a1
	lea     FZB_REC+FZ_NREC*FZ_RSZ(a2),a4
	moveq   #$10,d5                 ; pass 1 (the HUD's objects, the pair bullets)
	movea.l #G_DX_OBJ1,a0
	move.l  #G_DX_OBJ2,d4
	bsr.w   fz_pass
	moveq   #0,d5
	movea.l #G_DX_OBJ2,a0
	move.l  #G_DX_OBJ3,d4
	bsr.w   fz_pass
	bsr.w   fz_group
	movea.l #G_DX_OBJ4,a0
	move.l  #G_DX_OBJ5,d4
	bsr.w   fz_pass
	move.l  a1,d0
	sub.l   a2,d0
	subi.w  #FZB_REC,d0
	lsr.w   #4,d0
	move.w  d0,FZB_N(a2)
	clr.l   (a1)+                   ; the terminator: its "routine" fz_toh (the HUD
	move.l  #fz_toh,(a1)+           ; pass), one piece, no charge: fz_ntab takes it as
	clr.l   (a1)+                   ; any record (no end compare, 2026-10-18)
	clr.l   (a1)+
	move.w  HAL_FRAMES+2,d0
	lea     fz_btab(pc),a3          ; a complete buffer with the same stamp (two rounds
	moveq   #FZ_NB-1,d1             ; in one frame, after a lost one): the arcade's
.same:	movea.l (a3)+,a0                ; handler copies the later list only - that one
	cmpi.b  #1,FZB_ST(a0)           ; was converted twice, the first set freed unseen,
	bne.s   .sn                     ; 2026-10-18.  The free is a TAS now: the slot took
	cmp.w   FZB_STAMP(a0),d0        ; the buffer into the pass between the test and the
	bne.s   .sn                     ; clear once (fz46, nation 1 seed 9, frame 85,211: the
	tas     FZB_ST(a0)              ; next build overwrote the records the pass was
	cmpi.b  #$81,FZB_ST(a0)         ; reading, a jump through a half-written record, a
	bne.s   .st                     ; reboot; latent since fz21).  Bit 7 set, fz_due passes
	clr.b   FZB_ST(a0)              ; the buffer by; still $81 = ours to free, $82 = the
	addq.w  #1,FZ_NDUP              ; slot's meanwhile: bit 7 cleared, nothing else (fz50,
	bra.s   .sn                     ; 2026-10-19; masking interrupts instead cost half a
.st:	andi.b  #$7f,FZB_ST(a0)         ; point of lost logic, fz47; freeing at the slot only,
.sn:	dbra    d1,.same                ; fz49, a third of a point: a buffer less for a round)
	move.w  d0,FZB_STAMP(a2)
	move.l  FZ_BLD,FZB_SEQ(a2)      ; (the build's number: fz_due keeps the later of two
                                    ; complete buffers with one stamp, the case the slot
                                    ; took the earlier one before the later was built)
	move.l  #FZ_MAGICV,FZB_MAGIC(a2)
	move.b  #1,FZB_ST(a2)
	addq.l  #1,FZ_BLD
.out:	movea.l #G_DX_LIST,a6           ; (as hal/dx.s leaves it: an empty list)
	move.w  #$c000,(a6)+
	movem.l (sp)+,d2-d3
	jmp     $2bfaa

; the objects a0 .. d4 ($60 bytes each), eight slots a turn
fz_pass:
.s:	cmpa.l  d4,a0
	bhs.s   .x
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
	bra.s   .s
.a7:	lea     $60(a0),a0
.a6:	lea     $60(a0),a0
.a5:	lea     $60(a0),a0
.a4:	lea     $60(a0),a0
.a3:	lea     $60(a0),a0
.a2:	lea     $60(a0),a0
.a1:	lea     $60(a0),a0
	cmpa.l  d4,a0
	bhs.s   .x
.act:
	ifne FZ_SHED
	tst.b   FZ_SH_LV                ; (FZ_SHED: while shedding, the object's records
	beq.s   .r0                     ; marked from here)
	move.l  a1,-(sp)
	bsr.w   fz_rec
	bsr.w   fz_shmark
	addq.l  #4,sp
	bra.s   .r1
.r0:
	endif
	bsr.w   fz_rec
	ifne FZ_SHED
.r1:
	endif
	lea     $60(a0),a0
	bra.s   .s
.x:	rts

; the group $ff42c0..$ff48c0 in x order (hal/dx.s dx_group), in slot order if $ff90e6
fz_group:
	tst.w   G_DX_90E6
	beq.s   .s
	movea.l #G_DX_OBJ3,a0
	move.l  #G_DX_OBJ4,d4
	bra.w   fz_pass
.s:	lea     -16*6(sp),sp            ; (key.w, object.l) x 16 at most
	movea.l sp,a5
	moveq   #0,d6
	movea.l #G_DX_OBJ3,a0
	moveq   #15,d7
.o:	tst.b   (a0)
	bpl.s   .on
	move.w  $10(a0),d0
	addi.w  #$8000,d0
	movea.l a5,a3                   ; the first entry with a key >= d0
	move.w  d6,d1
	bra.s   .c1
.c:	cmp.w   (a3),d0
	bls.s   .ins
	addq.l  #6,a3
.c1:	dbra    d1,.c
.ins:	move.w  d6,d1                   ; shift the rest up, from the end
	mulu    #6,d1
	lea     (a5,d1.w),a6
.sh:	cmpa.l  a3,a6
	bls.s   .put
	move.l  -4(a6),2(a6)
	move.w  -6(a6),(a6)
	subq.l  #6,a6
	bra.s   .sh
.put:	move.w  d0,(a3)
	move.l  a0,2(a3)
	addq.w  #1,d6
.on:	lea     $60(a0),a0
	dbra    d7,.o
	movea.l a5,a6
	bra.s   .e1
.e:	movea.l 2(a6),a0
	move.w  d6,d2                   ; (fz_rec clobbers d6: the loop ran on into stale
	ifne FZ_SHED
	tst.b   FZ_SH_LV
	beq.s   .r0
	move.l  a1,-(sp)
	bsr.w   fz_rec
	bsr.w   fz_shmark
	addq.l  #4,sp
	bra.s   .r1
.r0:
	endif
	bsr.w   fz_rec                  ; stack entries - garbage records, a reboot at the
	ifne FZ_SHED
.r1:
	endif
	move.w  d2,d6                   ; attract's missiles, 2026-10-18; d2 is fz_build's)
	addq.l  #6,a6
.e1:	dbra    d6,.e
	lea     16*6(sp),sp
	rts

; object a0 (active) -> its records at a1 (none past a4: FZB_OVF).  d5 = the pass's
; flags (bit 4: pass 1).  Clobbers d0, d1, d6, d7, a3.
fz_rec:
	ifne FZ_FASTR
; (FZ_FASTR, AUDIT 46) the template fast record's way first: 85% of the drawn objects of a
; dense frame take it, and the general set-up before it (the routine flags in d6, tested
; again bit by bit, the pair-bullet test) cost ~130 cycles a record.  The objects it does
; not cover go to the original's way, fz_reco, unchanged: type $18 (the pair bullets) and
; $2e (zoom), d5 bits 5-7 (they would fold into the flags), B/A tables, more than one
; piece, no template, the buffer full.  The record is fz_reco's .tnf/.tw/.rr one: w2 | w3
; the template's long with the piece's colour kept unless the object has its own (5(a0)
; bit 7), its flips unless the object has its own ($2a non-zero), the object's w2 byte
; (the front bit from $19, its flips, its colour) on top, pass 1's bits.  d6 is left as
; it came (fz_reco set it to the flags: neither caller reads it after).
; FZ_FASTRCHK: fz_reco builds the record again over it and the two are compared
; (FZ_FRN records, FZ_FRBAD different).
	if FZ_RC|BP_SHOTS|FZ_TPLCHK|(FZ_TPL=0)|(FZ_FINAL=0)
	fail    "FZ_FASTR wants FZ_TPL and FZ_FINAL, and not FZ_RC, BP_SHOTS or FZ_TPLCHK"
	endif
	ifne FZ_FASTRCHK
FZ_FRN          equ $d00f30         ; l: (OVR_DIAG's RAM: not together) records compared
FZ_FRBAD        equ $d00f34         ; l: different
	endif
	move.w  $16(a0),d1
	cmpi.w  #$18,d1
	beq.w   fz_reco
	cmpi.w  #$2e,d1
	beq.w   fz_reco
	moveq   #-$20,d1                ; (d5 bits 5-7)
	and.b   d5,d1
	bne.w   fz_reco
	moveq   #-$40,d1                ; B or A ($43 bits 6-7)
	and.b   $43(a0),d1
	bne.w   fz_reco
	tst.b   4(a0)                   ; pieces - 1
	bne.w   fz_reco
	moveq   #-2,d1                  ; the table (bit 0: the game's flag)
	and.l   $1a(a0),d1
	movea.l d1,a3
	move.w  (a3),d3                 ; its template (as fz_reco's FZ_TPL test)
	subi.w  #$4001,d3
	cmpi.w  #$1fff,d3
	bhs.w   fz_reco
	cmpa.l  a4,a1
	bhs.w   fz_reco
	lsl.w   #4,d3
	lea     FZ_TPL_AT+16,a3
	adda.w  d3,a3
	ifne FZ_FASTRCHK
	move.l  a1,-(sp)                ; the record's start, for the compare
	endif
	addq.l  #4,a1                   ; (+0: the routine, last)
	move.w  $e(a0),d1
	add.w   4(a3),d1                ; y + the piece's
	move.w  $10(a0),d7
	add.w   6(a3),d7                ; x
	cmp.w   FZ_FYM,d1               ; on the screen whole (FZ_FINAL)
	bhs.s   .tnf
	cmpi.w  #320,d7
	bhs.s   .tnf
	move.b  12(a3),(a1)+            ; +4 w0 = w0's high byte | y
	move.b  d1,(a1)+
	move.w  14(a3),d1               ; +6 w1 = w1's high byte << 8 | x
	or.w    d7,d1
	move.w  d1,(a1)+
	move.w  #(FZU_FAST<<8)|$fe,d7
	bra.s   .tw
.tnf:	move.w  d1,(a1)+                ; +4 y, +6 x (the pass's tests)
	move.w  d7,(a1)+
	move.w  #(FZU_FAST<<8)|$ff,d7
.tw:	move.l  8(a3),d3                ; w2 | w3
	moveq   #$20,d0                 ; the w2 byte: in front unless $19 bit 7 set, bit 0
	move.b  $19(a0),d1              ; clear
	bpl.s   .fr
	btst    #0,d1
	bne.s   .fr
	moveq   #0,d0
.fr:	move.b  $2a(a0),d1              ; the object's flips: the piece's go
	beq.s   .pf
	or.b    d1,d0
	andi.l  #$0fffffff,d3
.pf:	move.b  5(a0),d1                ; the object's colour: the piece's goes
	bpl.s   .pc
	andi.b  #$f,d1
	or.b    d1,d0
	andi.l  #$c0ffffff,d3
.pc:	ror.l   #8,d0
	or.l    d0,d3
	btst    #4,d5                   ; pass 1
	beq.s   .np
	ori.l   #$10002000,d3
.np:	move.l  d3,(a1)+                ; +8 w2, +10 w3
	move.w  d7,(a1)+                ; +12 the charge, +13 the flag
	move.w  12(a3),(a1)+            ; +14 w0's high byte, +15 w1's
	swap    d3                      ; the shape routine: the template's entry + the flips'
	lsr.w   #5,d3                   ; $200/$400
	andi.w  #$600,d3
	movea.l (a3),a3
	move.l  (a3,d3.w),-16(a1)
	ifne FZ_FASTRCHK
	movea.l (sp)+,a3                ; the record, then fz_reco's over it
	move.l  12(a3),-(sp)
	move.l  8(a3),-(sp)
	move.l  4(a3),-(sp)
	move.l  (a3),-(sp)
	move.l  a1,-(sp)
	movea.l a3,a1
	bsr.w   fz_reco
	addq.l  #1,FZ_FRN
	cmpa.l  (sp)+,a1
	bne.s   .cb
	movea.l a1,a3
	lea     -16(a3),a3
	cmpm.l  (sp)+,(a3)+
	bne.s   .cb4
	cmpm.l  (sp)+,(a3)+
	bne.s   .cb3
	cmpm.l  (sp)+,(a3)+
	bne.s   .cb2
	cmpm.l  (sp)+,(a3)+
	beq.s   .ck
	bra.s   .cb1
.cb:	addq.l  #4,sp
.cb4:	addq.l  #4,sp
.cb3:	addq.l  #4,sp
.cb2:	addq.l  #4,sp
.cb1:	addq.l  #1,FZ_FRBAD
.ck:
	endif
	rts
fz_reco:
	endif
	moveq   #0,d6                   ; the routine: zoom from the object 8, its colour
	move.b  d5,d7                   ; 4, flips from the pieces 2, pass 1 1 (d5 bit 4)
	lsr.b   #4,d7
	or.b    d7,d6
	moveq   #0,d7                   ; the zoom nibble
	cmpi.w  #$2e,$16(a0)
	bne.s   .nz
	addq.w  #8,d6
	move.b  1(a0),d7
	lsl.b   #4,d7                   ; (the record's zoom nibble << 4)
.nz:	moveq   #0,d0                   ; the w2 byte (fx_objg's d5)
	tst.b   $19(a0)
	bpl.s   .p0
	btst    #0,$19(a0)
	beq.s   .p1
.p0:	moveq   #$20,d0
.p1:	move.b  $2a(a0),d1              ; flips
	beq.s   .f0
	or.b    d1,d0
	bra.s   .f1
.f0:	addq.w  #2,d6                   ; (from the pieces)
.f1:	move.b  5(a0),d1
	bpl.s   .nc
	andi.b  #$f,d1
	or.b    d1,d0
	addq.w  #4,d6                   ; colour from the object
.nc:
	ifne FZ_RC
	; (FZ_RC, 2026-10-19) a one-piece, unzoomed, no-B/A object: its fast record is a function
	; of its table, its w2 byte (d0: the front bit, the object's flips and colour) and its
	; routine flags (d6) alone, but for y and x - the template of the last such record for
	; this table is kept (FZ_RC_AT, hashed by the table) and replayed: ~500 cycles instead of
	; ~875.  The general fast path below fills the cache.  FZ_RCCHK: the general path runs
	; anyway and the hit's template is compared with its record.
	btst    #3,d6
	bne.w   .rcn
	tst.b   4(a0)
	bne.w   .rcn
	move.b  $43(a0),d1
	andi.b  #$c0,d1
	bne.w   .rcn
	move.l  $1a(a0),d1
	bclr    #0,d1
	move.w  d1,d3
	lsl.w   #3,d3
	andi.w  #FZ_RC_MASK,d3
	lea     FZ_RC_AT,a3
	adda.w  d3,a3
	cmp.l   (a3),d1
	bne.w   .rcn
	cmp.b   4(a3),d0
	bne.w   .rcn
	cmp.b   5(a3),d6
	bne.w   .rcn
	ifne FZ_RCCHK
	move.l  a3,FZ_RCE               ; (a hit: compared at the fill)
	bra.w   .rcm
	endif
	cmpa.l  a4,a1
	bhs.w   .full
	move.l  12(a3),(a1)+            ; +0 the shape routine
	move.l  6(a3),d3                ; w2 | w3
	move.w  10(a3),d7               ; w0's and w1's high bytes
	movea.l d1,a3                   ; the descriptor: the piece's offsets
	ifne FZ_ANCHSUM
	moveq   #$e,d1
	and.b   10(a3),d1
	lsr.w   #1,d1
	addq.w  #1,d1
	add.w   d1,FZB_COLS(a2)
	endif
	move.w  $e(a0),d1
	add.w   4(a3),d1
	move.w  d1,(a1)+                ; +4 y
	move.w  $10(a0),d1
	add.w   6(a3),d1
	move.w  d1,(a1)+                ; +6 x
	move.l  d3,(a1)+                ; +8 w2, +10 w3
	move.w  #(FZU_FAST<<8)|$ff,(a1)+
	move.w  d7,(a1)+
	rts
.rcn:
	ifne FZ_RCCHK
	clr.l   FZ_RCE
.rcm:
	endif
	endif
	; a pair bullet (hal/fx.s fxb_obj's conditions): type $18 in pass 1, two pieces of
	; one of FXB_N tables, the C table only, flips and colour from the pieces, in front
	cmpi.w  #$18,$16(a0)
	ifne BP_STABLE
	bne.w   .nb
	else
	bne.s   .nb
	endif
	btst    #4,d5
	ifne BP_STABLE
	beq.w   .nb
	else
	beq.s   .nb
	endif
	cmpi.b  #1,4(a0)
	ifne BP_STABLE
	bne.w   .nb
	else
	bne.s   .nb
	endif
	move.b  $43(a0),d1
	andi.b  #$c0,d1
	bne.s   .nb
	tst.b   $2a(a0)
	bne.s   .nb
	tst.b   5(a0)
	bmi.s   .nb
	btst    #5,d0
	beq.s   .nb
	move.l  $1a(a0),d1
	subi.l  #FXB_T0,d1
	cmpi.l  #(FXB_N-1)*FXB_TS,d1
	bhi.s   .nb
	move.w  d1,d7
	andi.w  #3,d7
	bne.s   .nb
	lsr.w   #2,d1
	lea     fxb_ok,a3
	move.b  (a3,d1.w),d1
	beq.s   .nb
	cmpa.l  a4,a1
	bhs.w   .full
	move.l  $1a(a0),d7              ; (bit 0: the game's flag, as fx_objg clears it: an
	bclr    #0,d7                   ; odd table would be an address error; d1 is the
	move.l  d7,(a1)+                ; fxb_ok value: the w2, fz_bul's fxb_k index)
	ifne BP_STABLE
	move.l  a0,d3                   ; (BP_STABLE) the object's index in the long's high
	subi.l  #G_DX_OBJ1,d3           ; byte (24-bit addressing ignores it): the pool's slot
	lsr.w   #5,d3
	lea     bp_kidx,a3
	move.b  (a3,d3.w),-4(a1)
	endif
					; one record: fz_bul, its fxb_ok value as the w2
	move.l  #fz_bul,(a1)+           ; word, 2 pieces (fz_bul's general way, fz_anch)
	move.l  $e(a0),(a1)+
	ori.w   #(FZU_TAB+2*FZU_PIECE)<<8,d1
	move.w  d1,(a1)+
	move.w  #$0001,(a1)+
	ifne FZ_ANCHSUM
	bra.w   .cols
	else
	rts
	endif
.nb:
	ifne FZ_FAST
	; (FZ_FAST, 2026-10-18) a fast record: one table (C), one piece, no zoom, a descriptor
	; that is not a HUD strip and, in pass 1, not in the HUD's lookup range (the take).  Its
	; words as the piece routine fz_pd_* would compose them and its shape routine as
	; fz_disp would pick it, here: +0 l the shape routine, +4 w y and +6 w x with the
	; piece's offsets, +8 w w2, +10 w w3, +12 b the charge, +13 b $ff (the flag: a w2 byte
	; is at most $ef), +14 b w0's high byte (header 0 | zoomy << 4), +15 b w1's.
	move.b  $43(a0),d1
	andi.b  #$c0,d1                 ; B or A
	bne.w   .gen
	tst.b   4(a0)                   ; pieces - 1
	bne.w   .gen
	btst    #3,d6                   ; the zoom
	bne.w   .gen
	move.l  $1a(a0),d1
	bclr    #0,d1
	movea.l d1,a3
	ifne FZ_TPL
	; (FZ_TPL, 2026-10-19) the descriptor's template: FZ_TPL_AT + 16 x its first word's
	; bits 0-12, with bit 14 (FZD_FD: a descriptor the tool edited) set: the word in
	; $4001-$5fff.  Below it: a raw table the census never saw ($0000-$0007, its ROM
	; pointer's high word - the attract demo's draws some: the first builds took the
	; word's low bits alone and gave them templates 1-7), a HUD piece ($2000 - the
	; lookup range, in either pass), a descriptor the tool gave no template ($4000);
	; above it a HUD piece ($6000: both flags - the build that tested the sign alone
	; sent it to slot $1fff, an address error).  The record as the general fast path
	; below composes it, from the template's words: y/x and the high bytes as
	; FZ_FINAL, w2 | w3 as one long (the piece's byte masked as the flags say, the
	; object's d0 in, pass 1's bits), the shape routine from the template's
	; spr_fast_jt entry + the flips' $200/$400.
	move.w  (a3),d3
	ifne BP_SHOTS
	btst    #12,d3                  ; (BP_SHOTS: a poolable shot piece - the index's lsl
	sne     FZ_PSN                  ; drops the bit)
	endif
	subi.w  #$4001,d3               ; the index - 1: 0-$1ffe, the rest wraps or exceeds
	cmpi.w  #$1fff,d3
	ifne FZ_TPLCHK
	bhs.w   .tm
	else
	bhs.w   .gen
	endif
	lsl.w   #4,d3
	lea     FZ_TPL_AT+16,a3
	adda.w  d3,a3
	cmpa.l  a4,a1
	bhs.w   .full
	ifne FZ_TPLCHK
	move.l  d1,-(sp)                ; the descriptor, the record: the general path's turn
	move.l  a1,-(sp)
	endif
	addq.l  #4,a1                   ; (+0: the routine, last)
	move.w  $e(a0),d1
	add.w   4(a3),d1                ; y + the piece's
	move.w  $10(a0),d7
	add.w   6(a3),d7                ; x
	cmp.w   FZ_FYM,d1               ; on the screen whole (as .fok's FZ_FINAL)
	bhs.s   .tnf
	cmpi.w  #320,d7
	bhs.s   .tnf
	move.b  12(a3),(a1)+            ; +4 w0 = w0's high byte | y
	move.b  d1,(a1)+
	move.w  14(a3),d1               ; +6 w1 = w1's high byte << 8 | x
	or.w    d7,d1
	move.w  d1,(a1)+
	move.w  #(FZU_FAST<<8)|$fe,d7
	bra.s   .tw
.tnf:	move.w  d1,(a1)+                ; +4 y, +6 x (the pass's tests)
	move.w  d7,(a1)+
	move.w  #(FZU_FAST<<8)|$ff,d7
.tw:	move.l  8(a3),d3                ; +8 w2 = (the piece's colour | flips, as the flags
	btst    #2,d6                   ; say, | d0) << 8, +10 w3 = the map; | $1000, $2000
	beq.s   .tc                     ; in pass 1
	andi.l  #$c0ffffff,d3           ; (colour from the object: the piece's flips only)
.tc:	btst    #1,d6
	bne.s   .tf
	andi.l  #$0fffffff,d3           ; (flips from the object: the piece's colour only)
.tf:	moveq   #0,d1
	move.b  d0,d1
	ror.l   #8,d1
	or.l    d1,d3
	btst    #0,d6
	beq.s   .tp
	ori.l   #$10002000,d3
.tp:	move.l  d3,(a1)+
	move.w  d7,(a1)+                ; +12 the charge, +13 the flag
	move.w  12(a3),(a1)+            ; +14 w0's high byte, +15 w1's
	swap    d3                      ; the shape routine: the template's entry (the sizes,
	lsr.w   #5,d3                   ; the zoom, in front) + the flips' (w2 bits 14-15:
	andi.w  #$600,d3                ; $200, $400 - as .fz's index)
	ifne BP_SHOTS
	tst.b   FZ_PSN                  ; (BP_SHOTS) a poolable piece, its words final: the
	beq.s   .rr                     ; pass puts it in the pool (fz_pshot), or dispatches
	sf      FZ_PSN                  ; it as any fast record
	cmpi.b  #$fe,-3(a1)
	bne.s   .rr
	move.l  #fz_pshot,-16(a1)
	ifne BP_STABLE
	move.l  a0,d3                   ; (BP_STABLE) the object's index in the routine long's
	subi.l  #G_DX_OBJ1,d3           ; high byte
	lsr.w   #5,d3
	lea     bp_kidx,a3
	move.b  (a3,d3.w),-16(a1)
	endif
	rts
.rr:
	endif
	movea.l (a3),a3
	move.l  (a3,d3.w),-16(a1)
	ifne FZ_TPLCHK
	move.l  -4(a1),-(sp)            ; the record kept; the general path builds it again
	move.l  -8(a1),-(sp)            ; over it, .fend compares
	move.l  -12(a1),-(sp)
	move.l  -16(a1),-(sp)
	movea.l 16(sp),a1
	movea.l 20(sp),a3
	st      FZ_TPLE
	bra.s   .fchk
	endif
	rts
	ifne FZ_TPLCHK
.tm:	sf      FZ_TPLE
	endif
	endif
	ifne (FZ_TPL=0)|FZ_TPLCHK
.fchk:	move.b  (a3),d1                 ; a descriptor (FZD_FD), not a HUD table (FZD_FH)
	ifne FZ_TPL
	andi.b  #(1<<FZD_FD)|(1<<FZD_FH),d1
	cmpi.b  #1<<FZD_FD,d1
	else
	andi.b  #3,d1
	subq.b  #1,d1
	endif
	bne.w   .gen
	tst.w   2(a3)                   ; the map's bit 15: the lookup range
	bpl.s   .fok
	btst    #0,d6                   ; (pass 1: the take)
	bne.w   .gen
.fok:	cmpa.l  a4,a1
	bhs.w   .full
	ifne FZ_TPLCHK
	tst.b   FZ_TPLE
	bne.s   .fk
	addq.w  #1,FZ_TPLMISS
.fk:
	endif
	ifne FZ_ANCHSUM
	moveq   #$e,d1                  ; the piece's columns onto the buffer's total
	and.b   10(a3),d1
	lsr.w   #1,d1
	addq.w  #1,d1
	add.w   d1,FZB_COLS(a2)
	endif
	addq.l  #4,a1                   ; (+0: the routine, last)
	ifne FZ_FINAL
	move.w  $e(a0),d1
	add.w   4(a3),d1                ; y + the piece's
	move.w  $10(a0),d7
	add.w   6(a3),d7                ; x
	cmp.w   FZ_FYM,d1               ; (FZ_FINAL) on the screen whole: 0 <= y < 224 (FZ_FYM:
	bhs.s   .nf                     ; 0 with the scroll words set, never), 0 <= x < 320 -
	cmpi.w  #320,d7                 ; no wrap, no clip: w0 and w1 as fz_fast_rd would make
	bhs.s   .nf                     ; them, the flag $fe (fz_fastv: no screen tests)
	move.b  8(a3),(a1)+             ; +4 w0 = w0's high byte | y (y < 224: a byte)
	move.b  d1,(a1)+
	move.w  10(a3),d1               ; +6 w1 = w1's high byte | x (x < 320: bit 8 - a
	clr.b   d1                      ; byte store lost it, fz54: the intro's entries
	or.w    d7,d1                   ; differed in 52 rounds, x $120 as $20)
	move.w  d1,(a1)+
	move.w  #(FZU_FAST<<8)|$fe,d7
	bra.s   .fw
.nf:	move.w  d1,(a1)+                ; +4 y (the pass's tests: fz_fast_rd)
	move.w  d7,(a1)+                ; +6 x
	move.w  #(FZU_FAST<<8)|$ff,d7
.fw:
	else
	move.w  $e(a0),d1
	add.w   4(a3),d1
	move.w  d1,(a1)+                ; +4 y + the piece's
	move.w  $10(a0),d1
	add.w   6(a3),d1
	move.w  d1,(a1)+                ; +6 x
	endif
	moveq   #0,d1                   ; +8 w2: colour | bit 5 | flips << 8 (| $1000), the
	move.b  12(a3),d1               ; piece's colour nibble and flips as the flags say
	btst    #2,d6                   ; (FZPD: colour from the object: its flips only)
	beq.s   .fc
	andi.b  #$c0,d1
.fc:	btst    #1,d6                   ; (flips from the object: its colour only)
	bne.s   .ff
	andi.b  #$0f,d1
.ff:	or.b    d0,d1
	lsl.w   #8,d1
	btst    #0,d6
	beq.s   .fp
	ori.w   #$1000,d1
.fp:	move.w  d1,(a1)+
	move.w  2(a3),d3                ; +10 w3 = map (| $2000 in pass 1)
	andi.w  #$3fff,d3
	btst    #0,d6
	beq.s   .f3
	ori.w   #$2000,d3
.f3:	move.w  d3,(a1)+
	ifne FZ_FINAL
	move.w  d7,(a1)+                ; +12 the charge, +13 the flag ($ff, $fe final)
	else
	move.w  #(FZU_FAST<<8)|$ff,(a1)+        ; +12 the charge, +13 the flag
	endif
	move.b  8(a3),(a1)+             ; +14 w0's high byte
	move.b  10(a3),(a1)+            ; +15 w1's
	moveq   #$e,d3                  ; the shape routine: spr_fast_jt's entry at
	and.b   8(a3),d3                ; ((w2 bits 13-15) << 6 | ysize << 3 | xsize) x 4,
	lsl.w   #4,d3                   ; the zoomed shapes' table 2048 on (fz_disp)
	moveq   #$e,d7
	and.b   10(a3),d7
	add.w   d7,d7
	add.w   d7,d3
	lsr.w   #5,d1
	andi.w  #$700,d1
	add.w   d1,d3
	move.b  8(a3),d7
	or.b    10(a3),d7
	andi.b  #$f0,d7
	beq.s   .fz
	addi.w  #2048,d3
.fz:	ori.w   #$100,d3                ; (the shape's own routine: an entry behind tilemap 1
	lea     spr_fast_jt,a3          ; - w2 bit 13 clear - has spr_lo_v/z in the table,
	move.l  (a3,d3.w),-16(a1)       ; which wants the offset in d1; fz_fast does its part)
	ifne FZ_RC
	move.l  $1a(a0),d1              ; the template kept
	bclr    #0,d1
	move.w  d1,d3
	lsl.w   #3,d3
	andi.w  #FZ_RC_MASK,d3
	lea     FZ_RC_AT,a3
	adda.w  d3,a3
	ifne FZ_RCCHK
	cmpa.l  FZ_RCE,a3               ; (shadow mode: a hit's template against the record)
	bne.s   .rcf
	addq.w  #1,FZ_RCHIT
	move.l  12(a3),d3
	cmp.l   -16(a1),d3
	bne.s   .rcb
	move.l  6(a3),d3
	cmp.l   -8(a1),d3
	bne.s   .rcb
	move.w  10(a3),d3
	cmp.w   -2(a1),d3
	beq.s   .rcf
.rcb:	addq.w  #1,FZ_RCBAD
.rcf:
	endif
	move.l  d1,(a3)
	move.b  d0,4(a3)
	move.b  d6,5(a3)
	move.l  -8(a1),6(a3)
	move.w  -2(a1),10(a3)
	move.l  -16(a1),12(a3)
.rcx:
	endif
	ifne FZ_TPLCHK
	tst.b   FZ_TPLE                 ; (shadow mode: the template's record, on the stack,
	beq.s   .fx                     ; against this one)
	addq.w  #1,FZ_TPLHIT
	movem.l (sp)+,d1/d3/d7/a3
	cmp.l   -16(a1),d1
	bne.s   .tbad
	cmp.l   -12(a1),d3
	bne.s   .tbad
	cmp.l   -8(a1),d7
	bne.s   .tbad
	cmpa.l  -4(a1),a3
	beq.s   .tok
.tbad:	addq.w  #1,FZ_TPLBAD
.tok:	addq.l  #8,sp                   ; (the record and descriptor pointers)
.fx:
	endif
	rts
	endif
.gen:
	endif
	move.b  $43(a0),d1
	bpl.s   .c                      ; B (b43 bit 7): the table at $44
	ifne FZ_ANCHSUM
	bsr.w   .ba
	else
	bsr.s   .ba
	endif
.c:	cmpa.l  a4,a1                   ; C: the table at $1a
	bhs.w   .full
	move.l  $1a(a0),d1
	bclr    #0,d1                   ; (even: see above)
	move.l  d1,(a1)+
	ifne FZ_PD
	movea.l d1,a3                   ; (the table's first byte: $01 = descriptors)
	btst    #FZD_FD,(a3)
	beq.s   .cem
	btst    #FZD_FH,(a3)                 ; (a HUD table: the record-level take)
	beq.s   .cpd
	lea     fz_pdht,a3
	bra.s   .csel
.cpd:	lea     fz_pdt,a3
	bra.s   .csel
.cem:
	endif
	lea     fz_emt,a3
.csel:	move.w  d6,d1
	add.w   d1,d1
	add.w   d1,d1
	move.l  (a3,d1.w),(a1)+
	move.l  $e(a0),(a1)+
	moveq   #0,d1                   ; the charge: FZU_TAB + FZU_PIECE x pieces
	move.b  4(a0),d1
	addq.w  #1,d1
	lsl.w   #3,d1
	addi.w  #FZU_TAB,d1
	lsl.w   #8,d1
	or.w    d0,d1
	move.w  d1,(a1)+
	move.b  d7,(a1)+
	move.b  4(a0),(a1)+
	ifne FZ_ANCHSUM
	bsr.s   .cols
	endif
	btst    #6,$43(a0)              ; A (b43 bit 6): the table at $44 again
	beq.s   .x
	bsr.s   .ba
.x:	rts
	ifne FZ_ANCHSUM
	; the record just written (a1 past it): its table's pieces' columns, unclipped, onto
	; the buffer's total (what fz_anch summed walking the records).  Clobbers d1, d3.
.cols:	move.l  a3,-(sp)
	movea.l -16(a1),a3
	moveq   #0,d1
	move.b  -1(a1),d1
.cl:
	ifne FZ_PD
	btst    #FZD_FD,(a3)
	beq.s   .cr
	moveq   #$e,d3
	and.b   11(a3),d3
	bra.s   .cz
.cr:
	endif
	move.l  a3,-(sp)
	movea.l (a3),a3
	moveq   #$e,d3
	and.b   1(a3),d3
	movea.l (sp)+,a3
.cz:	lsr.w   #1,d3
	addq.w  #1,d3
	add.w   d3,FZB_COLS(a2)
	lea     14(a3),a3
	dbra    d1,.cl
	movea.l (sp)+,a3
	rts
	endif
.ba:	cmpa.l  a4,a1                   ; a B/A record: without the object's colour when
	bhs.s   .fba                    ; b43 bit 4 (fx_objg)
	move.l  $44(a0),d1
	bclr    #0,d1                   ; (even: see above)
	move.l  d1,(a1)+
	ifne FZ_PD
	movea.l d1,a3
	endif
	move.w  d6,d1
	move.w  d0,-(sp)
	btst    #4,$43(a0)
	beq.s   .bc
	andi.w  #$fb,d1
	andi.w  #$f0,d0
.bc:
	ifne FZ_PD
	btst    #FZD_FD,(a3)
	beq.s   .bem
	btst    #FZD_FH,(a3)
	beq.s   .bpd
	lea     fz_pdht,a3
	bra.s   .bsel
.bpd:	lea     fz_pdt,a3
	bra.s   .bsel
.bem:
	endif
	lea     fz_emt,a3
.bsel:	add.w   d1,d1
	add.w   d1,d1
	move.l  (a3,d1.w),(a1)+
	move.l  $e(a0),(a1)+
	moveq   #$f,d1
	and.b   $43(a0),d1
	move.w  d1,-(sp)
	addq.w  #1,d1                   ; the charge
	lsl.w   #3,d1
	addi.w  #FZU_TAB,d1
	lsl.w   #8,d1
	or.w    d0,d1
	move.w  d1,(a1)+
	move.w  (sp)+,d1
	move.w  (sp)+,d0
	move.b  d7,(a1)+
	move.b  d1,(a1)+
	ifne FZ_ANCHSUM
	bra.w   .cols
	else
	rts
	endif
.fba:	addq.l  #4,sp                   ; (the record's room: as .full)
.full:	st      FZB_OVF(a2)
	rts

; ---------------------------------------------------------------- the slot's side
; hal_vid_prep (fx_snap_begin's place).  Clobbers d0.
fz_prep:
	jmp     fx_magic                ; (fz_reset when the boot RAM test wiped the state)

; after the game's boot RAM test (fx_magic): no buffers, no pass.  Keeps all.
fz_reset:
	movem.l d0/a0-a1,-(sp)
	lea     FZ_V,a0
	moveq   #(FZ_VEND-FZ_V)/4-1,d0
.c:	clr.l   (a0)+
	dbra    d0,.c
	lea     fz_btab(pc),a1
	moveq   #FZ_NB-1,d0
.b:	movea.l (a1)+,a0
	clr.l   (a0)
	clr.l   4(a0)
	clr.l   FZB_MAGIC(a0)
	dbra    d0,.b
	ifne FZ_PD
	clr.w   FZ_HCOK                 ; (the HUD cache: no slot trusted)
	endif
	move.w  HAL_SPR_W,d0            ; a pass in work read records just lost (a stage
	bmi.s   .nw                     ; change wipes the sprite RAM: it went on through
	lea     HAL_SPR_ST,a0           ; wiped pointers to address 0 - a reboot loop at
	clr.b   (a0,d0.w)               ; the first stage change, fz17-fz20, 2026-10-18):
	move.w  #-1,HAL_SPR_W           ; its set freed (never shown), the pass over
	clr.l   HAL_SPR_RA5
	st      HAL_SPR_DONE
	sf      HAL_SPR_BLK
.nw:	movem.l (sp)+,d0/a0-a1
	rts

; hal_spr_work: the buffer due in this slot (complete, stamp + 2 <= HAL_FRAMES): the
; newest such; older due ones are dropped (late already: never shown).  None: the
; buffer a slot early (stamp + 1), if any (FZ_EARLY; the commit's tail only before:
; a dense scene's passes, each a slot's time, could not catch up after a burst - the
; HAL idled with the next buffer complete, 2026-10-18).  Z set: none.
; Clobbers d0-d3, a0-a3.
fz_due:
	lea     fz_btab(pc),a2
	suba.l  a1,a1
	ifne FZ_EARLY
	suba.l  a3,a3
	endif
	move.w  #$7fff,d2
	move.w  HAL_FRAMES+2,d1
	moveq   #FZ_NB-1,d0
.l:	movea.l (a2)+,a0
	cmpi.b  #1,FZB_ST(a0)
	bne.s   .n
	cmpi.l  #FZ_MAGICV,FZB_MAGIC(a0)
	bne.s   .bad
	move.w  d1,d3
	sub.w   FZB_STAMP(a0),d3        ; (frame numbers wrap: the sign of the difference)
	cmpi.w  #2,d3
	bge.s   .due
	cmpi.w  #1,d3                   ; a slot early, after its commit's flip (the set that
	bne.s   .n                      ; flip freed is the one to convert into: three sets
	ifne FZ_EARLY
	move.l  a3,d3                   ; still; the set is shown at its RDY all the same).
	beq.s   .e1                     ; Two of them (one stamp: two rounds in one frame):
	move.l  FZB_SEQ(a0),d3          ; the later build is the one, the earlier dropped
	cmp.l   FZB_SEQ(a3),d3          ; (fz_build freed it itself until 2026-10-19: the race
	bhi.s   .e2                     ; above)
	bsr.s   .dup
	bra.s   .n
.e2:	exg     a0,a3
	bsr.s   .dup
	exg     a0,a3
.e1:	movea.l a0,a3
	bra.s   .n
	else
	tst.w   HAL_SPR_TAILU           ; still), for a whole slot's tail more of time (the
	beq.s   .n                      ; set is shown at its RDY all the same: 2026-10-18)
	endif
.due:
	cmp.w   d2,d3
	bhi.s   .old                    ; (older than the best so far: dropped)
	bne.s   .nw
	move.l  FZB_SEQ(a0),d3          ; the same stamp (two rounds in one frame): the
	cmp.l   FZB_SEQ(a1),d3          ; later build is the one, the other never shown
	bhi.s   .d2
	bsr.s   .dup
	bra.s   .n
.d2:	exg     a0,a1
	bsr.s   .dup
	exg     a0,a1
	bra.s   .new
.nw:	move.l  a1,d3                   ; newer than the best so far: that one is dropped
	beq.s   .new
	exg     a0,a1
	bsr.s   .drop
	exg     a0,a1
.new:	movea.l a0,a1
	move.w  d1,d2
	sub.w   FZB_STAMP(a0),d2
	bra.s   .n
.old:	bsr.s   .drop
	bra.s   .n
.bad:	clr.b   FZB_ST(a0)
.n:	dbra    d0,.l
	ifne FZ_EARLY
	move.l  a1,d0
	bne.s   .x
	ifne FZ_EARLYB
	tst.b   HAL_SCH_BUSY            ; (FZ_EARLYB, AUDIT 46: the slot began with the game
	bne.s   .x                      ; still in its round - no buffer a slot early: its
	endif                           ; pass would run in the game's time; due next slot)
	movea.l a3,a1
.x:
	endif
	move.l  a1,FZ_DUE
	move.l  a1,d0
	rts
.drop:	clr.b   FZB_ST(a0)
	addq.w  #1,FZ_NDUE
	rts
.dup:	clr.b   FZB_ST(a0)              ; (the earlier build of a duplicate round)
	addq.w  #1,FZ_NDUP
	rts

; hal/sched.s .hold (FZ_EARLY): Z set when the set in work (if any) is not for the next
; flip (its RDY past HAL_FRAMES + 1): the game is not held for it (a pass begun a slot
; early held the game as if it were: coast/river lost 9.5% of its logic frames
; against 3.1%, 2026-10-18).  Clobbers d0, a0.
fz_urgent:
	move.w  HAL_SPR_W,d0
	bmi.s   .y
	add.w   d0,d0
	lea     HAL_SPR_RDY,a0
	move.w  (a0,d0.w),d0
	sub.w   HAL_FRAMES+2,d0         ; (frame numbers wrap: the sign)
	subq.w  #1,d0
	ble.s   .y
	moveq   #0,d0                   ; Z: for a later flip
	rts
.y:	moveq   #1,d0                   ; NZ: hold (as before)
	rts

; hal_spr_work, after hal_spr_begin: the pass over FZ_DUE into set HAL_SPR_W begins.
; Clobbers d0-d1, a0-a1.
fz_begin:
	ifne FZ_SHED
	move.l  HAL_SPR_DROP,d0         ; (FZ_SHED) the last pass dropped sprites: shed one
	cmp.l   FZ_SH_D,d0              ; level more (at most 2); FZ_SHCALM passes without a
	beq.s   .shc                    ; drop: one less
	move.l  d0,FZ_SH_D
	clr.b   FZ_SH_C
	cmpi.b  #2,FZ_SH_LV
	bhs.s   .shp
	addq.b  #1,FZ_SH_LV
	bra.s   .shp
.shc:	tst.b   FZ_SH_LV
	beq.s   .shp
	addq.b  #1,FZ_SH_C
	cmpi.b  #FZ_SHCALM,FZ_SH_C
	blo.s   .shp
	clr.b   FZ_SH_C
	subq.b  #1,FZ_SH_LV
.shp:	not.b   FZ_SH_P                 ; (the parity: the other half next pass)
	endif
	ifne FZ_MERGE
	move.w  #$ffff,FZ_MG_HN         ; (FZ_MERGE: no last record; on for a set after a large
	cmpi.w  #FZ_MGT,HAL_SPR_PREV    ; one)
	scc     FZ_MG_ON
	endif
	movea.l FZ_DUE,a0
	move.b  #2,FZB_ST(a0)
	move.l  a0,FZ_PBUF
	lea     FZB_REC(a0),a1
	move.l  a1,FZ_RECS
	move.l  a1,FZ_REC               ; the first record (the list's order: hal_spr_go
	moveq   #0,d0                   ; went up the walk's list, the first entry on top)
	move.w  FZB_N(a0),d0
	lsl.l   #4,d0
	adda.l  d0,a1
	move.l  a1,FZ_RECE
	clr.b   FZ_PH
	clr.w   FZ_LEFT
	move.w  G_DX_SCRY,FZ_SY
	move.w  G_DX_SCRX,FZ_SX
	addq.l  #1,FZ_PASSN
	move.w  FZB_STAMP(a0),d0        ; its number: the slot the arcade first shows this
	addq.w  #3,d0                   ; round's list in (the first slot after the round's
	move.w  d0,FX_WSEQ              ; builder point, + 2: its sprite RAM is double
                                    ; buffered); the HUD queue's number too (hal/fx.s)
	move.w  HAL_SPR_W,d0
	add.w   d0,d0
	lea     FZ_SEQ,a0
	move.w  FX_WSEQ,(a0,d0.w)
	lea     HAL_SPR_RDY,a0          ; shown from that slot (hal_spr_work set the slot
	move.w  FX_WSEQ,(a0,d0.w)       ; after this one: a pass begun a slot early would
	lea     FZ_PBN,a0               ; show a frame early)
	clr.w   (a0,d0.w)
	move.w  d0,d1                   ; its pool records (8 x BP_N a set)
	lsl.w   #7,d1
	lea     FZ_POOL,a0
	adda.w  d1,a0
	move.l  a0,FZ_PBP
	lea     8*BP_N(a0),a0
	move.l  a0,FZ_PBE
	jsr     bp_poll                 ; (hal/fx.s: the pool on, off)
	ifne BP_SIZED
	movea.l FZ_PBP,a0               ; (BP_SIZED: the room for records at the pool's size
	move.w  BP_NV,d1                ; now - FZ_PBE stays the area's end: the count is
	lsl.w   #3,d1                   ; taken from it)
	adda.w  d1,a0
	move.l  a0,FZ_PBL
	endif
	clr.w   FX_HSEEN                ; (the HUD: as fx_snap_begin)
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
	rts

; hal_spr_work .fin: the pass complete (its pool records counted, its buffer free).
; Clobbers d0-d1, a0.
fz_fin:
	move.w  HAL_SPR_W,d0
	add.w   d0,d0
	move.l  FZ_PBP,d1
	sub.l   FZ_PBE,d1
	addi.l  #8*BP_N,d1
	lsr.w   #3,d1
	lea     FZ_PBN,a0
	move.w  d1,(a0,d0.w)
	movea.l FZ_PBUF,a0
	clr.b   FZB_ST(a0)
	rts

; hal_spr_go .rst: the pass from its start again (the set begun again at the top).
; Clobbers d0, a1.
fz_rst:
	ifeq FUSED-2
	bsr.w   fz_gt_start             ; (the objects from the first again; fz_next's
	clr.w   FZ_LEFT                 ; table end then goes to fz_gt_scan)
	move.l  #fz_gt_scan,FZ_CONT
	else
	move.l  FZ_RECS,FZ_REC
	clr.b   FZ_PH
	clr.w   FZ_LEFT
	endif
	move.l  FZ_PBE,d0
	subi.l  #8*BP_N,d0
	move.l  d0,FZ_PBP
	clr.w   FX_HSEEN
	clr.w   FX_HSAME
	ifne FX_HOV
	clr.w   FX_HSUS
	sf      FX_HR1
	endif
	rts


; hal_spr_begin (SPR_ANCH): spr_begin_anch from the due records instead of the list: a
; set begun below the newest set's end ends at SPR_PB as its pieces need - an upper
; bound here: the pieces unclipped (the walk's list held only the visible ones) -, at
; most ANLN pieces looked at (more: the start as it was).  d0 = the start, in and out.
; Clobbers d1-d6, a1-a3.
fz_anch:
	tst.b   HAL_SPR_ORDN
	beq.w   .x
	tst.b   HAL_SPR_SPS
	bpl.w   .x
	move.w  HAL_SPR_GNEXT,d2
	cmp.w   d2,d0
	bhi.w   .x                      ; (from the top)
	moveq   #0,d1
	move.b  HAL_SPR_ORD,d1
	add.w   d1,d1
	lea     HAL_SPR_START,a1
	cmp.w   (a1,d1.w),d2            ; (the tail below the newest set's end: the room
	bhi.w   .x                      ; ends there)
	movea.l FZ_DUE,a1
	ifne FZ_ANCHSUM
	move.w  FZB_COLS(a1),d2         ; the columns (fz_build's total; 4 as spr_begin_anch)
	addq.w  #4,d2
	bra.s   .sum
	endif
	move.w  FZB_N(a1),d3            ; the records
	lea     FZB_REC(a1),a1
	moveq   #4,d2                   ; the columns (as spr_begin_anch counts them)
	moveq   #ANLN,d4                ; pieces looked at, at most
	bra.s   .r1
.r:
	ifne FZ_FAST
	ifne FZ_FINAL
	cmpi.b  #$fe,13(a1)             ; (a fast record, $ff or $fe: one piece, w1's high
	blo.s   .rg                     ; byte at +15)
	else
	cmpi.b  #$ff,13(a1)             ; (a fast record: one piece, w1's high byte at +15)
	bne.s   .rg
	endif
	subq.w  #1,d4
	bmi.s   .x
	moveq   #$e,d5
	and.b   15(a1),d5
	lsr.w   #1,d5
	addq.w  #1,d5
	add.w   d5,d2
	bra.s   .rn
.rg:
	endif
	movea.l (a1),a2                 ; the record's table
	moveq   #0,d1
	move.b  15(a1),d1
	bsr.s   .tab
	bmi.s   .x
.rn:	lea     FZ_RSZ(a1),a1
.r1:	dbra    d3,.r
.sum:	addi.w  #SPR_PB,d2
	cmp.w   HAL_SPR_GNEXT,d2
	bhs.s   .x
	move.w  d2,d0
.x:	rts
	; the table a2, d1 = pieces - 1: their columns onto d2.  N set: ANLN pieces past.
.tab:	subq.w  #1,d4
	bmi.s   .tx
	ifne FZ_PD
	btst    #FZD_FD,(a2)
	beq.s   .tr
	moveq   #$e,d5
	and.b   11(a2),d5               ; (a descriptor: the header's xsize byte at +11)
	bra.s   .tz
.tr:
	endif
	movea.l (a2),a3
	moveq   #$e,d5
	and.b   1(a3),d5
.tz:	lsr.w   #1,d5
	addq.w  #1,d5
	add.w   d5,d2
	lea     14(a2),a2
	dbra    d1,.tab
	moveq   #0,d5                   ; (N clear)
.tx:	rts

	ifne FZ_DIAG
; (FZ_DIAG) the line counter now into FZ_T0 / the lines since it in d0.  Clobbers d0.
fz_tbeg:
	move.w  REG_LSPCMODE,d0
	lsr.w   #7,d0
	move.w  d0,FZ_T0
	rts
fz_tlin:
	move.w  REG_LSPCMODE,d0
	lsr.w   #7,d0
	sub.w   FZ_T0,d0
	bpl.s   .k
	addi.w  #264,d0
.k:	rts
; a pass run ends (hal_spr_go's .stop/.done): in a commit's tail, its lines noted
fz_tend:
	movem.l d0,-(sp)
	bsr.s   fz_tlin
	tst.w   HAL_SPR_TAILU
	beq.s   .x
	addq.w  #1,FZ_TN
	andi.l  #$ffff,d0
	add.l   d0,FZ_TSUM
	cmp.w   FZ_TMAX,d0
	ble.s   .x
	move.w  d0,FZ_TMAX
	move.b  FZ_PH,FZ_TPHM
.x:	movem.l (sp)+,d0
	rts
	endif

; ---------------------------------------------------------------- the pass
; hal_spr_go (FUSED): set a6 from where the pass stopped (or its start).  Z set: all
; done; Z clear: stopped (hal_spr_go's .late/.stop/.done paths, (sp) popped there).
fz_go:
	ifne FZ_DIAG
	jsr     fz_tbeg
	endif
	move.l  a6,HAL_SPR_WPTR
	lea     G_SPRLUT,a2
	lea     REG_VRAMRW,a3
	move.w  #1,REG_VRAMMOD
	jsr     hal_spr_lim
	lea     SS_HADR(a6),a4
	adda.w  SS_HOFF(a6),a4
	move.l  #(-FZU_GO<<16)|$7fff,d7 ; (no credit: the first charge refills, this run's
	move.l  a6,d0                   ; entry and exit counted)
	addi.l  #SS_HADR+2*SS_MAXHEAD,d0
	move.l  d0,-(sp)                ; the head slots' end
	movea.l HAL_SPR_RA5,a5
	movea.l FZ_RTN,a0
	tst.b   FZ_PH                   ; (a resume in the HUD pass)
	bne.w   fz_hudp
	; (falls into fz_next)

; the next piece of the table (a5 up one, a0 its routine), or the next table
fz_next:
	ifeq FUSED-2
	move.w  FZ_SR,sr                ; (the piece's VRAM sequence done: the slot may come)
	subq.w  #1,FZ_LEFT
	bmi.s   .tabend
	lea     14(a5),a5
	ori.w   #$0700,sr               ; the next piece: no slot between its address and
	move.w  #1,REG_VRAMMOD          ; data writes (and its own modulo)
	jmp     (a0)
.tabend:
	movea.l FZ_CONT,a1              ; the table done: the object's next table, or on
	jmp     (a1)
	else
	subq.w  #1,FZ_LEFT
	bmi.s   fz_ntab
	lea     14(a5),a5
	FZD     FZ_D0
	jmp     (a0)
	endif

; the next record (a table: its routine, pieces, the object's y, x, w2 byte, zoom), or
; the HUD pass once the records are done.  A record is charged FZU_TAB + FZU_PIECE x
; pieces units (its set-up and the pieces' clip tests; a visible piece's shape routine
; charges the rest, PRE_MAX of tools/gen_sprfast.py bounding the way to its dispatch)
; before FZ_REC moves on, so a stop here resumes with the same record.
	ifnd FZU_TAB
FZU_TAB         equ 26              ; a record's set-up (fz_ntab: measured ~370 cycles; the
	endif                           ; commit's tail overran by ~20% of its credit at 14)
FZU_GO          equ 16              ; a pass run's entry (fz_go) and exit (.stop/.hoff)
	ifnd FZU_PIECE
FZU_PIECE       equ 8               ; a piece's clip tests (fz_next, fz_em_*: ~110)
	endif
	ifnd FZU_FASTX
FZU_FASTX       equ 6               ; (FZ_FAST) units given back at a fast record's dispatch on
	endif                           ; top of its own charge: the shape routine's charge keeps
                                    ; PRE_MAX (~620 cycles) for the general way before it, the
                                    ; fast way is ~500 at most.  Measured (fzcost, fz35c): the
                                    ; fast records' slack 0.90 of 1,064 cycles = ~6 units; 12
                                    ; made 172 overruns a battery, 6 made 18 (fz36 12), lost
                                    ; logic 3.11 -> 2.79% (AUDIT.md 29, 2026-10-18)
FZU_HUDT        equ 90+(7-4*FX_HOVCHG)*FX_HOV ; a pass-1 piece in the HUD's lookup range: fx_hud_take
                                    ; (FX_HOV: + its yield and suspect tests, the charge after it)
                                    ; (the cache's way before it is FZU_HHIT's, charged first)
FZU_HOV         equ FXU_HOV         ; (FX_HOV) fx_hud_ov after a new strip's take (hal/fx.s)
FZU_HLUT        equ 20              ; (FZ_PD) the cache's compare of a strip's entries when the
                                    ; lookup generation moved (fz_pdh_*: ~250 cycles)
FZU_HHIT        equ 28+(3-2*FX_HOVCHG)*FX_HOV ; (FZ_PD) a HUD piece taken from the cache (fz_pdh_*: ~500
                                    ; cycles with its fz_next; the tails ran 1-2 lines over
                                    ; charged FZU_PIECE alone, 2026-10-18)
                                    ; (measured 1,340-1,430 cycles a piece with its fz_em_ way
                                    ; in the commit tails; 40 until 2026-10-18: the tails' 2-7
                                    ; line overruns, work/play/fh/fzev.lua + fzcost.py)
FZ_HUDRES       equ 5*48            ; the HUD pass keeps this back (hal/fx.s fx_walk:
                                    ; its HUD pass runs up to ~5 lines over its charge)
fz_ntab:
	movea.l FZ_REC,a1
	ifne FZ_SHED
	tst.b   (a1)                    ; (FZ_SHED) a sheddable record, shedding on: skipped
	bpl.s   .ns                     ; at level 2, every other one (by its index and the
	move.b  FZ_SH_LV,d0             ; pass's parity: each shown every other frame) at 1
	beq.s   .cl
	cmpi.b  #2,d0
	bhs.s   .sk
	move.w  a1,d0
	lsr.w   #4,d0
	move.b  FZ_SH_P,d6
	eor.b   d6,d0
	btst    #0,d0
	bne.s   .cl
.sk:	addi.l  #FZ_RSZ,FZ_REC
	addq.l  #1,FZ_SHN
	lea     HAL_SPR_MIX,a1          ; (the set a slip, as a drop)
	move.w  HAL_SPR_W,d0
	bset    #1,(a1,d0.w)
	bra.s   fz_ntab
.cl:	bclr    #7,(a1)                 ; (kept: its long whole again before anything jumps
.ns:                                    ; through it - a PC with bit 31 set would reach the
	endif                           ; stack and the resume addresses)
	ifne FZ_FAST&FZ_FASTCHG
	ifne FZ_FINAL
	cmpi.b  #$fe,13(a1)             ; (a fast record: $fe final - fz_fastv, no screen test;
	beq.w   fz_fastv                ; $ff - fz_fast, charged when its piece is clipped; a
	bhi.w   fz_fast                 ; visible one by its shape routine's charge)
	else
	cmpi.b  #$ff,13(a1)             ; (a fast record: charged in fz_fast when its piece is
	beq.w   fz_fast                 ; clipped; a visible one by its shape routine's charge)
	endif
	endif
	move.w  12(a1),d1               ; the charge (high byte), the w2 byte
	move.w  d1,d6
	lsr.w   #8,d6
	swap    d7
	sub.w   d6,d7
	bpl.s   .tk
	move.w  d6,d0
	jsr     hal_spr_refill
	bmi.s   .nt
.tk:	swap    d7
	ifne FZ_FAST&(FZ_FASTCHG=0)
	cmpi.b  #$ff,d1                 ; (a fast record: its own way)
	beq.w   fz_fast
	endif
	andi.w  #$ff,d1
	move.w  d1,FZ_W2
	move.l  8(a1),FZ_Y              ; y, x
	move.w  14(a1),d1               ; zoom << 12 | pieces - 1
	move.w  d1,d0
	andi.w  #$f000,d0
	move.w  d0,FZ_ZOOM
	movea.l 4(a1),a0                ; its routine
	movea.l (a1),a5                 ; the table
	addi.l  #FZ_RSZ,FZ_REC
	andi.w  #$ff,d1                 ; pieces - 1
	bne.s   .mp                     ; (one piece: straight to it)
	clr.w   FZ_LEFT
	jmp     (a0)
.mp:	addq.w  #1,d1                   ; (more: fz_next steps onto each)
	move.w  d1,FZ_LEFT
	lea     -14(a5),a5
	bra.w   fz_next
.nt:	swap    d7
	FZD     FZ_D1
	jmp     spr_go_stop
	; the pieces done (the terminator record's routine): the HUD's slots (hal/fx.s
	; fx_walk's HUD pass, FX_PASS 4 -> 5, with the time left as its units)
fz_toh:	move.w  #4,FX_PASS
	clr.w   FX_GI
	st      FZ_PH
fz_hudp:
	swap    d7
	move.w  #FZ_HUDRES,d0
	jsr     hal_spr_refill
	bmi.w   .hnt
	move.w  d7,d6
	swap    d7
	ifne FZ_DIAG
	move.w  REG_LSPCMODE,d0
	lsr.w   #7,d0
	move.w  d0,FZ_T1
	move.w  d6,FZ_HD6T
	endif
	movem.l d7/a2-a6,-(sp)
	jsr     fx_walk
	movem.l (sp)+,d7/a2-a6
	ifne FZ_DIAG
	tst.w   HAL_SPR_TAILU
	beq.s   .nh
	move.w  REG_LSPCMODE,d0
	lsr.w   #7,d0
	sub.w   FZ_T1,d0
	bpl.s   .h1
	addi.w  #264,d0
.h1:	cmp.w   FZ_HMAX,d0
	ble.s   .nh
	move.w  d0,FZ_HMAX
	move.w  FZ_HD6T,FZ_HD6
	move.w  d6,FZ_HD6A
.nh:
	endif
	cmpi.w  #5,FX_PASS
	bne.s   .hn
	FZD     FZ_D5
	jmp     spr_go_done
.hn:	FZD     FZ_D3
	jmp     spr_go_stop
.hnt:	swap    d7
	FZD     FZ_D2
	jmp     spr_go_stop

; a pair bullet's record (its routine; FZ_W2 = its fxb_ok value): one entry, or a pool
; record (hal/fx.s fxb_obj from its .t on)
fz_bul:
	clr.w   FZ_LEFT                 ; (one entry for the record's two pieces; a budget
	addq.w  #1,BP_SEEN              ; stop steps back onto it: the pool's policy count)
	move.w  FZ_Y,d0                 ; the walk's clip, each half: y - 16 and y in
	addi.w  #288-16,d0              ; -288..223
	cmpi.w  #512,d0
	bhs.w   .tn
	cmpi.w  #512-16,d0
	bhs.w   .gen                    ; (the upper only: the general way)
	move.w  FZ_X,d1                 ; x - 16 in -192..319
	addi.w  #192-16,d1
	cmpi.w  #512,d1
	bhs.w   fz_next                 ; (neither)
	move.w  FZ_Y,d2                 ; w0 = y - 16 + scroll | ysize 1
	add.w   FZ_SY,d2
	subi.w  #16,d2
	andi.w  #$1ff,d2
	cmpi.w  #224,d2
	blo.s   .vy
	cmpi.w  #512-32,d2
	bls.w   fz_next
.vy:	ori.w   #$200,d2
	move.w  FZ_X,d3                 ; w1 = x - 16 + scroll | xsize 1
	add.w   FZ_SX,d3
	subi.w  #16,d3
	andi.w  #$1ff,d3
	cmpi.w  #320,d3
	blo.s   .vx
	cmpi.w  #512-32,d3
	bls.w   fz_next
.vx:	ori.w   #$200,d3
	move.w  FZ_W2,d0
	lea     fxb_k-1,a1              ; w2 = ($30 | colour) << 8 | $80, w3 = map | $2000
	move.l  (a1,d0.w),d0
	cmpi.b  #2,BP_ST                ; the bullet pool on, room in its records?
	bne.s   .ls
	movea.l FZ_PBP,a1
	ifne BP_SIZED
	cmpa.l  FZ_PBL,a1
	else
	cmpa.l  FZ_PBE,a1
	endif
	bhs.s   .ls
	ifne BP_STABLE
	movea.l FZ_REC,a1               ; (BP_STABLE: the record as the flip writes it; the
	move.b  -FZ_RSZ(a1),d1          ; object's index = the record's byte 0)
	movea.l FZ_PBP,a1
	andi.w  #$1ff,d2                ; w0 = SCB3: (496 - y) << 7 | 2 (the rows)
	neg.w   d2
	lsl.w   #7,d2
	addi.w  #(496<<7)+2,d2
	move.w  d2,(a1)+
	andi.w  #$1ff,d3                ; w1 = SCB4: x << 7 | the index's low 7 bits
	lsl.w   #7,d3
	move.b  d1,d4
	andi.w  #$7f,d4
	or.w    d4,d3
	move.w  d3,(a1)+
	swap    d0                      ; w2 = the attribute (the palette) | the index's bit 7
	andi.w  #$1f00,d0
	addi.w  #NPAL_SPR<<8,d0
	andi.b  #$80,d1
	or.b    d1,d0
	swap    d0
	move.l  d0,(a1)+                ; w3 = the map
	else
	move.w  d2,(a1)+
	move.w  d3,(a1)+
	move.l  d0,(a1)+
	endif
	move.l  a1,FZ_PBP
	bra.w   fz_next
.ls:	move.w  d0,d5                   ; else an entry (hal/spr.s spr_go_bul)
	swap    d0
	move.w  d0,d4
	bra.w   fz_disp
.tn:	addi.w  #16,d0                  ; the upper half out: the lower one in?
	cmpi.w  #512,d0
	bhs.w   fz_next
.gen:	subq.w  #1,BP_SEEN              ; the general way: its two pieces (the C table,
	clr.w   FZ_ZOOM                 ; flips from them, colour from them, pass 1)
	move.w  #$20,FZ_W2
	move.w  #1,FZ_LEFT              ; (a5 = the table = its first piece, one more after)
	lea     fz_em_0011,a0
	ifne FZ_PD
	btst    #FZD_FD,(a5)                 ; (descriptors: their routine)
	beq.s   .g0
	lea     fz_pd_0011,a0
.g0:
	endif
	jmp     (a0)

; d2-d5 = the entry's words: the shape routine (hal_spr_go's dispatch; no head slot
; left: the rest dropped)
fz_disp:
	ifne FZ_DIAG
	lea     FZ_DW,a1
	movem.w d2-d5,(a1)
	endif
	ifeq FUSED-2
	cmpa.l  FZ_HEND,a4
	else
	cmpa.l  (sp),a4
	endif
	bhs.w   fz_nsl
	ifne FZ_MERGE
	tst.b   FZ_MG_ON
	beq.s   .nm
	bsr.w   fz_mg                   ; (merged: it goes on at fz_next itself)
.nm:
	endif
	move.w  d2,d1                   ; (w2 bits 13-15) << 6 | ysize << 3 | xsize, x4
	lsr.w   #4,d1
	andi.w  #$e0,d1
	move.w  d3,d0
	lsr.w   #7,d0
	andi.w  #$1c,d0
	add.w   d0,d1
	move.w  d4,d0
	lsr.w   #5,d0
	andi.w  #$700,d0
	add.w   d0,d1
	lea     spr_fast_jt,a1
	move.w  d2,d0
	or.w    d3,d0
	cmpi.w  #$1000,d0               ; zoomed: the zoomed shapes' table
	blo.s   .fj
	lea     2048(a1),a1
.fj:	movea.l (a1,d1.w),a1
	jmp     (a1)
fz_nsl:	FZD     FZ_D6
	addq.l  #1,HAL_SPR_DROP         ; (as hal_spr_go .nsl: a slip)
	lea     HAL_SPR_MIX,a1
	move.w  HAL_SPR_W,d0
	bset    #1,(a1,d0.w)
	ifeq FUSED-2
	jmp     fz_gt_hud               ; (the rest dropped: the HUD pass, the set complete)
	else
	move.w  #4,FX_PASS
	clr.w   FX_GI
	move.b  #5,FZ_PH
	bra.w   fz_hudp
	endif

	ifne FZ_FAST
; (FZ_FAST) a fast record (fz_rec: +0 l its shape routine, +4 w y, +6 w x, +8 w w2, +10 w
; w3, +14 b w0's high byte, +15 b w1's): the screen tests as the piece routines' (the
; builder's, then the Neo screen's with the wrap), the four words, the shape routine
; straight.  a1 = the record (fz_ntab: charged FZU_FAST; the way from there to the
; dispatch is ~340 cycles against the ~620 a shape routine's charge keeps for it: the
; charge is given back at the dispatch, a clipped piece keeps it).  A budget stop in
; the shape routine steps back a "piece" (spr_go_late: a5 - 14, FZ_LEFT + 1): a5 is
; the record, a0 fz_fast_rd, so fz_next comes back here with the record done again.
	ifnd FZU_FAST
FZU_FAST        equ 15              ; (fz_ntab to fz_next for a clipped piece: ~230 cycles)
	endif
fz_fast:
	addi.l  #FZ_RSZ,FZ_REC
	movea.l a1,a5
	lea     fz_fast_rd(pc),a0
	clr.w   FZ_LEFT
	ifd FZ_COST
	move.l  a1,FZ_COST2             ; (diagnostics, work/play/fh/fzev.lua)
	endif
	ifne FZ_FASTCHG
FZ_CLIP	macro                           ; (a clipped piece: the record's charge now, then on)
	bhs.w   .clip
	endm
FZ_CLIPB	macro
	bls.w   .clip
	endm
	else
FZ_CLIP	macro
	bhs.w   fz_next
	endm
FZ_CLIPB	macro
	bls.w   fz_next
	endm
	endif
fz_fast_rd:
	move.w  4(a5),d2                ; y
	cmpi.w  #$fee0,d2
	bhs.s   .yv
	cmpi.w  #$e0,d2
	FZ_CLIP
.yv:	move.w  6(a5),d3                ; x
	cmpi.w  #$ff40,d3
	bhs.s   .xv
	cmpi.w  #$140,d3
	FZ_CLIP
.xv:	add.w   FZ_SY,d2                ; w0 = y + scroll | the high byte (zoomy, header 0)
	andi.w  #$1ff,d2
	cmpi.w  #224,d2
	blo.s   .vy
	moveq   #$e,d6
	and.b   14(a5),d6
	lsl.w   #3,d6
	add.w   d2,d6
	cmpi.w  #512-16,d6
	FZ_CLIPB
.vy:	move.w  14(a5),d6
	andi.w  #$ff00,d6
	or.w    d6,d2
	add.w   FZ_SX,d3                ; w1 = x + scroll | the high byte (zoomx, header 1)
	andi.w  #$1ff,d3
	cmpi.w  #320,d3
	blo.s   .vx
	moveq   #$e,d6
	and.b   15(a5),d6
	lsl.w   #3,d6
	add.w   d3,d6
	cmpi.w  #512-16,d6
	FZ_CLIPB
.vx:	move.w  14(a5),d6
	lsl.w   #8,d6
	or.w    d6,d3
	movem.w 8(a5),d4-d5             ; w2, w3
	ifne FZ_DIAG
	lea     FZ_DW,a1
	movem.w d2-d5,(a1)
	endif
	cmpa.l  (sp),a4                 ; (fz_disp: no head slot left)
	bhs.w   fz_nsl
	swap    d7
	ifeq FZ_FASTCHG
	addi.w  #FZU_FAST+FZU_FASTX,d7  ; (the charge back: the shape routine's covers the way)
	else
	addq.w  #FZU_FASTX,d7           ; (the shape routine's measured slack, as before: without
	endif                           ; it the pass stopped ~3k cycles earlier, fz52: +1.3 points)
	btst    #13,d4                  ; behind tilemap 1: as spr_lo_v/z (hal/spr.s) before
	bne.s   .fr                     ; the shape's routine (the record holds that one: a
	st      SS_PRIO(a6)             ; garbage jump through spr_lo's d1 until 2026-10-18,
	subi.w  #LO_UNITS,d7            ; fz35-fz39: garbage sprites in the title and the
.fr:	swap    d7                      ; game over screens on the device and in MAME)
	movea.l (a5),a1
	jmp     (a1)
	ifne FZ_FASTCHG
.clip:	swap    d7                      ; the clipped piece's charge (its way to here); no time:
	subi.w  #FZU_FAST,d7            ; this record again (as fz_hud's .nt)
	bpl.s   .ck
	moveq   #FZU_FAST,d0
	jsr     hal_spr_refill
	bmi.s   .cnt
.ck:	swap    d7
	jmp     fz_next
.cnt:	swap    d7
	lea     -14(a5),a5
	addq.w  #1,FZ_LEFT
	jmp     spr_go_stop
	endif
	ifne FZ_FINAL
; (FZ_FINAL) a final fast record (fz_rec: its piece on the screen whole, the scroll words
; zero: +4 w w0, +6 w w1, +8 w w2, +10 w w3 as fz_fast_rd would make them): the four words
; and the shape routine, no screen test.  As fz_fast otherwise (a0 = fz_fastv_rd for a
; budget stop's way back).
	ifne BP_SHOTS
; (BP_SHOTS) a poolable shot piece's record (fz_fastv: d2-d5 its final words): the bullet
; pool on with room -> a pool record (w2 low byte $40: hal/fx.s bp_apply's generic kind,
; the sizes in w0/w1 bits 9-11, the flips in w2 bits 14-15) and nothing in the set; else
; the record's shape routine as fz_disp picks it.  BP_SEEN counts it either way (the
; pool's policy, as the pair bullets).
fz_pshot:
	addq.w  #1,BP_SEEN
	cmpi.b  #2,BP_ST
	bne.s   .d
	movea.l FZ_PBP,a1
	ifne BP_SIZED
	cmpa.l  FZ_PBL,a1
	else
	cmpa.l  FZ_PBE,a1
	endif
	bhs.s   .d
	ifne BP_STABLE
	move.w  d2,d0                   ; (BP_STABLE: the record as the flip writes it) w0 =
	lsr.w   #8,d0                   ; SCB3: (496 - y) << 7 | the rows
	lsr.w   #1,d0
	andi.w  #7,d0
	addq.w  #1,d0
	andi.w  #$1ff,d2
	neg.w   d2
	lsl.w   #7,d2
	add.w   d0,d2
	addi.w  #496<<7,d2
	move.w  d2,(a1)+
	move.w  d3,d0                   ; w1 = SCB4: x << 7 | the object's index (its low 7
	andi.w  #$1ff,d0                ; bits; the routine long's high byte)
	lsl.w   #7,d0
	move.b  (a5),d1
	move.b  d1,d2
	andi.w  #$7f,d2
	or.w    d2,d0
	move.w  d0,(a1)+
	move.w  d4,d0                   ; w2 = the attribute (palette, flips) | $40 | the
	andi.w  #$1f00,d0               ; index's bit 7 | the columns - 1 (bit 2)
	addi.w  #(NPAL_SPR<<8)+$40,d0
	rol.w   #2,d4
	andi.w  #3,d4
	or.w    d4,d0
	andi.b  #$80,d1
	or.b    d1,d0
	lsr.w   #8,d3
	lsr.w   #1,d3
	andi.w  #1,d3
	lsl.w   #2,d3
	or.w    d3,d0
	move.w  d0,(a1)+
	move.w  d5,(a1)+                ; w3 = the lookup index
	else
	movem.w d2-d5,(a1)
	ori.b   #$40,5(a1)
	addq.l  #8,a1
	endif
	move.l  a1,FZ_PBP
	jmp     fz_next
.d:	jmp     fz_disp
	endif

fz_fastv:
	addi.l  #FZ_RSZ,FZ_REC
	movea.l a1,a5
	lea     fz_fastv_rd(pc),a0
	clr.w   FZ_LEFT
	ifd FZ_COST
	move.l  a1,FZ_COST2
	endif
fz_fastv_rd:
	movem.w 4(a5),d2-d5             ; w0, w1, w2, w3
	ifne FZ_DIAG
	lea     FZ_DW,a1
	movem.w d2-d5,(a1)
	endif
	cmpa.l  (sp),a4                 ; (fz_disp: no head slot left)
	bhs.w   fz_nsl
	swap    d7
	addi.w  #FZU_FASTV,d7           ; (the shape routine's slack and the tests not run)
	btst    #13,d4                  ; behind tilemap 1: as fz_fast_rd
	bne.s   .fr
	st      SS_PRIO(a6)
	subi.w  #LO_UNITS,d7
.fr:	swap    d7
	ifne FZ_MERGE
	tst.b   FZ_MG_ON
	beq.s   .nm
	bsr.w   fz_mg                   ; (merged: it goes on at fz_next itself)
.nm:
	endif
	movea.l (a5),a1
	jmp     (a1)
	endif
	endif

	ifne FZ_SHED
; ---------------------------------------------------------------- FZ_SHED (AUDIT 48)
; Load shedding in the boss fights' overloads: the ring holds the shown set and the one in
; work, ~170-180 columns each in the densest boss frames (with the pair-bullet pool's 64
; columns taken, 137 each) - the set in work runs out and its last records are dropped,
; the same ones every frame of an episode (up to 2 s).  Instead, after a pass that dropped,
; the effects (explosions, sparks, smoke, debris, the bomb's flash, shadows: fz_shtab) are
; shed first - every other one, alternating, at level 1 (each still shown every other
; frame), all of them at level 2 - and the level comes down after FZ_SHCALM passes
; without a drop.  A record is marked sheddable by bit 7 of its first byte (the routine's
; or table's long: the 68000's addresses are 24 bits, nothing compares the long whole
; with BP_STABLE and FZ_RC off).  Shed records count in FZ_SHN, the set marked a slip.
	if BP_STABLE|FZ_RC
	fail    "FZ_SHED wants the records' first byte free (BP_STABLE, FZ_RC off)"
	endif
FZ_SH           equ $10fc30         ; (the idle stack's deep end before the collision index:
FZ_SH_LV        equ FZ_SH           ; AUDIT 45's WATCH) b: the level (0-2)
FZ_SH_C         equ FZ_SH+1         ; b: passes without a drop since
FZ_SH_D         equ FZ_SH+2         ; l: HAL_SPR_DROP at the last pass's begin
FZ_SHN          equ FZ_SH+6         ; l: records shed
FZ_SH_P         equ FZ_SH+10        ; b: the pass's parity
	if FZ_SH+11>$10fc40
	fail    "FZ_SHED's state over the collision index's"
	endif
; after fz_rec: the object's records (from 4(sp) to a1) marked when its type is an effect's.
; Clobbers d0, a3.
fz_shmark:
	move.w  $16(a0),d0
	cmpi.w  #$ff,d0
	bhi.s   .x
	lea     fz_shtab,a3
	tst.b   (a3,d0.w)
	beq.s   .x
	movea.l 4(sp),a3
.m:	cmpa.l  a1,a3
	bhs.s   .x
	bset    #7,(a3)
	lea     FZ_RSZ(a3),a3
	bra.s   .m
.x:	rts
; the effect types (work/catalog/type_handlers.tsv): explosions 09, 33, 60, 6c, 99, 9b;
; sparks 0e, 16, a3; the bomb's flash and big explosion 20; shadows 2f, 34, 88
fz_shtab:
GXI	set     0
	rept    256
	if (GXI=$09)|(GXI=$0e)|(GXI=$16)|(GXI=$20)|(GXI=$2f)|(GXI=$33)|(GXI=$34)|(GXI=$60)|(GXI=$6c)|(GXI=$88)|(GXI=$99)|(GXI=$9b)|(GXI=$a3)
	dc.b    1
	else
	dc.b    0
	endif
GXI	set     GXI+1
	endr
	even
	endif

	ifne FZ_MERGE
; ---------------------------------------------------------------- FZ_MERGE (AUDIT 48)
; Column merging: a piece (a fast record's, fz_fastv, or any record's, fz_disp:
; unzoomed, not a pool record, its lookup run not wrapping) right after another in the
; set's column order (the set's SS_HNEXT where the last one's
; shape routine left it: nothing allocated between them), at the same x and width, in
; the same tilemap-1 class, its top a whole number of tiles at or below the last one's
; bottom (a gap of at most FZ_MGGAP rows) and the two within 32 rows: its tiles go into
; the last one's columns (the gap transparent), the last one's head taller - no columns
; of its own.  The picture is the same: the two are consecutive in the draw order and do
; not overlap, and a Neo column's tiles carry their own palette and flips.  The boss
; fights' sets are ~15% smaller (work/play/fh/mergecen.lua), their drops the double-
; buffered sets over the ring's 338 columns.  On while the previous set took FZ_MGT
; columns or more (fz_begin: FZ_MG_ON); the state at FZ_MG (the idle stack's deep end,
; after the collision index: AUDIT 45's WATCH found no write to 0x10fc30..0x10fdaf).
FZ_MG           equ $10fd9c
FZ_MG_HN        equ FZ_MG           ; w: SS_HNEXT after the last record's shape (its column 0)
FZ_MG_XW        equ FZ_MG+2         ; w: its w1 & $fff (x, width)
FZ_MG_CL        equ FZ_MG+4         ; w: its w2 & $2000 (in front of tilemap 1)
FZ_MG_Y         equ FZ_MG+6         ; w: its column's top (y)
FZ_MG_R         equ FZ_MG+8         ; w: the column's rows
FZ_MG_HV        equ FZ_MG+10        ; l: its head's SCB3 value in the set's head table
FZ_MG_ON        equ FZ_MG+14        ; b: merging on for this pass
FZ_MG_T         equ FZ_MG+16        ; w: (a merge) the column's rows after it
FZ_MG_G         equ FZ_MG+18        ; w: the gap's rows
	if FZ_MG+20>$10fdb0
	fail    "FZ_MERGE's state past the checked RAM"
	endif
	ifne FZ_MGDIAG
FZ_MGN          equ $d00f38         ; l: (OVR_DIAG's RAM: not together) merges
FZ_MGC          equ $d00f3c         ; l: columns saved
	endif
; (a subroutine of fz_fastv's and fz_disp's dispatch: d2-d5 = w0-w3, a2 the lookup RAM, a3
; the VRAM data port, a4 the next head slot, a6 the set; d7 credit | $7fff.  Not merged:
; this piece the last one, rts (d2-d5, a0, a2-a6 kept); merged: on at fz_next.)
fz_mg:
	swap    d7                      ; (these tests' cost: the shape's own charge refills)
	subi.w  #FZU_MGC,d7
	swap    d7
	move.w  d2,d0                   ; unzoomed, not a pool record: else no last
	or.w    d3,d0
	andi.w  #$f000,d0
	bne.w   .inv
	tst.b   d4
	bmi.w   .inv
	move.w  d2,d6                   ; d6 = rows, d1 = columns of this shape
	rol.w   #7,d6
	andi.w  #7,d6
	addq.w  #1,d6
	move.w  d3,d1
	rol.w   #7,d1
	andi.w  #7,d1
	addq.w  #1,d1
	move.w  d6,d0                   ; its lookup run must not wrap (as the shape's own
	mulu.w  d1,d0                   ; test: map + rows x columns <= $4000)
	neg.w   d0
	addi.w  #$4000,d0
	move.w  d5,-(sp)
	andi.w  #$3fff,(sp)
	cmp.w   (sp)+,d0
	bcs.w   .inv
	move.w  SS_HNEXT(a6),d0         ; consecutive?
	cmp.w   FZ_MG_HN,d0
	bne.w   .new
	move.w  d3,d0                   ; the same x and width
	andi.w  #$fff,d0
	cmp.w   FZ_MG_XW,d0
	bne.w   .new
	move.w  d4,d0                   ; the same class
	andi.w  #$2000,d0
	cmp.w   FZ_MG_CL,d0
	bne.w   .new
	move.w  d2,d0                   ; the top: tile-aligned, at or below the last bottom
	andi.w  #$1ff,d0
	sub.w   FZ_MG_Y,d0
	bcs.w   .new
	moveq   #15,d1
	and.w   d0,d1
	bne.w   .new
	lsr.w   #4,d0                   ; d0 = its first row in the column
	move.w  d0,d1
	sub.w   FZ_MG_R,d1              ; d1 = the gap's rows
	bcs.w   .new
	cmpi.w  #FZ_MGGAP,d1
	bhi.w   .new
	add.w   d6,d0                   ; the column's rows after it
	cmpi.w  #32,d0
	bhi.w   .new
	; merge: charge first (FZU_MG0 + 3 units a tile row of each column; the refill may
	; leave: the record is then done again, nothing written)
	addq.l  #4,sp                   ; (no return: on at fz_next)
	btst    #13,d4                  ; behind tilemap 1: as spr_lo (the set flagged)
	bne.s   .fr
	st      SS_PRIO(a6)
	move.w  d1,-(sp)
	swap    d7
	subi.w  #LO_UNITS,d7
	swap    d7
	move.w  (sp)+,d1
.fr:	move.w  d0,FZ_MG_T
	move.w  d1,FZ_MG_G
	add.w   d6,d1                   ; tile rows a column
	move.w  d3,d0
	rol.w   #7,d0
	andi.w  #7,d0
	addq.w  #1,d0
	mulu.w  d1,d0
	move.w  d0,d1
	add.w   d1,d1
	add.w   d1,d0
	addi.w  #FZU_MG0,d0             ; d0 = the charge
	swap    d7
	sub.w   d0,d7
	bpl.s   .c
	jsr     spr_fast_refill         ; (d0 the charge, d7 swapped: returns only with credit)
.c:	swap    d7
	movem.l d2-d5/a0/a5,-(sp)
	move.w  d3,d5                   ; d5 = the columns
	rol.w   #7,d5
	andi.l  #7,d5
	addq.w  #1,d5
	ifne FZ_MGDIAG
	addq.l  #1,FZ_MGN
	add.l   d5,FZ_MGC
	endif
	move.w  d4,d0                   ; the attribute: palette, the flips (w2 bit 14 x,
	andi.w  #$1f00,d0               ; 15 y: Neo bit 0 x, 1 y)
	addi.w  #NPAL_SPR<<8,d0
	btst    #14,d4
	beq.s   .f1
	addq.w  #1,d0
.f1:	btst    #15,d4
	beq.s   .f2
	addq.w  #2,d0
.f2:	movea.w d0,a5                   ; a5 = the attribute
	move.w  14(sp),d1               ; the lookup run (w3 as it came): a1 the first tile
	andi.w  #$3fff,d1               ; to write of column 0
	andi.w  #$3fff,d1
	add.w   d1,d1
	lea     (a2,d1.w),a1
	move.w  d5,d3                   ; d3 = the row step in the run (2 x columns)
	add.w   d3,d3
	btst    #15,d4                  ; y flip: from the last row, upwards
	beq.s   .f3
	move.w  d6,d0
	subq.w  #1,d0
	mulu.w  d3,d0
	adda.w  d0,a1
	neg.w   d3
.f3:	moveq   #2,d0                   ; the column step in the run: x flip from the last
	btst    #14,d4                  ; column, leftwards
	beq.s   .f4
	move.w  d5,d0
	subq.w  #1,d0
	add.w   d0,d0
	adda.w  d0,a1
	moveq   #-2,d0
.f4:	move.w  d0,-(sp)                ; 2(sp): the column step
	move.w  FZ_MG_G,-(sp)           ; (sp): the gap's rows
	move.w  FZ_MG_HN,d4             ; d4 = column 0's SCB1 + 2 x the column's rows so far
	lsl.w   #6,d4
	add.w   FZ_MG_R,d4
	add.w   FZ_MG_R,d4
	subq.w  #1,d5                   ; (dbra)
.col:	move.w  d4,-2(a3)
	move.w  (sp),d0                 ; the gap: transparent rows
	bra.s   .g1
.g:	move.w  #BLANK_TILE,(a3)
	move.w  #0,(a3)
.g1:	dbra    d0,.g
	movea.l a1,a0                   ; this column's rows of the shape
	move.w  d6,d0
	subq.w  #1,d0
.r:	move.w  (a0),d1
	and.w   d7,d1
	move.w  d1,(a3)
	adda.w  d3,a0                   ; (between the two data writes: >= 12 cycles)
	move.w  a5,(a3)
	dbra    d0,.r
	addi.w  #64,d4                  ; the next column
	adda.w  2(sp),a1
	dbra    d5,.col
	addq.l  #4,sp
	movea.l FZ_MG_HV,a0             ; the head: its rows
	move.w  (a0),d0
	andi.w  #$ffc0,d0
	or.w    FZ_MG_T,d0
	move.w  d0,(a0)
	move.w  FZ_MG_T,FZ_MG_R
	movem.l (sp)+,d2-d5/a0/a5
	jmp     fz_next
	; not merged: this record the last one (its shape allocates its columns below)
.new:	move.w  d3,d1                   ; (d1: its columns, from w1 again)
	rol.w   #7,d1
	andi.w  #7,d1
	addq.w  #1,d1
	move.w  SS_HNEXT(a6),d0
	sub.w   d1,d0
	move.w  d0,FZ_MG_HN
	move.w  d3,d0
	andi.w  #$fff,d0
	move.w  d0,FZ_MG_XW
	move.w  d4,d0
	andi.w  #$2000,d0
	move.w  d0,FZ_MG_CL
	move.w  d2,d0
	andi.w  #$1ff,d0
	move.w  d0,FZ_MG_Y
	move.w  d6,FZ_MG_R
	lea     SS_HVAL-SS_HADR(a4),a1
	move.l  a1,FZ_MG_HV
	rts
.inv:	move.w  #$ffff,FZ_MG_HN
	rts
	endif

	ifne FZ_SPLANCH
; hal_spr_go .spl (FUSED): where a split set's lower run starts (spr_split_anch from the
; records): d1 = HAL_SPR_BEGG in; out the lower of that and SPR_PB + the columns the records
; left would take (unclipped: an upper bound) + 4, that column's SCB3 cleared (the run hangs
; from it).  Up to SPLN records looked at (more: BEGG as it was).  Until 2026-10-18 the lower
; run began at BEGG - below the previous set's end - and the ring below it, down to SPR_PB,
; was stranded: the next set, placed in the hole above the lower run, ran out of columns
; with ~110 free below (every drop of a boss fight, work/play/fh/dropwhy2.lua).  Keeps d0,
; a2, a4-a6; a3 = the VRAM data port.  Clobbers d1-d6, a1.
fz_split_anch:
	swap    d7
	subi.w  #(SPLN*60+15)/16,d7
	swap    d7
	movea.l FZ_REC,a1               ; (the record in work: fz_ntab moved on)
	lea     -FZ_RSZ(a1),a1
	move.l  FZ_RECE,d3
	sub.l   a1,d3
	lsr.l   #4,d3                   ; the records left
	subq.w  #1,d3
	bmi.s   .x
	cmpi.w  #SPLN-1,d3
	bls.s   .n
	moveq   #SPLN-1,d3
.n:	moveq   #4,d2
	move.w  #SPLN,d4                ; (pieces looked at, at most)
.r:
	ifne FZ_FAST
	ifne FZ_FINAL
	cmpi.b  #$fe,13(a1)             ; (a fast record, $ff or $fe: w1's high byte at +15)
	blo.s   .rg
	else
	cmpi.b  #$ff,13(a1)             ; (a fast record: w1's high byte at +15)
	bne.s   .rg
	endif
	subq.w  #1,d4
	bmi.s   .x
	moveq   #$e,d5
	and.b   15(a1),d5
	lsr.w   #1,d5
	addq.w  #1,d5
	add.w   d5,d2
	bra.s   .rn
.rg:
	endif
	movea.l (a1),a2
	moveq   #0,d1
	move.b  15(a1),d1
.t:	subq.w  #1,d4
	bmi.s   .x
	ifne FZ_PD
	btst    #FZD_FD,(a2)
	beq.s   .tr
	moveq   #$e,d5
	and.b   11(a2),d5
	bra.s   .tz
.tr:
	endif
	movea.l (a2),a6
	moveq   #$e,d5
	and.b   1(a6),d5
.tz:	lsr.w   #1,d5
	addq.w  #1,d5
	add.w   d5,d2
	lea     14(a2),a2
	dbra    d1,.t
.rn:	lea     FZ_RSZ(a1),a1
	dbra    d3,.r
	addi.w  #SPR_PB,d2
	move.w  HAL_SPR_BEGG,d1
	cmp.w   d1,d2
	bhs.s   .y
	move.w  d2,d1
	addi.w  #SCB3,d2
	move.w  d2,-2(a3)
	move.w  #0,(a3)
	bra.s   .y
.x:	move.w  HAL_SPR_BEGG,d1         ; (nothing done: the caller's d1)
.y:	lea     G_SPRLUT,a2             ; (the pass's registers again)
	move.w  HAL_SPR_W,d0
	movea.l HAL_SPR_WPTR,a6
	rts
	endif

; the entry is the HUD's (fx_hud_take: Z set, on the fix layer: not a sprite)
fz_hud:
	swap    d7                      ; (charged: FZU_HUDT)
	subi.w  #FZU_HUDT,d7
	bpl.s   .k
	moveq   #FZU_HUDT,d0
	jsr     hal_spr_refill
	ifne FX_HOV
	bmi.w   .nt
	else
	bmi.s   .nt
	endif
.k:	swap    d7
	lea     FZ_WORDS,a1
	movem.w d2-d5,(a1)
	addq.l  #8,a1
	movem.l d7/a0/a4,-(sp)
	jsr     fx_hud_take
	movem.l (sp)+,d7/a0/a4
	ifne FX_HOV
	sne     d0                      ; (FX_HOV) fx_hud_ov's slots charged after the fact
	tst.b   FX_HOVRAN               ; (the credit may go negative: the next charge's
	beq.s   .nov                    ; refill measures the time left)
	sf      FX_HOVRAN
	swap    d7
	subi.w  #FZU_HOV,d7
	swap    d7
.nov:	tst.b   d0
	endif
	bne.w   fz_disp
	ifne FZ_PD&FZ_HC
	lea     FZ_WORDS+8,a1           ; taken: the slot's key is this record's, not shown
	jsr     fx_hud_slot             ; until fx_hud_draw says so
	move.w  d1,d6
	movea.l FZ_REC,a1
	move.l  -FZ_RSZ(a1),d0          ; the record's table (fz_ntab moved on)
	lsl.w   #4,d1
	lea     FZ_HKEY,a1
	adda.w  d1,a1
	move.l  FZ_Y,(a1)+
	move.l  FZ_W2,(a1)+
	move.l  d0,(a1)+
	move.w  FZ_LUTGEN,(a1)
	move.w  FX_HSAME,d1             ; taken unchanged: shown with these entries, the take
	btst    d6,d1                   ; verified it (else the key store's bclr kept every
	move.w  FZ_HCOK,d0              ; slot the game's refresh rewrote alike out of the
	beq.s   .hc                     ; cache for good: 77 overruns per 20k frames, 2026-10-18)
	bset    d6,d0
	bra.s   .hs
.hc:	bclr    d6,d0
.hs:	move.w  d0,FZ_HCOK
	endif
	bra.w   fz_next
.nt:	swap    d7                      ; (no time: this piece again, as spr_go_late)
	lea     -14(a5),a5
	addq.w  #1,FZ_LEFT
	jmp     spr_go_stop

; The piece a5 of the record (FZ_Y/FZ_X its object's position, FZ_W2 the table's w2
; byte, FZ_ZOOM): on screen (the builder's test, then the Neo screen's with the wrap)
; -> its four words in d2-d5 -> fz_disp; else fz_next.  \1 zoom from the object, \2
; colour from the object, \3 flips from the piece, \4 pass 1 (the HUD's strips).
; Clobbers d0, d1, d6, a1.
FZEM	macro
fz_em_\1\2\3\4:
	move.w  FZ_Y,d2                 ; y
	add.w   4(a5),d2
	cmpi.w  #$fee0,d2
	bhs.s   .yv
	cmpi.w  #$e0,d2
	bhs.w   .n1
.yv:	move.w  FZ_X,d3                 ; x
	add.w   6(a5),d3
	cmpi.w  #$ff40,d3
	bhs.s   .xv
	cmpi.w  #$140,d3
	bhs.w   .n1
.xv:	movea.l (a5),a1                 ; the piece's graphic
	add.w   FZ_SY,d2                ; w0 = y + scroll | zoomy << 12 | (a1)+0 << 8
	andi.w  #$1ff,d2
	cmpi.w  #224,d2
	blo.s   .vy
	moveq   #$e,d6
	and.b   (a1),d6
	lsl.w   #3,d6
	add.w   d2,d6
	cmpi.w  #512-16,d6
	bls.w   .n2
.vy:
	ifne \1
	or.w    FZ_ZOOM,d2
	else
	move.b  $a(a5),d6
	beq.s   .zy
	ror.w   #4,d6
	andi.w  #$f000,d6
	or.w    d6,d2
.zy:
	endif
	move.w  (a1),d6
	andi.w  #$ff00,d6
	or.w    d6,d2
	add.w   FZ_SX,d3                ; w1 = x + scroll | zoomx << 12 | (a1)+1 << 8
	andi.w  #$1ff,d3
	cmpi.w  #320,d3
	blo.s   .vx
	moveq   #$e,d6
	and.b   1(a1),d6
	lsl.w   #3,d6
	add.w   d3,d6
	cmpi.w  #512-16,d6
	bls.w   .n2
.vx:
	ifne \1
	or.w    FZ_ZOOM,d3
	else
	move.b  $b(a5),d6
	beq.s   .zx
	ror.w   #4,d6
	andi.w  #$f000,d6
	or.w    d6,d3
.zx:
	endif
	move.w  (a1),d6
	lsl.w   #8,d6
	or.w    d6,d3
	move.w  FZ_W2,d4                ; w2 = colour | bit 5 | flips << 8 (| $1000)
	ifeq \2
	move.b  $c(a5),d6
	andi.b  #$f,d6
	or.b    d6,d4
	endif
	ifne \3
	move.b  8(a5),d6                ; bit 0 -> 7
	ror.b   #1,d6
	andi.b  #$80,d6
	or.b    d6,d4
	move.b  9(a5),d6                ; bits 1-0 -> 7-6
	ror.b   #2,d6
	andi.b  #$c0,d6
	or.b    d6,d4
	endif
	lsl.w   #8,d4
	ifne \4
	ori.w   #$1000,d4
	endif
	move.w  2(a1),d5                ; w3 = map (| $2000)
	ifne \4
	ori.w   #$2000,d5
	cmpi.w  #$24ec,d5               ; the HUD's, the game-over texts?
	bls.s   .t
	move.w  d5,d6
	andi.w  #$3fc0,d6
	cmpi.w  #$3fc0,d6
	bne.w   fz_disp
	bra.s   .h
.t:	cmpi.w  #$24cf,d5
	blo.w   fz_disp
	beq.s   .h
	cmpi.w  #$24d7,d5
	beq.s   .h
	cmpi.w  #$24dd,d5
	beq.s   .h
	cmpi.w  #$24e2,d5               ; (the digits, "INSERT COINS!")
	blo.w   fz_disp
.h:	tst.b   FX_HOK
	beq.w   fz_disp
	jmp     fz_hud
	else
	jmp     fz_disp
	endif
.n1:
.n2:	jmp     fz_next
	endm

	FZEM    0,0,0,0
	FZEM    0,0,0,1
	FZEM    0,0,1,0
	FZEM    0,0,1,1
	FZEM    0,1,0,0
	FZEM    0,1,0,1
	FZEM    0,1,1,0
	FZEM    0,1,1,1
	FZEM    1,0,0,0
	FZEM    1,0,0,1
	FZEM    1,0,1,0
	FZEM    1,0,1,1
	FZEM    1,1,0,0
	FZEM    1,1,0,1
	FZEM    1,1,1,0
	FZEM    1,1,1,1
fz_emt:
	dc.l    fz_em_0000,fz_em_0001,fz_em_0010,fz_em_0011
	dc.l    fz_em_0100,fz_em_0101,fz_em_0110,fz_em_0111
	dc.l    fz_em_1000,fz_em_1001,fz_em_1010,fz_em_1011
	dc.l    fz_em_1100,fz_em_1101,fz_em_1110,fz_em_1111

	ifne FZ_PD
; ---------------------------------------------------------------- piece descriptors
; (FZ_PD, 2026-10-18) tools/aerofgt2neo.py rewrites every piece entry of the catalogue's
; tables (work/catalog/sprites/objects.json) in place, in DIRECT FUSED builds: the game
; itself reads only an entry's first word (the end-of-animation sentinels $ffff/$fffe and
; a sign test) and the link after $fffe; the rest was the builder's, which these builds
; replace.  A descriptor keeps the first word positive and no sentinel: +0 w the pointer's
; high word | $0100 (bit 0 of the first byte: the flag fz_rec and fz_anch test; FZ_TPL
; builds: $4000 | the template's index, the flags bits 6 and 5 of the first byte - FZD_FD,
; FZD_FH - and the pointer's byte gone; fz_rec takes a template only with FZD_FD set, a
; raw table's word being the pointer's high word, 0-7), +2 w the map (bit 15: in the
; HUD's lookup range, the \4 tests of FZEM precomputed), +4 w y, +6 w x (as before),
; +8 w (header byte 0 | the piece's zoomy << 4) << 8 | header byte 0, +10 w the same of
; byte 1 and zoomx, +12 b the piece's colour nibble | its flips as FZEM composes them
; (byte 8 bit 0 -> 7, byte 9 bits 1-0 -> 7-6), +13 b 0.  The same words as FZEM's, with
; no header read, no per-piece zoom/colour/flip composition, no map range tests.
FZPD	macro
	ifne \5
fz_pdh_\1\2\3:
	ifne FZ_HC
	; a HUD piece (pass 1; bit 1 of the descriptor's first byte, its slot at +13): with
	; the fix layer free, the slot not taken this walk, shown as last taken and holding
	; this record's key, fx_hud_take would find it unchanged: marked so, the piece skipped
	btst    #FZD_FH,(a5)
	beq.w   .p
	swap    d7                      ; (charged before the way, hit or not: a stop lands
	subi.w  #FZU_HHIT,d7            ; before the work; the take's FZU_HUDT comes on top)
	bpl.s   .hc0
	moveq   #FZU_HHIT,d0
	jsr     hal_spr_refill
	bmi.w   .hnt
.hc0:	swap    d7
	ifne FZ_DIAG
	addq.w  #1,$d0fdf6              ; (HC: entries)
	endif
	tst.b   FX_HOK
	ifne FZ_DIAG&FZ_HCX
	beq.w   .e1
	else
	beq.w   .p
	endif
	moveq   #0,d6
	move.b  13(a5),d6               ; the slot
	move.w  FX_HSEEN,d0
	btst    d6,d0
	ifne FZ_DIAG&FZ_HCX
	bne.w   .e2
	else
	bne.w   .p
	endif
	ifne FX_HOV
	move.w  FX_HSUS,d0              ; (FX_HOV) a suspect or a yielder: fx_hud_take decides
	or.w    FX_HYIELD,d0
	btst    d6,d0
	bne.w   .p
	endif
	move.w  FZ_HCOK,d0
	btst    d6,d0
	ifne FZ_DIAG&FZ_HCX
	beq.w   .e3
	else
	beq.w   .p
	endif
	move.w  d6,d0                   ; and its strip's cells (fx_hud_take's own test: the
	lsl.w   #5,d0                   ; shown bit must not outlive the strip - on the MiSTer
	move.w  d0,d1                   ; the sprite RAM persists across sessions while the
	add.w   d0,d0                   ; game clears the strips' RAM: no HUD until a death
	add.w   d1,d0                   ; changed the keys, 2026-10-18)
	lea     FX_HSHD,a1
	tst.w   FXH_COL+4(a1,d0.w)
	ifne FZ_DIAG&FZ_HCX
	beq.w   .e4
	else
	beq.w   .p
	endif
	ifne FZ_DIAG
	addq.w  #1,$d0fdf8              ; (HC: shown)
	endif
	movea.l FZ_REC,a1
	move.l  -FZ_RSZ(a1),d4          ; the record's key: table, y, x, w2, zoom, the
	move.l  FZ_Y,d2                 ; lookup RAM's generation
	move.l  FZ_W2,d3
	move.w  FZ_LUTGEN,d5
	move.w  d6,d1
	lsl.w   #4,d1
	lea     FZ_HKEY,a1
	adda.w  d1,a1
	cmp.l   (a1),d2
	ifne FZ_DIAG&FZ_HCX
	bne.w   .e5
	else
	bne.w   .p
	endif
	cmp.l   4(a1),d3
	ifne FZ_DIAG&FZ_HCX
	bne.w   .e6
	else
	bne.w   .p
	endif
	cmp.l   8(a1),d4
	ifne FZ_DIAG&FZ_HCX
	bne.w   .e7
	else
	bne.w   .p
	endif
	cmp.w   12(a1),d5               ; the lookup generation
	beq.s   .hk
	; moved (the game's HUD refresh, the loader): the strip's entries against the
	; shadow's copy, fx_hud_take's own compare (~250 cycles): the same -> the key's
	; generation renewed, a hit.  (A refresh rewrites a player's three strips alike but
	; for the one that changed; a take of each, ~2,000 cycles, ran the tails of refresh
	; frames 1-3 lines past their deadline: 22 of 24 overruns per 20k frames, 2026-10-18)
	swap    d7
	subi.w  #FZU_HLUT,d7
	bpl.s   .hl
	moveq   #FZU_HLUT,d0
	jsr     hal_spr_refill
	bmi.w   .hnt
.hl:	swap    d7
	move.l  a3,-(sp)
	move.w  2(a5),d0                ; the live entries (the index as the dispatch makes
	andi.w  #$3fff,d0               ; w3: bit 13 set - the descriptor's map lacks it)
	ori.w   #$2000,d0
	add.w   d0,d0
	lea     G_SPRLUT,a3
	adda.w  d0,a3
	move.w  d6,d0                   ; the shadow's copy (slot x 96 + FXH_LUT)
	lsl.w   #5,d0
	move.w  d0,d1
	add.w   d0,d0
	add.w   d1,d0
	lea     FX_HSHD+FXH_LUT,a1
	adda.w  d0,a1
	move.b  9(a5),d0                ; tiles - 1 (the header's ysize)
	lsr.b   #1,d0
	andi.w  #7,d0
.lc:	cmpm.w  (a3)+,(a1)+
	dbne    d0,.lc
	movea.l (sp)+,a3
	ifne FZ_DIAG&FZ_HCX
	bne.w   .e8
	else
	bne.w   .p
	endif
	move.w  d6,d0                   ; the same: the key's generation is this one
	lsl.w   #4,d0
	lea     FZ_HKEY,a1
	move.w  d5,12(a1,d0.w)
	ifne FZ_DIAG
	addq.w  #1,$d0fdfc              ; (HC: renewed)
	endif
.hk:
	ifne FZ_DIAG
	addq.w  #1,$d0fdfa              ; (HC: hits)
	endif
	move.w  FX_HSEEN,d0             ; taken unchanged
	bset    d6,d0
	move.w  d0,FX_HSEEN
	move.w  FX_HSAME,d0
	bset    d6,d0
	move.w  d0,FX_HSAME
	jmp     fz_next
.hnt:	swap    d7                      ; (no time: this piece again, as spr_go_late)
	lea     -14(a5),a5
	addq.w  #1,FZ_LEFT
	jmp     spr_go_stop
	ifne FZ_DIAG&FZ_HCX

.e1:	addq.w  #1,FZ_HX+0
	bra.w   .p
.e2:	addq.w  #1,FZ_HX+2
	bra.w   .p
.e3:	addq.w  #1,FZ_HX+4
	bra.w   .p
.e4:	addq.w  #1,FZ_HX+6
	bra.w   .p
.e5:	addq.w  #1,FZ_HX+8
	bra.w   .p
.e6:	addq.w  #1,FZ_HX+10
	bra.w   .p
.e7:	addq.w  #1,FZ_HX+12
	bra.w   .p
.e8:	addq.w  #1,FZ_HX+14
	bra.w   .p
	endif
.p:
	endif
	else
fz_pd_\1\2\3\4:
	endif
	move.w  FZ_Y,d2                 ; y
	add.w   4(a5),d2
	cmpi.w  #$fee0,d2
	bhs.s   .yv
	cmpi.w  #$e0,d2
	bhs.w   .n1
.yv:	move.w  FZ_X,d3                 ; x
	add.w   6(a5),d3
	cmpi.w  #$ff40,d3
	bhs.s   .xv
	cmpi.w  #$140,d3
	bhs.w   .n1
.xv:	add.w   FZ_SY,d2                ; w0 = y + scroll | zoomy << 12 | header 0 << 8
	andi.w  #$1ff,d2
	cmpi.w  #224,d2
	blo.s   .vy
	moveq   #$e,d6
	and.b   9(a5),d6
	lsl.w   #3,d6
	add.w   d2,d6
	cmpi.w  #512-16,d6
	bls.w   .n2
.vy:	move.w  8(a5),d6
	ifne \1
	lsl.w   #8,d6                   ; (the object's zoom: the header byte alone)
	or.w    d6,d2
	or.w    FZ_ZOOM,d2
	else
	andi.w  #$ff00,d6
	or.w    d6,d2
	endif
	add.w   FZ_SX,d3                ; w1 = x + scroll | zoomx << 12 | header 1 << 8
	andi.w  #$1ff,d3
	cmpi.w  #320,d3
	blo.s   .vx
	moveq   #$e,d6
	and.b   11(a5),d6
	lsl.w   #3,d6
	add.w   d3,d6
	cmpi.w  #512-16,d6
	bls.w   .n2
.vx:	move.w  10(a5),d6
	ifne \1
	lsl.w   #8,d6
	or.w    d6,d3
	or.w    FZ_ZOOM,d3
	else
	andi.w  #$ff00,d6
	or.w    d6,d3
	endif
	move.w  FZ_W2,d4                ; w2 = colour | bit 5 | flips << 8 (| $1000)
	if (\2=0)|(\3=1)
	move.b  12(a5),d6
	ifne \2
	andi.b  #$c0,d6                 ; (the colour is the object's: the flips only)
	endif
	ifeq \3
	andi.b  #$0f,d6                 ; (the flips are the object's: the colour only)
	endif
	or.b    d6,d4
	endif
	lsl.w   #8,d4
	ifne \4
	ori.w   #$1000,d4
	endif
	move.w  2(a5),d5                ; w3 = map (| $2000); bit 15: the HUD's range
	ifne \4
	bmi.s   .h
	ori.w   #$2000,d5
	jmp     fz_disp
.h:	andi.w  #$3fff,d5
	ori.w   #$2000,d5
	tst.b   FX_HOK
	beq.w   fz_disp
	jmp     fz_hud
	else
	andi.w  #$3fff,d5
	jmp     fz_disp
	endif
.n1:
.n2:	jmp     fz_next
	endm

	FZPD    0,0,0,0,0
	FZPD    0,0,0,1,0
	FZPD    0,0,1,0,0
	FZPD    0,0,1,1,0
	FZPD    0,1,0,0,0
	FZPD    0,1,0,1,0
	FZPD    0,1,1,0,0
	FZPD    0,1,1,1,0
	FZPD    1,0,0,0,0
	FZPD    1,0,0,1,0
	FZPD    1,0,1,0,0
	FZPD    1,0,1,1,0
	FZPD    1,1,0,0,0
	FZPD    1,1,0,1,0
	FZPD    1,1,1,0,0
	FZPD    1,1,1,1,0
	FZPD    0,0,0,1,1
	FZPD    0,0,1,1,1
	FZPD    0,1,0,1,1
	FZPD    0,1,1,1,1
	FZPD    1,0,0,1,1
	FZPD    1,0,1,1,1
	FZPD    1,1,0,1,1
	FZPD    1,1,1,1,1
fz_pdt:
	dc.l    fz_pd_0000,fz_pd_0001,fz_pd_0010,fz_pd_0011
	dc.l    fz_pd_0100,fz_pd_0101,fz_pd_0110,fz_pd_0111
	dc.l    fz_pd_1000,fz_pd_1001,fz_pd_1010,fz_pd_1011
	dc.l    fz_pd_1100,fz_pd_1101,fz_pd_1110,fz_pd_1111
fz_pdht:                                ; (HUD tables: pass 1 piece by piece with the cache)
	dc.l    fz_pd_0000,fz_pdh_000,fz_pd_0010,fz_pdh_001
	dc.l    fz_pd_0100,fz_pdh_010,fz_pd_0110,fz_pdh_011
	dc.l    fz_pd_1000,fz_pdh_100,fz_pd_1010,fz_pdh_101
	dc.l    fz_pd_1100,fz_pdh_110,fz_pd_1110,fz_pdh_111
; the game's lookup RAM loader (0x2bbca: movea.l #lookup,a2 -> jsr here): the HUD cache's
; keys are stale once the tiles change
fz_lutld:
	addq.w  #1,FZ_LUTGEN
	movea.l #G_SPRLUT,a2
	rts
; the game's HUD refresh (0x192be: jsr $2a63e, then $2a676 and $2a6c4 - the bombs, lives
; and score entries written straight into the lookup RAM when the player's HUD-dirty
; bit is set, not through the loader): the keys are stale too.  Without this the MiSTer
; drew the 1P strips blank at a game's start and kept them (the refresh landed after
; the first take there; MAME's order differed), 2026-10-18.
fz_hudrf:
	addq.w  #1,FZ_LUTGEN
	jmp     $2a63e
	endif

	ifeq FUSED-2
; ================================================================ the game-time pass
; (AUDIT.md 24, 2026-10-18): 0x2bee0 -> fz_gt: the whole conversion at the builder's
; point, in the game's round, instead of records for a slot pass.  The ring's freed sets
; are reclaimed, a free set begun, the objects walked as the builder would (pass 1, pass
; 2, the group in x order, pass 3; per object its tables B, C, A), each piece clipped,
; composed and dispatched into its shape routine, then the HUD pass, then the set is
; complete: shown from the slot after the next - one frame before the arcade shows it
; (its sprite RAM is double buffered; three sets in the ring hold just this) - and the
; game's scroll FIFO reads a stage fresher to match (tools/aerofgt2neo.py).  No records,
; no budget: a round whose logic and conversion overrun the vblank leaves the set shown,
; as the arcade's handler copies no new list then; the set is shown when it is done.
; The HAL slot (the LSPC timer's interrupt) can preempt the pass anywhere, so every VRAM
; sequence runs with interrupts masked: a piece's columns from its dispatch to fz_next,
; the reclaim, the begin, the HUD pass; the modulo is set again for each.  hal/dx.s's
; conventions: d2/d3 kept, a6 left as an empty list's end; back to 0x2bfaa.
fz_gt:
	movem.l d2-d3,-(sp)
	addq.l  #1,FZ_GTN
	move.w  sr,FZ_SR
	tst.b   FZ_GTWAIT               ; a pass left waiting at the tail and the round went
	beq.s   .fresh                  ; on (no slot between): its set complete as it is
	addq.l  #1,FZ_WSTALE
	sf      FZ_GTWAIT
	move.w  HAL_SPR_W,d0
	jsr     hal_spr_set
	movea.l FZ_WA4,a4
	bsr.w   fz_gt_fin
.fresh:
	ori.w   #$0700,sr
	jsr     hal_spr_reclaim         ; the ring's freed sets
	move.w  FZ_SR,sr
	lea     HAL_SPR_ST,a0           ; a free set (neither shown, complete nor in the
	lea     HAL_SPR_INQ,a1          ; ring): none - the arcade's list stays too
	moveq   #0,d0
.f:	move.b  (a0,d0.w),d1
	or.b    (a1,d0.w),d1
	beq.s   .got
	addq.w  #1,d0
	cmpi.w  #NSPRSETS,d0
	blo.s   .f
	addq.l  #1,FZ_GTSKIP
	bra.w   .out
.got:	move.w  d0,FZ_GTSET
	move.b  #2,(a0,d0.w)            ; converting: the flip leaves it alone
	move.w  d0,HAL_SPR_W            ; (hal_spr_go's drop, split, restart and zoom paths
	lea     HAL_SPR_MIX,a0          ; index the sets by it; hal/sched.s does not hold on it)
	sf      (a0,d0.w)
	lea     HAL_SPR_RDY,a0          ; shown FZ_SHOW slots after this round's (which has
	move.w  HAL_FRAMES+2,d1         ; not begun yet; if it has - the round overran it -
	addq.w  #1+FZ_SHOW,d1           ; one later)
	add.w   d0,d0
	move.w  d1,(a0,d0.w)
	lsr.w   #1,d0
	tst.b   HAL_SCH_BUSY            ; (hal/sched.s: the slot began with the game busy:
	beq.s   .nl                     ; this round's)
	addq.l  #1,FZ_GTLATE
.nl:	ori.w   #$0700,sr
	jsr     hal_spr_begin           ; where it starts, the ring (a6 = its state)
	bsr.w   fz_gt_begin
	move.w  FZ_SR,sr
	lea     G_SPRLUT,a2             ; the pass's registers (hal_spr_go's)
	lea     REG_VRAMRW,a3
	lea     SS_HADR(a6),a4
	move.l  #$7fff,d7
	move.l  a6,d0
	addi.l  #SS_HADR+2*SS_MAXHEAD,d0
	move.l  d0,FZ_HEND
	bsr.w   fz_gt_start
	bra.w   fz_gt_scan
.out:
fz_gt_out:
	tst.b   FZ_GTCTX
	bne.s   .slot
	movea.l #G_DX_LIST,a6           ; (as hal/dx.s leaves it: an empty list)
	move.w  #$c000,(a6)+
	movem.l (sp)+,d2-d3
	jmp     $2bfaa
.slot:	sf      FZ_GTCTX                ; (resumed by hal_spr_work: back to it)
	rts

; hal_spr_go's .drop (no columns down to the tail) while a complete set waits for its
; flip, which frees the oldest: the pass stops here, the piece to be done again, and the
; slot's commit tail goes on with it (fz_gt_resume) over the objects as they still are
; (the game idles until the slot).  Registers as the pass's.
fz_gt_wait:
	addq.l  #1,FZ_WAITN
	lea     -14(a5),a5              ; this piece again
	addq.w  #1,FZ_LEFT
	move.l  a4,FZ_WA4
	move.l  a5,FZ_WA5
	move.l  a0,FZ_RTN
	st      FZ_GTWAIT
	bra.w   fz_gt_out

; hal_spr_work, in the commit's tail (the flip done): the waiting pass on, in the
; slot's context (interrupts masked already: FZ_SR = the slot's SR).
fz_gt_resume:
	sf      FZ_GTWAIT
	st      FZ_GTCTX
	move.w  sr,FZ_SR
	jsr     hal_spr_reclaim         ; (the flip freed the oldest: the tail moves)
	move.w  HAL_SPR_W,d0
	jsr     hal_spr_set
	jsr     hal_spr_lim
	lea     G_SPRLUT,a2
	lea     REG_VRAMRW,a3
	move.w  #1,REG_VRAMMOD
	movea.l FZ_WA4,a4
	movea.l FZ_WA5,a5
	movea.l FZ_RTN,a0
	move.l  #$7fff,d7
	jmp     fz_next

; the pass's state at its start (also hal_spr_go's .rst: the set begun again)
fz_gt_start:
	clr.w   FZ_PASS
	move.l  #G_DX_OBJ1,FZ_OBJ
	move.l  #G_DX_OBJ2,FZ_OEND
	move.w  #1,FZ_P1
	move.w  #-1,FZ_GN
	move.l  FZ_PBE,d0               ; (the pool records from the start)
	subi.l  #8*BP_N,d0
	move.l  d0,FZ_PBP
	clr.w   FX_HSEEN
	clr.w   FX_HSAME
	ifne FX_HOV
	clr.w   FX_HSUS
	sf      FX_HR1
	endif
	rts

; as fz_begin without the records: the HUD and the pool for the set HAL_SPR_W would be
; (FZ_GTSET), the scroll offsets.  Clobbers d0-d1, a0.
fz_gt_begin:
	jsr     hal_spr_lim             ; (SS_HMIN)
	move.w  G_DX_SCRY,FZ_SY
	move.w  G_DX_SCRX,FZ_SX
	move.w  HAL_FRAMES+2,FX_WSEQ    ; (hal/fx.s: the HUD queue's number for this pass)
	move.w  FZ_GTSET,d0
	add.w   d0,d0
	lea     FZ_SEQ,a0
	move.w  FX_WSEQ,(a0,d0.w)
	lea     FZ_PBN,a0
	clr.w   (a0,d0.w)
	move.w  d0,d1                   ; its pool records (8 x BP_N a set)
	lsl.w   #7,d1
	lea     FZ_POOL,a0
	adda.w  d1,a0
	move.l  a0,FZ_PBP
	lea     8*BP_N(a0),a0
	move.l  a0,FZ_PBE
	jsr     bp_poll                 ; (hal/fx.s: the pool on, off: VRAM, masked here)
	ifne BP_SIZED
	movea.l FZ_PBP,a0
	move.w  BP_NV,d1
	lsl.w   #3,d1
	adda.w  d1,a0
	move.l  a0,FZ_PBL
	endif
	sf      FX_HPEND
	tst.w   HAL_FIXUSED
	seq     FX_HOK
	ifeq FX_HUDON
	sf      FX_HOK
	endif
	rts

; hal_spr_where (FUSED=2): where the new set starts, d0 = the column above its first one:
; the top of the LARGEST free run between the live sets (the shown one, a complete one;
; at most two) and the ring's ends - the slot's allocator went below the newest set and
; only jumped to the top when the bottom looked short, waiting for the flip otherwise;
; the game's pass cannot wait, and the shown set sitting at the top every third frame
; left a hole it never used (drops, 2026-10-18).  A run's columns hang down (chained)
; onto the START column of the live set below it, kept 0 by that set's predecessor's
; reclaim, and the column above a run is the live set above's last head or past the
; top.  Z set (no waiting).  Clobbers d0-d4, a1.
fz_gt_where:
	movem.l d5-d7/a0,-(sp)
	lea     HAL_SPR_ST,a0
	lea     HAL_SPR_START,a1
	move.w  HAL_SPR_W,d7            ; (the set begun: not live yet)
	moveq   #-1,d5                  ; U: the live set with the highest START
	moveq   #-1,d6                  ; L: the other
	moveq   #0,d1
.l:	cmp.w   d7,d1
	beq.s   .n
	tst.b   (a0,d1.w)
	beq.s   .n
	move.w  d1,d2
	add.w   d2,d2
	move.w  (a1,d2.w),d2
	tst.w   d5
	bmi.s   .u0
	move.w  d5,d3
	add.w   d3,d3
	cmp.w   (a1,d3.w),d2
	blo.s   .asl
	move.w  d5,d6
.u0:	move.w  d1,d5
	bra.s   .n
.asl:	move.w  d1,d6
.n:	addq.w  #1,d1
	cmpi.w  #NSPRSETS,d1
	blo.s   .l
	lea     HAL_SPR_END,a0
	move.w  RING_TOP,d0             ; the top run: RING_TOP - 1 .. U.START + 1
	move.w  d0,d1
	subi.w  #SPR_PB,d1              ; (no live set: down to SPR_PB)
	tst.w   d5
	bmi.s   .x
	move.w  d5,d2
	add.w   d2,d2
	move.w  d0,d1
	sub.w   (a1,d2.w),d1
	subq.w  #1,d1
	move.w  (a0,d2.w),d3            ; U.END: the run below U
	move.w  d3,d4
	tst.w   d6
	bmi.s   .nol
	move.w  d6,d2
	add.w   d2,d2
	sub.w   (a1,d2.w),d4            ; U.END - 1 .. L.START + 1
	subq.w  #1,d4
	cmp.w   d1,d4
	ble.s   .m1
	move.w  d4,d1
	move.w  d3,d0
.m1:	move.w  (a0,d2.w),d3            ; L.END - 1 .. SPR_PB
	move.w  d3,d4
	subi.w  #SPR_PB,d4
	cmp.w   d1,d4
	ble.s   .x
	move.w  d3,d0
	bra.s   .x
.nol:	subi.w  #SPR_PB,d4              ; U.END - 1 .. SPR_PB
	cmp.w   d1,d4
	ble.s   .x
	move.w  d3,d0
.x:	movem.l (sp)+,d5-d7/a0
	moveq   #0,d1
	rts

; hal_spr_lim (FUSED=2): the set a6's lowest column now (SS_HMIN): above the START
; column of the nearest live set below its SS_HNEXT (that column is kept 0: the run hangs
; onto it), else SPR_PB.  Clobbers d0, d1, a1.
fz_gt_lim:
	movem.l d2-d3/a0,-(sp)
	move.w  SS_HNEXT(a6),d1
	move.w  #SPR_PB-1,d0
	lea     HAL_SPR_ST,a1
	lea     HAL_SPR_START,a0
	moveq   #NSPRSETS-1,d2
.l:	cmp.w   HAL_SPR_W,d2
	beq.s   .n
	tst.b   (a1,d2.w)
	beq.s   .n
	move.w  d2,d3
	add.w   d3,d3
	move.w  (a0,d3.w),d3
	cmp.w   d1,d3
	bhs.s   .n
	cmp.w   d0,d3
	ble.s   .n
	move.w  d3,d0
.n:	dbra    d2,.l
	addq.w  #1,d0
	move.w  d0,SS_HMIN(a6)
	movem.l (sp)+,d2-d3/a0
	rts

; the objects of the pass's range from FZ_OBJ, eight slots a turn; an active one is
; done by fz_gt_obj (which comes back here); the range's end: the next pass
fz_gt_scan:
	move.w  FZ_PASS,d0
	cmpi.w  #2,d0
	bne.s   .ng
	tst.w   G_DX_90E6               ; the group: in x order unless $ff90e6 is set
	beq.w   fz_gt_grp
.ng:	cmpi.w  #4,d0
	beq.w   fz_gt_hud
	movea.l FZ_OBJ,a0
	movea.l FZ_OEND,a1
.s:	cmpa.l  a1,a0
	bhs.s   .pend
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
	bra.s   .s
.a7:	lea     $60(a0),a0
.a6:	lea     $60(a0),a0
.a5:	lea     $60(a0),a0
.a4:	lea     $60(a0),a0
.a3:	lea     $60(a0),a0
.a2:	lea     $60(a0),a0
.a1:	lea     $60(a0),a0
	cmpa.l  a1,a0
	bhs.s   .pend
.act:	lea     $60(a0),a1
	move.l  a1,FZ_OBJ               ; (the next slot, for the way back)
	bra.w   fz_gt_obj
.pend:	addq.w  #1,FZ_PASS              ; the next pass
	move.w  FZ_PASS,d0
	clr.w   FZ_P1
	subq.w  #1,d0
	bne.s   .p2
	move.l  #G_DX_OBJ2,FZ_OBJ       ; pass 2
	move.l  #G_DX_OBJ3,FZ_OEND
	bra.w   fz_gt_scan
.p2:	subq.w  #1,d0
	bne.s   .p3
	move.l  #G_DX_OBJ3,FZ_OBJ       ; the group (in slot order when $ff90e6)
	move.l  #G_DX_OBJ4,FZ_OEND
	bra.w   fz_gt_scan
.p3:	move.l  #G_DX_OBJ4,FZ_OBJ       ; pass 3 (and past it: done)
	move.l  #G_DX_OBJ5,FZ_OEND
	bra.w   fz_gt_scan

; the group $ff42c0..$ff48c0 in x order (hal/dx.s dx_group), sorted once into FZ_SORT
fz_gt_grp:
	tst.w   FZ_GN
	bpl.s   .g
	lea     FZ_SORT,a5
	moveq   #0,d6
	movea.l #G_DX_OBJ3,a0
	moveq   #15,d4
.o:	tst.b   (a0)
	bpl.s   .on
	move.w  $10(a0),d0
	addi.w  #$8000,d0
	movea.l a5,a3                   ; the first entry with a key >= d0
	move.w  d6,d1
	bra.s   .c1
.c:	cmp.w   (a3),d0
	bls.s   .ins
	addq.l  #6,a3
.c1:	dbra    d1,.c
.ins:	move.w  d6,d1                   ; shift the rest up, from the end
	mulu    #6,d1
	lea     (a5,d1.w),a1
.sh:	cmpa.l  a3,a1
	bls.s   .put
	move.l  -4(a1),2(a1)
	move.w  -6(a1),(a1)
	subq.l  #6,a1
	bra.s   .sh
.put:	move.w  d0,(a3)
	move.l  a0,2(a3)
	addq.w  #1,d6
.on:	lea     $60(a0),a0
	dbra    d4,.o
	move.w  d6,FZ_GN
	clr.w   FZ_GI
.g:	move.w  FZ_GI,d0
	cmp.w   FZ_GN,d0
	bhs.w   .gend
	addq.w  #1,FZ_GI
	mulu    #6,d0
	lea     FZ_SORT+2,a0
	movea.l (a0,d0.w),a0
	bra.w   fz_gt_obj
.gend:	move.w  #3,FZ_PASS              ; pass 3
	move.l  #G_DX_OBJ4,FZ_OBJ
	move.l  #G_DX_OBJ5,FZ_OEND
	bra.w   fz_gt_scan

; object a0 (active): its zoom, w2 bytes and routines (hal/fx.s fx_objg's), a pair
; bullet's one entry (fz_bul), else its tables B, C, A, each through fz_gt_tab; back to
; fz_gt_scan at the end (FZ_CONT).  (The registers of the pass: a2-a4, a6, d7.)
fz_gt_obj:
	move.l  a0,FZ_CUR
	move.l  $e(a0),FZ_Y             ; y, x
	move.w  FZ_P1,d6                ; the routine: zoom from the object 8, its colour
	cmpi.w  #$2e,$16(a0)            ; 4, flips from the pieces 2, pass 1 1
	bne.s   .nz
	addq.w  #8,d6
	moveq   #0,d0
	move.b  1(a0),d0
	ror.w   #4,d0
	andi.w  #$f000,d0
	move.w  d0,FZ_ZOOM
	bra.s   .z
.nz:	clr.w   FZ_ZOOM
.z:	moveq   #0,d0                   ; the w2 byte
	tst.b   $19(a0)
	bpl.s   .p0
	btst    #0,$19(a0)
	beq.s   .p1
.p0:	moveq   #$20,d0
.p1:	move.b  $2a(a0),d1              ; flips
	beq.s   .f0
	or.b    d1,d0
	bra.s   .f1
.f0:	addq.w  #2,d6                   ; (from the pieces)
.f1:	move.w  d0,FZ_W2B               ; (B/A without the object's colour: b43 bit 4)
	move.w  d6,d5
	move.b  5(a0),d1
	bpl.s   .nc
	andi.b  #$f,d1
	or.b    d1,d0
	addq.w  #4,d6                   ; colour from the object
.nc:	move.w  d0,FZ_W2C
	; a pair bullet (hal/fx.s fxb_obj's conditions): type $18 in pass 1, two pieces of
	; one of FXB_N tables, the C table only, flips and colour from the pieces, in front
	cmpi.w  #$18,$16(a0)
	bne.s   .nb
	tst.w   FZ_P1
	beq.s   .nb
	cmpi.b  #1,4(a0)
	bne.s   .nb
	move.b  $43(a0),d1
	andi.b  #$c0,d1
	bne.s   .nb
	tst.b   $2a(a0)
	bne.s   .nb
	tst.b   5(a0)
	bmi.s   .nb
	btst    #5,d0
	beq.s   .nb
	move.l  $1a(a0),d1
	subi.l  #FXB_T0,d1
	cmpi.l  #(FXB_N-1)*FXB_TS,d1
	bhi.s   .nb
	moveq   #3,d2
	and.w   d1,d2
	bne.s   .nb
	lsr.w   #2,d1
	lea     fxb_ok,a1
	move.b  (a1,d1.w),d1
	beq.s   .nb
	move.w  d1,FZ_W2                ; (fz_bul: its fxb_ok value)
	movea.l $1a(a0),a5              ; (its general way: the C table's two pieces)
	clr.w   FZ_LEFT
	move.l  #fz_gt_scan,FZ_CONT
	lea     fz_bul(pc),a0
	bra.w   fz_gt_piece
.nb:	move.b  $43(a0),d1
	lea     fz_emt,a1
	move.w  d6,d0
	add.w   d0,d0
	add.w   d0,d0
	move.l  (a1,d0.w),FZ_RTC
	move.w  d5,d0                   ; B/A: the object's colour too unless b43 bit 4
	btst    #4,d1
	bne.s   .wo
	move.w  d6,d0
	move.w  FZ_W2C,FZ_W2B
.wo:	add.w   d0,d0
	add.w   d0,d0
	move.l  (a1,d0.w),FZ_RTB
	tst.b   d1
	bpl.w   fz_gt_c                 ; no B
	movea.l $44(a0),a5              ; B: the table at $44, b43 bits 0-3 + 1 pieces
	moveq   #$f,d0
	and.b   d1,d0
	move.l  #fz_gt_c,FZ_CONT
	move.w  FZ_W2B,FZ_W2
	movea.l FZ_RTB,a0
	bra.w   fz_gt_tab
fz_gt_c:
	movea.l FZ_CUR,a0
	movea.l $1a(a0),a5              ; C: the table at $1a, b4 + 1 pieces
	moveq   #0,d0
	move.b  4(a0),d0
	move.l  #fz_gt_a,FZ_CONT
	move.w  FZ_W2C,FZ_W2
	movea.l FZ_RTC,a0
	bra.w   fz_gt_tab
fz_gt_a:
	movea.l FZ_CUR,a0
	move.b  $43(a0),d1
	btst    #6,d1
	beq.w   fz_gt_scan              ; no A: the object done
	movea.l $44(a0),a5              ; A: as B
	moveq   #$f,d0
	and.b   d1,d0
	move.l  #fz_gt_scan,FZ_CONT
	move.w  FZ_W2B,FZ_W2
	movea.l FZ_RTB,a0
	; the table a5 (d0 = pieces - 1) through the routine a0: its first piece now, the
	; others by fz_next; interrupts masked for the piece's VRAM writes
fz_gt_tab:
	move.w  d0,FZ_LEFT
fz_gt_piece:
	ori.w   #$0700,sr
	move.w  #1,REG_VRAMMOD
	jmp     (a0)

; the objects done (or the head slots out): the HUD's slots (hal/fx.s fx_walk's HUD
; pass; VRAM: masked), then the set complete
fz_gt_hud:
	move.w  #4,FX_PASS
	clr.w   FX_GI
	move.w  #$7000,d6
	ori.w   #$0700,sr
	move.w  #1,REG_VRAMMOD
	movem.l d7/a2-a6,-(sp)
	jsr     fx_walk
	movem.l (sp)+,d7/a2-a6
	move.w  FZ_SR,sr
	bsr.s   fz_gt_fin
	bra.w   fz_gt_out
; the set a6 complete (hal_spr_go's .hoff and hal_spr_work's .fin): its heads (a4), where
; the next set starts, its pool records, its state.  Clobbers d0-d1, a1.
fz_gt_fin:
	move.l  a4,d0
	sub.l   a6,d0
	subi.w  #SS_HADR,d0
	move.w  d0,SS_HOFF(a6)
	move.w  SS_HNEXT(a6),HAL_SPR_GNEXT
	move.w  FZ_GTSET,d0
	add.w   d0,d0
	lea     HAL_SPR_END,a1
	move.w  SS_HNEXT(a6),(a1,d0.w)
	lea     HAL_SPR_START,a1
	move.w  (a1,d0.w),d1
	sub.w   SS_HNEXT(a6),d1
	move.w  d1,HAL_SPR_PREV
	move.l  FZ_PBP,d1
	sub.l   FZ_PBE,d1
	addi.l  #8*BP_N,d1
	lsr.w   #3,d1
	lea     FZ_PBN,a1
	move.w  d1,(a1,d0.w)
	lsr.w   #1,d0
	lea     HAL_SPR_ST,a1
	move.b  #1,(a1,d0.w)            ; complete: waits for its flip
	move.w  #-1,FZ_GTSET
	move.w  #-1,HAL_SPR_W
	clr.l   HAL_SPR_RA5
	rts
	endif
