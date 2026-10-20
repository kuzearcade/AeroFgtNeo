; Idle-loop harvesting: the time the original spends spinning in its idle loop
; (0xb84 cmpi.b #1,$ff8055 / bcs) becomes HAL time.
;
; The builder sends the loop's bcs through 0xbd0 (jmp (-$400,a7)) to a RAM trampoline
; G_TRAMP that the HAL keeps up to date:
;   ori.w #$700,sr      enter hal_idle: the game is idle until the virtual vblank,
;   jmp hal_idle        so the HAL computes where that interrupt hits the loop and
;                       starts the frame's slot at once
; The bcs is also taken right after a virtual vblank that interrupted the loop after
; its cmpi (stacked PC 0xb8c, C set): the original then re-runs the cmpi, finds the
; flag set and leaves at 0xb8e 38 cycles after the RTE.  hal_idle sees the flag set
; and goes to 0xb8e on a fixed path, POST_DELAY cycles later than the original; the
; slot that set up that return already scheduled the next virtual vblank as much
; later (hal_frame), so virtual time stays exact.  (An interrupt at 0xbd0 / G_TRAMP
; is mapped back to the original's boundary by hal_probe.)
;
; With E = the idle loop's first cmpi (odd, like every post-IACK instruction boundary)
; and T = the chain expiry of the virtual vblank, the original takes the IRQ at the
; first loop boundary b >= T + 6 (tests/irq_fit.py), b = E+20+30m (stacked PC 0xb8c)
; or E+30+30m (0xb84), and the vector starts at the next 5-mod-10 cycle >= b + 50
; (hal_lat_table).  T - E is measured against the raster:
;   * the vernier gives E's phase within the 202752-cycle Neo frame (line counter,
;     2-cycle resolution, no interrupt acknowledge involved),
;   * T's phase is tracked: calibrated once by a vernier at an exactly known chain
;     time (the probe), then advanced by T_next - T every frame (the probe-2 class is
;     read back from the probe-2 stack frame the next frame).
; A constant kappa (where the line counter changes relative to our sampling) cancels.
; The wake W stays where the plan put it: the timer is reloaded at U, a fixed time
; after the vernier's last sample, i.e. at a known raster phase.

; ---------------------------------------------------------------- constants
; (cycles; checked by tests/idle_trace.py on an instruction trace)
V_A             equ 40              ; vernier entry -> first polling sample
F_U             equ 502             ; last vernier sample -> counter load (U), less 2-2*seen
ENTRY_E         equ 636             ; idle loop cmpi (E) -> vernier entry
PREFIX_P        equ 284             ; probe vector start -> vernier entry (calibration)
POST_DELAY      equ 70              ; RTE to 0xb8c -> 0xb8e: 108 cycles here vs 38 (= 0 mod 10)
D_MAX           equ 163200              ; > the original's frame (163105.5 cycles)
U_AFTER_T       equ 20*768          ; U is at most this far after T (T came during the vernier)
P2PC_OFF        equ -76             ; probe-2 stacked PC, relative to HAL_STACK_TOP

VERN_N0         equ 7               ; base shift count of the variable step delay
VERN_CNT        equ 66              ; dbra count of the fixed step delay
VERN_CNT1       equ 69              ; dbra count before the burst
VERN_NB         equ 17              ; base shift count of the delay after the burst
VERN_CNTB       equ 60              ; dbra count of that delay (138 + 2 NB + 10 CNTB = 772)

; ---------------------------------------------------------------- vernier
; One successive-approximation step: sample the line counter at t* + 768j - (acc + b)
; (t* = the polling sample that saw the change C); seen <=> u >= acc + b, u = t* - C.
; Then wait exactly 768 + b/2 - seen*b cycles to the next step's sample.
VSTEP	macro                           ; \1 = b (16, 8, 4)
	move.w  (a0),d5                 ; 8   sample
	and.w   d3,d5                   ; 4
	sub.w   d2,d5                   ; 4   0: still the old line
	neg.w   d5                      ; 4   X = seen
	subx.w  d7,d7                   ; 4   d7 = -seen
	moveq   #\1,d5                  ; 4
	and.w   d7,d5                   ; 4
	add.w   d5,d4                   ; 4   acc += seen * b
	move.w  (a0),d2                 ; 8   36 cycles after the sample: the new line for sure
	and.w   d3,d2                   ; 4
	moveq   #\1/2,d5                ; 4
	and.w   d7,d5                   ; 4
	moveq   #VERN_N0+\1/4,d7        ; 4
	sub.w   d5,d7                   ; 4   n = N0 + b/4 - seen*b/2
	lsl.l   d7,d5                   ; 8+2n
	move.w  #VERN_CNT,d5            ; 8
.d\@:	dbra    d5,.d\@                 ; 10*CNT+14
	endm                            ; total 94 + 2n + 10*CNT = 768 + b/2 - seen*b

; Raster sync.  Polls the line counter until it changes (30 cycles a turn), then
; resolves the change point C to 2 cycles with three more line changes (a burst of
; three samples 8 cycles apart, then two successive-approximation steps).  Every path is
; fixed-length except the polling turns and the step delays, and those cancel: the
; code after the return runs at a fixed raster phase.
; out: d6.w = masked counter value of line L (the line that started at C)
;      d1.w = polling turns i, d4.w = acc (u rounded down to the sampling parity)
;      phase(entry) - kappa = L*768 + acc - 30*i + 30 - V_A
;      phase(last sample + F_U + (2 - 2*seen) cycles) - kappa = L*768 + 2304 + F_U
; Clobbers d0-d7, a0.  Interrupts must be masked.
hal_vernier:
	lea     REG_LSPCMODE,a0         ; 12
	move.w  #$ff80,d3               ; 8   line counter (bits 0-6: flags, frame counter)
	move.w  (a0),d0                 ; 8
	and.w   d3,d0                   ; 4
	moveq   #0,d1                   ; 4
.c:	addq.w  #1,d1                   ; 4
	move.w  (a0),d2                 ; 8   polling sample: entry + V_A + 30*(i-1)
	and.w   d3,d2                   ; 4
	cmp.w   d2,d0                   ; 4
	beq.s   .c                      ; 10 (8 out)
	move.w  d2,d6                   ; 4
	moveq   #0,d4                   ; 4
	move.w  #VERN_CNT1,d5           ; 8
.d0:	dbra    d5,.d0                  ; 10*CNT1+14: first burst sample at t* + 744
	; burst at t* + 768 - 24, -16, -8: u >= 24, 16, 8 -> acc = 8 x seen
	move.w  (a0),d0                 ; 8   (u >= 24)
	move.w  (a0),d7                 ; 8   (u >= 16)
	move.w  (a0),d5                 ; 8   (u >= 8): t_3
	and.w   d3,d0                   ; 4
	sub.w   d2,d0                   ; 4
	neg.w   d0                      ; 4   X = seen
	addx.w  d4,d4                   ; 4   (d4 = 0)
	and.w   d3,d7                   ; 4
	sub.w   d2,d7                   ; 4
	neg.w   d7                      ; 4
	moveq   #0,d0                   ; 4   (X kept)
	addx.w  d0,d4                   ; 4
	and.w   d3,d5                   ; 4
	sub.w   d2,d5                   ; 4
	neg.w   d5                      ; 4
	moveq   #0,d0                   ; 4
	addx.w  d0,d4                   ; 4
	move.w  (a0),d2                 ; 8   long after the change: the new line
	and.w   d3,d2                   ; 4
	lsl.w   #3,d4                   ; 12  acc
	moveq   #VERN_NB,d7             ; 4
	move.w  d4,d5                   ; 4
	lsr.w   #1,d5                   ; 8
	sub.w   d5,d7                   ; 4   n = NB - acc/2
	lsl.l   d7,d5                   ; 8+2n
	move.w  #VERN_CNTB,d5           ; 8
.db:	dbra    d5,.db                  ; 10*CNTB+14: t_3 -> next sample 772 - acc
	VSTEP   4
	move.w  (a0),d5                 ; 8   last sample (t_4)
	and.w   d3,d5                   ; 4
	sub.w   d2,d5                   ; 4
	neg.w   d5                      ; 4
	subx.w  d7,d7                   ; 4
	moveq   #2,d5                   ; 4
	and.w   d7,d5                   ; 4
	add.w   d5,d4                   ; 4
	moveq   #1,d5                   ; 4   2 - 2*seen more cycles: fixed phase from here
	add.w   d7,d5                   ; 4
	lsl.l   d5,d5                   ; 8+2n
	rts                             ; 16

; branchless, fixed length: "if (d5 >= K) d5 -= F" / "if (d5 < 0) d5 += F" (clobber d7)
SUBGE	macro                           ; \1 = K
	move.l  d5,d7                   ; 4
	subi.l  #\1,d7                  ; 16
	add.l   d7,d7                   ; 8   X = (d5 < K)
	subx.l  d7,d7                   ; 8
	not.l   d7                      ; 6
	andi.l  #FRAME_CYCLES,d7        ; 16
	sub.l   d7,d5                   ; 8
	endm                            ; 66
ADDNEG	macro
	move.l  d5,d7                   ; 4
	add.l   d7,d7                   ; 8
	subx.l  d7,d7                   ; 8
	andi.l  #FRAME_CYCLES,d7        ; 16
	add.l   d7,d5                   ; 8
	endm                            ; 44

; d5 = any value in (-F, 2F) -> d5 mod F (variable length)
hal_modf:
	tst.l   d5
	bpl.s   .p
	addi.l  #FRAME_CYCLES,d5
.p:	cmpi.l  #FRAME_CYCLES,d5
	blo.s   .x
	subi.l  #FRAME_CYCLES,d5
.x:	rts

; d0.w = vpos 0..263 -> d5.l = vpos*768
hal_line768:
	moveq   #0,d5
	move.w  d0,d5
	mulu    #768,d5
	rts

; ---------------------------------------------------------------- idle entry
; From the trampoline, IPL 7, at E + 72.  The game's registers and stack are exactly
; as in the original's idle loop; its IRQ frame goes at fff000-6.
hal_idle:
	tst.b   G_VBFLAG                ; 16
	bne.w   hal_post                ; 10 (8 not taken)
	move    sr,HAL_IDLE_SR          ; X as in the loop (N Z V C: the cmpi's, known)
	move.l  sp,HAL_SAVED_SP
	lea     HAL_STACK_TOP,sp
	movem.l d0-d7/a0-a6,-(sp)
	subq.l  #6,sp                   ; same stack depth as the probe path
	move.b  #MODE_PROBE,HAL_MODE
	; T's phase: last frame's probe-2 sled position (its class) -> HAL_TPH
	move.l  HAL_STACK_TOP+P2PC_OFF,d0
	sub.l   #hal_sled+2*JMIN,d0
	move.l  d0,HAL_IDLE_J
	bsr     hal_tph_next
	bsr     hal_vernier
	; ---- fixed length from the vernier's last sample to the counter load
	moveq   #0,d0                   ; 4
	move.w  d6,d0                   ; 4
	lsr.w   #7,d0                   ; 20
	subi.w  #$f8,d0                 ; 8   L
	move.l  d0,d5                   ; 4
	lsl.l   #8,d5                   ; 24
	move.l  d5,d7                   ; 4
	add.l   d7,d7                   ; 8
	add.l   d7,d5                   ; 8   L*768
	addi.l  #3*768+F_U,d5           ; 16  phase(U) - kappa (< 2F)
	sub.l   HAL_TPH,d5              ; 22
	ADDNEG                          ; 44
	SUBGE   FRAME_CYCLES            ; 66  U - T mod F
	SUBGE   U_AFTER_T               ; 66  ... in [U_AFTER_T - F, U_AFTER_T)
	move.l  HAL_DWR,d7              ; 20  W (- RELOFS on the MiSTer, hal.s)
	sub.l   d5,d7                   ; 8   W - U
	subi.l  #W_IN+2,d7              ; 16
	lsr.l   #1,d7                   ; 10  counter value
	move.l  d7,HAL_TIMW             ; 20
	lea     HAL_TIMW,a1             ; 12
	moveq   #0,d7                   ; 4
	move.w  #AUTOANIM_OFF|TIMER_IRQ_EN|TIMER_REPEAT|TIMER_LOAD_REL,REG_LSPCMODE ; 20
	move.w  0(a1,d7.l),REG_TIMERHIGH        ; 26
	move.w  2(a1,d7.l),REG_TIMERLOW         ; U: counter load -> expiry at W
	; ---- variable length again
	move.w  #AUTOANIM_OFF|TIMER_IRQ_EN|TIMER_REPEAT,REG_LSPCMODE
	move.w  #(Q2/2-1)>>16,REG_TIMERHIGH     ; reload at W: probe 2 at W + Q2
	move.w  #(Q2/2-1)&$ffff,REG_TIMERLOW
	move.w  #ACK_TIMER,REG_IRQACK           ; T may have expired while masked
	move.w  REG_LSPCMODE,HAL_LINE_AT_PROBE  ; the slot's own "probe" is U
	move.l  d5,HAL_PROBE_AT
	move.l  d5,HAL_IDLE_U
	move.w  d0,HAL_IDLE_L
	move.w  d1,HAL_IDLE_I
	move.w  d4,HAL_IDLE_ACC
	move.l  HAL_IDLE_J,d0           ; MiSTer: last probe 2b's PC (hal.s checks it in hal_frame)
	add.l   #hal_sled+2*JMIN,d0
	move.l  d0,HAL_P2BPC

	; T's line, for the phase lock: vpos(U) - (U - T)/768
	move.w  HAL_LINE_AT_PROBE,d0
	bsr     hal_vpos_of
	move.l  HAL_IDLE_U,d1
	divs    #768,d1
	sub.w   d1,d0
	bpl.s   .t1
	addi.w  #264,d0
.t1:	cmpi.w  #264,d0
	blo.s   .t2
	subi.w  #264,d0
.t2:	move.w  d0,HAL_TLINE

	; ---- D = T - E
	move.w  HAL_IDLE_L,d0
	bsr     hal_line768
	moveq   #0,d1
	move.w  HAL_IDLE_ACC,d1
	add.l   d1,d5
	move.w  HAL_IDLE_I,d1
	mulu    #30,d1
	sub.l   d1,d5
	addi.l  #30-V_A-ENTRY_E,d5      ; phase(E) - kappa
	neg.l   d5
	add.l   HAL_TPH,d5              ; (-F, 2F)
	bsr     hal_modf
	cmpi.l  #D_MAX,d5               ; an idle is shorter than an original frame;
	blo.s   .dp                     ; above that, an undetected Q2-multiple error in
	subi.l  #FRAME_CYCLES,d5        ; T's phase put a short one below 0 (only D mod
				; 30 matters: 600 = 0 mod 30, while F = 12 mod 30)
.dp:	move.l  d5,HAL_IDLE_D
	; first loop boundary b >= D + 6 (b = 20 or 30 mod 30, relative to E):
	; b - D = 6 + delta, delta = 0, 20 - (D+6) mod 30 or 30 - (D+6) mod 30
	move.l  d5,d2
	addi.l  #6+30*4000,d2           ; (positive for the division)
	divu    #30,d2
	swap    d2                      ; (D+6) mod 30
	moveq   #6,d1
	move.l  #$b84,d3
	tst.w   d2
	beq.s   .b
	move.l  #$b8c,d3
	moveq   #20+6,d1
	cmpi.w  #20,d2
	bls.s   .b2
	move.l  #$b84,d3
	moveq   #30+6,d1
.b2:	sub.w   d2,d1
.b:	ext.l   d1                      ; b - D = (E + b) - T
	; vector start: + LAT[(RBASE + b - D) mod 10]
	move.w  d1,d2                   ; (6..36)
	add.w   HAL_RBASE,d2
	lea     hal_mod10,a0
	move.b  (a0,d2.w),d2
	ext.w   d2
	lea     hal_lat_table,a0
	moveq   #0,d0
	move.b  (a0,d2.w),d0
	beq.w   hal_fault6                      ; boundary not on the IACK parity
	add.l   d0,d1
	move.l  d1,HAL_DX
	; the original's IRQ frame: SR (IPL 1, the loop's flags) and the PC it interrupted
	movea.l HAL_SAVED_SP,a0
	subq.l  #6,a0
	move.l  a0,HAL_SAVED_SP
	move.w  HAL_IDLE_SR,d0
	andi.w  #$0010,d0
	ori.w   #$2109,d0               ; IPL 1, X, cmpi.b #1 of a 0 flag: N C
	move.w  d0,(a0)
	move.l  d3,2(a0)
	addq.l  #1,HAL_IDLES
	bra     hal_frame

