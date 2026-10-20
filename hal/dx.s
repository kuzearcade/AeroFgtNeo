; Not cycle-exact (AEROFGT_DIRECT builds): the game's sprite-list builder.
;
; The original (0x2bee0..0x2bf9a: three passes over the object tables, the x-sorted
; group in between, each object through the emitters 0x2c0d2 / 0x2c0ec / 0x2c0b4)
; spends ~38% of a busy frame (48-61k cycles), mostly on call overhead and on
; recomputing per-object values for every piece.  This one writes exactly the same
; data (list at 0xff6800, attribute words into 0xff7400 / 0xff7000, counts, the
; pointers 0xff8d0a / 0xff8d0e / 0xff9242; the vblank handler copies them as before)
; in a fraction of that; the time it frees is idle time the HAL harvests.  Not written
; any more: the sort's scratch (0xff9026.., 0xff80d0..).  Entered from 0x2bee0 (jmp),
; back to 0x2bf9a; keeps d2/d3 (the original never touches them).

dx_build:
	movem.l d2-d3,-(sp)
	movea.l #G_DX_LIST,a6
	move.w  #$c000,(a6)+
	move.w  #$1000,G_DX_923E
	move.w  #$2000,G_DX_9240
	move.w  #1,G_DX_LOCK
	move.w  G_DX_SCRY,d2            ; (for the whole frame)
	move.w  G_DX_SCRX,d3
	; pass 1: 0xff0000..0xff30c0 into 0xff7400
	movea.l #G_DX_BUF1,a1
	clr.w   G_DX_CNT1
	movea.l #G_DX_CNT1,a2
	movea.l #G_DX_OBJ1,a0
	move.l  #G_DX_OBJ2,d4
	bsr     dx_pass
	move.l  a1,G_DX_PTR1
	clr.w   G_DX_923E
	clr.w   G_DX_9240
	; passes 2, the group (x-sorted), 3 into 0xff7000
	movea.l #G_DX_BUF0,a1
	clr.w   G_DX_CNT0
	movea.l #G_DX_CNT0,a2
	movea.l #G_DX_OBJ2,a0
	move.l  #G_DX_OBJ3,d4
	bsr     dx_pass
	bcs.s   .f
	bsr     dx_group
	bcs.s   .f
	movea.l #G_DX_OBJ4,a0
	move.l  #G_DX_OBJ5,d4
	bsr     dx_pass
.f:	move.l  a1,G_DX_PTR0
	move.l  a6,G_DX_LPTR
	movem.l (sp)+,d2-d3
	ifeq DIRECT-2
	; check build: keep this output, run the original builder on the same objects,
	; compare at its end (dx_check, from 0x2bf9a)
	lea     DXC_SAVE,a1
	movea.l #G_DX_LIST,a0
	move.w  #$400/4-1,d0
.c1:	move.l  (a0)+,(a1)+
	dbra    d0,.c1
	movea.l #G_DX_BUF0,a0           ; (both buffers: 0x800 bytes)
	move.w  #$800/4-1,d0
.c2:	move.l  (a0)+,(a1)+
	dbra    d0,.c2
	move.l  G_DX_CNT0,(a1)+         ; (both counts)
	move.l  G_DX_PTR0,(a1)+
	move.l  G_DX_PTR1,(a1)+
	move.l  G_DX_LPTR,(a1)+
	movea.l #G_DX_LIST,a6           ; the original's first instruction
	jmp     $2bee6
	else
	jmp     $2bf9a
	endif

	ifeq DIRECT-2
DXC_SAVE        equ G_SPRRAM+$1000      ; (sprite RAM the game leaves alone)
; at the original builder's end (0x2bf9a, jmp from there): compare, then on with the
; instruction the jmp replaced (tst.w lock).  Mismatching frames: HAL_SPR_DBGI.
dx_check:
	movem.l d0-d1/a0-a2,-(sp)
	lea     DXC_SAVE,a1
	moveq   #0,d1
	movea.l #G_DX_LIST,a0           ; the list up to its end
	move.l  G_DX_LPTR,d0
	sub.l   a0,d0
	lsr.w   #1,d0
	bra.s   .l1
.l:	cmpm.w  (a0)+,(a1)+
	beq.s   .l1
	moveq   #1,d1
.l1:	dbra    d0,.l
	lea     DXC_SAVE+$400,a1        ; buffer 0 up to its count, buffer 1 likewise
	movea.l #G_DX_BUF0,a0
	move.w  G_DX_CNT0,d0
	lsl.w   #2,d0
	bra.s   .b1
.b:	cmpm.w  (a0)+,(a1)+
	beq.s   .b1
	moveq   #1,d1
