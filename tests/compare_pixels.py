"""Compare per-game-frame screen captures (tests/harness.lua HARNESS_PIXELS).

usage: compare_pixels.py orig.bin neo.bin [offset]
The conversion's capture may trail the original by a constant number of game frames
(offset, default: try 0 and +1)."""
import struct
import sys

import numpy as np


def frames(path):
    with open(path, "rb") as f:
        while True:
            h = f.read(12)
            if len(h) < 12:
                return
            gf, w, hgt = struct.unpack("<III", h)
            yield gf, np.frombuffer(f.read(w * hgt * 4), dtype=np.uint32).reshape(hgt, w) & 0xffffff


def compare(a, b, off):
    bad = []
    for gf, pa in sorted(a.items()):
        pb = b.get(gf + off)
        if pb is not None and (pa != pb).any():
            bad.append((gf, int((pa != pb).sum())))
    return bad


if __name__ == "__main__":
    a = dict(frames(sys.argv[1]))
    b = dict(frames(sys.argv[2]))
    offs = [int(sys.argv[3])] if len(sys.argv) > 3 else [0, 1]
    for off in offs:
        bad = compare(a, b, off)
        print("offset %+d: %d of %d frames differ; first %s" % (off, len(bad), len(a), bad[:20]))