; Returned from a virtual vblank to the loop's bcs (see the top): 16+10 so far
hal_post:
	andi.w  #$f9ff,sr               ; 20  IPL 7 -> 1, flags kept
	jmp     $0b8e.w                 ; 10  (RTE + 108; the original: RTE + 38)

; ---------------------------------------------------------------- calibration
; Called from the probe at a fixed time after its vector start (PREFIX_P), before
; anything variable.  Stores the vernier result; hal_cal_finish turns it into T's
; phase once the probe has measured where its own vector start was.
hal_cal_vernier:
	bsr     hal_vernier
	move.l  d1,HAL_VCAL_I
	move.w  d6,d0
	lsr.w   #7,d0
	subi.w  #$f8,d0
	move.w  d0,HAL_IDLE_L
	move.w  d4,HAL_IDLE_ACC
	rts

; d0.l = j (probe sled position) -> HAL_TPH, HAL_CAL set.
; probe vector start - T = dX + C_S + 4j + LAT[(5 + C_S + 4j) mod 10]
hal_cal_finish:
	tst.b   HAL_MISTER
	beq.s   .mame
	move.l  HAL_P1BVS,d2            ; MiSTer: probe-1b vector start - T
	addi.l  #PREFIX_PB,d2           ; vernier entry - T
	bra.s   .ve
