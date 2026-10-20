"""hudtiles.py pre.bin...: the HUD's lookup tiles (0x3fc0-0x3fff) and its list entries."""
import struct, sys, collections
R = 4 + 0x800 + 0x20 + 0x4000 + 0x2000 + 0x8000
SP = 4 + 0x800 + 0x20 + 0x4000
LU = SP + 0x2000
tiles = collections.Counter(); attrs = collections.Counter(); per = collections.Counter()
for p in sys.argv[1:]:
    with open(p, 'rb') as f:
        n = 0
        while True:
            r = f.read(R)
            if len(r) < R: break
            n += 1
            lut = struct.unpack('>64H', r[LU + 0x7f80:LU + 0x8000])
            spr = r[SP:SP + 0x2000]
            lst = struct.unpack('>512H', spr[:0x400])
            seen = set()
            for w in lst:
                if w & 0x4000: break
                if w & 0x8000: continue
                a = struct.unpack('>4H', spr[(w & 0x3ff) * 8:(w & 0x3ff) * 8 + 8])
                m = ((a[2] & 1) << 16) | a[3]
                if (m & 0x3fc0) == 0x3fc0:
                    ys = (a[0] >> 9) & 7; xs = (a[1] >> 9) & 7
                    attrs[(m, a[0] & 0x1ff, a[1] & 0x1ff, ys, xs, a[0] >> 12, a[1] >> 12, (a[2] >> 8) & 0xff)] += 1
                    for k in range((ys + 1) * (xs + 1)):
                        seen.add(((m + k) & 0x3fff) - 0x3fc0)
            for k in seen:
                tiles[lut[k]] += 1
    print(p, n, 'records')
print(len(tiles), 'distinct tiles drawn:', ' '.join('%04x' % t for t in sorted(tiles)))
for a, c in sorted(attrs.items()):
    print('map %05x y %3d x %3d ys %d xs %d zy %x zx %x b2 %02x  x%d' % (a + (c,)))
