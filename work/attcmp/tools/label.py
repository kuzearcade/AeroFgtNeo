# label.py x_th.npz al.npz scale : label segments with the original's scene names, print the scene sequence
import sys, numpy as np
SC = [(1,34,'boot'),(84,269,'logo'),(337,1026,'intro'),(1027,1613,'title'),(1681,2368,'demo1'),(2404,2761,'brief2'),
      (2826,3328,'demo2'),(3385,3682,'brief3'),(3736,4838,'demo3'),(4878,5235,'brief4'),(5301,5969,'demo4'),(5998,6386,'rank')]
def name(f):
    for a,b,n in SC:
        if a-5 <= f <= b+5: return n
    return 'blk'
d = np.load(sys.argv[1]); th = d['th'].astype(np.int16); fr = d['fr']
al = np.load(sys.argv[2]); best = al['best']; sc = float(sys.argv[3])
lum = th.mean((1,2,3)); blk = lum < 3
lab = np.array([('blk' if blk[i] else name(best[i])) for i in range(len(th))])
# smooth: majority label over runs separated by black
i = 0; segs = []
while i < len(lab):
    j = i
    while j+1 < len(lab) and blk[j+1] == blk[i]: j += 1
    if blk[i]: segs.append([i, j, 'blk'])
    else:
        v, c = np.unique(lab[i:j+1], return_counts=True); segs.append([i, j, v[c.argmax()]])
    i = j+1
# merge neighbours with the same label (short black flickers inside scenes)
m = []
for s in segs:
    if m and (m[-1][2] == s[2] or (s[2]=='blk' and s[1]-s[0] < 6)): m[-1][1] = s[1]
    elif m and m[-1][2]=='blk' and m[-1][1]-m[-1][0] < 6 and len(m) > 1 and m[-2][2] == s[2]: m.pop(); m[-1][1] = s[1]
    else: m.append(s)
for a, b, n in m:
    print(f"{n:7s} x {fr[a]:6d}-{fr[b]:6d}  len {(b-a+1)*sc:7.1f}")