.mame:
	move.l  d0,d2
	lsl.l   #2,d2
	addi.l  #C_S,d2                 ; C_S + 4j
	move.l  d2,d1
	addq.l  #5,d1
	divu    #10,d1
	swap    d1
	lea     hal_lat_table,a0
	moveq   #0,d3
	move.b  (a0,d1.w),d3
	beq.w   hal_fault7
	add.l   d3,d2
	add.l   HAL_DX_MEAS,d2          ; this machine's X (before the idle-loop mapping)
	addi.l  #PREFIX_P,d2            ; vernier entry - T
.ve:
	move.w  HAL_IDLE_L,d0
	bsr     hal_line768
	moveq   #0,d1
	move.w  HAL_IDLE_ACC,d1
	add.l   d1,d5
	move.l  HAL_VCAL_I,d1
	mulu    #30,d1
	sub.l   d1,d5
	addi.l  #30-V_A,d5              ; phase(vernier entry) - kappa
	sub.l   d2,d5
	bsr     hal_modf
	bsr     hal_modf
	move.l  d5,HAL_TPH
	move.l  d5,HAL_VCAL
	move.w  #$ff00,HAL_CAL          ; calibrated, clean
	addq.l  #1,HAL_CALS
	rts

; ---------------------------------------------------------------- tracking
; d0.l = last frame's probe-2 sled offset (2 x table entry; entry i has class i mod 5)
; -> HAL_TPH advanced to this frame's T: + T_next - T of that class (HAL_DTN_CLASS,
; written by last frame's hal_frame), mod F.  Fixed length (part of ENTRY_E).
; Clobbers d0-d1, d5, d7, a0.
hal_tph_next:
	andi.w  #$7e,d0                 ; 8   (any value: an entry of the table)
	lea     hal_cls4,a0             ; 12
	moveq   #0,d1                   ; 4
	move.b  (a0,d0.w),d1            ; 14  4 x class
	lea     HAL_DTN_CLASS,a0        ; 12
	move.l  (a0,d1.w),d5            ; 18
	add.l   HAL_TPH,d5              ; 22  (-F, 2F)
	ADDNEG                          ; 44
	SUBGE   FRAME_CYCLES            ; 66
	move.l  d5,HAL_TPH              ; 20
	rts                             ; 16
