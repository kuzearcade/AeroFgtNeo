# runs.py al.npz [maxgap] : collapse the alignment into runs where the matched ref frame advances steadily
import sys, numpy as np
d = np.load(sys.argv[1]); b = d['best']; ds = d['dist']; x = d['xfr']
gap = int(sys.argv[2]) if len(sys.argv) > 2 else 30
s = 0
def out(s, e):
    if e - s < 8: return
    print(f"x {x[s]:6d}-{x[e]:6d} ({e-s+1:5d})  ref {b[s]:5d}..{b[e]:5d}  span {b[e]-b[s]+1:5d}  dist {np.median(ds[s:e+1]):5.1f}")
for i in range(1, len(b)):
    if not (0 <= b[i]-b[i-1] <= gap): out(s, i-1); s = i
out(s, len(b)-1)
