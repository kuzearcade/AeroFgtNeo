"""Write orig | neo | diff-mask PNGs for given game frames (neo frame = gf + offset)."""
import struct
import sys
import zlib

import numpy as np

sys.path.insert(0, __import__("os").path.dirname(__file__))
from compare_pixels import frames  # noqa: E402


def png(arr, path):
    h, w = arr.shape
    rgb = np.dstack([(arr >> 16) & 255, (arr >> 8) & 255, arr & 255]).astype(np.uint8)
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) +
                           chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


a = dict(frames(sys.argv[1]))
b = dict(frames(sys.argv[2]))
off = int(sys.argv[3])
for g in map(int, sys.argv[5:]):
    pa, pb = a[g], b[g + off]
    d = pa != pb
    ys, xs = np.nonzero(d)
    print(g, "diff px", int(d.sum()), "bbox x %d-%d y %d-%d" % (xs.min(), xs.max(), ys.min(), ys.max()) if d.any() else "")
    png(np.hstack([pa, pb, np.where(d, 0xff0000, pa)]), "%s/diff_%05d.png" % (sys.argv[4], g))