; 4 x ((offset / 2) mod 5) per sled offset 0..126
hal_cls4:
cli	set 0
	rept 64
	dc.b    4*(cli-(cli/5)*5),4*(cli-(cli/5)*5)
cli	set cli+1
	endr

; ---------------------------------------------------------------- trampoline
; Rewritten every frame (the game's boot RAM test/clear runs over it).
;   +0   ori.w #$700,sr  | bra.s +10    harvest | replica (T's phase unknown)
;   +4   jmp hal_idle
;   +10  bra.s +14                      replica: two 10-cycle hops put the loop back
;   +14  cmpi.b #1,flag                 on the original's boundaries (E+60, E+80...)
;   +22  bcs.s +14                      so the virtual vblank hits it exactly as the
;   +24  30 cycles                      original (hal_probe maps the PCs back); the
;   +34  jmp $b8e.w                     way out after a vblank costs POST_DELAY too
; T's phase is calibrated by the boot frame's probe (before the game first reaches
; the loop) and by the probe that the replica gets after a late wake.
TR_HOP          equ 10
TR_CMPI         equ 14
TR_BCS          equ 22
TR_REPLICA      equ $6000+TR_HOP-2      ; bra.s +10
hal_tramp:
	lea     G_TRAMP,a0
	move.l  #$007c0700,(a0)         ; ori.w #$0700,sr
	cmpi.w  #$ff00,HAL_CAL
	beq.s   .h
	move.w  #TR_REPLICA,(a0)
.h:	cmpi.l  #$60024e71,10(a0)       ; the rest still there? (only the game's boot
	bne.s   .w                      ; RAM test/clear runs over it)
	cmpi.l  #$65f6c140,22(a0)
	bne.s   .w
	cmpi.l  #$4ef80b8e,34(a0)
	bne.s   .w
	cmpi.l  #hal_idle,6(a0)
	beq.s   .x
