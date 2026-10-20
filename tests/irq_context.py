"""Show the instructions just before the n-th game IRQ, timed relative to the previous
handler start (virtual time), for an original or a Neo trace."""
import re
import sys

mode, path, nth = sys.argv[1], sys.argv[2], int(sys.argv[3])
lines = open(path).read().splitlines()
recs = []
for l in lines:
    m = re.match(r'\s*\(interrupted at ([0-9A-F]+)', l)
    if m:
        recs.append(("irq", int(m.group(1), 16)))
        continue
    m = re.match(r'(\d+) ([0-9A-F]{6}): (.*)', l)
    if m:
        recs.append((int(m.group(1)), int(m.group(2), 16), m.group(3)))
count = 0
last_handler = None
for i, r in enumerate(recs):
    if r[0] != "irq" and r[1] == 0x888:
        last_handler = r[0]
    if r[0] == "irq" and r[1] < 0x80000:
        count += 1
        if count == nth + 1:
            for j in range(i - 6, i + 1):
                rr = recs[j]
                if rr[0] == "irq":
                    print("   IRQ (next pc %06x)" % rr[1])
                else:
                    print("%8d %06x %s" % (rr[0] - last_handler, rr[1], rr[2]))
            nxt = recs[i + 1]
            print("%8d vector start" % (nxt[0] - last_handler))
            break
