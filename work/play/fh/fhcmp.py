#!/usr/bin/env python3
"""fhcmp.py <a/out.txt> <b/out.txt>: compare two fliphash runs (work/play/fh/fliphash.lua)
of the same bot movie.  Lines: game frame, HAL_FRAMES, set, heads, columns, hash,
HAL_SPR_LATE, the set's MIX byte, HAL_SPR_DROPN.  Flips are joined by HAL_FRAMES; a flip
is "clean" in a run when HAL_SPR_LATE did not grow since the previous flip and the
set's MIX byte is 0 (no drop, no mixed set).  Reports: flips, matched frames, equal
hashes, the differences among frames clean in both runs (with the first few), and how
many of B's hashes appear in A within +-2 frames (a late set shows the same content a
frame later)."""
import sys, collections

def load(p):
    d = {}
    seq = []
    last_late = None
    for l in open(p):
        f = l.split()
        if len(f) < 9:
            continue
        gf, hf, s, nh, nc, h, late, mix, dropn = int(f[0]), int(f[1]), int(f[2]), int(f[3]), int(f[4]), f[5], int(f[6]), int(f[7]), int(f[8])
        clean = (last_late is None or late == last_late) and mix == 0
        last_late = late
        d[hf] = (gf, nh, nc, h, clean, late, mix)
        seq.append(hf)
    return d, seq

a, sa = load(sys.argv[1])
b, sb = load(sys.argv[2])
print("flips A %d B %d" % (len(a), len(b)))
common = sorted(set(a) & set(b))
eq = diff = both_clean = diff_clean = 0
first = []
hash_a = collections.defaultdict(list)
for hf, v in a.items():
    hash_a[v[3]].append(hf)
near = 0
nonempty_b = 0
for hf in common:
    va, vb = a[hf], b[hf]
    if va[3] == vb[3]:
        eq += 1
    else:
        diff += 1
    if va[4] and vb[4]:
        both_clean += 1
        if va[3] != vb[3]:
            diff_clean += 1
            if len(first) < 12:
                first.append((hf, va[0], va[1], va[2], vb[1], vb[2], va[3], vb[3]))
for hf, vb in b.items():
    if vb[1] == 0:
        continue
    nonempty_b += 1
    if any(abs(x - hf) <= 2 for x in hash_a.get(vb[3], [])):
        near += 1
print("common frames %d: equal %d different %d" % (len(common), eq, diff))
print("both clean %d: different %d" % (both_clean, diff_clean))
print("B's non-empty sets found in A within +-2 frames: %d of %d" % (near, nonempty_b))
la = max(v[5] for v in a.values()) if a else 0
lb = max(v[5] for v in b.values()) if b else 0
print("LATE at the end: A %d B %d; MIX!=0 flips: A %d B %d" % (la, lb, sum(1 for v in a.values() if v[6]), sum(1 for v in b.values() if v[6])))
for t in first:
    print("  HF %d gf %d: A heads %d cols %d / B heads %d cols %d  %s %s" % t)