.w:	addq.l  #4,a0
	move.w  #$4ef9,(a0)+            ; jmp hal_idle
	move.l  #hal_idle,(a0)+
	move.l  #$60024e71,(a0)+        ; +10 bra.s +14 / (filler)
	move.l  #$0c390001,(a0)+        ; +14 cmpi.b #1,G_VBFLAG
	move.l  #G_VBFLAG,(a0)+
	move.l  #$65f6c140,(a0)+        ; +22 bcs.s +14 / exg d0,d0
	move.l  #$c140c140,(a0)+
	move.l  #$c140c140,(a0)+
	move.l  #$4ef80b8e,(a0)         ; +34 jmp $0b8e.w
.x:	rts

; ---------------------------------------------------------------- scanlines
; d0 = current vpos 0..263.  Clobbers nothing else.
hal_vpos:
	move.w  REG_LSPCMODE,d0
hal_vpos_of:
	lsr.w   #7,d0
	cmpi.w  #$100,d0
	bhs.s   .lo
	addq.w  #256-$f8,d0             ; 0xf8..0xff = vpos 256..263
	rts
.lo:	subi.w  #$100,d0                ; vpos 0..255
	rts

; Work budget in scanlines from the slot's start: (W - start - margin) / 768
MARGIN_LINES    equ 3               ; slack before the wake expiry (one palette + exit path)
hal_deadline:
	move.w  HAL_LINE_AT_PROBE,d0
	bsr.s   hal_vpos_of
	move.w  d0,HAL_PROBE_VPOS
	addq.w  #8,d0                   ; the line counter as k = (vpos + 8) mod 264,
	cmpi.w  #264,d0                 ; which counts up from vpos 256
	blo.s   .k
	subi.w  #264,d0
