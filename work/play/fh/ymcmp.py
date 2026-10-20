#!/usr/bin/env python3
"""ymcmp.py <orig out.txt> <neo out.txt>: ymtap.lua logs of the same game. Per stage visit (runs of the
stage index), FM key-ons / ADPCM-A / ADPCM-B / SSG per 1000 frames on both; then every stretch of the
conversion with no FM key-on for 600+ frames while ADPCM-A plays (music silent, effects on), with the
arcade's FM key-ons over the same frames."""
import sys
def load(p):
    r = {}
    for l in open(p):
        f = l.split()
        if len(f) >= 10: r[int(f[0])] = [int(x) for x in f[1:9]]
    return r
O, N = load(sys.argv[1]), load(sys.argv[2])
fr = sorted(set(O) & set(N))
segs = []; cur = None
for f in fr:
    k = (N[f][0], N[f][1])
    if cur is None or cur[0] != k: cur = [k, f, f]; segs.append(cur)
    else: cur[2] = f
def rate(D, a, b, i): return 1000.0 * sum(D[f][i] for f in range(a, b + 1) if f in D) / max(1, b - a + 1)
print('%-12s %7s %7s | %9s %9s | %9s %9s | %9s %9s' % ('stage(idx,id)', 'from', 'frames', 'FM orig', 'FM neo', 'AA orig', 'AA neo', 'AB orig', 'AB neo'))
for (k, a, b) in segs:
    if b - a < 300: continue
    print('%-12s %7d %7d | %9.1f %9.1f | %9.1f %9.1f | %9.1f %9.1f' % (k, a, b - a + 1, rate(O, a, b, 2), rate(N, a, b, 2), rate(O, a, b, 4), rate(N, a, b, 4), rate(O, a, b, 5), rate(N, a, b, 5)))
print('\nconversion stretches with no FM key-on for 600+ frames while ADPCM-A plays:')
last = None; aa = 0
for f in fr:
    if N[f][2] > 0:
        if last is not None and f - last >= 600 and aa > 0:
            ok = sum(O[g][2] for g in range(last + 1, f) if g in O)
            print('  frames %d-%d (%d): stage %s, ADPCM-A %d; arcade FM key-ons there %d' % (last + 1, f - 1, f - 1 - last, tuple(N[last + 1][:2]), aa, ok))
        last = f; aa = 0
    else: aa += N[f][4]
