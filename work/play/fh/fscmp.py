#!/usr/bin/env python3
"""fscmp.py <A/out.txt> <B/out.txt>: flipscroll.lua outputs of two builds: for every
distinct non-empty set content of B (its head-column hash), the same content in A must
come with the same tilemap scroll registers (x0, x1 at the flip), else sprites and
tilemaps are misaligned by the frames' scroll difference.  Prints the matches, the
scroll-equal count, and the first mismatches with their scroll values."""
import sys, collections

def load(p):
    d = collections.defaultdict(list)
    for l in open(p):
        f = l.split()
        if len(f) < 11:
            continue
        gf, hf, s, nh, nc, h = int(f[0]), int(f[1]), int(f[2]), int(f[3]), int(f[4]), f[5]
        x0, x1 = int(f[9]), int(f[10])
        if nh:
            d[h].append((gf, x0, x1))
    return d

A = load(sys.argv[1]); B = load(sys.argv[2])
found = eq = 0; miss = []
for h, lb in B.items():
    if h not in A:
        continue
    la = A[h]
    for gf, x0, x1 in lb[:1]:
        found += 1
        if any(a[1] == x0 and a[2] == x1 for a in la):
            eq += 1
        else:
            miss.append((gf, x0, x1, la[0]))
print("B's distinct sets found in A: %d; same scroll: %d; different: %d" % (found, eq, len(miss)))
for t in miss[:10]:
    print("  B gf %d x0 %d x1 %d  A first (gf %d x0 %d x1 %d)" % (t[0], t[1], t[2], t[3][0], t[3][1], t[3][2]))
