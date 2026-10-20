"""Convert the original Aero Fighters graphics into Neo Geo C (sprite) and S (fix) ROMs.

Original formats (MAME region order):
  tiles    8x8x4 packed, MSB nibble first, 32 bytes/tile, 32768 tiles (both tilemaps)
  sprites  16x16x4 packed, MSB nibble first, 128 bytes/tile, 32768 tiles
Pen 15 is transparent for sprites and tilemap 1; tilemap 0 is opaque.  Neo pen 0 is
transparent, so every pen is remapped to (pen + 1) & 15 and the Neo palettes are
built to match (see PALETTE LAYOUT below).

Neo sprite tile map (tile numbers, 128 bytes each in the interleaved C1/C2 region):
  SPR_BASE   + n          original sprite tile n (identity; the sprite lookup RAM values
                          are tile numbers, so the HAL copies them straight to SCB1)
  BLK1_BASE  + g          tilemap block g, transparent variant (tilemap 1)
  BLK0_BASE  + g          tilemap block g, opaque variant (tilemap 0)
  UNI1_BASE / UNI0_BASE + k   a block made of four copies of tile k*0x800 (cleared maps)
  BLKS1_BASE / BLKS0_BASE + g  block g shifted by half: base word w = 4g + 2 (the staff
                          screens draw pictures this way); tile numbers above 0xffff, so
                          the HAL sets tile bit 16 in the SCB1 attribute word

A tilemap "block" is the 16x16 area the game writes as one unit (0x2c924, 0x5e0c):
base word w at tilemap (row r, col c+1), w+1 at (r+1, c+1), w+2 at (r, c), w+3 at
(r+1, c), with r and c even and w & 3 == 0.  Group g = physical tile number >> 2, so
there are 8192 blocks; quadrants are TL = 4g+2, TR = 4g, BL = 4g+3, BR = 4g+1.

Tilemap 0 is opaque, but a Neo tile only has 15 opaque pens.  Blocks of tilemap 0 that
use pen 15 have it moved onto a pen the block does not use (1, 14 or 11; chosen
greedily, see L0_REMAP_PENS), and are drawn with a palette variant whose slot for that
pen holds colour 15.  L0_VARIANT[g] tells the HAL which variant (0 = none) a block
needs; blocks using all 16 pens keep pen 15 transparent (reported, never seen in play).

Fix layer: the HAL uses it for tilemap-1 cells that are not part of a block (the boot,
warning and service-mode text written one character at a time by 0x129e, the staff
screens' panels) while tilemap 1 is 8-pixel aligned.  The S ROM's 4096 tiles (the
LSPC's 12-bit fix tile numbers) cannot hold tilemap 1's 16384, so it holds the tiles
seen drawn cell by cell (analysis/s_tiles.txt), then banks 8 and 9 (the font),
identical tiles once, fully transparent ones not at all; S_REMAP (64KB in the P ROM)
maps every physical tile to its S tile, S_TRANSP or S_NONE.
"""

import numpy as np

C_TILE = 128
SPR_BASE = 0x00000
BLK1_BASE = 0x08000
BLK0_BASE = 0x0a000
UNI1_BASE = 0x0c000
UNI0_BASE = 0x0c010
C_TILES_USED = 0x0c020          # (BLANK_TILE: transparent)
SOLID_BASE = 0x0c030            # + p: a block of solid original pen p (0..14), DIRECT builds
BLKS1_BASE = 0x10000
BLKS0_BASE = 0x12000            # BLKSx_BASE - BLKx_BASE = 0x8000 for both layers
C_TILES_END = 0x14000

N_SPR = 0x8000
LOGO_TILES = 0x3a               # (UB_LOGO) the Universe BIOS splash logo: tiles 0..0x39
LOGO_RELOC = 0x1cf0             # where the original's tiles 0..0x39 go (0x1cf0-0x1d71: never in a
                                # stage's lookup table)
