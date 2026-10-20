#!/usr/bin/env python3
"""encmp.py <A/out.txt> <B/out.txt>: compare two entries.lua outputs (DETAIL=1) per logic
round: the entry sequences (pieces, then the pool records tagged P) must be the same.
Prints the rounds compared, equal, different, and for the first differing rounds the
entries side by side (A only / B only, in order)."""
import sys

def load(p, shift=0):
    # (the fused build's records are stamped before the builder point increments the round:
    # its keys are one less than the walk's)
    d = {}
    for l in open(p):
        f = l.split()
        if len(f) < 3:
            continue
        r = int(f[0]) + shift; ents = f[3:]
        d.setdefault(r, []).extend(ents)
    return d

import os
MASKW3 = os.environ.get('MASKW3') == '1'   # the map word left out (animation phases tick per vblank)
def norm(e):
    if MASKW3 and len(e) >= 16:
        return e[:-4] + '----'
    return e

def dedup(l):
    # a budget stop inside a shape routine re-dispatches the same entry (its first try wrote
    # nothing): consecutive repeats count once
    r = []
    for e in l:
        if not r or r[-1] != e: r.append(e)
    return r

A = load(sys.argv[1]); B = load(sys.argv[2], 1)
common = sorted(set(A) & set(B))
eq = 0; diff = []
for r in common:
    a = dedup([norm(e) for e in A[r] if e]); b = dedup([norm(e) for e in B[r] if e])
    if a == b:
        eq += 1
    else:
        diff.append(r)
print("rounds A %d B %d common %d: equal %d different %d" % (len(A), len(B), len(common), eq, len(diff)))
onlyA = sorted(set(A) - set(B)); onlyB = sorted(set(B) - set(A))
print("rounds only in A %d (first %s), only in B %d (first %s)" % (len(onlyA), onlyA[:5], len(onlyB), onlyB[:5]))
for r in diff[:6]:
    a = dedup([norm(e) for e in A[r] if e]); b = dedup([norm(e) for e in B[r] if e])
    sa, sb = set(a), set(b)
    print("round %d: A %d entries, B %d entries; same multiset: %s" % (r, len(a), len(b), sorted(a) == sorted(b)))
    print("   A only:", [e for e in a if e not in sb][:8])
    print("   B only:", [e for e in b if e not in sa][:8])
    if sorted(a) == sorted(b):
        for i, (x, y) in enumerate(zip(a, b)):
            if x != y:
                print("   first order difference at %d: A %s B %s" % (i, x, y)); break
