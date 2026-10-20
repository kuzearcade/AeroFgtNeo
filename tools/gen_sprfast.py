"""Generate the sprite conversion fast path (hal/spr.s includes the result as sprfast.inc).

One straight-line routine per sprite shape: ysize, xsize (0..7), the two flips and
zoomed or not.  Each first tests whether its lookup run wraps (map + tiles > 0x4000:
those go down hal_spr_go's general path).  A zoomed shape also writes its columns' SCB2 (horizontal shrink =
the gap to the next column, from spr_zw by zoomx, the last column MAME's own width;
vertical shrink 255 - 8 zoomy) and lists them for hal_spr_reclaim to restore.  Neither
the Neo's horizontal nor its vertical shrink picks the pixels MAME's zoom does, so a
set with a zoomed sprite is a slip.  Everything that depends on the shape is a constant:
the charge, the column count, the lookup offset of every tile, the flip bits.

hal_spr_go dispatches through spr_fast_jt (zoomed shapes: the table after it) with
    index = (w2 bits 13-15) << 6 | ysize << 3 | xsize     (x4 in the table)
w2 bit 13 (colour bit 5) set = in front of tilemap 1; clear = behind it, which has no
Neo sprites of its own: those entries go to spr_lo_v / spr_lo_z (hal/spr.s), which
flag the set and continue in the same shape's routine (charging themselves).

In:  d2-d5 = attribute words w0-w3, a2 = lookup RAM, a3 = VRAM data port, a4 = next
     head, a6 = set state, d7 = credit (high word) / 0x7fff (low word).
Out: back to spr_go_ent (next entry), spr_go_drop (no columns left: wait or drop),
     spr_go_wrap (a lookup run that wraps: the general path, before any charge or
     write; d5 = w3 & $3fff) or spr_go_late via spr_fast_refill (budget).

Each routine is charged an upper bound of its own cycles plus PRE_MAX, the most the
common code before the dispatch can take (hal_spr_go: entry decode, visibility with
the wrap-around detours, zoom/wrap tests, index, dispatch).
"""

import os
import re
import sys

PRE_MAX = 438           # cycles, .ent .. jmp (a1), worst visible path (plain shapes:
                        # 318 + 60 for each of the y and x wrap-around detours)
PRE_MAX_Z = 446         # the same for zoomed shapes (table switch)
LO_EXTRA = 0            # (behind-tilemap entries: spr_lo_v/z charge themselves)
MARGIN = 32
if os.environ.get("AEROFGT_RETAIN", "0") != "0":
    # hal/sprr.s: hal_spr_go's .ent sets each entry's columns (move, lsl, lea, 2 moves)
    PRE_MAX += 96
    PRE_MAX_Z += 96
if os.environ.get("AEROFGT_DIRECT", "0") == "1":
    # hal/fx.s: hal_spr_go's .ent takes the list's next entry (no more than the
    # original list's word, but +92 in an update in place: the kept entries' table), the
    # walk lists only visible ones (no tests here: -60, no wrap-around detours: -120)
    PRE_MAX -= 88
    PRE_MAX_Z -= 88



class Code:
    """Instructions with their cycles (the path the charge must bound)."""

    def __init__(self):
        self.lines, self.cyc = [], 0

    def __call__(self, text, cyc=0):
        self.lines.append(text)
        self.cyc += cyc


