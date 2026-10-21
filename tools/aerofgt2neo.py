#!/usr/bin/env python3
"""aerofgt.zip -> Neo Geo MVS cartridge set (aerofgtn).

  python3 -I tools/aerofgt2neo.py --aerofgt mame_roms/aerofgt.zip \
          --secref mame_roms/sonicwi3.zip --out out

builds the release (RELEASE_DIRECT, RELEASE_DEFS below) unless AEROFGT_DIRECT / AEROFGT_DEFS
are set in the environment.

Writes out/aerofgtn/*.p1/.s1/.m1/.v1/.c1/.c2 (a MAME-loadable directory set),
out/aerofgtn.zip and out/aerofgtn_driver.txt (ROM_START block with CRC/SHA1).
"""

import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

# The release build's video path and switches, used unless the environment defines its own:
# AEROFGT_DIRECT=0 with AEROFGT_DEFS= (empty) gives the plain build; any AEROFGT_DEFS, even an
# empty one, replaces the whole list.  Set before anything below reads them.
RELEASE_DIRECT = "1"
RELEASE_DEFS = ("FUSED=1,GX_XPRE=1,FZ_PD=1,GX_SCAN=1,FZ_TPL=1,FX_HOV=1,BG_HIDECLR=1,BG_SETSCR=1,"
                "UB_LOGO=1,BG_CUTCAP=1,BG_SCRRING=1,SPR_FLIPRES=1,FX_HOVCHG=1,GX_BAND=1,GX_CULLK=1,"
                "FZ_FASTR=1,FZ_EARLYB=1,FZ_OVF=2,FZ_OVFPB=1,FZ_HOLE=1,FZ_FLIPM=1")
os.environ.setdefault("AEROFGT_DIRECT", RELEASE_DIRECT)
os.environ.setdefault("AEROFGT_DEFS", RELEASE_DEFS)

import analyze68k  # noqa: E402
import memmap      # noqa: E402
import reloc       # noqa: E402
import romset      # noqa: E402
import z80patch    # noqa: E402
import gfx         # noqa: E402

VASM68K = os.path.join(ROOT, "third_party", "vasm", "vasmm68k_mot")
VASMZ80 = os.path.join(ROOT, "third_party", "vasm", "vasmz80_oldstyle")

NGH = 0x0538                # (unused by any Neo Geo title: the official list ends at NGH-272, and the
                            # Universe BIOS 4.0 game table has no 0x0538)
SND_SOAK = re.search(r"(^|,)\s*SND_SOAK\s*=\s*1\b", os.environ.get("AEROFGT_DEFS", "")) is not None
SOAK_AT = 0x0f0000          # (SND_SOAK, diagnostics) the replayed sound command stream, over the palette table (64 KB)
if SND_SOAK:
    memmap.SOUND_LATCH_NEO = 0xd00ec1   # the game's own sound writes go to the I/O mirror sink


def soak_stream():
    """(SND_SOAK) AEROFGT_SOAK (lines "<game frame> <command hex>") -> pairs (command, calls to
    wait after it), waits over 255 split with command-0 pairs, ended by (0, 0)."""
    ev = [(int(f), int(c, 16)) for f, c in (l.split() for l in open(os.environ["AEROFGT_SOAK"]) if l.strip())]
    out = bytearray()
    for i, (f, c) in enumerate(ev):
        d = ev[i + 1][0] - f if i + 1 < len(ev) else 120
        d = max(d, 1)
        first = True
        while d > 0:
            part = min(d, 255)
            out += bytes([c if first else 0, part])
            first = False; d -= part
    return bytes(out + b"\0\0")


BP_SHOTS = re.search(r"(^|,)\s*BP_SHOTS\s*=\s*1\b", os.environ.get("AEROFGT_DEFS", "")) is not None
SHOT_TYPES = ("000e", "000f", "0011", "0012", "0013", "0016", "0017")    # the player shot object types
if re.search(r"(^|,)\s*UB_LOGO\s*=\s*1\b", os.environ.get("AEROFGT_DEFS", "")):
    os.environ["AEROFGT_UBLOGO"] = "1"      # (gfx.build: the logo tiles; build_prom: the lookup tables)
HAL_BASE = 0x080000
P_SIZE = 0x100000
S_SIZE = 0x20000
M_SIZE = 0x20000
V_SIZE = 0x200000
C_SIZE = 0x1000000          # total sprite ROM (c1+c2 interleaved)
# P ROM tables for the real-cart video conversion (outside the original 512KB)
S_REMAP_AT = 0x0c8000       # 64KB: physical tile -> S tile / S_TRANSP / S_NONE (gfx.s_layout); a HAL
                            # that outgrows 0x80000-0xc8000 moves it and L0VAR up (build_prom, 4KB steps)
FZ_TPL_AT = 0x07b470        # (FZ_TPL) the free ROM after the game's, to 0x80000: hal/fz.s fz_rec's fast-record
                            # templates, 16 bytes a piece descriptor (hal/fz.s FZ_TPL_AT)
GXV_AT = 0x0dc800           # (GX_VEL) 14KB free below 0xe0000: hal/gx.s gx_vel's speed x direction products:
GXV_MAPN = 368              # a byte per |speed| 0..367 (its slot, 0xff none), then 32 x 8 bytes a slot
GXV_SPEEDS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 24, 25, 28, 32, 33, 36, 40, 41, 44, 48, 52, 53, 56, 60, 62, 64, 68, 69, 72, 76, 80, 84, 92, 96, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 144]  # the |speeds| seen (work/play/fh/gxhist.lua, 2026-10-18), others the original's way
L0VAR_AT = 0x0d8000         # 8KB: tilemap-0 pen-15 palette variant per block (gfx.py)
L0SVAR_AT = L0VAR_AT + 0x8000   # 8KB: the same per shifted block (hal/bg.s indexes both
                            # from one register: BLKS0_BASE - BLK0_BASE = 0x8000)
PALTAB_AT = 0x0f0000        # 64KB: xRGB555 -> Neo colour, rotated (gfx.neo_colour_table_rotated)
UNIVAR_AT = 0x0edf00        # 16 bytes: tilemap-0 pen-15 variant of the uniform blocks
BG_TRANSP_AT = 0x0da000     # 10KB: a bit per C tile, set if transparent (hal/tx.s)
HUD_STAB_AT = 0x0e4000      # 10KB: HUD sprite tile -> its four S tiles (gfx.hud_layout)
SOLIDPEN_AT = 0x0e8000      # 16KB: solid pen per physical tile, nibbles (gfx.solid_pen_table)
SOFTDIP_AT = 0x0ed000       # MVS soft DIP table (BIOS settings menu), < 0xf00 bytes

ORIG_RESET = 0x00045a
ORIG_IRQ = 0x000888
SECURITY_AT = 0x000200

# Original work RAM read by the HAL video code (original addresses; relocated below)
GAME_VARS = [
    ("G_PALFLAGS", 0xff8ac0),   # quarters the vblank handler copies (0x2bcd4)
    ("G_PALBUF", 0xff7800),     # RAM palette buffer, source of those copies
    ("G_PCPY_ON", 0xff9150),    # 16-entry copy pending, src/dst pointers
    ("G_PCPY_SRC", 0xff9148),
    ("G_PCPY_DST", 0xff914c),
    ("G_CYC_OFF", 0xff8aae),    # palette cycling (0x2a2de) state
    ("G_CYC_ON", 0xff922e),
    ("G_CYC_CNT", 0xff91aa),
    ("G_CYC_POS", 0xff91ac),
    ("G_CYC_SRC", 0xff91ae),
    ("G_CYC_DST", 0xff91ee),
    ("G_FLASH", 0xff9020),      # bit 1: tilemap-1 palettes filled white (0x1e922, 0x22624)
    ("G_PALETTE", 0x1a0000),
    ("G_VRAM0", 0x1b2000),      # tilemaps (64x64 words each)
    ("G_VRAM1", 0x1b4000),
    ("G_SCROLLX0", 0x1b0000),   # raster RAM word 0 / 0x200: x scroll (+18 / +20)
    ("G_SCROLLX1", 0x1b0400),
    ("G_GFXBANK", 0xffff80),    # 8 bytes: tile bank per (layer, code bits 11-12)
    ("G_SCROLLY0", 0xffff88),
    ("G_SCROLLY1", 0xffff90),
    ("G_HALSCRATCH", 0xfef000), # 4KB the game only touches in its boot RAM test/clear
    ("G_VBFLAG", 0xff8055),     # byte: vblank flag the idle loop waits on
    ("G_SPRBUF", 0xff9280),     # 2 x 0x16c0: converted sprite sets (a gap in the game's RAM
                                # map: no instruction addresses 0xff9266-0xffbfff, never touched)
    ("G_BGSTG", 0xff9880),      # 64 bytes: slot's staged column not copied to VRAM yet
    ("G_BGBUF", 0xff9900),      # 64 x 128 bytes: staged SCB1 column per slot (same gap)
    ("G_SLIPLOG", 0xffb900),    # 0x700 bytes: display slip log (hal/video.s; same gap)
    ("G_PALSTG", 0xffc280),     # 0x800 bytes: (DIRECT) palette stage (hal/video.s; the game
                                # never touches 0xffc280-0xffd35f: 5 runs incl. 3 whole
                                # playthroughs, work/ramuse, 2026-10-17)
    ("G_BXEX", 0xff98c0),       # 64 bytes (same gap): scratch of the builder replica (AEROFGT_BUILDX)
    ("G_BX923E", 0xff923e),     # the builder's attribute word ors (tools/gen_buildx.py)
    ("G_BX9240", 0xff9240),
    ("G_DX_LIST", 0xff6800),    # (AEROFGT_DIRECT: the sprite-list builder's own data, hal/dx.s)
    ("G_DX_BUF0", 0xff7000),
    ("G_DX_BUF1", 0xff7400),
    ("G_DX_CNT0", 0xff8d06),
    ("G_DX_CNT1", 0xff8d08),
    ("G_DX_PTR0", 0xff8d0a),
    ("G_DX_PTR1", 0xff8d0e),
    ("G_DX_LOCK", 0xff9236),
    ("G_DX_923E", 0xff923e),
    ("G_DX_9240", 0xff9240),
    ("G_DX_LPTR", 0xff9242),
    ("G_DX_90E6", 0xff90e6),
    ("G_DX_SCRY", 0xff8b4c),
    ("G_DX_SCRX", 0xff8b4a),
    ("G_DX_OBJ1", 0xff0000),
    ("G_DX_OBJ2", 0xff30c0),
    ("G_DX_OBJ3", 0xff42c0),
    ("G_DX_OBJ4", 0xff48c0),
    ("G_DX_OBJ5", 0xff60c0),
    ("G_SPRRAM", 0x1d0000),     # sprite list + attributes
    ("G_SPRLUT", 0x1c0000),     # sprite tile lookup
    ("G_TRAMP", 0xffec00),      # 48 bytes: idle-loop trampoline (deepest 1KB of the
                                # idle/handler stack, never reached; boot test/clear only)
]

