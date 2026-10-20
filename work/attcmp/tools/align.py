# align.py ref_th.npz ref_from ref_to x_th.npz : nearest reference frame for each frame of x (20x14 features)
# prints runs: x frames -> ref frames, with mean distance
import sys, numpy as np
def feat(th):
    t = th.astype(np.float32).reshape(len(th), 14, 4, 20, 4, 3).mean((2, 4)).reshape(len(th), -1)
    return t
R = np.load(sys.argv[1]); a, b = int(sys.argv[2]), int(sys.argv[3])
rf = feat(R['th'][a:b]); rfr = R['fr'][a:b]
X = np.load(sys.argv[4]); xf = feat(X['th']); xfr = X['fr']
rn = (rf**2).sum(1)
best = np.zeros(len(xf), np.int64); dist = np.zeros(len(xf), np.float32)
for s in range(0, len(xf), 2000):
    blk = xf[s:s+2000]; d = (blk**2).sum(1)[:, None] + rn[None] - 2*blk@rf.T
    best[s:s+2000] = d.argmin(1); dist[s:s+2000] = np.sqrt(np.maximum(d.min(1), 0)/rf.shape[1])
np.savez(sys.argv[5] if len(sys.argv) > 5 else '/dev/null', best=rfr[best], dist=dist, xfr=xfr)