.b1:	dbra    d0,.b
	lea     DXC_SAVE+$800,a1
	movea.l #G_DX_BUF1,a0
	move.w  G_DX_CNT1,d0
	lsl.w   #2,d0
	bra.s   .d1
.d:	cmpm.w  (a0)+,(a1)+
	beq.s   .d1
	moveq   #1,d1
.d1:	dbra    d0,.d
	lea     DXC_SAVE+$c00,a1
	move.l  G_DX_CNT0,d0
	cmp.l   (a1)+,d0
	beq.s   .p0
	moveq   #1,d1
.p0:	move.l  G_DX_PTR0,d0
	cmp.l   (a1)+,d0
	beq.s   .p1
	moveq   #1,d1
.p1:	move.l  G_DX_PTR1,d0
	cmp.l   (a1)+,d0
	beq.s   .p2
	moveq   #1,d1
.p2:	move.l  G_DX_LPTR,d0
	cmp.l   (a1)+,d0
	beq.s   .p3
	moveq   #1,d1
.p3:	add.w   d1,HAL_SPR_DBGI
	addq.w  #1,HAL_SPR_DBGD         ; (frames checked)
	movem.l (sp)+,d0-d1/a0-a2
	tst.w   G_DX_LOCK
	jmp     $2bfa0
	endif

; the objects a0..d4 (0x60 bytes each).  C set: the buffer is full.
dx_pass:
.l:	tst.b   (a0)
	bpl.s   .n
	bsr.w   dx_obj
	bcs.s   .x
.n:	lea     $60(a0),a0
	cmpa.l  d4,a0
	blo.s   .l
	andi    #$fe,ccr                ; (C clear)
.x:	rts

; the x-sorted group 0xff42c0..0xff48c0 (16 objects; in slot order if 0xff90e6 is set):
; the original inserts each active object before the first with a key (x + 0x8000)
; that is higher or the same.  C set: full.
dx_group:
	tst.w   G_DX_90E6
	beq.s   .s
	movea.l #G_DX_OBJ3,a0
	move.l  #G_DX_OBJ4,d4
	bra.w   dx_pass
.s:	lea     -16*6(sp),sp            ; (key.w, object.l) x 16 at most
	movea.l sp,a4
	moveq   #0,d6                   ; entries
	movea.l #G_DX_OBJ3,a0
	moveq   #15,d7
.o:	tst.b   (a0)
	bpl.s   .on
	move.w  $10(a0),d0
	addi.w  #$8000,d0
	movea.l a4,a3                   ; first entry with a key >= d0 (unsigned)
	move.w  d6,d1
	bra.s   .c1
.c:	cmp.w   (a3),d0
	bls.s   .ins
	addq.l  #6,a3
.c1:	dbra    d1,.c
.ins:	move.w  d6,d1                   ; shift the rest up: from the end
	mulu    #6,d1
	lea     (a4,d1.w),a5
.sh:	cmpa.l  a3,a5
	bls.s   .put
	move.l  -4(a5),2(a5)
	move.w  -6(a5),(a5)
	subq.l  #6,a5
	bra.s   .sh
.put:	move.w  d0,(a3)
	move.l  a0,2(a3)
	addq.w  #1,d6
.on:	lea     $60(a0),a0
	dbra    d7,.o
	movea.l a4,a5
	bra.s   .e1
.e:	movea.l 2(a5),a0
	movem.l d6/a5,-(sp)
	bsr.w   dx_obj
	movem.l (sp)+,d6/a5
	bcs.s   .x
	addq.l  #6,a5
.e1:	dbra    d6,.e
	andi    #$fe,ccr
.x:	lea     16*6(sp),sp             ; (C kept)
	rts

; one object a0: the original's emitters 0x2c0d2 (b43 bit 7: the table at $44, b43
; bits 0-3 + 1 pieces), 0x2c0ec (the table at $1a, b4 + 1 pieces), 0x2c0b4 (b43
; bit 6: as the first).  C set: full.
dx_obj:
	move.b  $43(a0),d0
	bpl.s   .c
	movea.l $44(a0),a3
	moveq   #$f,d6
	and.b   d0,d6
	moveq   #$10,d5
	and.b   d0,d5
	bsr.w   dx_tab
	bcs.s   .x
.c:	movea.l $1a(a0),a3
	moveq   #0,d6
	move.b  4(a0),d6
	moveq   #0,d5
	bsr.w   dx_tab
	bcs.s   .x
	move.b  $43(a0),d0
	btst    #6,d0
	beq.s   .x                      ; (C clear)
	movea.l $44(a0),a3
	moveq   #$f,d6
	and.b   d0,d6
	moveq   #$10,d5
	and.b   d0,d5
	bsr.w   dx_tab
.x:	rts