# HAL work areas (Neo addresses); see tools/memmap.py for the map of the original RAM
HAL_SOFTDIP = 0xd00810      # 16 bytes copied from BIOS_GAME_DIP at takeover
HAL_STACK_TOP = 0xd00e00    # HAL stack grows down from here (0xd00c00-0xd00dff)
# HAL variables (backup RAM area the BIOS never touches)
HAL_VARS = [
    ("HAL_SAVED_SP", 0xd00820), ("HAL_MODE", 0xd00824), ("HAL_BOOT", 0xd00825),
    ("HAL_RBASE", 0xd00826), ("HAL_RBASE_NEXT", 0xd00828), ("HAL_CCR", 0xd0082a),
    ("HAL_RW_HI", 0xd0082c), ("HAL_RW_LO", 0xd0082e), ("HAL_PROBE_AT", 0xd00830),
    ("HAL_DW", 0xd00834), ("HAL_DW_NEXT", 0xd00838), ("HAL_DX", 0xd0083c),
    ("HAL_DRES", 0xd00840), ("HAL_DTNEXT", 0xd00844), ("HAL_XI", 0xd00848),
    ("HAL_XR", 0xd0084c), ("HAL_YLAST", 0xd00850), ("HAL_DYNEXT", 0xd00854),
    ("HAL_PHASE_ADJ", 0xd00858), ("HAL_FRAMES", 0xd0085c), ("HAL_FAULT", 0xd00860),
    ("HAL_LINE_AT_PROBE", 0xd00864),
    ("HAL_SLOWN", 0xd00868),        # long: held frames (DIRECT=1 slowdown, hal/sched.s)
    ("HAL_SCH_TIMN", 0xd0086c),     # long: slots the timer started (game still busy)
    ("HAL_SCH_EXT", 0xd00870),      # byte: this slot's held frames
    ("HAL_PALFIRST", 0xd00871),     # byte: (DIRECT=1) the palettes waited: split if they must now
    ("HAL_PALPART", 0xd00872),      # byte: (DIRECT=1) this commit's copy split (time checked each)
    ("HAL_PALSTT", 0xd00873),       # byte: (DIRECT=1) staging time-checked (1), ran out ($ff)
    ("HAL_GX_MISS", 0xd00874),      # long: (AEROFGT_GXCHECK) enemy slots the collision lists lacked
    ("HAL_SLOWB", 0xd00878),        # long: held for a conversion not begun in its slot (hal/sched.s)
    ("HAL_SPR_DELTAN", 0xd0087c),   # long: sprite sets updated in place (hal/dl.s)
    ("HAL_LOG", 0xd00880),      # 32 x 12 bytes
    ("HAL_JTAB", 0xd00a00),     # probe-2 table, up to 64 x 8 bytes
    ("HAL_JCLASS", 0xd00b40),   # 5 x 8 bytes: probe-2 class results
    # video conversion state (0xd00412-0xd007ff: backup RAM the BIOS never uses)
    ("HAL_DEADLINE", 0xd00420),     # HAL work budget in scanlines after the probe
    ("HAL_PROBE_VPOS", 0xd00432),   # vpos at the probe
    ("HAL_DBG_COMMIT", 0xd00434),   # vpos when the vblank work started (diagnostics)
    ("HAL_DBG_END", 0xd00436),      # vpos when it ended
    ("HAL_DBG_PREP", 0xd00438),     # vpos at prep start / after the prediction
    ("HAL_DBG_PRED", 0xd0043a),
    ("HAL_DBG_FIXMAX", 0xd0043c),   # longest fix-layer block (scanlines)
    ("HAL_DBG_ROWMAX", 0xd0043e),   # longest 8-row chunk incl. checked text blocks
    ("HAL_DBG_LASTOK", 0xd005c0),   # line counter (as HAL_KDL) + needed at the last passing deadline check
    ("HAL_DBG_LASTPC", 0xd005c4),   # and its caller
    ("HAL_DBG_T2", 0xd005c8),       # vpos after placing / after palettes
    ("HAL_DBG_T3", 0xd005ca),
    ("HAL_DBG_SCRUBN", 0xd006b0),   # columns verified (diagnostics)
    ("HAL_DBG_T4", 0xd005cc),       # vpos at the tilemap passes / after pass 1
    ("HAL_DBG_T5", 0xd005ce),
    ("HAL_FLASH_PREV", 0xd00422),
    ("HAL_SCRUB", 0xd00424),        # palette scrub position (word)
    ("HAL_PALMISS", 0xd00428),      # palettes found stale by the scrub (count)
    ("HAL_PALDEFER", 0xd0042c),     # frames whose palette work hit the deadline (count)
    ("HAL_SLIP", 0xd00430),         # this frame's display slip flags (bit 0: palette)
    ("HAL_PALDIRTY", 0xd00440),     # 64 bytes: original palette q needs converting
    # background layers (2 x 21 sprite columns)
    ("HAL_BG_SLOTCOL", 0xd00480),   # 2 x 32 bytes: block column shown by slot (0xff free)
    ("HAL_BG_COLSLOT", 0xd004c0),   # 2 x 32 bytes: slot showing block column (0xff none)
    ("HAL_BG_PEND", 0xd00500),      # 2 x 32 bytes: slot needs converting
    ("HAL_BG_C0", 0xd00540),        # 2 words: first visible block column
    ("HAL_BG_SX", 0xd00544),        # 2 words: x scroll last positioned
    ("HAL_BG_SY", 0xd00548),        # 2 words: y scroll last positioned
    ("HAL_BG_POS", 0xd0054c),       # 2 bytes: positions need rewriting
    ("HAL_BG_SCRUB", 0xd0054e),     # word: next slot to verify (0..63)
    ("HAL_BG_BURST", 0xd00550),     # word: frames of fast verification left
    ("HAL_FIXUSED", 0xd00552),      # word: fix layer holds tilemap-1 text
    ("HAL_FIXCLR", 0xd00554),       # word: next fix column to clear (40 = none)
    ("HAL_BG_HID", 0xd00556),       # 2 bytes: per layer, hidden after the game cleared it (BG_HIDECLR, hal/bg.s)
    ("HAL_BGMISS", 0xd00558),       # long: columns found stale by verification
    ("HAL_BGDEFER", 0xd0055c),      # long: frames whose tilemap work hit the deadline
    ("HAL_BGODD", 0xd00560),        # long: cells drawn approximately (no Neo equivalent)
    ("HAL_RESV", 0xd00564),         # word: scanlines hal_late_n keeps back (early work)
    ("HAL_BG_EARLY", 0xd00566),     # byte: early work (before the real vblank) running
    ("HAL_BG_P1", 0xd00567),        # byte: tilemap conversion of the rows in view only
    ("HAL_EARLY_ST", 0xd00568),     # word: early-work stage of this slot
    ("HAL_K0", 0xd0056a),           # word: (slot start vpos + 8) mod 264
    ("HAL_OUT", 0xd0056c),          # byte: a deadline check with no reserve failed
    ("HAL_BG_WORK", 0xd0056d),      # byte: a PEND/LOW flag may be set (cleared by a scan finding none)
    ("HAL_BG_R", 0xd0056e),         # 2 bytes: per layer, slot of the first column in the window
    ("HAL_SPR_CARRY", 0xd00570),    # long: sprite conversions carried over to the next slot
    ("HAL_BG_ROW", 0xd00580),       # 2 x 32 bytes: block row a stopped conversion resumes at
    ("HAL_BG_APX", 0xd005d0),       # 2 x 32 bytes: the slot's column shows approximated cells
    ("HAL_BG_SUB", 0xd007e8),       # 4 words: tile base per bank select (conversion), then
                                    # 4 words uniform tile, 4 bytes tilemap-0 uniform variant
    ("HAL_SCRH", 0xd00610),         # 3 x 8 bytes: the scroll (sx0, sy0, sx1, sy1) of this slot and the two before (BG_SETSCR, hal/bg.s)
    ("HAL_BG_CAPN", 0xd00628),      # byte: (BG_CUTCAP) columns of a cleared layer still to convert under the cap
    ("HAL_BG_CAPS", 0xd00629),      # byte: converted under the cap this slot
    ("HAL_BG_CAPF", 0xd0062a),      # word: the slot of HAL_BG_CAPS
    ("HAL_SCRI", 0xd0062c),         # byte: (BG_SCRRING) HAL_SCRH's current entry
    ("HAL_BG_R0", 0xd00630),        # 2 x 32 bytes: first block row of the conversion
    ("HAL_BG_LOW", 0xd00670),       # 2 x 32 bytes: rows out of view still to convert
    # idle-loop harvesting (hal/idle.s)
    ("HAL_TPH", 0xd006c0),          # long: raster phase of this frame's chain expiry T, - kappa
    ("HAL_CAL", 0xd006c4),          # byte: HAL_TPH is calibrated (idle entries harvested)
    ("HAL_TPH_DIRTY", 0xd006c5),    # byte: a late wake put HAL_TPH off by 0 mod 30: recalibrate
    ("HAL_IDLE_SR", 0xd006c6),      # word: SR at the idle entry (CCR of the idle loop)
    ("HAL_TLINE", 0xd006c8),        # word: vpos of T (phase lock)
    ("HAL_IDLE_L", 0xd006ca),       # word: vernier line
    ("HAL_IDLES", 0xd006cc),        # long: harvested idle entries (diagnostics)
    ("HAL_IDLE_D", 0xd006d0),       # long: last T - E (diagnostics)
    ("HAL_IDLE_U", 0xd006d4),       # long: last U - T
    ("HAL_TIMW", 0xd006d8),         # 2 words: counter load for the re-anchored wake
    ("HAL_VCAL", 0xd006dc),         # long: calibrated HAL_TPH (diagnostics)
    ("HAL_DTN_CLASS", 0xd006e0),    # 5 longs: T_next - T per probe-2 class
    ("HAL_IDLE_I", 0xd006f4),       # word: vernier polling turns
    ("HAL_IDLE_ACC", 0xd006f6),     # word: vernier fine offset
    ("HAL_IDLE_J", 0xd006f8),       # long: last probe-2 table offset read back
    ("HAL_VCAL_I", 0xd006fc),       # long: calibration vernier polling turns
    ("HAL_BG_BANK", 0xd00700),      # 2 x 4 bytes: tile banks the layers were converted with
    ("HAL_BG_SAMP", 0xd00708),      # word: next visible block row sample (hal_bg_sample)
    ("HAL_BG_RETROP", 0xd0070a),    # byte: a stale find awaits its slip flag (commit)
    ("HAL_BG_RETROF", 0xd0070c),    # word: first slot (HAL_FRAMES) of the last logged stale range
    ("HAL_BG_RETRON", 0xd00710),    # long: stale ranges logged (slips)
    ("HAL_BG_SAMPF", 0xd00720),     # 60 words: slot each sample (half row) was last found right
    ("HAL_BG_STGF", 0xd007a0),     # 2 x 32 bytes: first block row staged (G_BGSTG = how many)
    ("HAL_BG_CS", 0xd007e0),       # word: block row a column conversion call started at
    ("HAL_BG_CD", 0xd007e2),       # byte: rows done before it
    ("HAL_SPR_PRIN", 0xd007fc),    # long: shown sets with sprites behind tilemap 1 put in front
    # MiSTer timing model (free backup RAM 0xd00f60..)
    ("HAL_SCH_BUSY", 0xd00f44),     # byte: (hal/sched.s) the slot began with the game busy (timer)
    ("HAL_SCH_YLD", 0xd00f45),      # byte: the slot yielded to the game; resumes at HAL_SCH_RES
    ("HAL_SCH_RES", 0xd00f46),      # long: where the yielded slot goes on
    ("HAL_SCH_YN", 0xd00f4a),       # long: yields (diagnostics)
    ("HAL_RWB_HI", 0xd00f60), ("HAL_RWB_LO", 0xd00f62),    # reload after probe 1b: wake W
    ("HAL_P1PC", 0xd00f64),        # long: probe-1 stacked PC
    ("HAL_P1BVS", 0xd00f68),       # long: probe-1b vector start - BASE
    ("HAL_P2PC", 0xd00f6c),        # long: probe-2 stacked PC
    ("HAL_TLOAD", 0xd00f70),       # long: counter load for T_next (probe 2b)
    ("HAL_TRES", 0xd00f74),        # word: T_next's residue (y_next mod 10)
    ("HAL_P2BPC", 0xd00f76),       # long: last probe-2b stacked PC (copied before the slot's calls)
    ("HAL_MISTER", 0xd00f80),      # byte: timing model, set by hal_detect at boot (0 MAME, $ff MiSTer)
    ("HAL_MPROBE", 0xd00f81),      # byte: the model's probe mode
    ("HAL_MWAKE", 0xd00f82),       # byte: the model's wake mode
    ("HAL_DET_N", 0xd00f83),       # byte: hal_detect state; then its MiSTer votes
    ("HAL_DET_L", 0xd00f84),       # 4 words: latency estimate per hal_detect trial
    ("HAL_RELOFS", 0xd00f8c),      # long: LOAD_REL expiry delay of the model (0 / RELOFS)
    ("HAL_BG_APXN", 0xd00fa0),     # word: slots flagged in HAL_BG_APX (a tilemap slip while > 0)
    ("HAL_BG_APXF", 0xd00fa4),     # long: frames shown with approximated tilemap cells
    ("HAL_BG_SKIP", 0xd00fa8),     # byte: hal_bg_sample left a slot out (the row is not "checked")
    ("HAL_DWR", 0xd00f90),         # long: HAL_DW - HAL_RELOFS (the idle path's counter load)
    ("HAL_BG_KSTOP", 0xd007e4),    # word: line counter (as HAL_KDL) the column stops at
    # sprites (hal/spr.s)
    ("HAL_SPR_ST", 0xd00b68),       # 3 bytes: per set: 0 free, 1 complete, 2 converting, 3 shown
    ("HAL_SPR_MIX", 0xd00b6c),      # 3 bytes: per set: bit 0 its conversion spanned slots, bit 1 sprites dropped, bit 2 vertical zoom
    ("HAL_SPR_RDY", 0xd00b70),      # 3 words: per set: first slot (HAL_FRAMES) it may be shown in
    ("HAL_SPR_MIXN", 0xd00b78),     # long: sets shown that mix two frames' lists (slips)
    ("HAL_SPR_VZN", 0xd00b7c),      # long: sets shown with vertically zoomed sprites (approximated: slips)
    ("HAL_SPR_E", 0xd00b80),        # 24 bytes: scratch
    ("HAL_SPR_W", 0xd00b98),        # word: sprite set being converted (-1: none)
    ("HAL_SPR_DONE", 0xd00b9a),     # byte: this slot's list conversion started
    ("HAL_SPR_SHOWN", 0xd00b9c),    # word: sprite set shown (-1: none)
    ("HAL_SPR_DROP", 0xd00ba0),     # long: sprites dropped (no Neo sprites/buffer left)
    ("HAL_SPR_LATE", 0xd00ba4),     # long: sprite sets not shown in time (slips)
    ("HAL_SPR_RES", 0xd00ba8),      # word: scanlines the conversion leaves to the rest
    ("HAL_SPR_DBGI", 0xd00baa),     # word: conversions restarted from the ring's top (diagnostics)
    ("HAL_SPR_DBGD", 0xd00bac),     # word: deferred uploads
    ("HAL_KDL", 0xd00bae),          # word: HAL_K0R + HAL_DEADLINE
    ("HAL_SPR_TAILU", 0xd00bb0),    # word: credit (16-cycle units) kept back for the work after a stop
    ("HAL_SPR_ZOOM", 0xd00bb4),     # long: horizontally zoomed sprites converted
    ("HAL_K0R", 0xd00bb8),          # word: line counter (>> 7) at the slot's start
    ("HAL_SPR_KER", 0xd00bba),      # word: line counter (>> 7, +264 past the wrap) the conversion stops at
    ("HAL_JFALL", 0xd00bbc),        # long: probe-2 table offset/4 of a valid class (late wakes)
    ("HAL_LATEWAKE", 0xd00bc0),     # long: late wakes (slot ran past W)
    ("HAL_FAULTCODE", 0xd00bc4),    # word: which check stopped the HAL (diagnostics)
    ("HAL_DX_MEAS", 0xd00bc8),      # long: X - T as measured by the probe (calibration)
    ("HAL_SPR_VOK", 0xd00bcc),      # byte: VRAM holds the last uploaded sprite buffer
    ("HAL_SPR_SAME", 0xd00bd0),     # long: sprite records whose tiles were already there
    ("HAL_CALS", 0xd00bd4),         # long: calibrations of T's phase (diagnostics)
    ("HAL_CALNOW", 0xd00bd8),       # byte: this probe ran the calibration vernier
    ("HAL_JFALL_PC", 0xd00bdc),     # long: sled position of the late-wake class
    ("HAL_OVERRUN", 0xd00be0),      # long: slots that ended too close to W
    ("HAL_DBG_INP", 0xd00be4),      # word: vpos when the inputs were read
    ("HAL_DBG_OVRPC", 0xd00be8),    # long: last passing deadline check of the last overrun
    ("HAL_DBG_OVRLN", 0xd00bec),    # word: ... and its HAL_DBG_LASTOK
    ("HAL_SPR_WPTR", 0xd00bf0),     # long: state of set HAL_SPR_W (hal_spr_go)
    ("HAL_SPR_RA5", 0xd00bf4),      # long: its list position
    ("HAL_SPR_DROPN", 0xd00bf8),    # long: sets shown with sprites dropped (slips)
    # sprite column ring (hal/spr.s; free backup RAM 0xd00fac..0xd00fef, which the game's
    # boot RAM test does not touch, unlike the set states at G_SPRBUF)
    ("HAL_SPR_GNEXT", 0xd00fac),    # word: column below the newest set's last one (next start)
    ("HAL_SPR_ORDN", 0xd00fae),     # byte: sets in the ring
    ("HAL_SPR_ORD", 0xd00faf),      # 3 bytes: the ring's sets, oldest first
    ("HAL_SPR_BLK", 0xd00fb2),      # byte: the conversion waits for columns
    ("HAL_SPR_INQ", 0xd00fb3),      # 3 bytes: per set: in the ring (not reclaimed yet)
    ("HAL_SPR_START", 0xd00fba),    # 3 words: per set: the column above its first one
    ("HAL_SPR_RCLN", 0xd00fc0),     # long: sets reclaimed (diagnostics)
    ("HAL_SPR_BLKN", 0xd00fc4),     # long: conversions that waited for columns
    ("HAL_SPR_END", 0xd00fcc),      # 3 words: per set: its lowest column (its last head)
    ("HAL_SPR_PREV", 0xd00fd2),     # word: columns the last complete set took
    ("HAL_SPR_LEND", 0xd00fd4),     # long: the list end the set being converted started at
    ("HAL_SPR_RST", 0xd00fd8),      # 3 bytes: per set: restarted from the ring's top
    ("HAL_SPR_BEGG", 0xd00fdc),     # word: HAL_SPR_GNEXT when the set being converted began
    ("HAL_SPR_SPS", 0xd00fde),      # byte: the set split into a top and a bottom run ($ff: none)
    ("HAL_SPR_SPJ", 0xd00fe0),      # word: its top run's lowest column
    ("HAL_SPR_SPG", 0xd00fe2),      # word: the column above its bottom run (kept height 0)
    ("RING_TOP", 0xd00fe4),         # word: (DIRECT) the column above the ring's top (SPR_PT + 1, or
                                    # the bullet pool's lowest column while it has the top)
    ("RING_PT", 0xd00fe6),          # word: the ring's highest column it owns (SPR_PT, or below the
                                    # pool once the pool's columns are its own)
    ("RING_S3T", 0xd00fe8),         # word: SCB3 + RING_PT
    ("RING_TPM", 0xd00f96),         # word: RING_TOP - 1 (where sets may start: the pool wanted)
    ("BP_ST", 0xd00fea),            # byte: (DIRECT) bullet pool: 0 off, 1 wanted, 2 on, 3 to be off
    ("BP_INIT", 0xd00feb),          # byte: (DIRECT) the pool's columns are its own (written)
]


