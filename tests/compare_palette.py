"""Check the real-cart palette conversion frame by frame.

For every game frame k, the Neo palette RAM (dumped by tests/harness.lua with
HARNESS_NEOPAL at the end of the frame's vblank handler) must hold the conversion of
the original palette as dumped by the original run at the same point
(work/eq/orig.bin), for every displayed slot (tools/gfx.py PALETTE LAYOUT).
usage: compare_palette.py orig.bin npal.bin
"""

import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import gfx  # noqa: E402

REC = 4 + 0x10000 + 0x800 + 0x800 + 0x4000 + 0x8000 + 0x2000
POFF = 4 + 0x10000
NREC = 24 + 0x2000


def expected_slots():
    """list of (neo word index, original entry index or ('c15', entry))"""
    m = []
    for q in range(8):                              # tilemap 0, four variants
        for v in range(4):
            base = (gfx.NPAL_L0 + 4 * q + v) * 16
            for s in range(1, 16):
                m.append((base + s, q * 16 + s - 1))
            if v:
                m[-16 + gfx.L0_REMAP_PENS[v - 1] + 1] = (base + gfx.L0_REMAP_PENS[v - 1] + 1, q * 16 + 15)
    for q in range(16, 24):
        for s in range(1, 16):
            m.append(((gfx.NPAL_L1 + q - 16) * 16 + s, q * 16 + s - 1))
    for q in range(32, 64):
        for s in range(1, 16):
            m.append(((gfx.NPAL_SPR + q - 32) * 16 + s, q * 16 + s - 1))
    return np.array([a for a, _ in m]), np.array([b for _, b in m])


def main():
    table, _ = gfx.neo_colour_table()
    neo_idx, orig_idx = expected_slots()
    fo, fn = open(sys.argv[1], "rb"), open(sys.argv[2], "rb")
    bad_frames, total, first = 0, 0, []
    defers = misses = 0
    while True:
        a, b = fo.read(REC), fn.read(NREC)
        if len(a) < REC or len(b) < NREC:
            break
        fa = struct.unpack_from("<I", a)[0]
        fb, miss, defer, slip, deadline = struct.unpack_from("<IIIHH", b)
        assert fa == fb, (fa, fb)
        orig = np.frombuffer(a[POFF:POFF + 0x800], ">u2") & 0x7fff
        neo = np.frombuffer(b[24:], ">u2")
        want = table[orig[orig_idx]]
        got = neo[neo_idx]
        nbad = int((want != got).sum())
        total += 1
        if nbad:
            bad_frames += 1
            if len(first) < 15:
                pal = sorted(set((orig_idx[want != got] >> 4).tolist()))
                first.append((fa, nbad, pal[:8], "slip" if slip & 1 else ""))
        misses, defers = miss, defer
    print("frames %d, palette mismatching %d" % (total, bad_frames))
    print("scrub misses %d, frames with deferred palette work %d" % (misses, defers))
    for f in first:
        print("  frame %d: %d slots wrong, palettes %s %s" % f)


if __name__ == "__main__":
    main()