; d6 + 1 pieces of the table a3 for object a0 (d5: b43 bit 4, or 0): each piece on
; screen (y + dy in 0xfee0.. or ..0xdf, x + dx in 0xff40.. or ..0x13f) -> 4 attribute
; words at a1, its list word at a6, the count at a2 + 1.  C set: full.
DXF_COBJ        equ 8               ; d5: colour from the object (b5), not the table
DXF_FLIPS       equ 9               ; d5: flips from the table (b42 = 0)
DXF_K2E         equ 10              ; d5: zoom from the object (b1; type 0x2e), in d7
dx_tab:
	move.l  d4,-(sp)
	; per object: zoom (0x2e type: the object's b1 for both), colour, bit 5, b42
	moveq   #0,d1
	cmpi.w  #$2e,$16(a0)
	bne.s   .k
	moveq   #0,d7
	move.b  1(a0),d7
	ror.w   #4,d7
	andi.w  #$f000,d7
	bset    #DXF_K2E,d1
.k:
	tst.b   5(a0)
	bpl.s   .c0
	tst.w   d5
	bne.s   .c0
	move.b  5(a0),d1
	andi.b  #$f,d1
	bset    #DXF_COBJ,d1
.c0:	tst.b   $19(a0)
	bpl.s   .p0
	btst    #0,$19(a0)
	beq.s   .p1
.p0:	ori.b   #$20,d1
.p1:	move.b  $2a(a0),d0
	beq.s   .f0
	or.b    d0,d1
	bra.s   .f1
.f0:	bset    #DXF_FLIPS,d1
.f1:	move.w  d1,d5
.p:	movea.l (a3),a4
	move.w  $e(a0),d0               ; y
	add.w   4(a3),d0
	cmpi.w  #$fee0,d0
	bhs.s   .yv
	cmpi.w  #$e0,d0
	bhs.w   .nx
.yv:	add.w   d2,d0                   ; w0 = y + scroll | zoomy << 12 | (a4)+0 << 8
	andi.w  #$1ff,d0
	btst    #DXF_K2E,d5
	beq.s   .zy
	or.w    d7,d0
	bra.s   .zy1
.zy:	move.b  $a(a3),d1
	ror.w   #4,d1
	andi.w  #$f000,d1
	or.w    d1,d0
.zy1:	move.w  (a4),d1
	andi.w  #$ff00,d1
	or.w    d1,d0
	move.w  d0,(a1)                 ; (written before the x test, as the original)
	move.w  $10(a0),d4              ; x
	add.w   6(a3),d4
	cmpi.w  #$ff40,d4
	bhs.s   .xv
	cmpi.w  #$140,d4
	bhs.w   .nx
.xv:	addq.l  #2,a1
	add.w   d3,d4                   ; w1 = x + scroll | zoomx << 12 | (a4)+1 << 8
	andi.w  #$1ff,d4
	btst    #DXF_K2E,d5
	beq.s   .zx
	or.w    d7,d4
	bra.s   .zx1
.zx:	move.b  $b(a3),d1
	ror.w   #4,d1
	andi.w  #$f000,d1
	or.w    d1,d4
.zx1:	move.w  (a4),d1
	lsl.w   #8,d1
	or.w    d1,d4
	move.w  d4,(a1)+
	move.b  d5,d1                   ; w2 = colour | bit 5 | flips << 8 | 0xff923e
	btst    #DXF_COBJ,d5
	bne.s   .co
	move.b  $c(a3),d0
	andi.b  #$f,d0
	or.b    d0,d1
.co:	btst    #DXF_FLIPS,d5
	beq.s   .fl
	move.b  8(a3),d0                ; bit 0 -> 7
	ror.b   #1,d0
	andi.b  #$80,d0
	or.b    d0,d1
	move.b  9(a3),d0                ; bits 1-0 -> 7-6
	ror.b   #2,d0
	andi.b  #$c0,d0
	or.b    d0,d1
.fl:	lsl.w   #8,d1
	or.w    G_DX_923E,d1
	move.w  d1,(a1)+
	move.w  2(a4),d1                ; w3 = map | 0xff9240
	or.w    G_DX_9240,d1
	move.w  d1,(a1)+
	addq.w  #1,(a2)
	move.w  a1,d0                   ; list word: 0x100 + its index in the buffer
	subq.w  #4,d0
	lsr.w   #3,d0
	andi.w  #$ff,d0
	addi.w  #$100,d0
	move.w  d0,(a6)+
	move.w  a1,d0                   ; the buffer full (0x400 bytes): stop
	andi.w  #$3ff,d0
	beq.s   .full
.nx:	lea     14(a3),a3
	dbra    d6,.p
	move.l  (sp)+,d4
	andi    #$fe,ccr
	rts
.full:	move.l  (sp)+,d4
	ori     #1,ccr
	rts
