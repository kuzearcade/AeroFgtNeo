"""Tilemap errors that were not logged: bgcheck.py dir [offset] [jobs] [min_px]
dir holds orig.bin pre.bin pix_neo.bin npal.bin hal.bin (a harness run with
HARNESS_PRE/PIXELS/NEOPAL/HALLOG).  A tilemap error pixel differs from the reference
where the reference has no sprite from 3 frames before to 2 after (so neither late nor
mixed sprite sets explain it).  A frame counts as logged when its slot (or the next)
has the tilemap or palette slip bit, or a stale range logged later (HAL_BG_RETROF..) covers it."""
import multiprocessing as mp
import os
import struct
import sys

import numpy as np

sys.path.insert(0, '/home/vboxuser/AeroFgtNeo/tests')
sys.path.insert(0, '/home/vboxuser/AeroFgtNeo/tools')
sys.path.insert(0, '/home/vboxuser/AeroFgtNeo/work')
import compare_full as cf   # noqa: E402
import gfx                  # noqa: E402
import hallog               # noqa: E402
import romset               # noqa: E402
from compare_bg import render   # noqa: E402

D = sys.argv[1]
OFF = int(sys.argv[2]) if len(sys.argv) > 2 else 1
JOBS = int(sys.argv[3]) if len(sys.argv) > 3 else 14
MINPX = int(sys.argv[4]) if len(sys.argv) > 4 else 64
P = lambda n: os.path.join(D, n)


def work(args):
    ks, lo_of = args
    import full_par as fp
    oi = fp.index(P('orig.bin'), cf.REC)
    pi = fp.index(P('pre.bin'), cf.PRE)
    xi = fp.pix_index(P('pix_neo.bin'))
    reg = romset.load_aerofgt(os.path.join(cf.ROOT, 'mame_roms', 'aerofgt.zip'))
    t8 = gfx._unpack_tiles8(reg['tiles'])
    spr = gfx._unpack_sprites(reg['sprites'])
    rgb = cf.neo_rgb_table()
    out = []
    with open(P('orig.bin'), 'rb') as fo, open(P('pre.bin'), 'rb') as fpp, open(P('pix_neo.bin'), 'rb') as fx:
        def pre(k):
            fpp.seek(pi[k])
            return fpp.read(cf.PRE)
        for k in ks:
            lo = min(lo_of.get(k, k - 8), k - 8)
            if lo - 1 not in pi or k + 2 not in pi or k + OFF not in xi or k not in oi:
                continue
            fo.seek(oi[k] + cf.POFF)
            pal = np.frombuffer(fo.read(0x800), '>u2').astype(np.int32)
            pos, w, h = xi[k + OFF]
            fx.seek(pos)
            got = np.frombuffer(fx.read(w * h * 4), np.uint32).reshape(h, w) & 0xffffff
            pk = pre(k)
            bg = render(pk, pal, t8, rgb)
            e = got != bg
            if not e.any():
                continue
            for j in range(lo, k + 3):
                pj = pre(j)
                e &= cf.render_full(pj, pre(j - 1), pal, t8, spr, rgb) == render(pj, pal, t8, rgb)
            n = int(e.sum())
            if n >= MINPX:
                out.append((k, n))
    return out


def main():
    import full_par as fp
    L = hallog.load(P('hal.bin'))
    ks = sorted(L)
    # HAL_FRAMES <-> game frame, slips, stale ranges
    hf = {k: L[k]('HAL_FRAMES', 4) for k in ks}
    gf_of = {v: k for k, v in hf.items()}
    covered = set()
    for a, b in zip(ks, ks[1:]):
        if L[b]('HAL_BG_RETRON', 4) != L[a]('HAL_BG_RETRON', 4):
            lo = L[b]('HAL_BG_RETROF', 2)
            hi = hf[b] & 0xffff
            for f in range(lo, hi + 1):
                g = gf_of.get((hf[b] & ~0xffff) | f)
                if g is not None:
                    covered.add(g)
    d = open(P('npal.bin'), 'rb').read()
    R = 24 + 0x2000
    bgslip = set()
    for i in range(len(d) // R):
        g = struct.unpack_from('<I', d, i * R)[0]
        if struct.unpack_from('<H', d, i * R + 12)[0] & 3:      # tilemap or palette slip
            bgslip.add(g)
    # sprites the Neo may show at frame k: from the list the shown set was started
    # from (its HAL_SPR_RDY - 1, one more for a mixed set) on
    lo_of = {}
    for k in ks:
        g = L.get(k + OFF)
        if g is None:
            continue
        s_ = g('HAL_SPR_SHOWN', 2)
        if s_ > 2:
            continue
        rdy = g('HAL_SPR_RDY', 6)[0] if False else int.from_bytes(
            g('HAL_SPR_RDY', 6).to_bytes(6, 'big')[2 * s_:2 * s_ + 2], 'big')
        start = gf_of.get((hf[k + OFF] & ~0xffff) | ((rdy - 1) & 0xffff))
        if start is not None:
            lo_of[k] = start - 2
    cand = [k for k in fp.index(P('pre.bin'), cf.PRE)]
    with mp.Pool(JOBS) as p:
        res = p.map(work, [(cand[i::JOBS], lo_of) for i in range(JOBS)])
    errs = sorted(x for r in res for x in r)
    unl = [(k, n) for k, n in errs if not (k in covered or any((k + o) in bgslip for o in (OFF - 1, OFF, OFF + 1)))]
    print('frames with tilemap errors (>= %d px): %d; logged by a slip %d, by a stale range %d; unlogged %d'
          % (MINPX, len(errs), sum(1 for k, n in errs if any((k + o) in bgslip for o in (OFF - 1, OFF, OFF + 1))),
             sum(1 for k, n in errs if k in covered), len(unl)))
    print('unlogged:', unl[:40])
    print('errs:', errs)


if __name__ == '__main__':
    main()