LOGO_ROWS = (0x00, 0x0e, 0x1d, 0x2c)
N_BLK = 0x2000
N_UNI = 16
L0_REMAP_PENS = (1, 14, 11)     # variant v (1..3) moves pen 15 onto L0_REMAP_PENS[v-1]
S_TILES = 4096
S_DIAG = 16                     # the last S tiles: diagnostic builds' hex font
S_TRANSP = 0x8000               # S_REMAP: fully transparent tile (nothing to draw)
S_NONE = 0xffff                 # S_REMAP: not in the S ROM


def _unpack_tiles8(tiles):
    """tiles region -> (32768, 8, 8) original pens."""
    b = np.frombuffer(bytes(tiles), dtype=np.uint8).reshape(-1, 8, 4)
    return np.stack([b >> 4, b & 15], axis=-1).reshape(-1, 8, 8)


def _unpack_sprites(sprites):
    """sprites region -> (32768, 16, 16) original pens."""
    b = np.frombuffer(bytes(sprites), dtype=np.uint8).reshape(-1, 16, 8)
    return np.stack([b >> 4, b & 15], axis=-1).reshape(-1, 16, 16)


def transparent_pens(p):
    """original pens (15 = transparent) -> Neo pens (0 = transparent)."""
    return ((p.astype(np.uint8) + 1) & 15).astype(np.uint8)


def blocks(t8):
    """(32768, 8, 8) tiles -> (8192, 16, 16) blocks in screen orientation."""
    g = t8.reshape(-1, 4, 8, 8)
    out = np.empty((len(g), 16, 16), np.uint8)
    out[:, 0:8, 0:8] = g[:, 2]
    out[:, 0:8, 8:16] = g[:, 0]
    out[:, 8:16, 0:8] = g[:, 3]
    out[:, 8:16, 8:16] = g[:, 1]
    return out


