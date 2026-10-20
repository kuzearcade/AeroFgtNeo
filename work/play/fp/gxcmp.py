#!/usr/bin/env python3
"""gxcmp.py <A> <B> lo hi: AUDIT 43's measure - the collision code's cycles a frame in two profiles
(work/play/fp/<name>/frames.npz, each made with its own build's split map: map64g.txt / mapgbg.txt put
gx_scan in category 'dl' and gx_band + gx_bbuild in 'ram'; 'gx_upd' is the object loop's scanner),
over game frames lo..hi, overall and by the frame's player shots (botsel.lua's bot.txt, column 12),
with the frame's active objects (column 4) beside them."""
import sys, os, glob, numpy as np
R = os.path.expanduser('~/AeroFgtNeo/work/play/fp')
lo, hi = int(sys.argv[3]), int(sys.argv[4])

def load(n):
    z = np.load('%s/%s/frames.npz' % (R, n)); F = z['frames']; A = z['data']; names = list(z['names'])
    bot = {}
    for p in glob.glob('%s/%s/c*/bot.txt' % (R, n)):
        for l in open(p):
            f = l.split()
            if len(f) >= 19 and f[0].isdigit(): bot[int(f[0])] = (int(f[4]), int(f[12]))
    m = (F >= lo) & (F <= hi) & (A[:, names.index('cycles')] < 600000)
    col = lambda k: A[m, names.index(k)].astype(np.float64)
    gx = col('c_dl') + col('c_ram')
    ob = np.array([bot.get(int(f), (-1, -1)) for f in F[m]])
    return gx, col('c_gx_upd'), ob[:, 0], ob[:, 1]

a, b = load(sys.argv[1]), load(sys.argv[2])
print('collision (gx_scan + band) cycles a frame   %-10s %-10s' % (sys.argv[1], sys.argv[2]))
print('  all frames             %10.0f %10.0f   (frames %d / %d; objects %.1f / %.1f, shots %.1f / %.1f)' % (
    a[0].mean(), b[0].mean(), len(a[0]), len(b[0]), a[2].mean(), b[2].mean(), a[3].mean(), b[3].mean()))
print('  object loop scanner    %10.0f %10.0f' % (a[1].mean(), b[1].mean()))
for s0, s1 in ((0, 4), (4, 8), (8, 12), (12, 16), (16, 99)):
    ma = (a[3] >= s0) & (a[3] < s1); mb = (b[3] >= s0) & (b[3] < s1)
    if ma.sum() < 20 or mb.sum() < 20: continue
    print('  shots %2d-%-2d            %10.0f %10.0f   (frames %d / %d; objects %.1f / %.1f)' % (
        s0, s1 - 1, a[0][ma].mean(), b[0][mb].mean(), ma.sum(), mb.sum(), a[2][ma].mean(), b[2][mb].mean()))
