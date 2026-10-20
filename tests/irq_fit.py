"""Fit the interrupt-sampling model from an original cycle trace.

For each vblank IRQ k (x_k = k * P exact), report x_k relative to the start of the
instruction that took it (seen) and of the previous one (not seen), per opcode."""
import re
import sys
from fractions import Fraction

P = Fraction(16310552927744250, 10 ** 11)
recs = []
for l in open(sys.argv[1]):
    m = re.match(r'\s*\(interrupted at', l)
    if m:
        recs.append(None)
        continue
    m = re.match(r'(\d+) ([0-9A-F]{6}): (\S+)', l)
    if m:
        recs.append((int(m.group(1)), int(m.group(2), 16), m.group(3)))
rows = []
for i, r in enumerate(recs):
    if r is None and i >= 2 and recs[i - 1] and recs[i - 2] and recs[i + 1][1] == 0x888:
        seen, prev = recs[i - 1], recs[i - 2]
        k = round(Fraction(recs[i + 1][0]) / P)
        while k * P > recs[i + 1][0]:
            k -= 1
        x = k * P
        rows.append((float(x - seen[0]), seen[2], float(x - prev[0]), prev[2], float(x % 1)))
for r in sorted(rows, key=lambda r: (r[1], r[0])):
    print("seen %-6s x-start %7.3f | missed %-6s x-start %7.3f | frac %.3f" % (r[1], r[0], r[3], r[2], r[4]))
