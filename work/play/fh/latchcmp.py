#!/usr/bin/env python3
"""latchcmp.py <latchtap out.txt>: commands the 68000 wrote to REG_SOUND that the original sound driver never
read (a newer write first), the gaps between consecutive writes, and the writing PCs."""
import sys, collections
ev = []
for l in open(sys.argv[1]):
    f = l.split()
    if len(f) >= 6 and f[0] in ("W", "R"): ev.append((f[0], int(f[1]), float(f[2]), int(f[3], 16), f[5]))
W = [i for i, e in enumerate(ev) if e[0] == 'W' and e[1] > 0]
lost = []; gaps = []; pcs = collections.Counter()
for k, i in enumerate(W):
    pcs[ev[i][4]] += 1
    j = W[k + 1] if k + 1 < len(W) else len(ev)
    if k + 1 < len(W): gaps.append(ev[W[k + 1]][2] - ev[i][2])
    got = any(ev[x][0] == 'R' and ev[x][3] == ev[i][3] and int(ev[x][4], 16) < 0x7800 for x in range(i + 1, j))
    if not got: lost.append((ev[i][1], ev[i][2], ev[i][3], ev[j][3] if j < len(ev) else None, ev[j][2] - ev[i][2] if j < len(ev) else None))
gaps.sort()
print('writes %d; the original driver never read %d of them' % (len(W), len(lost)))
print('write PCs:', dict(pcs.most_common(6)))
print('smallest gaps between writes (us):', ['%.0f' % g for g in gaps[:10]])
print('writes closer than 1 ms apart: %d' % sum(1 for g in gaps if g < 1000))
for f, t, v, nv, dt in lost[:25]: print('  lost: frame %d cmd %02x, overwritten by %s %.0f us later' % (f, v, '%02x' % nv if nv is not None else '-', dt or 0))
