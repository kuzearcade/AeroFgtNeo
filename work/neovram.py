"""Neo sprite VRAM dump (harness HARNESS_VRAM) -> per-sprite placement.
neovram.py vram.bin game_frame [x y]"""
import struct, sys
REC = 4 + 0x8800 * 2


def load(path):
    out = {}
    with open(path, 'rb') as f:
        while True:
            b = f.read(REC)
            if len(b) < REC:
                return out
            out[struct.unpack_from('<I', b)[0]] = struct.unpack_from('>%dH' % 0x8800, b, 4)


def sprites(v):
    """(n, x, y, height, sticky, scb2, scb3) for sprites 1..380, chains resolved."""
    res = []
    x = y = h = 0
    for n in range(1, 381):
        s2, s3, s4 = v[0x8000 + n], v[0x8200 + n], v[0x8400 + n]
        if s3 & 0x40:
            x = (x + ((prev2 >> 8) & 0xf) + 1) & 0x1ff
        else:
            y = 496 - (s3 >> 7)
            h = s3 & 0x3f
            x = s4 >> 7
        res.append((n, x, y & 0x1ff, h, bool(s3 & 0x40), s2, s3))
        prev2 = s2
    return res


if __name__ == '__main__':
    V = load(sys.argv[1])
    v = V[int(sys.argv[2])]
    px, py = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (None, None)
    for n, x, y, h, st, s2, s3 in sprites(v):
        if h == 0:
            continue
        # screen: Neo line 16 = our row 0 (MAME visible area), x as is
        top = (y - 16) & 0x1ff
        if px is not None and not (x <= px < x + 16 and (py - top) % 512 < h * 16):
            continue
        tiles = [(v[n * 64 + 2 * r], v[n * 64 + 2 * r + 1]) for r in range(min(h, 4))]
        print('spr %3d x %3d y %3d top %3d h %2d %s scb2 %04x scb3 %04x tiles %s' % (
            n, x, y, top, h, 'chain' if st else 'head ', s2, s3, ' '.join('%04x/%04x' % t for t in tiles)))
