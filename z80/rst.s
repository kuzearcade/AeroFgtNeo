; RST handlers placed over the original reset code (0x0008-0x0037), which only ran
; once at power-on and is re-created by the shim.  Each replaces a 2-byte original
; instruction (RST + NOP) on the Neo Geo.

	org $0008
rst08:                          ; was OUT (C),A : YM2610 ports 0-3 -> 4-7
	push bc
	set 2,c
	out (c),a
	pop bc
	ret
	org $0010
rst10:                          ; was OUT (C),E
	push bc
	set 2,c
	out (c),e
	pop bc
	ret
	org $0018
rst18:                          ; was OUT (C),H
	push bc
	set 2,c
	out (c),h
	pop bc
	ret
	org $0020
rst20:                          ; was OUT (C),L
	push bc
	set 2,c
	out (c),l
	pop bc
	ret
	org $0028
rst28:                          ; was OUT ($04),A : 32K sound bank -> Neo windows
	jp bank_switch
	org $0030
rst30:                          ; was LD A,(HL) for the ADPCM-B address high bytes:
	ld a,(hl)                   ; ADPCM-B data sits 0x100000 into the shared V ROM
	add a,$10
	ret

bank_switch equ $7800