def zoom_heights():
    """spr_zh: per zoomy, 8 bytes: the head height in tiles for 1..8 rows, the lines
    the shrunk rows take: ceil(rows * (32 - zoomy) / 32)."""
    return [[max(1, -(-(r * (32 - zoomy)) // 32)) for r in range(1, 9)] for zoomy in range(16)]


def zoom_widths():
    """spr_zw: per zoomx, 8 words: (width of column c - 1) << 8, the width being the gap
    MAME leaves to column c + 1 (column c at ox + c * (32 - zoomx) // 2)."""
    rows = []
    for zoomx in range(16):
        zx = 32 - zoomx
        rows.append([((((c + 1) * zx >> 1) - (c * zx >> 1) - 1) << 8) for c in range(8)])
    return rows


def zoom_widths_last():
    """spr_zwl: as spr_zw, but the width of a sprite's LAST column: MAME draws every
    column (32 - zoomx + 1) // 2 wide, the gaps between them are that or one less (the
    columns overlap by a pixel, the one drawn first keeps it)."""
    return [[((((32 - zoomx) + 1) >> 1) - 1) << 8 for c in range(8)] for zoomx in range(16)]


def routine(ys, xs, fy, fx, zoom):
    rows, cols = ys + 1, xs + 1
    name = "sp%s_%d%d%d%d" % ("z" if zoom else "v", ys, xs, fy, fx)
    c = Code()
    if DIRECT and not zoom and (ys, xs, fy, fx) == (1, 1, 0, 0):
        # hal/fx.s pair bullets (w2 low byte 0x80): hal/spr.s spr_go_bul
        c("%s:\ttst.b   d4                       ; a pair bullet?" % name, 4)
        c("\tbmi.w   spr_go_bul", 12)
        c("\tandi.w  #$3fff,d5               ; lookup run: wraps?", 8)
    else:
        c("%s:\tandi.w  #$3fff,d5               ; lookup run: wraps?" % name, 8)
    c("\tcmpi.w  #$%04x,d5" % (0x4000 - rows * cols), 8)
    c("\tbls.s   .w", 10)
    c("\tjmp     spr_go_wrap")
    if GAMETIME:
        k_at = len(c.lines)
        c(".w:")
        c("SUBI"); c("MOVEK")       # (placeholders, replaced by nothing below)
    else:
        c(".w:\tswap    d7                       ; charge it", 4)
        k_at = len(c.lines)
        c("SUBI", 8)
        c("\tbpl.s   .c", 10)
        c("MOVEK")
        c("\tjsr     spr_fast_refill         ; (returns only with credit)")
        c(".c:\tswap    d7", 4)
    c("\tmove.w  SS_HNEXT(a6),d0         ; the set's lowest column in use", 12)
    c("\tsubq.w  #%d,d0                   ; column 0" % cols, 4)
    c("\tcmp.w   SS_HMIN(a6),d0", 12)
    c("\tbge.s   .a", 10)
    c("\tjmp     spr_go_drop")
    c(".a:\tmove.w  d0,SS_HNEXT(a6)", 12)
    if zoom:
        c("\tmove.w  SS_ZN(a6),d6            ; list the columns (hal_spr_reclaim restores their SCB2)", 12)
        c("\taddq.w  #1,SS_ZN(a6)", 16)
        c("\tcmpi.w  #ZL_MAX,d6", 8)
        c("\tbhs.s   .z", 8)
        c("\tadd.w   d6,d6", 4)
        c("\tadd.w   d6,d6", 4)
        c("\tmove.w  d0,SS_ZL(a6,d6.w)", 14)
        c("\tmove.w  #%d,SS_ZL+2(a6,d6.w)" % xs, 18)
        # zoomed at all: a slip when shown.  The Neo's shrink keeps other pixels than
        # MAME's zoom (the same only at widths 8 and 16; vertically approximated), and
        # odd 32 - zoomx overlaps columns by a pixel that MAME gives to the one drawn first
        c(".z:\tlea     HAL_SPR_MIX,a1", 12)
        c("\tmove.w  HAL_SPR_W,d6", 16)
        c("\tbset    #2,(a1,d6.w)", 22)
        c(".nv:\tmove.w  d0,d6                   ; SCB2 run", 4)
        c("\taddi.w  #SCB2,d6", 8)
        c("\tmove.w  d6,-2(a3)", 12)
        c("\tmove.w  d2,d1", 4)
        c("\trol.w   #7,d1", 20)
        c("\tandi.w  #$78,d1                 ; 8 zoomy", 8)
        c("\tlea     spr_zh+%d,a1             ; the head's height: the rows the shrink shows" % (rows - 1), 12)
        c("\tmoveq   #0,d6", 4)
        c("\tmove.b  (a1,d1.w),d6", 14)
        c("\tmove.w  d6,-(sp)", 8)
        c("\tneg.w   d1                      ; vertical shrink 255 - 8 zoomy", 4)
        c("\taddi.w  #255,d1", 8)
        c("\tmove.w  d3,d6                   ; column widths by zoomx (spr_zw)", 4)
        c("\tlsr.w   #8,d6", 22)
        c("\tandi.w  #$f0,d6", 8)
        c("\tlea     spr_zw,a1", 12)
        c("\tadda.w  d6,a1", 8)
        for i in range(cols):
            if i < cols - 1:
                c("\tmove.w  (a1)+,d6", 8)
            else:                   # the last column: MAME's full width (spr_zwl)
                c("\tmove.w  spr_zwl-spr_zw(a1),d6", 12)
            c("\tor.w    d1,d6", 4)
            c("\tmove.w  d6,(a3)", 8)
    c("\tlsl.w   #7,d3                   ; SCB4: ox << 7", 20)
    c("\tneg.w   d2                      ; head: SCB3 = (496 - oy) << 7 | rows", 4)
    c("\tlsl.w   #7,d2", 20)
    if zoom:
        c("\taddi.w  #$%04x,d2" % ((496 << 7) & 0xffff), 8)
        c("\tadd.w   (sp)+,d2", 8)
    else:
        c("\taddi.w  #$%04x,d2" % (((496 << 7) + rows) & 0xffff), 8)
    c("\tmove.w  d0,d6", 4)
    c("\taddi.w  #SCB3,d6", 8)
    c("\tmove.w  d6,(a4)+", 8)
    c("\tmove.w  d2,SS_HVAL-SS_HADR-2(a4)", 12)
    c("\taddi.w  #SCB4-SCB3,d6", 8)
    c("\tmove.w  d6,-2(a3)", 12)
    c("\tmove.w  d3,(a3)", 8)
    c("\tmove.w  d4,d1                   ; attributes", 4)
    c("\tandi.w  #$1f00,d1", 8)
    c("\taddi.w  #(NPAL_SPR<<8)+%d,d1" % (fy * 2 + fx), 8)
    c("\tadd.w   d5,d5                   ; lookup run", 4)
    c("\tlea     (a2,d5.w),a1", 12)
    c("\tlsl.w   #6,d0                   ; SCB1 of column 0", 18)
    for col in range(cols):
        c("\tmove.w  d0,-2(a3)", 12)
        sc = cols - 1 - col if fx else col
        # VRAM data writes at least 12 cycles apart (the LSPC drops one of two written
        # 8 cycles apart, measured on the MiSTer core): the next row's tile is fetched
        # between a row's tile and attribute writes, a NOP after the last row's tile
        def load(r):
            sr = rows - 1 - r if fy else r
            disp = 2 * (sr * cols + sc)
            if disp:
                c("\tmove.w  %d(a1),d4" % disp, 12)
            else:
                c("\tmove.w  (a1),d4", 8)
        load(0)
        c("\tand.w   d7,d4", 4)
        for r in range(rows):
            c("\tmove.w  d4,(a3)", 8)
            if r < rows - 1:
                load(r + 1)
            else:
                c("\tnop", 4)
            c("\tmove.w  d1,(a3)", 8)
            if r < rows - 1:
                c("\tand.w   d7,d4", 4)
        if zoom:
            # the vertical shrink maps the column's lines onto all its 32 rows: the
            # rows after the sprite's (fetched below the shrunk image) transparent
            for _ in range(2):
                c("\tmove.w  #BLANK_TILE,(a3)", 12)
                c("\tmove.w  #0,(a3)", 12)
        if col < cols - 1:
            c("\taddi.w  #64,d0", 8)
    c("\tjmp     %s" % ("fz_next" if FUSED else "spr_go_ent"), 12)
    total = c.cyc
    k = -(-((PRE_MAX_Z if zoom else PRE_MAX) + total + LO_EXTRA + MARGIN) // 16)
    if GAMETIME:
        c.lines[k_at + 1] = ""
        c.lines[k_at + 2] = ""
    else:
        c.lines[k_at] = "\tsubi.w  #%d,d7" % k
        c.lines[k_at + 2] = "\tmove.w  #%d,d0" % k
    return name, k, total, c.lines


DIRECT = os.environ.get("AEROFGT_DIRECT", "0") == "1"
# hal/fz.s (AUDIT.md 24): the routines return to its fz_next; the path before the
# dispatch (fz_next, fz_em_*, fz_disp) is bounded by the non-DIRECT PRE_MAX
_m = re.search(r"(^|,)\s*FUSED\s*=\s*([12])\b", os.environ.get("AEROFGT_DEFS", ""))
FUSED = DIRECT and bool(_m)
GAMETIME = FUSED and _m.group(2) == "2"   # hal/fz.s fz_gt: the pass in the game's round, no budget: no charge
if FUSED:
    # fz_next (~40), fz_em_* (~450 with the pass-1 HUD tests), fz_disp (~90): 620 (the
    # commit's tail overran by up to 17 lines at 500, 2026-10-17)
    PRE_MAX += 88 + 182
    PRE_MAX_Z += 88 + 182


def main():
    out = sys.argv[1]
    code = []
    worst = 0
    tables = []
    for zoom in (0, 1):
        names = {}
        for fy in (0, 1):
            for fx in (0, 1):
                for ys in range(8):
                    for xs in range(8):
                        name, k, total, lines = routine(ys, xs, fy, fx, zoom)
                        names[(ys, xs, fy, fx)] = name
                        worst = max(worst, k)
                        code += lines + [""]
        jt = []
        for n in range(512):
            xs, ys, g, fx, fy = n & 7, (n >> 3) & 7, (n >> 6) & 1, (n >> 7) & 1, (n >> 8) & 1
            jt.append(names[(ys, xs, fy, fx)] if g else ("spr_lo_z" if zoom else "spr_lo_v"))
        tables.append(jt)
    with open(out, "w") as f:
        f.write("; generated by tools/gen_sprfast.py: sprite conversion fast path (see there)\n")
        f.write("; charges in 16-cycle units, the largest %d\n\n" % worst)
        f.write("PRE_MAX_C       equ %d             ; (PRE_MAX: hal/spr.s spr_go_bul's charge)\n\n" % PRE_MAX)
        f.write("\teven\nspr_fast_jt:                    ; plain shapes; zoomed shapes 2048 bytes on\n")
        for jt in tables:
            for i in range(0, 512, 4):
                f.write("\tdc.l    %s\n" % ",".join(jt[i:i + 4]))
        f.write("\nspr_zw:                         ; per zoomx: (width of column c - 1) << 8\n")
        for row in zoom_widths():
            f.write("\tdc.w    %s\n" % ",".join("$%04x" % w for w in row))
        f.write("\nspr_zwl:                        ; per zoomx: (width of a last column - 1) << 8\n")
        for row in zoom_widths_last():
            f.write("\tdc.w    " + ",".join("$%04x" % v for v in row) + "\n")
        f.write("\nspr_zh:                         ; per zoomy: head height for 1..8 rows\n")
        for row in zoom_heights():
            f.write("\tdc.b    %s\n" % ",".join("%d" % h for h in row))
        f.write("\teven\n\n")
        f.write("\n".join(code))
        f.write("\n")


if __name__ == "__main__":
    main()
