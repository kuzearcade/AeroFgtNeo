"""Parallel tests/compare_full.py for long runs: full_par.py orig.bin pre.bin pix_neo.bin [offset] [jobs]
Prints the same list as FULL_ALL=1 compare_full.py (frames whose picture differs, with
the number of differing pixels).  Each worker seeks to its own frame range."""
import multiprocessing as mp
import os
import struct
import sys

import numpy as np

sys.path.insert(0, '/home/vboxuser/AeroFgtNeo/tests')
sys.path.insert(0, '/home/vboxuser/AeroFgtNeo/tools')
import compare_full as cf   # noqa: E402
import gfx                  # noqa: E402
import romset               # noqa: E402

ORIG, PREP, PIXP = sys.argv[1:4]
OFF = int(sys.argv[4]) if len(sys.argv) > 4 else 1
JOBS = int(sys.argv[5]) if len(sys.argv) > 5 else 12


def index(path, rec, key_at=0):
    """game frame -> file offset, for fixed-size records."""
    n = os.path.getsize(path) // rec
    out = {}
    with open(path, 'rb') as f:
        for i in range(n):
            f.seek(i * rec + key_at)
            out[struct.unpack('<I', f.read(4))[0]] = i * rec
    return out


def pix_index(path):
    out = {}
    with open(path, 'rb') as f:
        pos = 0
        while True:
            f.seek(pos)
            h = f.read(12)
            if len(h) < 12:
                return out
            gf, w, hh = struct.unpack('<III', h)
            out[gf] = (pos + 12, w, hh)
            pos += 12 + w * hh * 4


def work(args):
    ks, oi, pi, xi = args
    regions = romset.load_aerofgt(os.path.join(cf.ROOT, 'mame_roms', 'aerofgt.zip'))
    t8 = gfx._unpack_tiles8(regions['tiles'])
    spr = gfx._unpack_sprites(regions['sprites'])
    rgb = cf.neo_rgb_table()
    bad = []
    with open(ORIG, 'rb') as fo, open(PREP, 'rb') as fp, open(PIXP, 'rb') as fx:
        def pre(k):
            fp.seek(pi[k])
            return fp.read(cf.PRE)
        for k in ks:
            fo.seek(oi[k] + cf.POFF)
            pal = np.frombuffer(fo.read(0x800), '>u2').astype(np.int32)
            pos, w, h = xi[k + OFF]
            fx.seek(pos)
            got = np.frombuffer(fx.read(w * h * 4), np.uint32).reshape(h, w) & 0xffffff
            ref = cf.render_full(pre(k), pre(k - 1), pal, t8, spr, rgb)
            d = int((ref != got).sum())
            if d:
                bad.append((k, d))
    return bad


def main():
    oi = index(ORIG, cf.REC)
    pi = index(PREP, cf.PRE)
    xi = pix_index(PIXP)
    ks = [k for k in sorted(pi) if k - 1 in pi and k in oi and k + OFF in xi]
    chunks = [ks[i::JOBS] for i in range(JOBS)]
    with mp.Pool(JOBS) as p:
        res = p.map(work, [(c, oi, pi, xi) for c in chunks])
    bad = sorted(b for r in res for b in r)
    print('offset +%d: %d of %d frames differ; first %s' % (OFF, len(bad), len(ks), bad[:16]))
    print(bad)


if __name__ == '__main__':
    main()
