; Diagnostic builds only (AEROFGT_DIAG=1): on a fault, show the HAL's state on screen
; for hardware without a debugger.  Backdrop colour = fault code (1 red, 2 green,
; 3 blue, 4 yellow, 5 magenta, 6 cyan, 7 white); fix layer (hex digits in S tiles
; $ff0-$fff, put there by the builder for diagnostic builds): rows of
; "AAAA hex x 16 bytes" for the ranges in diag_list.
DG_REGS         equ $d00f00             ; d0-d7/a0-a7 at the fault (free backup RAM)
HAL_DG_J2       equ $d00f40             ; long: probe-2 table offset (x8) at fault 3

hal_fault3d:
	move.l  d0,HAL_DG_J2
	bra     hal_fault3

hal_diag_dump:
	move.w  #$2700,sr
	movem.l d0-d7/a0-a7,DG_REGS
	move.w  HAL_FAULTCODE,d1
	andi.w  #7,d1
	add.w   d1,d1
	lea     .fc(pc),a3
	move.w  (a3,d1.w),BACKDROP
	move.w  .tc-.fc(a3,d1.w),d2             ; text colour: contrast with it
	move.b  d0,REG_CRTFIX                   ; our S ROM: tiles $ff0-$fff = hex digits
	lea     $400000,a0                      ; fix palette 0
	clr.w   (a0)+
	moveq   #14,d1
.pl:	move.w  d2,(a0)+
	dbra    d1,.pl
	lea     REG_VRAMADDR,a0
	lea     REG_VRAMRW,a1
	move.w  #1,REG_VRAMMOD
	move.w  #SCB3,(a0)                      ; hide every sprite (height 0)
	move.w  #$200-1,d1
.hs:	move.w  #$0000,(a1)
	dbra    d1,.hs
	move.w  #FIXMAP,(a0)
	move.w  #$500-1,d1
.cl:	move.w  #$0000,(a1)
	move.b  d0,REG_WATCHDOG
	dbra    d1,.cl
	move.w  #32,REG_VRAMMOD                 ; along a row
	lea     diag_list(pc),a2
	moveq   #2,d3                           ; fix row
.r:	move.l  (a2)+,d4
	beq.s   .end
	move.w  (a2)+,d5
.rr:	move.w  d3,d0
	addi.w  #FIXMAP+32,d0                   ; column 1
	move.w  d0,(a0)
	move.w  d4,d2
	moveq   #3,d1
.a:	rol.w   #4,d2
	move.w  d2,d0
	bsr.s   .nib
	dbra    d1,.a
	move.w  #$0000,(a1)
	movea.l d4,a3
	moveq   #15,d1
.b:	move.b  (a3)+,d2
	move.b  d2,d0
	lsr.b   #4,d0
	bsr.s   .nib
	move.b  d2,d0
	bsr.s   .nib
	dbra    d1,.b
	addq.w  #1,d3
	addi.l  #16,d4
	move.b  d0,REG_WATCHDOG
	dbra    d5,.rr
	bra.s   .r
.end:	move.b  d0,REG_WATCHDOG
	bra.s   .end
.nib:	andi.w  #$f,d0
	addi.w  #$ff0,d0
	move.w  d0,(a1)
	rts
.fc:	dc.w    $0000,$4f00,$20f0,$100f,$6ff0,$5f0f,$30ff,$7fff
.tc:	dc.w    $7fff,$7fff,$8000,$7fff,$8000,$7fff,$8000,$8000

diag_list:                                      ; address, rows - 1
	ifne DIAGLAB
	dc.l    $10e060                         ; lab results: B d=0..12
	dc.w    5
	dc.l    $10e100                         ; F: STOP P4..P12, running P4..P12
	dc.w    9
	dc.l    0
	endif
	dc.l    DG_REGS                         ; d0-d7 a0-a7, J2
	dc.w    4
	dc.l    $d00820
	dc.w    4
	dc.l    $d00b70                         ; sprite slip counters (MIXN b78, VZN b7c,
	dc.w    9                               ; DROP ba0, LATE ba4, OVERRUN be0, DROPN bf8)
	dc.l    $d00fa0                         ; sprite column ring (fac..)
	dc.w    3
	dc.l    $d00f60                         ; MiSTer timing vars, model detection (f80)
	dc.w    2
	dc.l    $d00f50                         ; sound start: wait left, reply (0x55, 0xaa)
	dc.w    0
	dc.l    0
	even