.k:	move.w  d0,HAL_K0
	addi.w  #$f8,d0                 ; (as the line counter reads it)
	move.w  d0,HAL_K0R
	sf      HAL_OUT
	move.l  HAL_DW,d1
	sub.l   HAL_PROBE_AT,d1
	sub.l   #MARGIN_LINES*768,d1
	bpl.s   .p
	moveq   #0,d1
.p:	divu    #768,d1
	move.w  d1,HAL_DEADLINE
	add.w   HAL_K0R,d1
	move.w  d1,HAL_KDL
	rts

; Z clear (bne) when the budget is used up.  Clobbers d0.
hal_late:
	moveq   #0,d0
; same, but d0 = scanlines the next piece of work needs on top of the margin (and
; on top of HAL_RESV).  Once a check that needed at most 4 lines failed (reserve
; included), or fewer than 3 lines are left, every later one fails at once (HAL_OUT,
; until the next slot / commit).
hal_late_n:
	tst.b   HAL_OUT
	bne.s   .out
	add.w   HAL_RESV,d0
	ifeq DIRECT-1
	move.w  d1,-(sp)                ; (hal_late_raw inline: the common case, in time)
	move.w  REG_LSPCMODE,d1
	lsr.w   #7,d1
	cmp.w   HAL_K0R,d1
	bhs.s   .ip
	addi.w  #264,d1
