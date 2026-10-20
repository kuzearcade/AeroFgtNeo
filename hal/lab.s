; Timing lab v3 (diagnostic builds with AEROFGT_DIAGLAB=1): instead of the game, run
; timer experiments with 2-cycle resolution and show them with hal_diag_dump.
; A: LOAD_REL expiry LAB_N after the TIMERLOW write; a delay stub (0,4,6,8,10,12
;    cycles) between the write and a NOP sled: the sled position j moves by one NOP
;    per 4 cycles, and where it moves pins the IRQ boundary down to 2 cycles.
; B: the same write, REPEAT with reload LAB_R: the first IRQ is taken in sled A, its
;    handler returns through a delay stub into sled B, where the second IRQ lands.
; Each case 8 times with k = 0,1,2,3,4,0,1,2 NOPs before the write (E-clock phases).
; Results: LAB_RES rows (8 words): A d=0..12, then B d=0..12.
LAB_N           equ 2000
LAB_R           equ 3000
LAB_RES         equ $10e000
LAB_PC          equ $d00ff0-4
LAB_PC2         equ $d00ff0-8
LAB_STAGE       equ $d00ff0-9
LAB_CHAIN       equ $d00ff0-10
LAB_STUB2       equ $d00ff0-14              ; long: delay stub into sled B
LAB_RET         equ $d00ff0-18              ; long: where lab_irq's last IRQ returns

lab_main:
	move.w  #$2700,sr
	move.l  #lab_c,LAB_RET
	lea     LAB_RES,a6
	sf      LAB_CHAIN
	lea     lab_stubsA(pc),a4
	bsr.w   lab_series
	st      LAB_CHAIN
	lea     lab_stubsB(pc),a4
	bsr.w   lab_series
	lea     LAB_RES+$100,a6
	move.l  #lab_c2,LAB_RET
	bsr.w   lab_cde
	move.w  #2,HAL_FAULTCODE                ; green: lab done
	bra     hal_diag_dump

; F: absolute phase.  A pre-write delay (0, 2, 4, 6, 8 cycles: stubs P4..P12) shifts the
;    timer write, hence the expiry, against the CPU's own 4-cycle bus timing.
;    Part 0: STOP wake (LOAD_REL LAB_N), handler -> stub B0 -> sled B, reload LAB_R
;    lands there (as E).  Part 1: running, as B (sled A, then sled B).
; 8 measurements per row (k = NOP phases), rows part 0 P4..P12, part 1 P4..P12.
lab_cde:
	moveq   #0,d4
.p:	lea     lab_stubsP(pc),a4
.s:	move.l  (a4)+,d6
	beq.w   .np
	moveq   #0,d7
.m:	move.b  d0,REG_WATCHDOG
	clr.b   LAB_STAGE
	st      LAB_CHAIN
	move.l  #lab_stubB0,LAB_STUB2
	move.w  d7,d0
	cmpi.w  #5,d0
	blo.s   .k
	subq.w  #5,d0
.k:	add.w   d0,d0
	neg.w   d0
	movea.l d6,a5
	move.w  #ACK_TIMER,REG_IRQACK
	move.w  #AUTOANIM_OFF|TIMER_IRQ_EN|TIMER_LOAD_REL|TIMER_REPEAT,REG_LSPCMODE
	move.w  #0,REG_TIMERHIGH
	jsr     (a5)                            ; pre-write delay
	jmp     .kn(pc,d0.w)
	nop
	nop
	nop
	nop
.kn:	move.w  #LAB_N/2-1,REG_TIMERLOW
	move.w  #AUTOANIM_OFF|TIMER_IRQ_EN|TIMER_REPEAT,REG_LSPCMODE
	move.w  #0,REG_TIMERHIGH
	move.w  #LAB_R/2-1,REG_TIMERLOW
	tst.w   d4
	bne.s   .run
	jmp     lab_stubE0                      ; STOP
.run:	move.w  #$2100,sr
	jmp     lab_stubA0
.c:	move.w  #AUTOANIM_OFF,REG_LSPCMODE
	move.w  #ACK_TIMER,REG_IRQACK
	move.l  LAB_PC2,d0
	sub.l   #lab_sledB,d0
	lsr.l   #1,d0
	move.w  d0,(a6)+
	addq.w  #1,d7
	cmpi.w  #8,d7
	blo.w   .m
	bra.w   .s
.np:	addq.w  #1,d4
	cmpi.w  #2,d4
	blo.w   .p
	rts
lab_c2	equ .c

; a4 = list of stub addresses (0 = end); a row of 8 measurements per stub
lab_series:
.s:	move.l  (a4)+,d6
	beq.w   .x
	moveq   #0,d7
.m:	move.b  d0,REG_WATCHDOG
	clr.b   LAB_STAGE
	move.w  d7,d0
	cmpi.w  #5,d0
	blo.s   .k
	subq.w  #5,d0
.k:	add.w   d0,d0
	neg.w   d0
	movea.l d6,a5
	tst.b   LAB_CHAIN
	beq.s   .a
	move.l  d6,LAB_STUB2                    ; B: the stub is for sled B
	lea     lab_stubA0(pc),a5               ; sled A entered without delay
.a:	move.w  #ACK_TIMER,REG_IRQACK
	move.w  #AUTOANIM_OFF|TIMER_IRQ_EN|TIMER_LOAD_REL|TIMER_REPEAT,REG_LSPCMODE
	move.w  #0,REG_TIMERHIGH
	jmp     .kn(pc,d0.w)
	nop
	nop
	nop
	nop
