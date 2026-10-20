"""Check the real-cart tilemap layers against a reference render.

The reference is rendered from the tilemap state the HAL sees at virtual vblank
(HARNESS_PRE dump: what MAME's original draws for that frame) and the original
palette of that game frame (work/eq/orig.bin), converted to the colours MAME shows on
the Neo (tools/gfx.py colour table + DAC).  The conversion's screen capture
(HARNESS_PIXELS) must match it exactly; no game sprites are drawn yet (step 4).
usage: compare_bg.py orig.bin pre.bin pix_neo.bin [offset]
"""

import os
import struct
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gfx      # noqa: E402
import romset   # noqa: E402

REC = 4 + 0x10000 + 0x800 + 0x800 + 0x4000 + 0x8000 + 0x2000
POFF = 4 + 0x10000
PRE = 4 + 0x800 + 0x20 + 0x4000 + 0x2000 + 0x8000


def neo_rgb_table():
    t, _ = gfx.neo_colour_table()
    dac = np.array(gfx.NEO_DAC, np.uint32)
    w = t.astype(np.uint32)
    dark = w >> 15
    r = ((w >> 14) & 1) | ((w >> 7) & 0x1e)
    g = ((w >> 13) & 1) | ((w >> 3) & 0x1e)
    b = ((w >> 12) & 1) | ((w << 1) & 0x1e)
    return (dac[dark, r] << 16) | (dac[dark, g] << 8) | dac[dark, b]


def render(pre, pal, t8, rgb):
    raster = np.frombuffer(pre[4:4 + 0x800], ">u2")
    io = pre[4 + 0x800:4 + 0x820]
    vram = np.frombuffer(pre[4 + 0x820:4 + 0x820 + 0x4000], ">u2").reshape(2, 64, 64).astype(np.int32)
    banks = np.frombuffer(io[0:8], np.uint8).astype(np.int32)
    sy = [struct.unpack_from(">H", io, 8)[0] & 511, struct.unpack_from(">H", io, 16)[0] & 511]
    sx = [(int(raster[0]) - 18) & 511, (int(raster[0x200]) - 20) & 511]
    ys, xs = np.mgrid[0:224, 0:320]
    out = None
    for L in range(2):
        tx = (xs + sx[L]) & 511
        ty = (ys + sy[L]) & 511
        cell = vram[L][ty >> 3, tx >> 3]
        phys = (cell & 0x7ff) | (banks[L * 4 + ((cell >> 11) & 3)] << 11)
        pen = t8[phys & 0x7fff, ty & 7, tx & 7]
        col = pal[L * 256 + ((cell >> 13) & 7) * 16 + pen]
        px = rgb[col & 0x7fff]
        out = px if L == 0 else np.where(pen == 15, out, px)
    return out


def main():
    orig, prep, pixp = sys.argv[1:4]
    offs = [int(sys.argv[4])] if len(sys.argv) > 4 else [0, 1, 2]
    t8 = gfx._unpack_tiles8(romset.load_aerofgt(os.path.join(ROOT, "mame_roms", "aerofgt.zip"))["tiles"])
    rgb = neo_rgb_table()
    pals = {}
    with open(orig, "rb") as f:
        while True:
            b = f.read(REC)
            if len(b) < REC:
                break
            pals[struct.unpack_from("<I", b)[0]] = np.frombuffer(b[POFF:POFF + 0x800], ">u2").astype(np.int32)
    pres = {}
    with open(prep, "rb") as f:
        while True:
            b = f.read(PRE)
            if len(b) < PRE:
                break
            pres[struct.unpack_from("<I", b)[0]] = b
    pix = {}
    with open(pixp, "rb") as f:
        while True:
            h = f.read(12)
            if len(h) < 12:
                break
            gf, w, hh = struct.unpack("<III", h)
            pix[gf] = np.frombuffer(f.read(w * hh * 4), np.uint32).reshape(hh, w) & 0xffffff
    for off in offs:
        bad = []
        n = 0
        for k in sorted(pres):
            if k not in pals or k + off not in pix:
                continue
            n += 1
            ref = render(pres[k], pals[k], t8, rgb)
            d = int((ref != pix[k + off]).sum())
            if d:
                bad.append((k, d))
        print("offset +%d: %d of %d frames differ; first %s" % (off, len(bad), n, bad[:16]))
        if os.getenv("BG_ALL"):
            print(bad)


if __name__ == "__main__":
    main()


def detail(orig, prep, pixp, off, frames_wanted, outdir):
    """write ref / got / diff PNGs for chosen frames"""
    import zlib
    t8 = gfx._unpack_tiles8(romset.load_aerofgt(os.path.join(ROOT, "mame_roms", "aerofgt.zip"))["tiles"])
    rgb = neo_rgb_table()

    def png(path, a):
        h, w = a.shape
        raw = b"".join(b"\0" + np.dstack([(a >> 16) & 255, (a >> 8) & 255, a & 255]).astype(np.uint8)[y].tobytes() for y in range(h))
        def chunk(t, d):
            return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
        open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) +
                               chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    pals, pres, pix = {}, {}, {}
    with open(orig, "rb") as f:
        while True:
            b = f.read(REC)
            if len(b) < REC:
                break
            k = struct.unpack_from("<I", b)[0]
            if k in frames_wanted:
                pals[k] = np.frombuffer(b[POFF:POFF + 0x800], ">u2").astype(np.int32)
    with open(prep, "rb") as f:
        while True:
            b = f.read(PRE)
            if len(b) < PRE:
                break
            k = struct.unpack_from("<I", b)[0]
            if k in frames_wanted:
                pres[k] = b
    with open(pixp, "rb") as f:
        while True:
            h = f.read(12)
            if len(h) < 12:
                break
            gf, w, hh = struct.unpack("<III", h)
            d = f.read(w * hh * 4)
            if gf - off in frames_wanted:
                pix[gf - off] = np.frombuffer(d, np.uint32).reshape(hh, w) & 0xffffff
    os.makedirs(outdir, exist_ok=True)
    for k in frames_wanted:
        ref = render(pres[k], pals[k], t8, rgb)
        got = pix[k]
        png(os.path.join(outdir, "f%05d_ref.png" % k), ref)
        png(os.path.join(outdir, "f%05d_neo.png" % k), got)
        png(os.path.join(outdir, "f%05d_diff.png" % k), np.where(ref != got, 0xff0000, (ref >> 2) & 0x3f3f3f))
