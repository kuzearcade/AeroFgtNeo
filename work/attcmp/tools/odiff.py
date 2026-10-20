# odiff.py : original vs Neo (MAME, game frames) in the non-gameplay scenes; worst 8x8 block per frame
import numpy as np, re
def lab(p): return [(m.group(1), int(m.group(2)), int(m.group(3))) for m in (re.match(r'(\w+)\s+x\s+(\d+)-\s*(\d+)', l) for l in open(p))]
W, H = 320, 224; rec = 12 + W*H*4
def opn(p):
    mm = np.memmap(p, np.uint8, 'r'); n = len(mm)//rec
    fr = np.ndarray((n,), '<u4', mm, 0, (rec,)); return mm, fr
OM, OF = opn('attcmp/orig/pix.bin'); NM, NF = opn('attcmp/neo/pix.bin')
def px(mm, fr, f):
    i = int(np.searchsorted(fr, f))
    if i >= len(fr) or fr[i] != f: return None
    o = i*rec; return np.asarray(mm[o+12:o+rec]).reshape(H, W, 4)[:, :, 2::-1].astype(np.int16)
LO, LN = lab('attcmp/lab_orig.txt'), lab('attcmp/lab_neo.txt')
NG = ('logo', 'intro', 'brief2', 'brief3', 'brief4', 'rank')
out = []; used = {}
for n, a, b in LO:
    if n not in NG: continue
    k = used.get(n, 0); used[n] = k+1
    c = [s for s in LN if s[0] == n]
    if k >= len(c): continue
    na = c[k][1]
    for f in range(a, b+1):
        best = None
        for g in range(na+(f-a)-2, na+(f-a)+3):
            q = px(NM, NF, g); p = px(OM, OF, f)
            if q is None or p is None: continue
            d = np.abs(p-q).mean()
            if best is None or d < best[0]: best = (d, g, np.abs(p-q).max(2))
        if best is None: continue
        d, g, diff = best
        blk = (diff > 24).reshape(28, 8, 40, 8).mean((1, 3))
        by, bx = np.unravel_index(blk.argmax(), blk.shape)
        out.append('%s %d %d %.2f %.2f %d %d %d' % (n, f, g, d, blk.max(), by, bx, (blk > 0.5).sum()))
open('attcmp/odiff.txt', 'w').write('\n'.join(out)); print(len(out))
