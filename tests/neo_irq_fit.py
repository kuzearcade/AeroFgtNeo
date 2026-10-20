"""Neo counterpart of irq_fit.py: believed assertion T = X - dX (HAL log) relative to
the instruction that took the virtual IRQ and the previous one."""
import re
import sys

trace, ring = sys.argv[1], sys.argv[2]
dx = {}
for line in open(ring):
    p = line.split()
    if p[0] != "frames":
        dx[int(p[0])] = int(p[1])
recs = []
for l in open(trace):
    if re.match(r'\s*\(interrupted at', l):
        m = re.search(r'at ([0-9A-F]+)', l)
        recs.append(("irq", int(m.group(1), 16)))
        continue
    m = re.match(r'(\d+) ([0-9A-F]{6}): (\S+)', l)
    if m:
        recs.append((int(m.group(1)), int(m.group(2), 16), m.group(3)))
frame = 0
rows = []
for i, r in enumerate(recs):
    if r[0] == "irq" and r[1] < 0x80000:
        frame += 1
        X = recs[i + 1][0]
        if frame >= 2 and frame % 32 in dx:
            T = X - dx[frame % 32]
            seen, prev = recs[i - 1], recs[i - 2]
            rows.append((seen[2], T - seen[0], prev[2], T - prev[0], frame))
for r in sorted(rows, key=lambda r: (r[0], r[1])):
    print("frame %3d seen %-6s T-start %4d | missed %-6s T-start %4d" % (r[4], r[0], r[1], r[2], r[3]))
