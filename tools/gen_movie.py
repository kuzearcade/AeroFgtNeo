"""Deterministic bot input movie: 'frame p1 p2 system' (active-low bytes, original layout)."""
import random
import sys

frames, seed = int(sys.argv[1]), int(sys.argv[2])
rng = random.Random(seed)
joy = 0
dirs = [0, 1, 2, 4, 8, 5, 9, 6, 10]          # none U D L R UL UR DL DR (bit0 U,1 D,2 L,3 R)
for f in range(1, frames + 1):
    cyc = f % 600
    sysb = 0xff
    if 100 <= cyc < 106: sysb &= ~0x01        # coin 1
    if 120 <= cyc < 126: sysb &= ~0x02        # coin 2
    if 150 <= cyc < 156: sysb &= ~0x04        # start 1
    if 170 <= cyc < 176: sysb &= ~0x08        # start 2
    if f % 12 == 0:
        joy = rng.randrange(9)
    p = []
    for pl in range(2):
        d = dirs[(joy + 4 * pl) % 9]
        v = 0xff & ~d
        if f % 4 < 2: v &= ~0x10              # shot
        if rng.randrange(400) == 0: v &= ~0x20  # bomb
        p.append(v)
    print("%d %02x %02x %02x" % (f, p[0], p[1], sysb & 0xff))
