# scenes.py th.npz : segment into scenes by cuts and black frames
import sys, numpy as np
d = np.load(sys.argv[1]); th = d['th'].astype(np.int16); fr = d['fr']
thr = float(sys.argv[2]) if len(sys.argv) > 2 else 40
lum = th.mean((1, 2, 3))
diff = np.r_[0, np.abs(th[1:] - th[:-1]).mean((1, 2, 3))]
start = 0; segs = []
for i in range(1, len(th)):
    blk = lum[i] < 3; pblk = lum[i-1] < 3
    if diff[i] > thr or blk != pblk:
        segs.append((start, i-1)); start = i
segs.append((start, len(th)-1))
for a, b in segs:
    if b - a < 2 and lum[a:b+1].mean() >= 3: continue
    print(f"{fr[a]:6d}-{fr[b]:6d} len {b-a+1:5d} lum {lum[a:b+1].mean():5.1f}{' BLACK' if lum[a:b+1].max()<3 else ''}")
