; Neo Geo MVS hardware registers and BIOS entry points used by the HAL.

REG_P1CNT       equ $300000     ; byte read: P1 joystick/buttons, active low
REG_DIPSW       equ $300001     ; byte read: hardware DIP switches
REG_WATCHDOG    equ $300001     ; byte write: any value kicks the watchdog
REG_SOUND       equ $320000     ; byte write: command to Z80 / read: Z80 reply
REG_STATUS_A    equ $320001     ; byte read: coins/service, active low
REG_P2CNT       equ $340000     ; byte read: P2 joystick/buttons, active low
REG_STATUS_B    equ $380000     ; byte read: start/select, active low
REG_POUTPUT     equ $380001
REG_NOSHADOW    equ $3a0001
REG_SWPBIOS     equ $3a0003     ; use BIOS vector table
REG_BRDFIX      equ $3a000b     ; use BIOS fix tiles
REG_SRAMLOCK    equ $3a000d
REG_PALBANK1    equ $3a000f
REG_SHADOW      equ $3a0011
REG_SWPROM      equ $3a0013     ; use cartridge vector table
REG_CRTFIX      equ $3a001b     ; use cartridge fix tiles
REG_SRAMUNLOCK  equ $3a001d
REG_PALBANK0    equ $3a001f

REG_VRAMADDR    equ $3c0000
REG_VRAMRW      equ $3c0002
REG_VRAMMOD     equ $3c0004
REG_LSPCMODE    equ $3c0006
REG_TIMERHIGH   equ $3c0008
REG_TIMERLOW    equ $3c000a
REG_IRQACK      equ $3c000c
REG_TIMERSTOP   equ $3c000e

PALETTES        equ $400000
BACKDROP        equ $401ffe

; LSPCMODE timer control bits
TIMER_IRQ_EN    equ $0010
TIMER_LOAD_REL  equ $0020
TIMER_LOAD_VBL  equ $0040
TIMER_REPEAT    equ $0080
AUTOANIM_OFF    equ $0008

; IRQACK bits
ACK_IRQ3        equ $0001
ACK_TIMER       equ $0002
ACK_VBLANK      equ $0004

; VRAM layout
SCB1            equ $0000
FIXMAP          equ $7000
SCB2            equ $8000
SCB3            equ $8200
SCB4            equ $8400

; BIOS
BIOS_GAME_DIP       equ $10fd84
BIOS_USER_REQUEST   equ $10fdae
BIOS_USER_MODE      equ $10fdaf
SYSTEM_RETURN       equ $c00444
SYSTEM_INT1         equ $c00438

FRAME_PIXELS        equ 384*264     ; pixel clocks per frame (6 MHz)
VFRAME_PIXELS       equ 81553       ; original frame (163105.5 cycles @10MHz) in 6 MHz ticks
