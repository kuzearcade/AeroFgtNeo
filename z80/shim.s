; Neo Geo shim for the original Aero Fighters sound driver (fixed ROM 0x7800-0x7fff,
; RAM on the original board, so never used as code or data there).
;
; Power-on: answer the MVS BIOS (command 1 = slot switch, 3 = reset) until the HAL
; sends 0x55 0xaa, then run the original driver's reset code with its RAM relocated
; from 0x7800 to 0xf800.

ORIG_NMI_CONT  equ $0069        ; original NMI handler after its 3 displaced pushes
BIOS_STATE     equ $f900        ; BIOS-phase scratch (the original init clears RAM)
BIOS_SP        equ $f980

	org $7800
; 32K original bank n in A -> Neo windows 8000(16K)=2n C000(8K)=4n+2 E000(4K)=8n+6 F000(2K)=16n+14
bank_switch:
	push af
	push bc
	and $03
	add a,a
	ld b,a
	ld c,$0b
	in a,(c)                    ; 16K window @8000: bank 2n
	ld a,b
	add a,a
	add a,$02
	ld b,a
	ld c,$0a
	in a,(c)                    ; 8K window @C000: 4n+2
	ld a,b
	add a,a
	add a,$02
	ld b,a
	ld c,$09
	in a,(c)                    ; 4K window @E000: 8n+6
	ld a,b
	add a,a
	add a,$02
	ld b,a
	ld c,$08
	in a,(c)                    ; 2K window @F000: 16n+14
	pop bc
	pop af
	ret

; reset entry (0x0000 jumps here)
shim_reset:
	di
	im 1
	ld sp,BIOS_SP
	xor a
	ld (BIOS_STATE),a
	out ($0c),a
	out ($08),a                 ; enable NMI
	ei
bios_idle:
	jr bios_idle

; NMI entry (0x0066 jumps here).  BIOS-phase NMIs are recognised by where they
; interrupted: the shim's idle loop, or Z80 RAM (the MVS BIOS parks the Z80 in a RAM
; loop while it switches to the cartridge sound ROM).  Command 3 always resets.
shim_nmi:
	push af
	push hl
	in a,($00)
	cp $03
	jr z,bios_nmi
	ld hl,5
	add hl,sp
	ld a,(hl)                   ; high byte of the interrupted PC
	cp $f8
	jr nc,bios_nmi              ; in RAM
	cp bios_idle>>8
	jr nz,.game
	dec hl
	ld a,(hl)
	cp bios_idle&$ff
	jr z,bios_nmi
.game:	pop hl
	pop af
	push af                     ; the original handler's displaced instructions
	push bc
	push hl
	jp ORIG_NMI_CONT

bios_nmi:
	in a,($00)
	cp $01
	jr z,.slot
	cp $03
	jr z,.reset
	cp $55
	jr z,.arm
	cp $aa
	jr z,.start
.ack:	out ($0c),a
	xor a
	ld (BIOS_STATE),a
	pop hl
	pop af
	retn
.slot:	out ($0c),a
	pop hl
	pop af
	retn
.reset:	out ($0c),a
	pop hl
	pop af
	ld hl,shim_reset
	push hl
	retn
.arm:	out ($0c),a
	ld a,$55
	ld (BIOS_STATE),a
	pop hl
	pop af
	retn
.start:	out ($0c),a
	ld a,(BIOS_STATE)
	cp $55
	jr nz,.ack
	pop hl
	pop af
	ld hl,game_reset
	push hl
	retn

; the reset: the original power-on sequence, after the shim's own preamble
game_reset:
	di
	im 1
	ld sp,$0000
	; the MVS BIOS sound driver leaves YM2610 timers running with flags set; the
	; original board starts from a reset chip, so stop both timers and clear them
.ymb1:	in a,($04)
	bit 7,a
	jr nz,.ymb1
	ld a,$27
	out ($04),a
.ymb2:	in a,($04)
	bit 7,a
	jr nz,.ymb2
	ld a,$30
	out ($05),a
	xor a                       ; the original board resets its sound bank to 0
	call bank_switch
	; then the original's own sequence (its RAM clear, set-up calls and jump into its
	; main loop), copied from the user's sound ROM at build time (tools/z80patch.py)
	include "z80reset.inc"