def run(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        raise SystemExit("command failed: %s" % " ".join(cmd))
    return r.stdout


def load_data_pointer_list():
    """ROM data longs classified as pointers (analysis/data_pointers.txt)."""
    path = os.path.join(ROOT, "analysis", "data_pointers.txt")
    out = set()
    if os.path.exists(path):
        for line in open(path):
            line = line.split("#")[0].strip()
            if line:
                out.add(int(line.split()[0], 16))
    return out


def load_code_seeds():
    """Executed instruction starts (MAME coverage) + entries recovered from ROM pointer
    tables (tools/recover_code.py: code the coverage runs never reached)."""
    seeds = []
    for name in ("code_seeds.txt", "code_seeds_static.txt"):
        path = os.path.join(ROOT, "analysis", name)
        if not os.path.exists(path):
            continue
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    seeds.append(int(line, 16))
    return seeds


def sr_map(v):
    """Original IPL 0 -> 1 so the Neo vblank (level 1) stays masked; the virtual vblank is
    the LSPC timer on level 2, which plays the role of the original IRQ1."""
    if (v >> 8) & 7 == 0:
        return v | 0x0100
    return v


def build_prom(regions, security, build_dir, log, assist=False):
    global S_REMAP_AT, L0VAR_AT
    rom = bytes(regions["maincpu"])
    prog = analyze68k.Program(rom, load_code_seeds())
    if prog.errors:
        raise SystemExit("code discovery hit undecodable bytes: %r" % prog.errors[:5])
    patches, review = reloc.collect(rom, prog.ins, sr_map=sr_map)
    patches = override_io_writes(prog, patches)
    patches += reloc.collect_data_pointers(rom, prog.ins, patches, only=load_data_pointer_list())
    log.write("relocation patches: %d\n" % len(patches))
    for p in patches:
        log.write("  %r\n" % p)
    log.write("review items: %d\n" % len(review))
    for r in review:
        log.write("  %s\n" % r)
    patched = reloc.apply(rom, patches)
    patch_idle_loop(patched)

    # layout.inc for the HAL (written again when the HAL moves the video tables)
    def write_layout():
        with open(os.path.join(build_dir, "layout.inc"), "w") as f:
            f.write("; generated by tools/aerofgt2neo.py\n")
            for name, val in [("HAL_BASE", HAL_BASE), ("ORIG_RESET", ORIG_RESET), ("ORIG_IRQ", ORIG_IRQ),
                              ("IO_MIRROR", memmap.IO_MIRROR), ("HAL_SOFTDIP", HAL_SOFTDIP),
                              ("HAL_STACK_TOP", HAL_STACK_TOP),
                              ("L0VAR", L0VAR_AT), ("PALTAB_MID", PALTAB_AT + 0x8000)] + HAL_VARS + \
                    [(n, memmap.map_addr(a)) for n, a in GAME_VARS]:
                f.write("%-16s equ $%06x\n" % (name, val))
            for name, val in [("NPAL_L0", gfx.NPAL_L0), ("NPAL_L1", gfx.NPAL_L1), ("NPAL_SPR", gfx.NPAL_SPR),
                              ("BLK0_BASE", gfx.BLK0_BASE), ("BLK1_BASE", gfx.BLK1_BASE),
                              ("UNI0_BASE", gfx.UNI0_BASE), ("UNI1_BASE", gfx.UNI1_BASE),
                              ("BLANK_TILE", gfx.C_TILES_USED), ("UNIVAR", UNIVAR_AT),
                              ("S_REMAP", S_REMAP_AT), ("S_TRANSP", gfx.S_TRANSP), ("GXV_AT", GXV_AT), ("GXV_MAPN", GXV_MAPN),
                              ("HUD_STAB", HUD_STAB_AT), ("HUD_T0", gfx.HUD_T0), ("HUD_TN", gfx.HUD_TN),
                              ("BG_TRANSP", BG_TRANSP_AT),
                              ("SOLIDPEN", SOLIDPEN_AT), ("SOLID_BASE", gfx.SOLID_BASE),
                              ("BLKS0_BASE", gfx.BLKS0_BASE), ("BLKS1_BASE", gfx.BLKS1_BASE)] + \
                    [("L0_SLOT%d" % (i + 1), pen + 1) for i, pen in enumerate(gfx.L0_REMAP_PENS)]:
                f.write("%-16s equ %d\n" % (name, val))
        write_timing_inc(os.path.join(build_dir, "timing.inc"))
        softdip_inc(os.path.join(build_dir, "dips.inc"))
        with open(os.path.join(build_dir, "variant.inc"), "w") as f:
            f.write("ASSIST           equ %d\n" % (1 if assist else 0))
            f.write("DIAGBUILD        equ %d\n" % int(os.environ.get("AEROFGT_DIAG", "0")))
            f.write("DIAG_FAULTAT     equ %d\n" % int(os.environ.get("AEROFGT_DIAG_FAULTAT", "0")))
            f.write("DIAGLAB          equ %d\n" % int(os.environ.get("AEROFGT_DIAGLAB", "0")))
            # timing model: 0 detected at boot, 1 MAME's, 2 the MiSTer core's
            f.write("HAL_FORCE        equ %d\n" % int(os.environ.get("AEROFGT_TIMING", "0")))
            f.write("BOOT_SYNC_LINE   equ %d\n" % int(os.environ.get("AEROFGT_SYNCLINE", "0x1a8"), 0))
            f.write("ASSIST_SNAPSHOT  equ $2fffc0\n")
            f.write("BUILDX           equ %d\n" % (0 if assist else int(os.environ.get("AEROFGT_BUILDX", "0"))))
            f.write("SPR_RETAIN       equ %d\n" % (0 if assist else int(os.environ.get("AEROFGT_RETAIN", "0"))))
            f.write("DIRECT           equ %d\n" % (0 if assist else int(os.environ.get("AEROFGT_DIRECT", "0"))))
            f.write("GX_VERIFY        equ %d\n" % int(os.environ.get("AEROFGT_GXCHECK", "0")))
            # hal/gx.s gx_cull (GX_CULLK): the cull rect at 0x2b326 (y0, x0, y1, x1) ^ $8000
            for i in range(4):
                f.write("GXC_R%d          equ $%04x\n" % (i, int.from_bytes(patched[0x2b326 + 2 * i:0x2b328 + 2 * i], "big") ^ 0x8000))
            f.write("FX_DIAG          equ %d\n" % int(os.environ.get("AEROFGT_FXDIAG", "0")))
            f.write("NOEXPL           equ %d\n" % (0 if assist else int(os.environ.get("AEROFGT_NOEXPL", "0"))))
            if "AEROFGT_FXDELAY" in os.environ:
                f.write("FX_DELAY         equ %d\n" % int(os.environ["AEROFGT_FXDELAY"]))
            if "AEROFGT_FXHUD" in os.environ:
                f.write("FX_HUDON         equ %d\n" % int(os.environ["AEROFGT_FXHUD"]))
            # experiments: AEROFGT_DEFS="NAME=value,..." (constants the sources default with ifnd)
            for d in filter(None, os.environ.get("AEROFGT_DEFS", "").split(",")):
                name, val = d.split("=")
                f.write("%-16s equ %s\n" % (name.strip(), val.strip()))
        run([sys.executable, os.path.join(ROOT, "tools", "gen_sprfast.py"), os.path.join(build_dir, "sprfast.inc")])
        with open(os.path.join(build_dir, "fxb.inc"), "w") as f:
            # hal/fx.s fxb_obj: per pair-bullet table (0x52e4e + 0x1c k) its entry's w2, w3
            f.write("; generated by tools/aerofgt2neo.py: pair bullets' w2, w3 per table\nfxb_k:\n")
            for t in range(0x52e4e, 0x52e4e + 4 * 0x1c, 0x1c):
                d = int.from_bytes(patched[t:t + 4], "big")
                mp = int.from_bytes(patched[d + 2:d + 4], "big") if d + 4 <= len(patched) else 0
                f.write("\tdc.w    $%04x,$%04x\n" % ((((patched[t + 12] & 15) | 0x30) << 8) | 0x80, mp | 0x2000))
        run([sys.executable, os.path.join(ROOT, "tools", "gen_buildx.py"), os.path.join(build_dir, "buildx.inc")])
        # hal/gx.s gx_vel (GX_VEL): obj_move_dir_speed's products, speed x the direction table
        # at 0x2b976 (32 x (dy, dx) words), speeds -GXV_MAX..GXV_MAX, as its two muls.w give them;
        # a binary at GXV_AT (the free ROM between the transparency and HUD tables)
        dirs = [(int.from_bytes(patched[0x2b976 + 4 * d:0x2b976 + 4 * d + 2], "big", signed=True),
                 int.from_bytes(patched[0x2b976 + 4 * d + 2:0x2b976 + 4 * d + 4], "big", signed=True)) for d in range(32)]
        gxmap = bytearray(b"\xff" * GXV_MAPN)
        for i, sp in enumerate(GXV_SPEEDS):
            gxmap[sp] = i
        gxvel = bytes(gxmap) + b"".join(struct.pack(">ll", sp * dy, sp * dx) for sp in GXV_SPEEDS for dy, dx in dirs)
        assert len(gxvel) <= 0xe0000 - GXV_AT, "velocity table room"
    write_layout()
    gx_vel_on = re.search(r"(^|,)\s*GX_VEL\s*=\s*1\b", os.environ.get("AEROFGT_DEFS", "")) is not None
    fz_pd = (not assist and os.environ.get("AEROFGT_DIRECT", "0") == "1"
             and re.search(r"(^|,)\s*FUSED\s*=\s*1\b", os.environ.get("AEROFGT_DEFS", "")) is not None
             and re.search(r"(^|,)\s*FZ_PD\s*=\s*1\b", os.environ.get("AEROFGT_DEFS", "")) is not None)
    fz_tpl = fz_pd and re.search(r"(^|,)\s*FZ_TPL\s*=\s*1\b", os.environ.get("AEROFGT_DEFS", "")) is not None
    pd_edits, pd_tpl = fz_pd_prepare(patched, build_dir, fz_tpl) if fz_pd else ({}, {})
    if os.environ.get("AEROFGT_UBLOGO", "0") == "1":
        relocate_plane_tiles(patched, log)
    hal_bin = os.path.join(build_dir, "hal_assist.bin" if assist else "hal.bin")
    def assemble():
        run([VASM68K, "-quiet", "-m68000", "-Fbin", "-no-opt", "-I", os.path.join(ROOT, "hal"), "-I", build_dir,
             "-L", os.path.join(build_dir, "hal_assist.lst" if assist else "hal.lst"), "-o", hal_bin, os.path.join(ROOT, "hal", "hal.s")])
        return open(hal_bin, "rb").read()
    hal = assemble()
    if HAL_BASE + len(hal) > S_REMAP_AT:
        # (2026-10-19) the HAL outgrew its 288KB: S_REMAP and L0VAR move up in 4KB steps (room to GXV_AT),
        # the layout written again, the HAL assembled again (its size does not depend on the addresses)
        shift = -(-(HAL_BASE + len(hal) - S_REMAP_AT) // 0x1000) * 0x1000
        S_REMAP_AT += shift
        L0VAR_AT += shift
        if L0VAR_AT + 0x2000 > GXV_AT:
            raise SystemExit("HAL too large: %d bytes past the video tables, no room to move them" % (HAL_BASE + len(hal) - 0x0c8000))
        msg = "HAL %d bytes: the video tables moved up by 0x%x (S_REMAP at 0x%x, L0VAR at 0x%x)" % (len(hal), shift, S_REMAP_AT, L0VAR_AT)
        print(msg)
        log.write(msg + "\n")
        write_layout()
        hal = assemble()

    p = bytearray(b"\xff" * P_SIZE)
    p[0:len(patched)] = patched
    if not assist and os.environ.get("AEROFGT_DIRECT", "0") == "1":
        # not cycle-exact: no sprite-list builder (0x2bee0: on at its end's clr.w lock,
        # 0x2bfaa), no list copy (0xa14: rts); hal/fx.s reads the objects
        assert p[0x2bee0:0x2bee2] == b"\x2c\x7c" and p[0x2bfaa:0x2bfac] == b"\x42\x79", "builder moved"
        assert p[0xa14:0xa16] == b"\x24\x7c", "list copy moved"
        bld = 0x2bfaa
        fm = re.search(r"(^|,)\s*FUSED\s*=\s*([12])\b", os.environ.get("AEROFGT_DEFS", ""))
        if fm:
            # hal/fz.s: the object half (FUSED=1) or the whole conversion (FUSED=2) at the
            # builder's point (AUDIT.md 24)
            lst = open(os.path.join(build_dir, "hal.lst")).read()
            name = "fz_build" if fm.group(2) == "1" else "fz_gt"
            m = re.search(r"^([0-9A-F]{8}) %s$" % name, lst, re.M)
            assert m, name + " not in the listing"
            bld = int(m.group(1), 16)
        p[0x2bee0:0x2bee6] = b"\x4e\xf9" + struct.pack(">I", bld)
        if fm and fm.group(2) == "2":
            # FUSED=2 shows a set 2 - FZ_SHOW frames before the arcade's sprite buffering
            # would: the handler's scroll registers (0x8e0/0x8f6/0x910/0x926, from 0xff9256..)
            # read the FIFO that many stages fresher (0xff924e.., or the game's own 0xff8ca8..)
            # so sprites and tilemaps stay aligned
            sm = re.search(r"(^|,)\s*FZ_SHOW\s*=\s*([01])\b", os.environ.get("AEROFGT_DEFS", ""))
            show = int(sm.group(2)) if sm else 1
            for i, at in enumerate((0x8e5, 0x8fb, 0x915, 0x92b)):
                assert p[at - 5:at - 3] == b"\x30\x39" and p[at - 1] == 0xa2 and p[at] == 0x56 + 2 * i, "scroll FIFO moved"
                if show == 1:
                    p[at] = 0x4e + 2 * i
                else:
                    p[at - 1] = 0x9c
                    p[at] = 0xa8 + 2 * i
        p[0xa14:0xa16] = b"\x4e\x75"
        # ... and the busy wait before it (0x9ce: move.w #$ff,D7 / dbra D7,*: ~2.6k cycles
        # a frame for the original's sprite copy; D7 is restored by the handler's movem)
        assert p[0x9ce:0x9d6].hex() == "3e3c00ff51cffffe", "vblank wait moved"
        p[0x9ce:0x9d0] = b"\x60\x06"
        # hal/gx.s: the main object loop and the collision scan, faster
        lst = open(os.path.join(build_dir, "hal.lst")).read()
        sym = lambda n: int(re.search(r"^([0-9A-F]{8}) %s$" % n, lst, re.M).group(1), 16)
        for at, old, name in ((0x1996a, "207c001010c0", "gx_upd"), (0x199a0, "d0fc0060b1fc", "gx_updn"),
                              (0x2a18c, "101202400031", "gx_col"), (0x2a1b0, "d4fc006051cf", "gx_coln"),
                              (0x2a088, "101202400031", "gx_col2"), (0x2a0ac, "d4fc006051cf", "gx_col2n"),
                              # hal/tm.s: the tilemap writers mark what they change
                              (0x2c924, "544036c05540", "tm_blk1"), (0x5e0c, "544036c05540", "tm_blk2"),
                              (0x1254, "267c00d02000", "tm_clr0"), (0x125e, "267c00d04000", "tm_clr1"),
                              (0x81c8, "48e73fe02079", "tm_fill")):
            assert p[at:at + 6].hex() == old, "game loop moved: %x" % at
            if name == "tm_fill":
                assert p[0x81ce:0x81d2].hex() == "00109cd6", "fill pointer moved"
            p[at:at + 6] = b"\x4e\xf9" + struct.pack(">I", sym(name))
        if re.search(r"(^|,)\s*GX_SCAN\s*=\s*1\b", os.environ.get("AEROFGT_DEFS", "")):
            # hal/gx.s gx_scan: shot_collide (0x2a142) with the shot's x bounds hoisted
            assert p[0x2a142:0x2a148].hex() == "267c00050858", "shot_collide moved"
            assert p[0x2a166:0x2a16c].hex() == "247c001019c0" and p[0x2a182:0x2a188].hex() == "247c001052c0", "pool scans moved"
            p[0x2a142:0x2a148] = b"\x4e\xf9" + struct.pack(">I", sym("gx_scan"))
        if re.search(r"(^|,)\s*GX_CULLK\s*=\s*1\b", os.environ.get("AEROFGT_DEFS", "")):
            # hal/gx.s gx_cull: obj_cull_outside_rect's entry with the ROM rect (lea, nop)
            assert p[0x2b2d4:0x2b2da].hex() == "45fa00504e71", "cull entry moved"
            p[0x2b2d4:0x2b2da] = b"\x4e\xf9" + struct.pack(">I", sym("gx_cull"))
        if SND_SOAK:
            # hal/soak.s (diagnostics): the game's sound sender (0x103c, once a frame from its
            # vblank handler) replays the recorded stream instead
            assert p[0x103c:0x103e].hex() == "41f9", "sound sender moved"
            p[0x103c:0x1042] = b"\x4e\xf9" + struct.pack(">I", sym("snd_soak"))
        if re.search(r"(^|,)\s*GX_VEL\s*=\s*1\b", os.environ.get("AEROFGT_DEFS", "")):
            # hal/gx.s gx_vel: obj_move_dir_speed's velocity products from a table
            assert p[0x2b950:0x2b956].hex() == "4a406700001c", "velocity routine moved"
            p[0x2b950:0x2b956] = b"\x4e\xf9" + struct.pack(">I", sym("gx_vel"))
        # hal/fx.s fxb_obj: the pair bullets' tables (4 at 0x52e4e, 0x1c apart): two
        # pieces of one def (a 32x16, one row), dy/dx -16/-16 turned (flips 3), 0/-16 plain
        w16 = lambda a: (p[a] << 8) | p[a + 1]
        l32 = lambda a: (w16(a) << 16) | w16(a + 2)
        for t in range(0x52e4e, 0x52e4e + 4 * 0x1c, 0x1c):
            d0, d1 = l32(t), l32(t + 14)
            ok = (d0 == d1 and d0 < 0x80000 and not d0 & 1 and p[d0] == 0 and p[d0 + 1] == 2
                  and w16(t + 4) == 0xfff0 and w16(t + 6) == 0xfff0 and w16(t + 18) == 0 and w16(t + 20) == 0xfff0
                  and bytes(p[t + 8:t + 12]) == b"\x01\x01\x00\x00" and bytes(p[t + 22:t + 26]) == b"\x00\x00\x00\x00"
                  and p[t + 12] == p[t + 26] and ((w16(d0 + 2) | 0x2000) & 0x3fff) <= 0x3ffe)
            assert ok, "pair bullet table moved: %x" % t
        if fz_pd:
            if fz_tpl:
                # hal/fz.s FZ_TPL: a 16-byte template per piece descriptor at FZ_TPL_AT (the
                # one-piece tables' entries first, then the others while the room lasts),
                # its index in the descriptor's first word, bits 0-12: +0 l spr_fast_jt's
                # entry for the piece's sizes and zoom, in front, no flips (fz_rec .fz's
                # index), +4 w y, +6 w x, +8 l colour | flips << 24 | map, +12 w w0's high
                # byte << 8 | w1's, +14 w w1's << 8.  Not for a HUD piece, nor an entry
                # sharing bytes with another table's (its first word is that one's +12/+13)
                jt = sym("spr_fast_jt")
                # the room is short of the eligible entries: work/catalog/sprites/tpl_rank.txt
                # ("<descriptor hex> <one-piece records>", work/play/fh/tplhist.lua over four
                # nations x 30k frames) ranks the ones seen drawn one-piece first, the rest by
                # the one-piece tables then address
                rank = {}
                rf = os.path.join(ROOT, "work", "catalog", "sprites", "tpl_rank.txt")
                if os.path.exists(rf):
                    for l in open(rf):
                        f = l.split()
                        if len(f) >= 2 and not l.startswith("#"): rank[int(f[0], 16)] = int(f[1])
                order = sorted(pd_tpl, key=lambda e: (-rank.get(e, 0), not pd_tpl[e][4], e))
                room = (0x80000 - FZ_TPL_AT) // 16 - 1
                chosen = order[:room]
                blob = bytearray()
                for i, e in enumerate(chosen):
                    hi0, hi1, pb, mp, one = pd_tpl[e]
                    idx = i + 1
                    assert idx < 0x2000 and pd_edits[e][1] == 0
                    pd_edits[e][0] |= idx >> 8
                    pd_edits[e][1] = idx & 0xff
                    zoom = 2048 if (hi0 | hi1) & 0xf0 else 0
                    blob += struct.pack(">I", jt + 0x100 + zoom + ((hi0 & 0xe) << 4) + ((hi1 & 0xe) << 1))
                    blob += bytes(p[e + 4:e + 8])
                    blob += struct.pack(">IHH", (pb << 24) | mp, (hi0 << 8) | hi1, hi1 << 8)
                assert all(b == 0xff for b in p[FZ_TPL_AT:FZ_TPL_AT + 16 + len(blob)]), "template room taken"
                p[FZ_TPL_AT + 16:FZ_TPL_AT + 16 + len(blob)] = blob
                print("piece templates: %d of %d eligible (%d of one-piece tables, %d ranked of %d), %d bytes at %x" % (
                    len(chosen), len(pd_tpl), sum(1 for e in chosen if pd_tpl[e][4]), sum(1 for e in chosen if e in rank),
                    sum(1 for e in rank if e in pd_tpl), len(blob), FZ_TPL_AT))
            for a, b in pd_edits.items():
                p[a:a + len(b)] = b
            # the lookup RAM loader (as hal/rs.s rs_lutld): the HUD cache's generation
            assert p[0x2bbca:0x2bbd0].hex() == "247c00d06000" and p[0x2bbda:0x2bbdc].hex() == "24dc", "lookup loader moved"
            p[0x2bbca:0x2bbd0] = b"\x4e\xb9" + struct.pack(">I", sym("fz_lutld"))
            # and the HUD refresh (0x192be: the bombs, lives and score entries written straight
            # into the lookup RAM): its first call goes through fz_hudrf
            assert p[0x192c6:0x192cc].hex() == "4eb90002a63e", "HUD refresh moved"
            p[0x192c6:0x192cc] = b"\x4e\xb9" + struct.pack(">I", sym("fz_hudrf"))
        if re.search(r"(^|,)\s*RES\s*=\s*1\b", os.environ.get("AEROFGT_DEFS", "")):
            # hal/rs.s: the lookup RAM loader (movea.l #lookup,a2 before its copy loop)
            # tells the resident sprites their tiles may be old
            assert p[0x2bbca:0x2bbd0].hex() == "247c00d06000" and p[0x2bbda:0x2bbdc].hex() == "24dc", \
                "lookup loader moved"
            p[0x2bbca:0x2bbd0] = b"\x4e\xb9" + struct.pack(">I", sym("rs_lutld"))
        if os.environ.get("AEROFGT_NOEXPL", "0") != "0":
            # test: no explosions (object types 0x09, 0x20: handler table 0x199ba)
            for t, old_h in ((0x09, 0x1ca10), (0x20, 0x1ac2a)):
                at = 0x199ba + 4 * t
                assert struct.unpack(">I", bytes(p[at:at + 4]))[0] == old_h, "explosion handler moved"
                p[at:at + 4] = struct.pack(">I", sym("gx_noexpl"))
    elif not assist and os.environ.get("AEROFGT_DIRECT", "0") != "0":
        # not cycle-exact: the sprite-list builder (0x2bee0..0x2bf9a) -> dx_build (hal/dx.s)
        lst = open(os.path.join(build_dir, "hal.lst")).read()
        m = re.search(r"^([0-9A-F]{8}) dx_build$", lst, re.M)
        assert m and p[0x2bee0:0x2bee2] == b"\x2c\x7c", "builder moved"
        p[0x2bee0:0x2bee6] = b"\x4e\xf9" + struct.pack(">I", int(m.group(1), 16))
        if os.environ.get("AEROFGT_DIRECT") == "2":
            # check build: the original builder's end -> dx_check (tst.w lock is 6 bytes too)
            m = re.search(r"^([0-9A-F]{8}) dx_check$", lst, re.M)
            assert m and p[0x2bf9a:0x2bf9c] == b"\x4a\x79", "builder end moved"
            p[0x2bf9a:0x2bfa0] = b"\x4e\xf9" + struct.pack(">I", int(m.group(1), 16))
    if not assist and os.environ.get("AEROFGT_BUILDX", "0") != "0":
        # the builder's first instruction (movea.l #$ff6800,a6, 12 cycles) -> jmp bx_entry (12)
        lst = open(os.path.join(build_dir, "hal.lst")).read()
        m = re.search(r"^([0-9A-F]{8}) bx_entry$", lst, re.M)
        assert m and p[0x2bee0:0x2bee2] == b"\x2c\x7c", "builder moved"
        p[0x2bee0:0x2bee6] = b"\x4e\xf9" + struct.pack(">I", int(m.group(1), 16))
    if len(hal) > P_SIZE - HAL_BASE:
        raise SystemExit("HAL too large")
    p[HAL_BASE:HAL_BASE + len(hal)] = hal
    if HAL_BASE + len(hal) > S_REMAP_AT:
        raise SystemExit("HAL overlaps the video tables")
    p[S_REMAP_AT:S_REMAP_AT + 0x10000] = gfx.s_layout(gfx._unpack_tiles8(regions["tiles"]))[1]
    if not assist and os.environ.get("AEROFGT_DIRECT", "0") == "1":
        # hal/fx.s: the HUD on the fix layer (its S tiles: gfx.build, same condition)
        t8 = gfx._unpack_tiles8(regions["tiles"])
        spr = gfx._unpack_sprites(regions["sprites"])
        assert gfx.hud_blank0(spr), "sprite tile 0 not transparent (hal/fx.s: HUD cells)"
        hud_tab = gfx.hud_layout(t8, spr)[1]
        assert L0SVAR_AT + 0x2000 <= HUD_STAB_AT and HUD_STAB_AT + len(hud_tab) <= SOFTDIP_AT
        p[HUD_STAB_AT:HUD_STAB_AT + len(hud_tab)] = hud_tab
        tt = gfx.transparent_tiles(regions)        # hal/tx.s
        assert BG_TRANSP_AT + len(tt) <= L0SVAR_AT
        p[BG_TRANSP_AT:BG_TRANSP_AT + len(tt)] = tt
        sp = gfx.solid_pen_table(regions)          # hal/bg.s
        assert HUD_STAB_AT + len(hud_tab) <= SOLIDPEN_AT and SOLIDPEN_AT + len(sp) <= SOFTDIP_AT
        p[SOLIDPEN_AT:SOLIDPEN_AT + len(sp)] = sp
    p[L0VAR_AT:L0VAR_AT + 0x2000] = gfx.l0_variant_table(regions)
    p[L0SVAR_AT:L0SVAR_AT + 0x2000] = gfx.l0s_variant_table(regions)
    p[UNIVAR_AT:UNIVAR_AT + 0x10] = gfx.uni_variant_table(regions)
    p[PALTAB_AT:PALTAB_AT + 0x10000] = gfx.neo_colour_table_rotated()
    if SND_SOAK:
        st = soak_stream()
        assert len(st) <= 0x10000, "soak stream room: %d bytes" % len(st)
        p[SOAK_AT:SOAK_AT + 0x10000] = st + bytes(0x10000 - len(st))   # (the palette table gone: wrong colours)
        print("SND_SOAK: %d stream bytes at 0x%x" % (len(st), SOAK_AT))
    if gx_vel_on and not assist:
        # (after every other table: the room must still be free)
        assert all(b == 0xff for b in p[GXV_AT:GXV_AT + len(gxvel)]), "velocity table room taken"
        p[GXV_AT:GXV_AT + len(gxvel)] = gxvel

    # ---- vector table: keep the original exception vectors, take over reset/IRQs
    vec = list(struct.unpack(">64I", bytes(rom[:256])))
    # vec[0]/vec[1] (SSP/reset) keep the original values: the Neo always resets through
    # the BIOS vector table, and the game reads the start of ROM as data through a
    # null object pointer (0x29efe), so these bytes must match the original.
    vec[24] = 0x00c00426                # spurious
    vec[25] = HAL_BASE + 0x06           # level 1: Neo vblank
    vec[26] = HAL_BASE + 0x0c           # level 2: Neo timer
    vec[27] = 0x00c00426                # level 3: BIOS
    p[0:256] = struct.pack(">64I", *vec)

    # ---- cartridge header ($100-$1ff is unused 0xff fill in the original program)
    assert all(b == 0xff for b in rom[0x100:0x400]), "header area not free"
    h = bytearray(b"\xff" * 0x100)
    h[0x00:0x08] = b"NEO-GEO\x00"
    struct.pack_into(">H", h, 0x08, NGH)
    struct.pack_into(">I", h, 0x0a, P_SIZE)
    struct.pack_into(">I", h, 0x0e, 0x0010f000)     # backup data pointer (unused, size 0)
    struct.pack_into(">H", h, 0x12, 0)
    h[0x14] = 2                                     # no eye-catcher
    h[0x15] = 0
    for off in (0x16, 0x1a, 0x1e):                  # soft DIP table (Japan, USA, Europe)
        struct.pack_into(">I", h, off, SOFTDIP_AT)
    for i, ent in enumerate((0x00, 0x12, 0x18, 0x1e)):     # USER, PLAYER_START, DEMO_END, COIN_SOUND
        struct.pack_into(">HI", h, 0x22 + i * 6, 0x4ef9, HAL_BASE + ent)
    struct.pack_into(">I", h, 0x82, SECURITY_AT)
    p[0x100:0x200] = h
    p[SECURITY_AT:SECURITY_AT + len(security)] = security
    t = softdip_table()
    assert len(t) <= 0xf00 and all(b == 0xff for b in p[SOFTDIP_AT:SOFTDIP_AT + len(t)])
    p[SOFTDIP_AT:SOFTDIP_AT + len(t)] = t
    return p


def patch_idle_loop(p):
    """Send the idle loop (0xb84 cmpi.b #1,$ff8055 / bcs) through a RAM trampoline.

    The bcs at 0xb8c now branches to 0xbd0 (task 0's entry slot: task 0 is the idle
    context and is never started; only the boot ROM read pass touches it), which holds
    jmp (-$400,a7): a7 is always the idle stack top fff000 there, so this lands on
    G_TRAMP.  The HAL keeps either `jmp $b8c.w' there (the loop period stays 30 cycles,
    boundaries map back to the original ones) or its idle entry (hal/idle.s).
    """
    assert p[0xb8c:0xb8e] == b"\x65\xf6", "idle loop moved"
    assert p[0xbd0:0xbd4] == b"\x00\x00\x00\x00", "task 0 entry slot not empty"
    p[0xb8d] = 0xbd0 - 0xb8e
    p[0xbd0:0xbd4] = bytes.fromhex("4eef fc00")      # jmp (-$400,a7)


def load_calibration():
    cal = {}
    with open(os.path.join(ROOT, "analysis", "timing_cal.txt")) as f:
        for line in f:
            line = line.split("#")[0].strip()
            if line:
                k, v = line.split("=")
                cal[k.strip()] = int(v.strip(), 0)
    return cal


def first_odd_at_or_above(num, den):
    """Timer schedule for the vblank at time num/den: first odd cycle >= floor(x), minus 2.

    Fitted against MAME cycle traces of both machines (tests/irq_fit.py and
    tests/neo_irq_fit.py); post-IACK instruction boundaries are on odd cycles.
    """
    i = num // den
    return (i if i & 1 else i + 1) - 2


def write_timing_inc(path):
    """Timing constants: original vblank schedule, boot constants, calibration."""
    cal = load_calibration()
    p_as = int(1e18 / 61.31)                 # MAME HZ_TO_ATTOSECONDS(61.31) for aerofgt
    cyc_as = 10 ** 11                        # 10 MHz cycle
    g = 250
    p_int, p_rem = divmod(p_as, cyc_as)
    assert p_rem % g == 0 and cyc_as % g == 0
    k_next = cal["BOOT_K_NEXT"]
    e_first = cal["BOOT_E_FIRST"]
    y = lambda k: first_odd_at_or_above(k * p_as, cyc_as)
    xi, xr = divmod((k_next + 1) * p_as, cyc_as)
    q1 = cal["Q1"]
    boot_x_est = cal["C5"] + (e_first - 34)          # boot entry, relative to tau_s
    base = boot_x_est - cal["BOOT_BASE_LEAD"]        # first chain expiry (relative to tau_s)
    sync_to_base = (base - cal["W_OFF"]) & ~1
    base = sync_to_base + cal["W_OFF"]
    c2p = cal["C2P_RAW"] + 4 * cal["WAKE_PAD4"] + 6 * cal["WAKE_PAD6"]
    assert c2p % 10 == 0, "probe-2 -> handler path must be a multiple of 10 cycles (got %d)" % c2p
    q2, c_s2 = cal["Q2"], cal["C_S2"]
    # tau_w - W is the STOP wake latency, 40..70 cycles when the slot ended in time
    # (measured: probe 2 then lands at j2 94..96).  Anything else means the wake was
    # taken late and probe 2 may be Q2 multiples late: outside the table, it takes
    # hal_p2late (exact resume, T's phase recalibrated).
    jmin = (q2 + 7 - 70 - c_s2) // 4
    jmax = (q2 + 7 - 40 - c_s2) // 4
    ntab = jmax - jmin + 1
    assert 0 < jmin and ntab <= 40      # HAL_JTAB must end below HAL_JCLASS
    consts = {
        "Q1": q1, "Q2": q2, "SLED_NOPS": cal["SLED_NOPS"], "C_S": cal["C_S"], "C_S2": c_s2,
        "K0": cal["K0"], "C_L": cal["C_L"], "W_IN": cal["W_IN"], "C2P": c2p,
        "WAKE_PAD4": cal["WAKE_PAD4"], "WAKE_PAD6": cal["WAKE_PAD6"],
        "WAKE_EXTRA": q2 + c2p + 60, "JMIN": jmin, "NTAB": ntab,
        "LAT1": cal["LAT1"], "LAT3": cal["LAT3"], "LAT5": cal["LAT5"], "LAT7": cal["LAT7"], "LAT9": cal["LAT9"],
        "FRAME_CYCLES": 202752,
        "PHASE_LINE": cal["PHASE_LINE"],
        "P_INT": p_int, "P_FRAC": p_rem // g, "P_MOD": cyc_as // g,
        "X_INIT_INT": xi, "X_INIT_REM": (xr // g),
        "Y_INIT": y(k_next + 1) & 0xffffffff, "DY_INIT": y(k_next + 1) - y(k_next),
        "BOOT_YNEXT_MINUS_E": y(k_next) - e_first,
        "SYNC_TO_BASE": sync_to_base,
        "BOOT_RBASE": (5 + base) % 10,
        "BOOT_PROBE_AT": q1,
        "BOOT_DW": q1 + cal["BOOT_RW"],
    }
    with open(path, "w") as f:
        f.write("; generated by tools/aerofgt2neo.py from analysis/timing_cal.txt\n")
        for k, v in consts.items():
            f.write("%-20s equ %d\n" % (k, v))


# The original's DIP switches as MVS soft DIPs (BIOS settings menu): (name, default,
# [(choice, DSW1 bits, DSW2 bits)]), MAME's aerofgt settings.  The BIOS keeps the chosen
# index per option at BIOS_GAME_DIP + 6 + n; hal_dips (hal/hal.s) ORs the bits of each
# chosen setting into SOFTDIP_BASE.  Not offered: flip screen (not converted) and the
# service mode switch (the Neo has its own test switch): both off.
COINS = ["3 COINS/1 CR", "2 COINS/1 CR", "1 COIN/1 CR", "1 COIN/2 CR",
         "1 COIN/3 CR", "1 COIN/4 CR", "1 COIN/5 CR", "1 COIN/6 CR"]
SOFTDIPS = [
    ("COIN SLOT", 0, [("SAME", 0x01, 0), ("INDIVIDUAL", 0x00, 0)]),
    ("COIN A", 2, [(c, v << 1, 0) for c, v in zip(COINS, (5, 6, 7, 4, 3, 2, 1, 0))]),
    ("COIN B", 2, [(c, v << 4, 0) for c, v in zip(COINS, (5, 6, 7, 4, 3, 2, 1, 0))]),
    ("START COIN", 0, [("1 COIN", 0x80, 0), ("2 COINS", 0x00, 0)]),
    ("DEMO SOUNDS", 0, [("ON", 0, 0x00), ("OFF", 0, 0x02)]),
    ("DIFFICULTY", 1, [("EASY", 0, 0x08), ("NORMAL", 0, 0x0c), ("HARD", 0, 0x04), ("HARDEST", 0, 0x00)]),
    ("LIVES", 2, [("1", 0, 0x20), ("2", 0, 0x10), ("3", 0, 0x30), ("4", 0, 0x00)]),
    ("BONUS LIFE", 0, [("200000", 0, 0x40), ("300000", 0, 0x00)]),
]
if os.environ.get("AEROFGT_UBLOGO", "0") == "1":
    # (UB_LOGO, 2026-10-19) the Universe BIOS 4.0 makes a game's settings entry with every option at its
    # first choice, not at the table's default nibble (the stock BIOS and it both hand the game the
    # table's defaults until the soft DIP page is first opened; from then on the entry rules): the
    # default choice goes first, so a page never visited and a page left untouched mean the same game.
    SOFTDIPS = [(name, 0, ch[dflt:] + ch[:dflt]) for name, dflt, ch in SOFTDIPS]
SOFTDIP_BASE = (0x00, 0x81)     # DSW1, DSW2 with every offered field 0: flip off, service off


def _dip_str(s):
    assert len(s) <= 12 and s == s.upper()
    return s.ljust(12).encode("ascii")


def softdip_table():
    """MVS soft DIP block: 16-char name, two time and two count settings (unused), 10
    option bytes (default << 4 | choices), then per option its name and its choices,
    12 characters each."""
    assert len(SOFTDIPS) <= 10
    t = bytearray(b"AERO FIGHTERS   ")
    t += b"\xff\xff\xff\xff"          # time settings 1/2: unused
    t += b"\xff\xff"                  # count settings 1/2: unused
    opts = bytearray(10)
    for n, (_name, dflt, ch) in enumerate(SOFTDIPS):
        assert 2 <= len(ch) <= 15 and dflt < len(ch)
        opts[n] = dflt << 4 | len(ch)
    t += opts
    for name, _dflt, ch in SOFTDIPS:
        t += _dip_str(name)
        for c, _d1, _d2 in ch:
            t += _dip_str(c)
    return bytes(t)


def softdip_inc(path):
    """hal_dipdata for hal_dips: option count, then per option choices, default and
    (DSW1, DSW2) bits per choice."""
    lines = ["; generated by tools/aerofgt2neo.py (SOFTDIPS)",
             "SOFTDIP_BASE1    equ $%02x" % SOFTDIP_BASE[0], "SOFTDIP_BASE2    equ $%02x" % SOFTDIP_BASE[1],
             "hal_dipdata:", "\tdc.b    %d" % len(SOFTDIPS)]
    for name, dflt, ch in SOFTDIPS:
        lines.append("\tdc.b    %d,%d%s     ; %s" % (len(ch), dflt, "".join(",$%02x,$%02x" % (d1, d2) for _c, d1, d2 in ch), name))
    lines.append("\teven")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


LOOKUP_STAGES_AT = 0x3b174      # the game's stage table (0x2bbb4): 16 bytes a stage, +8 the lookup
LOOKUP_STAGES = 10              # RAM's first half (sprite tiles < 0x4000), +12 its second (>= 0x4000)


def relocate_plane_tiles(p, log):
    """(UB_LOGO) The player-plane tiles 0..0x39 referenced by the stages' lookup tables move to
    gfx.LOGO_RELOC..: every word < 0x3a of each stage's first-half lookup table (its extent: to
    the next table the stage table points at) is offset.  Only the loader at 0x2bbda writes
    tiles below 0x40 into the lookup RAM (luttap.lua, the attract and 20k frames of play); the
    second halves hold tiles >= 0x4000 only."""
    ptrs = set()
    firsts = []
    for i in range(LOOKUP_STAGES):
        e = LOOKUP_STAGES_AT + 16 * i
        q = [struct.unpack(">I", p[e + k:e + k + 4])[0] for k in (0, 4, 8, 12)]
        assert all(x < 0x80000 for x in q), "stage table moved"
        ptrs.update(q)
        firsts.append(q[2])
    ptrs = sorted(ptrs)
    n = 0
    for t in sorted(set(firsts)):
        end = ptrs[ptrs.index(t) + 1]
        for a in range(t, end, 2):
            v = struct.unpack(">H", p[a:a + 2])[0]
            if v < gfx.LOGO_TILES:
                struct.pack_into(">H", p, a, v + gfx.LOGO_RELOC)
                n += 1
    log.write("UB_LOGO: %d lookup entries moved to tiles 0x%x.. in %d tables\n" % (n, gfx.LOGO_RELOC, len(set(firsts))))
    print("UB_LOGO: %d lookup entries of the planes moved to tiles 0x%x..%x" % (n, gfx.LOGO_RELOC, gfx.LOGO_RELOC + gfx.LOGO_TILES - 1))


def override_io_writes(prog, patches):
    """Writes to VS9209 port G (watchdog clock) go straight to the Neo watchdog register."""
    out = []
    for pt in patches:
        if pt.kind == "absl" and pt.old & 0xffffff == 0xffffad:
            ins = prog.ins.get(_instr_start(prog, pt.addr))
            is_write = ins is not None and ins.op in ("move", "clr", "st", "sf", "bset", "bclr", "bchg") \
                and ins.operands[-1].kind == 8 and ins.operands[-1].value & 0xffffff == 0xffffad
            if is_write and ins.op == "move":
                pt = reloc.Patch(pt.addr, 4, pt.old, 0x300001, "absl", pt.where + " [watchdog]")
            elif is_write:
                raise SystemExit("unexpected read-modify-write of port G at %06x" % ins.addr)
        out.append(pt)
    return out


def _instr_start(prog, byte_addr):
    for a in range(byte_addr & ~1, max(0, byte_addr - 10), -2):
        i = prog.ins.get(a)
        if i is not None and a + i.length > byte_addr:
            return a
    return None


def build_mrom(regions, build_dir, log):
    m = z80patch.patch(regions["audiocpu"], build_dir, log)
    assert len(m) == M_SIZE
    return m


def build_vrom(regions):
    v = bytearray(V_SIZE)
    v[0:0x100000] = regions["adpcma"]
    v[0x100000:0x140000] = regions["adpcmb"]
    return v


def build_gfx(regions, build_dir, log):
    c1, c2, s, info = gfx.build(regions, C_SIZE, S_SIZE, log)
    with open(os.path.join(build_dir, "l0_variant.bin"), "wb") as f:
        f.write(info["l0_variant"])
    log.write("gfx: S ROM %d tiles used; shifted blocks: C tiles 0x%x-0x%x\n"
              % (info["s_used"], gfx.BLKS1_BASE, gfx.C_TILES_END))
    return c1, c2, s


def swap16(b):
    o = bytearray(len(b))
    o[0::2] = b[1::2]
    o[1::2] = b[0::2]
    return o


HEXFONT = ["01110 10001 10011 10101 11001 10001 01110", "00100 01100 00100 00100 00100 00100 01110",
           "01110 10001 00001 00110 01000 10000 11111", "11110 00001 00001 01110 00001 00001 11110",
           "00010 00110 01010 10010 11111 00010 00010", "11111 10000 11110 00001 00001 10001 01110",
           "00110 01000 10000 11110 10001 10001 01110", "11111 00001 00010 00100 01000 01000 01000",
           "01110 10001 10001 01110 10001 10001 01110", "01110 10001 10001 01111 00001 00010 01100",
           "01110 10001 10001 11111 10001 10001 10001", "11110 10001 10001 11110 10001 10001 11110",
           "01110 10001 10000 10000 10000 10001 01110", "11110 10001 10001 10001 10001 10001 11110",
           "11111 10000 10000 11110 10000 10000 11111", "11111 10000 10000 11110 10000 10000 10000"]


def diag_font(s):
    """Diagnostic builds: S tiles 0xff0-0xfff = hex digits 0-F (pen 1), for hal/diag.s."""
    import numpy as np
    t = np.zeros((16, 8, 8), np.uint8)
    for d, rows in enumerate(HEXFONT):
        for y, r in enumerate(rows.split()):
            for x, c in enumerate(r):
                t[d, y, x + 1] = 1 if c == "1" else 0
    s = bytearray(s)
    s[0xff0 * 32:0x1000 * 32] = bytes(gfx.encode_s(t).astype(np.uint8))
    return bytes(s)


def write_set(outdir, files, name="aerofgtn"):
    setdir = os.path.join(outdir, name)
    os.makedirs(setdir, exist_ok=True)
    zpath = os.path.join(outdir, name + ".zip")
    lines = []
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for fname, data in files:
            with open(os.path.join(setdir, fname), "wb") as f:
                f.write(data)
            z.writestr(fname, bytes(data))
            lines.append((fname, len(data), zlib.crc32(data) & 0xffffffff, hashlib.sha1(data).hexdigest()))
    with open(os.path.join(outdir, name + "_driver.txt"), "w") as f:
        for fname, size, crc, sha in lines:
            f.write("%-12s size %07x CRC(%08x) SHA1(%s)\n" % (fname, size, crc, sha))
    return lines



def shot_tables():
    """(BP_SHOTS) the tables of the player shot object types (work/catalog/sprites/objects.json: by type, and
    the nation entries typed)."""
    j = json.load(open(os.path.join(ROOT, "work", "catalog", "sprites", "objects.json")))
    s = set()
    for key, es in j.items():
        for e in es:
            if e.get("type", key) in SHOT_TYPES:
                s.add(e["table"])
    return s


def fz_pd_prepare(rom, build_dir, tpl=False):
    """hal/fz.s FZPD (FZ_PD): the catalogue's piece entries as descriptors (the game reads
    only an entry's first word: sentinels $ffff/$fffe, a sign test) - the byte edits to apply
    after every check that reads the original tables - and the HUD tables' slot masks
    (build/fzhud.inc, before the assembly).  tpl (hal/fz.s FZ_TPL): the descriptor flags at
    bits 14 (a descriptor) and 13 (a HUD piece) of the first word, bits 0-12 its template's
    index (0 none; the pointer's high byte dropped)."""
    shot_tabs = shot_tables() if BP_SHOTS else set()
    npool = [0]
    import json
    w16 = lambda a: (rom[a] << 8) | rom[a + 1]
    l32 = lambda a: (w16(a) << 16) | w16(a + 2)
    tabs = {}; nation_tabs = set()
    for key, lst in json.load(open(os.path.join(ROOT, "work", "catalog", "sprites", "objects.json"))).items():
        for t in lst:
            tabs[t["table"]] = max(tabs.get(t["table"], 0), t["pieces"])
            if key == "nations": nation_tabs.add(t["table"])    # (work/play/fh/tabmerge.py: the other
                                                                # nations' tables, a census, unchecked)
    if os.environ.get("AEROFGT_NATTAB", "1") == "0":            # (the catalogue as before the census)
        for t in nation_tabs: tabs.pop(t, None)
        nation_tabs = set()
    if os.environ.get("AEROFGT_NATKEEP"):                       # (a file of hex tables: the census tables kept)
        keep = set(int(x, 16) for x in open(os.environ["AEROFGT_NATKEEP"]).read().split())
        for t in [t for t in nation_tabs if t not in keep]: tabs.pop(t, None); nation_tabs.discard(t)

    def hud_slot(m):            # hal/fx.s fx_hud_slot, m = map | 0x2000
        if m > 0x24ec: return (m >> 3) & 7
        if m == 0x24ec: return 10
        if m >= 0x24e2: return 12
        if m == 0x24dd: return 11
        if m == 0x24d7: return 9
        return 8
    # entries of different tables that overlap (the ROM packs some 14-byte entries 12 bytes
    # apart: a descriptor's +12/+13 would land on the next table's pointer): the census tables
    # among them are left raw; the catalogue's own may not overlap (2026-10-19, fz43 froze the
    # coast/river stage on every nation)
    rng = sorted((t + 14 * i, t + 14 * i + 14, t) for t, n in tabs.items() for i in range(n))
    overlap = set()
    for (a0, a1, ta), (b0, b1, tb) in zip(rng, rng[1:]):
        if b0 < a1 and ta != tb: overlap.add(ta); overlap.add(tb)
    bad = sorted(t for t in overlap if t not in nation_tabs)
    if bad:     # (the catalogue's own overlaps are as they were in every build since fz27: kept)
        print("catalogue tables overlapping (kept): %d, e.g. %s" % (len(bad), ", ".join("%x" % t for t in bad[:6])))
    skipped = sorted(t for t in overlap if t in nation_tabs)
    for t in skipped: tabs.pop(t, None)
    edits = {}; desc = {}; tpls = {}
    for t, n in tabs.items():
        tedits = {}; tdesc = {}; ttpl = {}; ok = True
        if t in nation_tabs and any(w16(t + 14 * i) >= 8 for i in range(n)):
            skipped.append(t); continue        # (a census table with a sentinel-like entry inside its
                                                # piece count: the raw path reads that entry's "pointer"
                                                # as it is, a descriptor path would not - left raw)
        for i in range(n):
            e = t + 14 * i
            if e in desc or e in tdesc or w16(e) >= 8:
                continue                        # (a table reached twice; a sentinel entry)
            g = l32(e)
            if not (g < 0x80000 and g + 4 <= len(rom)):
                ok = False; break
            b0, b1, mp = rom[g], rom[g + 1], w16(g + 2)
            zy, zx = rom[e + 10] & 15, rom[e + 11] & 15
            if not (mp < 0x4000 and (b0 >> 4) & zy == 0 and (b1 >> 4) & zx == 0):
                ok = False; break               # (a header the descriptor cannot hold)
            m = mp | 0x2000
            hud = (0x24e2 <= m <= 0x24ec) or m in (0x24cf, 0x24d7, 0x24dd) or (m & 0x3fc0) == 0x3fc0
            fl = ((rom[e + 8] & 1) << 7) | ((rom[e + 9] & 3) << 6)
            tdesc[e] = (hud, hud_slot(m))
            if not hud:                         # (FZ_TPL: w0's and w1's high bytes, the colour | flips
                ttpl[e] = (b0 | (zy << 4), b1 | (zx << 4), (rom[e + 12] & 15) | fl, mp, n == 1)   # byte, the map)
            tedits[e] = bytearray(struct.pack(">HH", 0x4000 if tpl else w16(e) | 0x0100, mp | (0x8000 if hud else 0)))
            if BP_SHOTS and tpl and not hud and n == 1 and t in shot_tabs and zy == 0 and zx == 0 \
                    and ((b0 >> 1) & 7) <= 1 and ((b1 >> 1) & 7) <= 1:
                tedits[e][0] |= 0x10               # (BP_SHOTS: a poolable shot piece - bit 12; hal/fz.s fz_pshot)
                npool[0] += 1
            tedits[e + 8] = bytearray(struct.pack(">HHBB", ((b0 | (zy << 4)) << 8) | b0, ((b1 | (zx << 4)) << 8) | b1, (rom[e + 12] & 15) | fl, 0))
        if not ok:
            assert t in nation_tabs, "not a piece / piece header: table %x" % t
            skipped.append(t); continue        # (a census table the descriptors cannot take: left raw)
        edits.update(tedits); desc.update(tdesc); tpls.update(ttpl)
    # (FZ_TPL) no template for a descriptor sharing bytes with another descriptor (the ROM packs
    # some entries 12 bytes apart: one's first word is the other's +12/+13, whichever edit won);
    # a sentinel entry of another table over it makes no edit and is no clash
    ds = sorted(desc)
    for a, b in zip(ds, ds[1:]):
        if b - a < 14: tpls.pop(a, None); tpls.pop(b, None)
    # HUD pieces (the lookup range): flagged (bit 1), their slot at +13 (hal/fz.s FZPD \\5)
    nh = 0
    for e, (hud, slot) in desc.items():
        if hud:
            edits[e][0] |= 0x20 if tpl else 0x02
            edits[e + 8][5] = slot
            nh += 1
    print("piece descriptors: %d entries of %d tables; HUD pieces %d; census tables left raw %d" % (len(desc), len(tabs) - len(skipped), nh, len(skipped)))
    if os.environ.get("AEROFGT_PDLIST"):        # (the bytes rewritten, per entry, for work/play/fh/romhits.lua)
        with open(os.environ["AEROFGT_PDLIST"], "w") as f:
            for e in sorted(desc):
                t = max(x for x in tabs if x <= e)
                f.write("%x %x %s\n" % (e, t, "n" if t in nation_tabs else "c"))
    if BP_SHOTS:
        print("BP_SHOTS: %d poolable shot descriptors (bit 12)" % npool[0])
    return edits, tpls


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--aerofgt", default=os.path.join(ROOT, "mame_roms", "aerofgt.zip"))
    ap.add_argument("--secref", default=os.path.join(ROOT, "mame_roms", "sonicwi3.zip"),
                    help="any Neo Geo MVS set you own; its BIOS security block is reused")
    ap.add_argument("--out", default=os.path.join(ROOT, "out"))
    args = ap.parse_args()

    build_dir = os.path.join(args.out, "build")
    os.makedirs(build_dir, exist_ok=True)
    regions = romset.load_aerofgt(args.aerofgt)
    security = romset.load_security_code(args.secref)
    with open(os.path.join(build_dir, "build.log"), "w") as log:
        p = build_prom(regions, security, build_dir, log)
    with open(os.path.join(build_dir, "build_z80.log"), "w") as log:
        m = build_mrom(regions, build_dir, log)
    v = build_vrom(regions)
    with open(os.path.join(build_dir, "build_gfx.log"), "w") as log:
        c1, c2, s = build_gfx(regions, build_dir, log)
    if os.environ.get("AEROFGT_DIAG", "0") != "0":
        s = diag_font(s)
    files = [("538-p1.p1", swap16(p)), ("538-s1.s1", s), ("538-m1.m1", m), ("538-v1.v1", v),
             ("538-c1.c1", c1), ("538-c2.c2", c2)]
    for name, size, crc, sha in write_set(args.out, files):
        print("%-12s %08x %s" % (name, crc, sha))

    # MAME-only video assist variant: same cart, HAL pokes the assist board each
    # virtual vblank; the board takes the original-format graphics
    with open(os.path.join(build_dir, "build_assist.log"), "w") as log:
        pa = build_prom(regions, security, build_dir, log, assist=True)
    afiles = [("538a-p1.p1", swap16(pa)), ("538a-t1.bin", regions["tiles"]), ("538a-t2.bin", regions["sprites"])]
    for name, size, crc, sha in write_set(args.out, afiles, "aerofgtna"):
        print("%-12s %08x %s" % (name, crc, sha))


if __name__ == "__main__":
    main()