.ip:	add.w   d0,d1
	cmp.w   HAL_KDL,d1
	bge.s   .il
	ifne OVR_DIAG
	move.w  d1,OVD_LN
	move.l  2(sp),OVD_PC
	endif
	move.w  (sp)+,d1
	cmp.w   d0,d0                   ; Z set: in time
	rts
.il:	move.w  (sp)+,d1
	else
	bsr.s   hal_late_raw
	beq.s   .ok
	endif
	cmpi.w  #4,d0
	ble.s   .lat
	moveq   #3,d0                   ; (under 3 lines left, reserve or not: the
	bsr.s   hal_late_raw            ; same, so the rest of the slot ends quickly)
	beq.s   .no
.lat:	st      HAL_OUT
.no:	move.w  #0,ccr
.ok:	rts
.out:	move.w  #0,ccr
	rts
; d0 = lines needed (may be negative), no reserve, HAL_OUT ignored.  Keeps d0.
hal_late_raw:
	move.w  d1,-(sp)
	move.w  REG_LSPCMODE,d1         ; the line counter, +264 past the wrap
	lsr.w   #7,d1
	cmp.w   HAL_K0R,d1
	bhs.s   .p
	addi.w  #264,d1
.p:	add.w   d0,d1                   ; + needed
	cmp.w   HAL_KDL,d1
	bge.s   .late
	ifne HAL_DIAG
	move.w  d1,HAL_DBG_LASTOK       ; diagnostics: last check that allowed work
	move.l  2+4(sp),HAL_DBG_LASTPC  ; (hal_late_n's caller)
	endif
	move.w  (sp)+,d1
	move.w  #4,ccr                  ; Z set: in time
	rts
.late:	move.w  (sp)+,d1
	move.w  #0,ccr
	rts
