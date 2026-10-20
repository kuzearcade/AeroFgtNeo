# mdiff.py : MiSTer capture vs MAME Neo (screen frames) in the non-gameplay scenes, full resolution.
# Per MiSTer frame: best MAME frame near the expected one, colour-corrected diff, worst 8x8 block.
import numpy as np, re
def lab(p): return [(m.group(1), int(m.group(2)), int(m.group(3))) for m in (re.match(r'(\w+)\s+x\s+(\d+)-\s*(\d+)', l) for l in open(p))]
W, H = 320, 224; rec = 12 + W*H*4
mis = np.memmap('attcmp/mister.rgb', np.uint8, 'r').reshape(-1, H, W, 3)
nb = np.memmap('attcmp/s_neo/pix.bin', np.uint8, 'r')
def neo(f):  # screen frame f (1-based)
    o = (f-1)*rec; return np.asarray(nb[o+12:o+rec]).reshape(H, W, 4)[:, :, 2::-1]
LM, LN = lab('attcmp/lab_mis.txt'), lab('attcmp/lab_s_neo.txt')
NG = ('logo', 'intro', 'brief2', 'brief3', 'brief4', 'rank')
# colour model: fit per channel on a few matched frames later; start with identity
res = []
used = {}
for n, a, b in LM:
    if n not in NG: continue
    k = used.get(n, 0); used[n] = k+1
    cands = [s for s in LN if s[0] == n]
    if k >= len(cands): continue
    na = cands[k][1]
    prev = na
    for c in range(a, b+1, 1):
        exp = na + round((c - a)*59.185/60)
        best = None
        for f in range(exp-3, exp+4):
            if f < 1 or f > 22000: continue
            d = np.abs(mis[c].astype(np.int16) - neo(f).astype(np.int16)).mean()
            if best is None or d < best[0]: best = (d, f)
        if best is None: continue
        d, f = best
        diff = np.abs(mis[c].astype(np.int16) - neo(f).astype(np.int16)).max(2)
        blk = diff.reshape(28, 8, 40, 8).mean((1, 3))
        by, bx = np.unravel_index(blk.argmax(), blk.shape)
        res.append((n, c, f, d, blk.max(), by, bx))
np.save('attcmp/mdiff.npy', np.array([r[1:] for r in res], float))
open('attcmp/mdiff.txt', 'w').write('\n'.join('%s %d %d %.2f %.1f %d %d' % r for r in res))
print(len(res))
