"""Verify the converted C/S ROMs against the original graphics.

Decodes the output set with the pixel addressing of MAME's Neo sprite / fix renderers
(gfx.decode_c / decode_s) and checks every pixel of every converted tile against the
original tile decoded as MAME's gfx_8x8x4_packed_msb / gfx_16x16x4_packed_msb do.
A vectorised decoder checks all tiles; the scalar MAME-formula decoder cross-checks it
on a sample.
usage: check_gfx.py [aerofgt.zip] [out/aerofgtn]
"""

import os
import random
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gfx      # noqa: E402
import romset   # noqa: E402


def decode_c_all(region, first, n):
    """vectorised equivalent of gfx.decode_c for tiles first..first+n-1."""
    t = region[first * 128:(first + n) * 128].reshape(n, 2, 16, 4)   # half, row, byte
    out = np.zeros((n, 16, 16), np.uint8)
    for half, xs in ((1, 0), (0, 8)):
        b = t[:, half]                                  # (n, 16, 4)
        for x in range(8):
            out[:, :, xs + x] = (((b[:, :, 3] >> x) & 1) << 3) | (((b[:, :, 1] >> x) & 1) << 2) | \
                                (((b[:, :, 2] >> x) & 1) << 1) | ((b[:, :, 0] >> x) & 1)
    return out


def main():
    zp = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "mame_roms", "aerofgt.zip")
    sd = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "out", "aerofgtn")
    reg = romset.load_aerofgt(zp)
    c1 = np.fromfile(os.path.join(sd, "538-c1.c1"), np.uint8)
    c2 = np.fromfile(os.path.join(sd, "538-c2.c2"), np.uint8)
    region = np.empty(len(c1) * 2, np.uint8)
    region[0::2], region[1::2] = c1, c2
    srom = np.fromfile(os.path.join(sd, "538-s1.s1"), np.uint8)

    t8 = gfx._unpack_tiles8(reg["tiles"])
    spr = gfx._unpack_sprites(reg["sprites"])
    blk = gfx.blocks(t8)
    variant = np.frombuffer(open(os.path.join(ROOT, "out", "build", "l0_variant.bin"), "rb").read(), np.uint8)
    fails = 0

    def check(name, got, want):
        nonlocal fails
        bad = int((got != want).any(axis=(1, 2)).sum())
        print("%-28s %6d tiles, %d mismatching" % (name, len(want), bad))
        fails += bad

    # sprites: transparent pen 15 -> 0, others +1
    check("sprites", decode_c_all(region, gfx.SPR_BASE, gfx.N_SPR), (spr + 1) & 15)
    # tilemap 1 blocks: quadrant layout from the game's block writer
    want1 = np.empty((gfx.N_BLK, 16, 16), np.uint8)
    q = t8.reshape(-1, 4, 8, 8)
    for (ys, xs), k in (((0, 0), 2), ((0, 8), 0), ((8, 0), 3), ((8, 8), 1)):
        want1[:, ys:ys + 8, xs:xs + 8] = (q[:, k] + 1) & 15
    check("blocks, tilemap 1", decode_c_all(region, gfx.BLK1_BASE, gfx.N_BLK), want1)
    # tilemap 0 blocks: colour seen through the variant palette must equal the original
    got0 = decode_c_all(region, gfx.BLK0_BASE, gfx.N_BLK)
    orig_pen = np.empty_like(got0)
    for (ys, xs), k in (((0, 0), 2), ((0, 8), 0), ((8, 0), 3), ((8, 8), 1)):
        orig_pen[:, ys:ys + 8, xs:xs + 8] = q[:, k]
    seen = (got0.astype(np.int16) - 1) & 15           # pen read through a normal palette
    for v, pen in enumerate(gfx.L0_REMAP_PENS, 1):
        sel = variant == v
        seen[sel] = np.where(got0[sel] == pen + 1, 15, seen[sel])
    full16 = (np.stack([(orig_pen == p).any(axis=(1, 2)) for p in range(16)], 1)).all(1)
    seen[full16] = np.where(got0[full16] == 0, 15, seen[full16])
    check("blocks, tilemap 0 (colours)", seen, orig_pen)
    print("  pen-15 variants:", [int((variant == v).sum()) for v in range(4)], "all-16-pen blocks:", int(full16.sum()))
    # every remapped pen must be unused by its block
    for v, pen in enumerate(gfx.L0_REMAP_PENS, 1):
        assert not (orig_pen[variant == v] == pen).any()
    # fix layer
    s = srom.reshape(-1, 4, 8)
    gots = np.zeros((gfx.S_TILES, 8, 8), np.uint8)
    for i, off in enumerate((0x10, 0x18, 0x00, 0x08)):
        d = s[:gfx.S_TILES, off // 8]
        gots[:, :, 2 * i] = d & 15
        gots[:, :, 2 * i + 1] = d >> 4
    # every physical tile S_REMAP maps to an S tile must show there (transparent ones
    # nowhere); S tile 0 stays blank (the cleared fix map)
    slots, remap = gfx.s_layout(t8)
    remap = np.frombuffer(remap, ">u2")
    m = remap < gfx.S_TRANSP
    check("fix tiles (S_REMAP)", gots[remap[m]], (t8[m] + 1) & 15)
    check("fix tile 0 blank", gots[0:1], np.zeros((1, 8, 8), np.uint8))
    tr = remap == gfx.S_TRANSP
    assert (t8[tr] == 15).all(), "S_TRANSP for a tile with opaque pixels"
    print("  S tiles used:", len(slots), " mapped physical tiles:", int(m.sum()), " transparent:", int(tr.sum()))
    # shifted blocks (BLKSx_BASE + g: base word 4g + 2), tilemap 1 variant
    sh = gfx.shifted_blocks(t8)
    check("shifted blocks, tilemap 1", decode_c_all(region, gfx.BLKS1_BASE, gfx.N_BLK), gfx.transparent_pens(sh))

    # scalar MAME-formula cross-check of the vectorised decoders
    rng = random.Random(1)
    for _ in range(300):
        t = rng.randrange(gfx.C_TILES_USED)
        assert (gfx.decode_c(region, t) == decode_c_all(region, t, 1)[0]).all(), t
        f = rng.randrange(gfx.S_TILES)
        assert (gfx.decode_s(srom, f) == gots[f]).all(), f
    print("scalar MAME-formula cross-check: 600 tiles ok")
    print("FAIL" if fails else "PASS")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