def shifted_blocks(t8):
    """(32768, 8, 8) tiles -> (8192, 16, 16): block g shifted by half, base word 4g+2
    (TR = 4g+2, BR = 4g+3, TL = 4g+4, BL = 4g+5); the last one has no right half."""
    pad = np.concatenate([t8, np.full((8, 8, 8), 15, np.uint8)])
    g4 = np.arange(len(t8) // 4) * 4
    out = np.empty((len(g4), 16, 16), np.uint8)
    out[:, 0:8, 0:8] = pad[g4 + 4]
    out[:, 0:8, 8:16] = pad[g4 + 2]
    out[:, 8:16, 0:8] = pad[g4 + 5]
    out[:, 8:16, 8:16] = pad[g4 + 3]
    return out


def opaque_variants(blk, strict=True):
    """Tilemap-0 blocks: per block variant number and Neo pens with pen 15 moved."""
    used = np.stack([(blk == p).any(axis=(1, 2)) for p in range(16)], axis=1)
    variant = np.zeros(len(blk), np.uint8)
    pending = used[:, 15] & ~used.all(axis=1)
    for v, pen in enumerate(L0_REMAP_PENS, 1):
        take = pending & ~used[:, pen]
        variant[take] = v
        pending &= ~take
    assert not strict or not pending.any()
    neo = transparent_pens(blk)
    for v, pen in enumerate(L0_REMAP_PENS, 1):
        sel = variant == v
        sub = blk[sel]
        neo[sel] = np.where(sub == 15, pen + 1, neo[sel])
    full16 = int(used.all(axis=1).sum())
    return variant, neo, full16


def encode_c(neo):
    """(n, 16, 16) Neo pens -> interleaved C region bytes (n * 128)."""
    n = len(neo)
    out = np.zeros((n, 2, 16, 4), np.uint8)     # half (0 = right, 1 = left), row, byte
    bitw = (1 << np.arange(8)).astype(np.uint16)
    for half, xs in ((0, slice(8, 16)), (1, slice(0, 8))):
        px = neo[:, :, xs].astype(np.uint16)     # (n, 16, 8)
        for k, plane in ((0, 0), (2, 1), (1, 2), (3, 3)):
            out[:, half, :, k] = (((px >> plane) & 1) * bitw).sum(axis=-1).astype(np.uint8)
    return out.reshape(-1)


def decode_c(region, tile):
    """Neo C region -> (16, 16) pens, straight from MAME's neosprite_regular draw_pixel."""
    out = np.zeros((16, 16), np.uint8)
    for y in range(16):
        for x in range(16):
            romaddr = (tile << 8) | (y << 4) | x
            src = ((romaddr & ~0xff) >> 1) | (((romaddr & 8) ^ 8) << 3) | ((romaddr & 0xf0) >> 2)
            b = x & 7
            out[y, x] = (((region[src + 3] >> b) & 1) << 3) | (((region[src + 1] >> b) & 1) << 2) | \
                        (((region[src + 2] >> b) & 1) << 1) | ((region[src] >> b) & 1)
    return out


def logo_tiles():
    """(LOGO_TILES, 16, 16) Neo pens of tools/vslogo.png for the Universe BIOS splash (see build)."""
    import os
    from PIL import Image
    im = np.asarray(Image.open(os.path.join(os.path.dirname(__file__), "vslogo.png")).convert("L"), np.int32)
    assert im.shape == (224, 64)
    out = np.zeros((LOGO_TILES, 16, 16), np.uint8)
    for my in range(224):
        for mx in range(64):
            lum = im[my, mx]
            pen = 1 if lum > 160 else 2 if lum > 100 else 3 if lum > 55 else 4 if lum > 20 else 0
            if not pen:
                continue
            x = 319 - (45 + my)
            y = 10 + mx
            c, tx = divmod(x - 51, 16)
            r, ty = divmod(y - 10, 16)
            out[LOGO_ROWS[r] + c, ty, tx] = pen
    return out


def encode_s(neo8):
    """(n, 8, 8) Neo pens -> S ROM bytes (n * 32)."""
    n = len(neo8)
    out = np.zeros((n, 4, 8), np.uint8)
    for i, col in enumerate((2, 3, 0, 1)):           # byte groups 0x00,0x08,0x10,0x18
        x = col * 2
        out[:, i, :] = neo8[:, :, x] | (neo8[:, :, x + 1] << 4)
    return out.reshape(-1)


def decode_s(srom, code):
    """S ROM -> (8, 8) pens, as MAME's draw_fixed_layer."""
    out = np.zeros((8, 8), np.uint8)
    for y in range(8):
        for i, off in enumerate((0x10, 0x18, 0x00, 0x08)):
            d = srom[(code << 5) + off + y]
            out[y, 2 * i] = d & 15
            out[y, 2 * i + 1] = d >> 4
    return out


def build(regions, c_size, s_size, log=None):
    """Return (c1, c2, s, info).  info carries the tables the HAL needs."""
    t8 = _unpack_tiles8(regions["tiles"])
    spr = _unpack_sprites(regions["sprites"])
    blk = blocks(t8)
    variant, blk0, full16 = opaque_variants(blk)
    uni = np.tile(t8[::0x800], (1, 2, 2))            # tile k*0x800 in all four quadrants
    uvar, uni0, _ = opaque_variants(uni)
    shb = shifted_blocks(t8)
    svariant, shb0, _ = opaque_variants(shb, strict=False)

    region = np.zeros(c_size, np.uint8)

    def put(base, neo):
        a = base * C_TILE
        region[a:a + len(neo) * C_TILE] = encode_c(neo)

    put(SPR_BASE, transparent_pens(spr))
    put(BLK1_BASE, transparent_pens(blk))
    put(BLK0_BASE, blk0)
    put(UNI1_BASE, transparent_pens(uni))
    put(UNI0_BASE, uni0)
    put(BLKS1_BASE, transparent_pens(shb))
    put(BLKS0_BASE, shb0)
    import os
    if os.environ.get("AEROFGT_DIRECT", "0") == "1":
        put(SOLID_BASE, np.repeat(np.arange(1, 16, dtype=np.uint8), 256).reshape(15, 16, 16))
    if os.environ.get("AEROFGT_UBLOGO", "0") == "1":
        # (UB_LOGO, 2026-10-19) the Universe BIOS splash draws its logo from the cartridge's tiles
        # 0x000-0x039 (14 x 4, rows 0x00, 0x0e, 0x1d, 0x2c; palettes 7 over 3, 2 px apart): the
        # original's player-plane tiles 0..0x39 move to LOGO_RELOC.. (aerofgt2neo.py patches the
        # stage lookup tables) and the tiles hold tools/vslogo.png, the VideoSystem emblem of the
        # attract's first screen (the "V SYSTEM" mark alone, centred), upright on the rotated monitor: monitor pixel (mx, my) of the
        # 64 x 224 image is Neo (x = 319 - (45 + my), y = 10 + mx) in the splash's block at
        # (51, 10); pens 1-4 are the BIOS palette's four golds, bright to dark, pen 0 clear.
        put(LOGO_RELOC, transparent_pens(spr)[:LOGO_TILES])
        put(SPR_BASE, logo_tiles())
    assert C_TILES_END * C_TILE <= c_size

    slots, remap = s_layout(t8)
    import os
    hud = hud_layout(t8, spr)[0] if os.environ.get("AEROFGT_DIRECT", "0") == "1" else []
    s = encode_s(np.concatenate([np.full((1, 8, 8), 0, np.uint8),
                                 transparent_pens(t8[slots[1:]])] +
                                ([np.stack(hud)] if hud else [])))
    s = np.concatenate([s, np.zeros(s_size - len(s), np.uint8)])    # (unused: pen 0, transparent)
    assert len(s) == s_size

    info = {"l0_variant": bytes(variant), "uni_variant": bytes(uvar), "l0_full16": full16,
            "l0s_variant": bytes(svariant), "s_remap": remap, "s_used": len(slots) + len(hud)}
    if log:
        log.write("gfx: %d sprite tiles, %d blocks x2, %d uniform x2, %d S tiles\n"
                  % (N_SPR, N_BLK, N_UNI, S_TILES))
        log.write("gfx: tilemap-0 pen-15 variants %s, blocks using all 16 pens %d\n"
                  % ([int((variant == v).sum()) for v in range(4)], full16))
    region = region.tobytes()
    return bytearray(region[0::2]), bytearray(region[1::2]), bytearray(s), info


# ---------------------------------------------------------------- palette
# PALETTE LAYOUT (Neo palette numbers), original palette q = entry >> 4:
#   tilemap 1  q 16..23  -> NPAL_L1 + (q - 16)          (0..15: fix layer can use them too)
#   tilemap 0  q 0..7    -> NPAL_L0 + 4 q + v           v = pen-15 variant (L0_REMAP_PENS)
#   sprites    q 32..63  -> NPAL_SPR + (q - 32)
# Slot s (1..15) holds original pen s - 1; slot 0 is transparent.
NPAL_L1 = 8
NPAL_L0 = 16
NPAL_SPR = 48

# MAME Neo Geo DAC output (8-bit) per 5-bit level, normal and "dark" (measured from
# neogeo_base_state::create_rgb_lookups via the palette device)
NEO_DAC = (
    (0, 8, 14, 22, 30, 38, 44, 52, 65, 73, 79, 86, 95, 103, 109, 117,
     138, 146, 152, 160, 169, 176, 182, 190, 203, 211, 217, 225, 233, 241, 247, 255),
    (0, 8, 14, 21, 30, 38, 44, 51, 64, 71, 77, 85, 94, 101, 107, 115,
     136, 144, 150, 158, 166, 174, 180, 188, 200, 208, 214, 221, 230, 238, 244, 251),
)


def neo_colour_table():
    """xRGB555 (bits 0-14) -> Neo colour word, nearest MAME-rendered colour to the
    original pal5bit() colour (dark bit chosen per colour)."""
    dac = np.array(NEO_DAC, np.int32)                       # (2, 32)
    want = np.array([(v << 3) | (v >> 2) for v in range(32)], np.int32)
    err = (dac[:, None, :] - want[None, :, None]) ** 2      # (dark, want, level)
    best = err.argmin(axis=2)                               # (dark, want) -> level
    besterr = err.min(axis=2)
    v = np.arange(0x8000)
    r, g, b = (v >> 10) & 31, (v >> 5) & 31, v & 31
    tot = besterr[:, r] + besterr[:, g] + besterr[:, b]     # (dark, v)
    dark = tot.argmin(axis=0)
    lr, lg, lb = best[dark, r], best[dark, g], best[dark, b]
    word = (dark << 15) | ((lr & 1) << 14) | ((lg & 1) << 13) | ((lb & 1) << 12) | \
           ((lr >> 1) << 8) | ((lg >> 1) << 4) | (lb >> 1)
    maxerr = int(np.sqrt(tot.min(axis=0)).max())
    return word.astype(np.uint16), maxerr


def neo_colour_table_rotated():
    """The HAL indexes the table with a sign-extended word (2 * colour): table base
    + 0x8000 is the entry for colour 0, colours 0x4000-0x7fff sit below it."""
    t, _ = neo_colour_table()
    rot = np.concatenate([t[0x4000:], t[:0x4000]])
    return rot.astype(">u2").tobytes()


def l0_variant_table(regions):
    """Per tilemap block g: pen-15 palette variant for tilemap 0 (0 = none)."""
    variant, _, _ = opaque_variants(blocks(_unpack_tiles8(regions["tiles"])))
    return bytes(variant)


def uni_variant_table(regions):
    """Per uniform block k (four copies of tile k*0x800): tilemap-0 palette variant."""
    t8 = _unpack_tiles8(regions["tiles"])
    variant, _, _ = opaque_variants(np.tile(t8[::0x800], (1, 2, 2)))
    return bytes(variant)


def solid_pen_table(regions):
    """Per physical tile (bank << 11 | code), a nibble (even tiles in the high one): the
    pen when every pixel has it and it is opaque (0..14), else 15.  hal/bg.s draws a
    tilemap-1 block of four such identical cells as SOLID_BASE + pen (DIRECT builds)."""
    f = _unpack_tiles8(regions["tiles"]).reshape(-1, 64)
    nib = np.where((f == f[:, :1]).all(1), f[:, 0], 15).astype(np.uint8)
    return bytes((nib[0::2] << 4) | nib[1::2])


def l0s_variant_table(regions):
    """Per shifted block g: pen-15 palette variant for tilemap 0 (0 = none; 0x80: pen 15
    stays transparent, no free pen to move it to: drawn approximately, a slip)."""
    sh = shifted_blocks(_unpack_tiles8(regions["tiles"]))
    variant, _, _ = opaque_variants(sh, strict=False)
    variant[(sh == 15).any(axis=(1, 2)) & (variant == 0)] = 0x80
    return bytes(variant)


HUD_T0 = 0x4300                 # hud_layout: the sprite tiles the table covers
HUD_TN = 0x500


# "GAME OVER" (lookup 0x24cf, 0x24d7), "INSERT COINS!" (0x24ec), "CONTINUE ?" (0x24dd)
# and its digit (0x24e2-0x24eb): strips hal/fx.s takes to the fix layer as the HUD's
HUD_TEXT_TILES = list(range(0x4710, 0x4719)) + list(range(0x4739, 0x473e)) + list(range(0x471e, 0x472d))


def hud_layout(t8, spr):
    """HUD strips on the fix layer (hal/fx.s): -> (Neo pens of the S tiles to append
    after s_layout's, the table: per sprite tile HUD_T0.. 4 big-endian words, its S tile
    per 8x8 quadrant (top left, top right, bottom left, bottom right; 0 transparent),
    or 0xffff if it is not in the S ROM).  The tiles seen in the HUD come first
    (analysis/hud_tiles.txt), then HUD_TEXT_TILES, then the rest of the range while the
    S ROM has room."""
    import os
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "analysis", "hud_tiles.txt")
    seen_t = [int(l, 16) for l in open(path) if l.strip() and not l.startswith("#")]
    slots, _ = s_layout(t8)
    have = {}
    for i, t in enumerate(slots[1:], 1):
        have.setdefault(transparent_pens(t8[t]).tobytes(), i)
    extra = []
    table = np.full((HUD_TN, 4), 0xffff, np.uint32)
    free = S_TILES - S_DIAG - len(slots)
    order = [t for t in seen_t if HUD_T0 <= t < HUD_T0 + HUD_TN]
    order += [t for t in HUD_TEXT_TILES if t not in set(order)]
    order += [t for t in range(HUD_T0, HUD_T0 + HUD_TN) if t not in set(order)]
    for t in order:
        quads = [transparent_pens(spr[t][y:y + 8, x:x + 8]) for y, x in ((0, 0), (0, 8), (8, 0), (8, 8))]
        new = [q for q in quads if q.any() and q.tobytes() not in have]
        new = list({q.tobytes(): q for q in new}.values())
        if len(new) > free - len(extra):
            continue
        for q in new:
            have[q.tobytes()] = len(slots) + len(extra)
            extra.append(q)
        table[t - HUD_T0] = [have[q.tobytes()] if q.any() else 0 for q in quads]
    return extra, table.astype(">u2").tobytes()