.kn:	move.w  #LAB_N/2-1,REG_TIMERLOW         ; counter load: first expiry
	move.w  #AUTOANIM_OFF|TIMER_IRQ_EN|TIMER_REPEAT,REG_LSPCMODE
	move.w  #0,REG_TIMERHIGH
	move.w  #LAB_R/2-1,REG_TIMERLOW         ; reload
	move.w  #$2100,sr
	jmp     (a5)
.c:						; lab_irq returns here (IRQs masked)
	move.w  #AUTOANIM_OFF,REG_LSPCMODE
	move.w  #ACK_TIMER,REG_IRQACK
	tst.b   LAB_CHAIN
	bne.s   .b
	move.l  LAB_PC,d0
	sub.l   #lab_sledA,d0
	bra.s   .st
.b:	move.l  LAB_PC2,d0
	sub.l   #lab_sledB,d0
.st:	lsr.l   #1,d0
	move.w  d0,(a6)+
	addq.w  #1,d7
	cmpi.w  #8,d7
	blo.w   .m
	bra.w   .s
.x:	rts
lab_c	equ .c

lab_irq:
	move.w  #ACK_TIMER,REG_IRQACK
	tst.b   LAB_CHAIN
	beq.s   .last
	tst.b   LAB_STAGE
	bne.s   .last2
	st      LAB_STAGE                       ; B: first IRQ -> stub -> sled B
	move.l  2(sp),LAB_PC
	move.l  LAB_STUB2,2(sp)
	rte
.last:	move.l  2(sp),LAB_PC
	bra.s   .out
.last2:	move.l  2(sp),LAB_PC2
.out:	move.l  LAB_RET,2(sp)
	move.w  #$2700,(sp)
	rte

; delay stubs: 0, 4, 6, 8, 10, 12 cycles, then the sled
lab_stubA0:
	bra.w   lab_sledA
lab_stubA4:
	nop
	bra.w   lab_sledA
lab_stubA6:
	exg     d0,d0
	bra.w   lab_sledA
lab_stubA8:
	nop
	nop
	bra.w   lab_sledA
lab_stubA10:
	nop
	exg     d0,d0
	bra.w   lab_sledA
lab_stubA12:
	exg     d0,d0
	exg     d0,d0
	bra.w   lab_sledA
lab_stubB0:
	bra.w   lab_sledB
lab_stubB4:
	nop
	bra.w   lab_sledB
lab_stubB6:
	exg     d0,d0
	bra.w   lab_sledB
lab_stubB8:
	nop
	nop
	bra.w   lab_sledB
lab_stubB10:
	nop
	exg     d0,d0
	bra.w   lab_sledB
lab_stubB12:
	exg     d0,d0
	exg     d0,d0
	bra.w   lab_sledB
lab_stubsA:	dc.l    lab_stubA0,lab_stubA4,lab_stubA6,lab_stubA8,lab_stubA10,lab_stubA12,0
lab_stubsB:	dc.l    lab_stubB0,lab_stubB4,lab_stubB6,lab_stubB8,lab_stubB10,lab_stubB12,0
lab_sledA:
	rept 1000
	nop
	endr
	bra.w   hal_fault1
lab_sledB:
	rept 1200
	nop
	endr
	bra.w   hal_fault1

lab_stubC0:
	bra.w   lab_sledC
lab_stubC4:
	nop
	bra.w   lab_sledC
lab_stubC6:
	exg     d0,d0
	bra.w   lab_sledC
lab_stubC8:
	nop
	nop
	bra.w   lab_sledC
lab_stubC10:
	nop
	exg     d0,d0
	bra.w   lab_sledC
lab_stubC12:
	exg     d0,d0
	exg     d0,d0
	bra.w   lab_sledC
lab_stubE0:
	stop    #$2100
	bra.w   hal_fault1
lab_stubE4:
	nop
	stop    #$2100
	bra.w   hal_fault1
lab_stubE6:
	exg     d0,d0
	stop    #$2100
	bra.w   hal_fault1
lab_stubE8:
	nop
	nop
	stop    #$2100
	bra.w   hal_fault1
lab_stubE10:
	nop
	exg     d0,d0
	stop    #$2100
	bra.w   hal_fault1
lab_stubE12:
	exg     d0,d0
	exg     d0,d0
	stop    #$2100
	bra.w   hal_fault1
lab_stubsC:	dc.l    lab_stubC0,lab_stubC4,lab_stubC6,lab_stubC8,lab_stubC10,lab_stubC12,0
lab_stubsE:	dc.l    lab_stubE0,lab_stubE4,lab_stubE6,lab_stubE8,lab_stubE10,lab_stubE12,0
lab_sledC:
	rept 1600
	nop
	endr
	bra.w   hal_fault1

lab_stubP4:
	nop
	rts
lab_stubP6:
	exg     d0,d0
	rts
lab_stubP8:
	nop
	nop
	rts
lab_stubP10:
	nop
	exg     d0,d0
	rts
lab_stubP12:
	exg     d0,d0
	exg     d0,d0
	rts
lab_stubsP:	dc.l    lab_stubP4,lab_stubP6,lab_stubP8,lab_stubP10,lab_stubP12,0
