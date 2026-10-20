"""fpmerge.py <name>: join the chunks' prof.txt (per-frame cycles by category, fprof.c) and
stat.txt (per-frame HAL state, fprof.lua) of work/play/fp/<name>/c*/ into <name>/frames.npz.
Chunk c<F> owns frames F..F+9999 (its first prof row is partial)."""
import sys, os, glob, re, numpy as np, hashlib
R = os.path.expanduser('~/AeroFgtNeo/work/play'); D = '%s/fp/%s' % (R, sys.argv[1])
STAT = ('f vpos LATE DROP DROPN OVERRUN CARRY MIXN PALDEFER BGDEFER SLOWB TIMN YN DELTAN BLKN RCLN BGMISS PALMISS ZOOM VZN PRIN IDLES APXF '
        'UNFIN K0 DEADLINE KDL BUSY EST SPR_W SPR_DONE SDONE ORDN SPS SPJ SPG GNEXT PREV SHOWN ST0 ST1 ST2 START0 START1 START2 END0 END1 END2 '
        'BLK FIXUSED QN WP LN0 LN1 LN2 LN3 LN4 PASS FAILS SKIPN BOFF DLR_ON DELTA PON ' + ' '.join('WHY%d' % i for i in range(1, 15)) +
        ' PALDIRTY BGPEND BGLOW NOBJ NOBJ1 ' + ' '.join('O_%s' % c for c in 'hud boss city air ebul expl gnd gstr item naval player bomb shot screen shadow other'.split()) + ' HASH').split()
rows = {}; cats = None; nm = None
for d in sorted(glob.glob(D + '/c*/'), key=lambda d: int(re.search(r'c(\d+)/$', d).group(1))):
    F = int(re.search(r'c(\d+)/$', d).group(1)); lo, hi = F, F + 9999
    P = {}
    if not os.path.exists(d + 'prof.txt'): continue
    for l in open(d + 'prof.txt'):
        if l[0] == '#':
            h = l.split()[1:]; n = 64; cats = h[5:5 + n]; continue
        p = l.split()
        if len(p) < 7 or not l.endswith('\n'): continue
        f = int(p[1])
        if f < lo or f > hi: continue
        n = int(p[5])
        if len(p) < 8 + n: continue
        nmk = int(p[6 + n]); nm = nmk
        if len(p) < 7 + n + nmk: continue
        P[f] = [int(p[2]), int(p[3]), int(p[4])] + [int(x) for x in p[6:6 + n]] + [int(x) for x in p[7 + n:7 + n + nmk]]
    for l in open(d + 'stat.txt'):
        p = l.split()
        if len(p) != 100 or not l.endswith('\n'): continue
        f = int(p[0])
        if f < lo or f > hi or f not in P: continue
        s = [int(x) for x in p[:-1]] + [int(p[-1], 16)]
        rows[f] = P[f] + s
fr = sorted(rows); A = np.array([rows[f] for f in fr], dtype=np.int64)
nc = 64; np_ = 3 + nc + nm
names = ['cycles', 'instrs', 'irqs'] + ['c_' + c for c in cats] + ['m_%d' % i for i in range(nm)] + STAT
assert A.shape[1] == len(names), (A.shape, len(names))
np.savez_compressed(D + '/frames.npz', frames=np.array(fr), data=A, names=np.array(names))
print(len(fr), 'frames', fr[0], '..', fr[-1], 'missing', (fr[-1] - fr[0] + 1) - len(fr), 'cols', len(names))
