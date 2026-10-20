"""Compare the HAL's predicted resume time (BASE + dRES) with the traced start of 0x888,
per frame, together with the predicted wake expiry residue."""
import re
import sys

trace, ring = sys.argv[1], sys.argv[2]
log = {}
for line in open(ring):
    p = line.split()
    if p[0] != "frames":
        log[int(p[0])] = tuple(int(v) for v in p[1:])
recs = []
for l in open(trace):
    if re.match(r'\s*\(interrupted at', l):
        m = re.search(r'at ([0-9A-F]+)', l)
        recs.append(("irq", int(m.group(1), 16)))
        continue
    m = re.match(r'(\d+) ([0-9A-F]{6}):', l)
    if m:
        recs.append((int(m.group(1)), int(m.group(2), 16)))
f = 0
pending = None
for i, r in enumerate(recs):
    if r[0] == "irq" and r[1] < 0x80000:
        f += 1
        X = recs[i + 1][0]
        dX, dRES, dT = log[f % 32]
        pending = (f, X - dX + dRES)
    elif r[0] != "irq" and r[1] == 0x888 and pending:
        fr, pred = pending
        print("frame %3d resume actual-pred %4d  pred mod10 %d" % (fr, r[0] - pred, pred % 10))
        pending = None
