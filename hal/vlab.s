; VRAM write lab (diagnostic builds with AEROFGT_DIAGLAB=2): instead of the game,
; write 32-word bursts to an unused SCB1 area (sprite 300) with VRAMMOD 1 at 8, 12,
; 16, 20, 24 and 32 cycles per write, once in the display (line 100) and once in the
; vblank (line 250), read every word back slowly and count the differences.  The
; values cycle through d0-d7 (8 distinct), so a lost write shifts the pattern.
; (line counter: $100 + vpos for vpos 0..255.)
; v2: 8-cycle bursts at several lines, address+data pairs, 12-cycle controls.
; Results (hal_diag_dump): 12 tests x 4 words at LAB_RES: errors, first bad index
; ($ffff: none), expected and read value there; then the first 16 words read back by
; the 8-cycle display test, and by the 12-cycle one.
LAB_RES         equ $10e060
LAB_RES2        equ $10e100
VL_ADDR         equ 300*64

lab_irq:
	rte

lab_main:
	move.w  #$2700,sr
	lea     LAB_RES,a6
	lea     vl_tests(pc),a5
.t:	move.l  (a5)+,d6                ; burst routine
	beq.s   .done
	move.w  (a5)+,d5                ; line to start at
	bsr.w   vl_clear
	bsr.w   vl_line
	lea     REG_VRAMRW,a3
	move.w  #1,REG_VRAMMOD
	move.w  #VL_ADDR,REG_VRAMADDR
	movea.l d6,a4                   ; (before d6 is a value)
	movem.l vl_vals(pc),d0-d7
	jsr     (a4)
	bsr.w   vl_check
	bra.s   .t
.done:	move.w  #2,HAL_FAULTCODE        ; green: lab done
	bra     hal_diag_dump

vl_tests:                               ; routine, line counter ($100 + vpos; $f8.. = 256..)
	dc.l    vl_b8
	dc.w    $100+20
	dc.l    vl_b8
	dc.w    $100+100
	dc.l    vl_b8
	dc.w    $100+180
	dc.l    vl_b8
	dc.w    $100+225
	dc.l    vl_b8
	dc.w    $100+236
	dc.l    vl_b8
	dc.w    $100+242
	dc.l    vl_b8
	dc.w    $100+250
	dc.l    vl_b8
	dc.w    $f8+2
	dc.l    vl_a8
	dc.w    $100+100
	dc.l    vl_a8
	dc.w    $100+250
	dc.l    vl_b12
	dc.w    $100+250
	dc.l    vl_b12
	dc.w    $f8+2
	dc.l    0

vl_vals:
	dc.w    0,$1201,0,$2302,0,$3403,0,$4504,0,$5605,0,$6706,0,$7807,0,$8908

; wait until the line counter (REG_LSPCMODE >> 7) is d5 (first wait until it is not)
vl_line:
	move.b  d0,REG_WATCHDOG         ; (a frame per test: the watchdog)
.a:	move.w  REG_LSPCMODE,d0
	lsr.w   #7,d0
	cmp.w   d5,d0
	beq.s   .a
.b:	move.w  REG_LSPCMODE,d0
	lsr.w   #7,d0
	cmp.w   d5,d0
	bne.s   .b
	rts

; the area: 32 words of $5a5a, written slowly
vl_clear:
	move.w  #1,REG_VRAMMOD
	move.w  #VL_ADDR,REG_VRAMADDR
	moveq   #32-1,d1
.c:	move.w  #$5a5a,REG_VRAMRW
	rept 8
	nop
	endr
	dbra    d1,.c
	rts

BURST	macro                           ; \1: NOPs after each write (8 + 4 * \1 cycles)
	rept 4
	move.w  d0,(a3)
	rept \1
	nop
	endr
	move.w  d1,(a3)
	rept \1
	nop
	endr
	move.w  d2,(a3)
	rept \1
	nop
	endr
	move.w  d3,(a3)
	rept \1
	nop
	endr
	move.w  d4,(a3)
	rept \1
	nop
	endr
	move.w  d5,(a3)
	rept \1
	nop
	endr
	move.w  d6,(a3)
	rept \1
	nop
	endr
	move.w  d7,(a3)
	rept \1
	nop
	endr
	endr
	rts
	endm
; address then data for every word (address write 12 cycles, the data 8 after it)
vl_a8:	lea     REG_VRAMADDR,a4
	lea     vl_addrs(pc),a0
	rept 4
	move.w  (a0)+,(a4)
	move.w  d0,(a3)
	move.w  (a0)+,(a4)
	move.w  d1,(a3)
	move.w  (a0)+,(a4)
	move.w  d2,(a3)
	move.w  (a0)+,(a4)
	move.w  d3,(a3)
	move.w  (a0)+,(a4)
	move.w  d4,(a3)
	move.w  (a0)+,(a4)
	move.w  d5,(a3)
	move.w  (a0)+,(a4)
	move.w  d6,(a3)
	move.w  (a0)+,(a4)
	move.w  d7,(a3)
	endr
	rts
vl_addrs:
vla	set VL_ADDR
	rept 32
	dc.w    vla
vla	set vla+1
	endr
vl_b8:	BURST   0
vl_b12:	BURST   1
vl_b16:	BURST   2
vl_b20:	BURST   3
vl_b24:	BURST   4
vl_b32:	BURST   6

; read the 32 words back slowly; a6: errors, first bad, expected, read (4 words)
vl_check:
	moveq   #0,d4                   ; errors
	move.w  #$ffff,d5               ; first bad
	moveq   #0,d6
	moveq   #0,d7
	lea     vl_vals(pc),a0
	moveq   #0,d1                   ; index
.r:	move.w  d1,d0
	addi.w  #VL_ADDR,d0
	move.w  d0,REG_VRAMADDR
	rept 16
	nop
	endr
	move.w  REG_VRAMRW,d0
	cmpa.l  #LAB_RES,a6             ; the 8-cycle display test: keep its words
	bne.s   .k1
	lea     LAB_RES2,a1
	move.w  d1,d2
	add.w   d2,d2
	move.w  d0,(a1,d2.w)
.k1:	cmpa.l  #LAB_RES+8,a6           ; and the 12-cycle one
	bne.s   .k2
	lea     LAB_RES2+64,a1
	move.w  d1,d2
	add.w   d2,d2
	move.w  d0,(a1,d2.w)
.k2:	moveq   #7,d2
	and.w   d1,d2
	add.w   d2,d2
	add.w   d2,d2
	move.w  2(a0,d2.w),d3           ; expected (the low word of d0..d7)
	cmp.w   d3,d0
	beq.s   .ok
	addq.w  #1,d4
	tst.w   d5
	bpl.s   .ok
	move.w  d1,d5
	move.w  d3,d6
	move.w  d0,d7
.ok:	addq.w  #1,d1
	cmpi.w  #32,d1
	blo.w   .r
	move.w  d4,(a6)+
	move.w  d5,(a6)+
	move.w  d6,(a6)+
	move.w  d7,(a6)+
	rts
