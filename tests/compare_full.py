"""Check the real-cart screen (tilemaps + sprites) against a reference render.

Reference = what MAME's original shows (aerofgt screen_update, vsystem_spr):
tilemaps of virtual vblank k (HARNESS_PRE record k), sprites buffered at vblank k-1
(record k-1), the original palette of game frame k, converted to the colours MAME
shows on the Neo (tools/gfx.py colour table + DAC).  The conversion's capture for
game frame k + offset (HARNESS_PIXELS) is compared with it.
usage: compare_full.py orig.bin pre.bin pix_neo.bin [offset] [png-dir frames...]
"""

import os
import struct
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gfx      # noqa: E402
import romset   # noqa: E402
from compare_bg import REC, POFF, PRE, neo_rgb_table, render   # noqa: E402

SPR_OFF = 4 + 0x800 + 0x20 + 0x4000
LUT_OFF = SPR_OFF + 0x2000


def draw_sprites(out, pri, pre, pal, spr, rgb):
    """vsystem_spr draw_sprites with aerofgt's callbacks, onto out (RGB) / pri.  Drawn from
    the last entry to the first, a covered pixel (pri 31) is never drawn again: the last
    entry ends on top."""
    ram = np.frombuffer(pre[SPR_OFF:SPR_OFF + 0x2000], ">u2").astype(np.int32)
    lut = np.frombuffer(pre[LUT_OFF:LUT_OFF + 0x8000], ">u2").astype(np.int32)
    end = 0
    while end < 0x200 and not (ram[end] >> 14) & 1:
        end += 1
    for offs in range(end - 1, -1, -1):
        if ram[offs] & 0x8000:
            continue
        a = 4 * (ram[offs] & 0x3ff)
        w0, w1, w2, w3 = (int(v) for v in ram[a:a + 4])
        oy, ysize, zoomy = w0 & 0x1ff, (w0 >> 9) & 7, w0 >> 12
        ox, xsize, zoomx = w1 & 0x1ff, (w1 >> 9) & 7, w1 >> 12
        flipx, flipy = (w2 >> 14) & 1, (w2 >> 15) & 1
        color = (w2 >> 8) & 0x3f
        mp = ((w2 & 1) << 16) | w3
        pmask = 0 if color & 0x20 else 0xcccc
        zx, zy = 32 - zoomx, 32 - zoomy
        sx_scale, sy_scale = zx << 11, zy << 11
        dw = (sx_scale * 16 + 0x8000) >> 16
        dh = (sy_scale * 16 + 0x8000) >> 16
        dx = (16 << 16) // dw
        dy = (16 << 16) // dh
        xi_src = ((np.arange(dw) * dx) >> 16) if not flipx else ((((dw - 1) * dx) - np.arange(dw) * dx) >> 16)
        yi_src = ((np.arange(dh) * dy) >> 16) if not flipy else ((((dh - 1) * dy) - np.arange(dh) * dy) >> 16)
        palbase = 512 + 16 * (color % 32)
        ys = range(ysize, -1, -1) if flipy else range(ysize + 1)
        for ycnt in ys:
            yo = oy + ycnt * zy // 2
            xs = range(xsize, -1, -1) if flipx else range(xsize + 1)
            for xcnt in xs:
                code = int(lut[mp & 0x3fff]) & 0x7fff
                mp += 1
                xo = ox + xcnt * zx // 2
                tile = spr[code][np.ix_(yi_src, xi_src)]
                for py in (yo, yo - 0x200):
                    for px in (xo, xo - 0x200):
                        y0, x0 = max(py, 0), max(px, 0)
                        y1, x1 = min(py + dh, 224), min(px + dw, 320)
                        if y0 >= y1 or x0 >= x1:
                            continue
                        t = tile[y0 - py:y1 - py, x0 - px:x1 - px].astype(np.int32)
                        o = out[y0:y1, x0:x1]
                        p = pri[y0:y1, x0:x1]
                        opaque = t != 15
                        allowed = (((1 << (p & 0x1f)) & pmask) == 0) & (p != 31)   # pdrawgfx: bit 31 always masked
                        draw = opaque & allowed
                        o[draw] = rgb[pal[palbase + t[draw]] & 0x7fff]
                        p[opaque] = 31


