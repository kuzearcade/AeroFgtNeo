#!/usr/bin/env python3
"""bisect_nat.py: which census tables (objects.json "nations") make the by-round entries of nation 0
differ from fz42's (en0_fz42d, rounds < LIM)?  Builds with AEROFGT_NATKEEP, runs 3,200 frames by
round, compares; bisects to each culprit, removes it, repeats until the rest is clean.  Writes the
culprits to work/play/fh/nat_bad.txt and the clean keep-list to nat_keep.txt.  Log: stdout."""
import json, os, subprocess, sys, time
R = os.path.expanduser('~/AeroFgtNeo'); FH = R + '/work/play/fh'; LIM = 3000
tabs = sorted(e['table'] for e in json.load(open(R + '/work/catalog/sprites/objects.json'))['nations'])
def load(p):
    d = {}
    for l in open(p):
        f = l.split()
        if len(f) >= 3: d.setdefault(int(f[0]), []).extend(f[3:])
    return d
def dedup(l):
    r = []
    for e in l:
        if not r or r[-1] != e: r.append(e)
    return r
A = load(FH + '/en0_fz42d/out.txt')
ntest = 0
def test(keep):
    global ntest
    ntest += 1
    kf = FH + '/nat_keep_try.txt'; open(kf, 'w').write(' '.join('%x' % t for t in keep))
    env = dict(os.environ, AEROFGT_DIRECT='1', AEROFGT_DEFS='FUSED=1,GX_XPRE=1,FZ_PD=1,GX_SCAN=1,FZ_DIAG=1', AEROFGT_NATKEEP=kf)
    r = subprocess.run([sys.executable, '-I', 'tools/aerofgt2neo.py', '--out', 'work/out_fzbis'], cwd=R, env=env, capture_output=True, text=True)
    if r.returncode != 0: print('BUILD FAILED', r.stdout[-300:], r.stderr[-300:]); sys.exit(1)
    env2 = dict(os.environ, HARNESS_BOTFILE=R + '/work/play/fp/botsel.lua', NATION='0', HARNESS_BY_ROUND='1', TGT='fz', DETAIL='1')
    subprocess.run(['sh', FH + '/runfh.sh', R + '/work/out_fzbis', FH + '/en0_bis', '3200', 'entries.lua'], env=env2, capture_output=True)
    B = load(FH + '/en0_bis/out.txt')
    bad = 0
    for rr in sorted(set(A) & set(B)):
        if rr >= LIM: break
        if dedup([e for e in A[rr] if e]) != dedup([e for e in B[rr] if e]): bad += 1
    print('test %d: keep %d tables -> differing rounds %d' % (ntest, len(keep), bad), flush=True)
    return bad == 0
culprits = []
remaining = list(tabs)
while True:
    if test(remaining):
        break
    lo, hi = remaining, []
    # bisect: find one culprit within lo (lo is bad as a whole)
    cand = list(remaining)
    while len(cand) > 1:
        half = cand[:len(cand) // 2]
        if not test(half): cand = half
        else:
            other = cand[len(cand) // 2:]
            if not test(other): cand = other
            else:
                print('culprit needs both halves (interaction): taking the first half as a unit'); cand = half  # (rare)
                break
    c = cand[0] if len(cand) == 1 else cand
    print('CULPRIT', ['%x' % x for x in (cand if isinstance(c, list) else [c])], flush=True)
    for x in (cand if isinstance(c, list) else [c]):
        culprits.append(x); remaining.remove(x)
    open(FH + '/nat_bad.txt', 'w').write('\n'.join('%x' % x for x in culprits) + '\n')
open(FH + '/nat_keep.txt', 'w').write(' '.join('%x' % t for t in remaining))
print('DONE culprits', ['%x' % x for x in culprits], 'kept', len(remaining), 'tests', ntest)
