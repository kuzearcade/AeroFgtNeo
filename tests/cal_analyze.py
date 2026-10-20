"""Derive timing calibration facts from a takeover trace (window 1) and a boot-frame
trace (window 2) of the conversion."""
import re
import sys


def parse(path):
    recs = []
    for l in open(path):
        m = re.match(r'\s*\(interrupted at ([0-9A-F]+)', l)
        if m:
            recs.append(("irq", int(m.group(1), 16)))
            continue
        m = re.match(r'(\d+) ([0-9A-F]{6}): (.*)', l)
        if m:
            recs.append((int(m.group(1)), int(m.group(2), 16), m.group(3)))
    return recs


sync_tr, boot_tr, sled, sync_to_base, q1, bdw, q2 = sys.argv[1], sys.argv[2], int(sys.argv[3], 16), *map(int, sys.argv[4:8])
r1 = parse(sync_tr)
# sync wake: first vector start through the HAL jump table (0x08000C), then the
# LOAD_REL low write that places BASE
for i, r in enumerate(r1):
    if r[0] != "irq" and r[1] == 0x08000C:
        tau_s = r[0]
        for rr in r1[i:i + 60]:
            if rr[0] != "irq" and "$3c000a" in rr[2]:
                low = rr[0]
                break
        break
print("tau_s", tau_s, "sync LOW write instr", low, "offset", low - tau_s)
r2 = parse(boot_tr)
ev = [(i, r[1]) for i, r in enumerate(r2) if r[0] == "irq"]
X = r2[ev[0][0] + 1][0]
for i, pc in ev[1:3]:
    pass
sled_starts = [r[0] for r in r2 if r[0] != "irq" and r[1] == sled]
p1 = ev[1]
wake = ev[2]
p2 = ev[3]
S1 = sled_starts[0]
S2 = [s for s in sled_starts if s > r2[wake[0] + 1][0]][0]
j1 = (p1[1] - sled) // 2
j2 = (p2[1] - sled) // 2
for w_in in (10, 12, 14):
    base = low + w_in + sync_to_base
    A1 = base + q1
    W = base + bdw
    A2 = W + q2
    print("w_in %d: base%%10=%d probe1 offset S1-(A1-4j1)=%d  probe2 offset S2-(A2-4j2)=%d  wake lat=%d" % (
        w_in, base % 10, S1 - (A1 - 4 * j1), S2 - (A2 - 4 * j2), r2[wake[0] + 1][0] - W))
print("X", X, "S1", S1, "tau_w", r2[wake[0] + 1][0], "S2", S2)
