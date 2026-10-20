"""For each game frame, map the Neo's believed assertion time T_k into original virtual
time using the previous handler start as anchor, and compare with x_k and with the
instruction boundaries seen on both machines."""
import re
import sys
from fractions import Fraction

P = Fraction(16310552927744250, 10 ** 11)


def parse(path):
    recs = []
    for l in open(path):
        if re.match(r'\s*\(interrupted at', l):
            m = re.search(r'at ([0-9A-F]+)', l)
            recs.append(("irq", int(m.group(1), 16)))
            continue
        m = re.match(r'(\d+) ([0-9A-F]{6}): (\S+)', l)
        if m:
            recs.append((int(m.group(1)), int(m.group(2), 16), m.group(3)))
    return recs


orig = parse(sys.argv[1])
neo = parse(sys.argv[2])
dx = {}
for line in open(sys.argv[3]):
    p = line.split()
    if p[0] != "frames":
        dx[int(p[0])] = int(p[1])
# original: handler starts and IRQ contexts
oh = [r[0] for r in orig if r[0] != "irq" and r[1] == 0x888]
oirq = [(orig[i - 1], orig[i - 2]) for i, r in enumerate(orig) if r[0] == "irq"]
# neo: resume (0x888) times, entries
nh = [r[0] for r in neo if r[0] != "irq" and r[1] == 0x888]
nent = [(neo[i + 1][0], neo[i - 1], neo[i - 2]) for i, r in enumerate(neo) if r[0] == "irq" and r[1] < 0x80000]
for f in range(1, min(len(oh), len(nh), len(nent)) - 1):
    O = nh[f - 1] - oh[f - 1]              # neo - virtual after handler f
    X, seen, prev = nent[f]
    T = X - dx[(f + 1) % 32]
    Tv = T - O
    k = round(Fraction(oh[f]) / P)
    while k * P > oh[f]:
        k -= 1
    x = k * P
    os_, op_ = oirq[f]
    print("f%2d k%d x-floor=%d Tv-floor(x)=%3d | orig seen %-6s at %3d | neo seen %-6s at %3d" % (
        f + 1, k, 0, Tv - int(x), os_[2], os_[0] - int(x), seen[2], seen[0] - O - int(x)))
