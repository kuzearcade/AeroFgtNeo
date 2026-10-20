#!/usr/bin/env python3
"""fhround.py <A/out.txt> <B/out.txt>: compare two fliphash4 runs by the game's logic round
instead of the vblank frame (the builds lose different numbers of logic frames, so the
game is at different points at the same frame).  A set's content belongs to the round
whose end state it shows; a flip's line carries the rounds completed at the flip.  For
each of B's distinct non-empty sets: is its hash in A at all, and at what round offset
(A's round - B's round, the nearest)?  Prints the offset histogram and the misses."""
import sys, collections

def load(p):
    seq = []
    for l in open(p):
        f = l.split()
        if len(f) < 10:
            continue
        gf, hf, s, nh, nc, h, late, mix, dropn, rnd = int(f[0]), int(f[1]), int(f[2]), int(f[3]), int(f[4]), f[5], int(f[6]), int(f[7]), int(f[8]), int(f[9])
        seq.append((rnd, h, nh, gf))
    return seq

A = load(sys.argv[1]); B = load(sys.argv[2])
ha = collections.defaultdict(list)
for rnd, h, nh, gf in A:
    if nh: ha[h].append(rnd)
# B's distinct sets (consecutive repeats collapsed)
hist = collections.Counter(); miss = []; n = 0; prev = None
for rnd, h, nh, gf in B:
    if not nh or h == prev:
        prev = h; continue
    prev = h; n += 1
    if h in ha:
        off = min((abs(r - rnd), r - rnd) for r in ha[h])[1]
        hist[off] += 1
    else:
        miss.append((gf, rnd, nh, h))
print("B distinct non-empty sets %d: found in A %d, missing %d" % (n, n - len(miss), len(miss)))
print("round offsets (A - B) of the found ones:", sorted(hist.items(), key=lambda x: -x[1])[:10])
# the same the other way: A's distinct sets found in B
hb = collections.defaultdict(list)
for rnd, h, nh, gf in B:
    if nh: hb[h].append(rnd)
na = 0; ma = 0; prev = None
for rnd, h, nh, gf in A:
    if not nh or h == prev:
        prev = h; continue
    prev = h; na += 1
    if h not in hb: ma += 1
print("A distinct non-empty sets %d: missing in B %d" % (na, ma))
for t in miss[:12]:
    print("  B gf %d round %d heads %d %s" % t)