def transparent_tiles(regions):
    """A bit per C tile (bit k of byte k >> 3, LSB first), set if the tile is fully
    transparent: the tilemap-1 tiles (blocks, shifted blocks, uniform blocks, the
    blank tile).  Up to C_TILES_END."""
    t8 = _unpack_tiles8(regions["tiles"])
    tr = np.zeros(C_TILES_END, bool)
    blk = blocks(t8)
    tr[BLK1_BASE:BLK1_BASE + len(blk)] = (blk == 15).reshape(len(blk), -1).all(1)
    shb = shifted_blocks(t8)
    tr[BLKS1_BASE:BLKS1_BASE + len(shb)] = (shb == 15).reshape(len(shb), -1).all(1)
    uni = np.tile(t8[::0x800], (1, 2, 2))
    tr[UNI1_BASE:UNI1_BASE + len(uni)] = (uni == 15).reshape(len(uni), -1).all(1)
    tr[C_TILES_USED] = True
    return np.packbits(tr.reshape(-1, 8)[:, ::-1], axis=1).reshape(-1).tobytes()


def hud_blank0(spr):
    """Sprite tile 0 (the HUD's empty cells) all transparent?"""
    return bool((spr[0] == 15).all())


def s_preferred():
    """Physical tiles seen drawn cell by cell (analysis/s_tiles.txt), first."""
    import os
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "analysis", "s_tiles.txt")
    return [int(l.split()[0], 16) for l in open(path) if l.strip() and not l.startswith("#")]


def s_layout(t8):
    """-> (physical tile per S tile (S tile 0: None, blank), S_REMAP bytes: big-endian
    word per physical tile)."""
    remap = np.full(len(t8), S_NONE, np.uint32)
    seen = {}
    slots = [None]                              # S tile 0: blank (the cleared fix map)
    for t in s_preferred() + list(range(0x4000, 0x5000)):
        if remap[t] != S_NONE:
            continue
        if (t8[t] == 15).all():
            remap[t] = S_TRANSP
            continue
        key = t8[t].tobytes()
        if key in seen:
            remap[t] = seen[key]
            continue
        if len(slots) == S_TILES - S_DIAG:
            continue
        seen[key] = len(slots)
        remap[t] = len(slots)
        slots.append(t)
    for t in range(len(t8)):                    # transparent anywhere: nothing to draw
        if remap[t] == S_NONE and (t8[t] == 15).all():
            remap[t] = S_TRANSP
        elif remap[t] == S_NONE and t8[t].tobytes() in seen:
            remap[t] = seen[t8[t].tobytes()]
    return slots, remap.astype(">u2").tobytes()