def render_full(pre_bg, pre_spr, pal, t8, spr, rgb):
    out = render(pre_bg, pal, t8, rgb).copy()
    # priority bitmap as aerofgt's screen_update leaves it: 1 tilemap 0, |2 opaque tilemap 1
    raster = np.frombuffer(pre_bg[4:4 + 0x800], ">u2")
    io = pre_bg[4 + 0x800:4 + 0x820]
    vram = np.frombuffer(pre_bg[4 + 0x820:4 + 0x820 + 0x4000], ">u2").reshape(2, 64, 64).astype(np.int32)
    banks = np.frombuffer(io[0:8], np.uint8).astype(np.int32)
    sy = struct.unpack_from(">H", io, 16)[0] & 511
    sx = (int(raster[0x200]) - 20) & 511
    ys, xs = np.mgrid[0:224, 0:320]
    tx, ty = (xs + sx) & 511, (ys + sy) & 511
    cell = vram[1][ty >> 3, tx >> 3]
    phys = (cell & 0x7ff) | (banks[4 + ((cell >> 11) & 3)] << 11)
    pen = t8[phys & 0x7fff, ty & 7, tx & 7]
    pri = np.where(pen == 15, 1, 3).astype(np.int32)
    draw_sprites(out, pri, pre_spr, pal, spr, rgb)
    return out


def load(orig, prep, pixp):
    pals, pres, pix = {}, {}, {}
    with open(orig, "rb") as f:
        while True:
            b = f.read(REC)
            if len(b) < REC:
                break
            pals[struct.unpack_from("<I", b)[0]] = np.frombuffer(b[POFF:POFF + 0x800], ">u2").astype(np.int32)
    with open(prep, "rb") as f:
        while True:
            b = f.read(PRE)
            if len(b) < PRE:
                break
            pres[struct.unpack_from("<I", b)[0]] = b
    with open(pixp, "rb") as f:
        while True:
            h = f.read(12)
            if len(h) < 12:
                break
            gf, w, hh = struct.unpack("<III", h)
            pix[gf] = np.frombuffer(f.read(w * hh * 4), np.uint32).reshape(hh, w) & 0xffffff
    return pals, pres, pix


def png(path, img):
    import zlib
    h, w = img.shape
    raw = b"".join(b"\0" + np.dstack([(img >> 16) & 255, (img >> 8) & 255, img & 255]).astype(np.uint8)[y].tobytes()
                   for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def main():
    orig, prep, pixp = sys.argv[1:4]
    off = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    regions = romset.load_aerofgt(os.path.join(ROOT, "mame_roms", "aerofgt.zip"))
    t8 = gfx._unpack_tiles8(regions["tiles"])
    spr = gfx._unpack_sprites(regions["sprites"])
    rgb = neo_rgb_table()
    pals, pres, pix = load(orig, prep, pixp)
    if len(sys.argv) > 5:
        outdir = sys.argv[5]
        for k in map(int, sys.argv[6:]):
            ref = render_full(pres[k], pres[k - 1], pals[k], t8, spr, rgb)
            got = pix[k + off]
            png(os.path.join(outdir, "f%05d_ref.png" % k), ref)
            png(os.path.join(outdir, "f%05d_got.png" % k), got)
            png(os.path.join(outdir, "f%05d_diff.png" % k), np.where(ref != got, 0xff0000, (got >> 2) & 0x3f3f3f))
            print(k, int((ref != got).sum()))
        return
    bad, n = [], 0
    for k in sorted(pres):
        if k - 1 not in pres or k not in pals or k + off not in pix:
            continue
        n += 1
        ref = render_full(pres[k], pres[k - 1], pals[k], t8, spr, rgb)
        d = int((ref != pix[k + off]).sum())
        if d:
            bad.append((k, d))
    print("offset +%d: %d of %d frames differ; first %s" % (off, len(bad), n, bad[:16]))
    if os.getenv("FULL_ALL"):
        print(bad)


if __name__ == "__main__":
    main()
