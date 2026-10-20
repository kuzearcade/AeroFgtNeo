"""walkmodel.py neo.bin [frames]: the builder's pieces (hal/dx.s rules) from each dumped
frame's object RAM vs the lists hal/fx.s left in sprite RAM (DIRECT=1 builds)."""
import struct, sys
sys.path.insert(0, 'tests'); import compare_state as c
P = bytearray(open(sys.argv[2] if len(sys.argv) > 2 else '/tmp/claude-1000/-home-vboxuser-AeroFgtNeo/560dbddd-2c54-4bd4-b6db-4e3d9472357d/scratchpad/p1s.bin', 'rb').read())
WR = 0  # offset of wram in a dump record
SPR = sum(r[2] for r in c.REGIONS[:5])
def rd(b, a, n):
    a &= 0xffffff
    if a < 0x80000: return P[a:a+n]
    if 0x100000 <= a < 0x110000: return b[WR + a - 0x100000: WR + a - 0x100000 + n]
    return bytes(n)
w = lambda b, a: struct.unpack('>H', rd(b, a, 2))[0]
l = lambda b, a: struct.unpack('>I', rd(b, a, 4))[0]
by = lambda b, a: rd(b, a, 1)[0]
O = lambda a: 0x100000 + a - 0xfef000      # original -> Neo work RAM
def model(b):
    out = []; sy = w(b, O(0xff8b4c)); sx = w(b, O(0xff8b4a))
    def obj(o, p1):
        def tab(t, n, d5):
            t &= ~1
            f = 0; zw = None
            if w(b, o+0x16) == 0x2e: zw = (by(b, o+1) & 0xf) << 12
            cobj = None
            if by(b, o+5) & 0x80 and d5 == 0: cobj = by(b, o+5) & 0xf
            base = 0
            if not (by(b, o+0x19) & 0x80) or (by(b, o+0x19) & 1): base |= 0x20
            b42 = by(b, o+0x2a); base |= b42
            for i in range(n + 1):
                pa = t + 14*i; a4 = l(b, pa) & ~1
                y = (w(b, o+0xe) + w(b, pa+4)) & 0xffff
                if not (y >= 0xfee0 or y < 0xe0): continue
                x = (w(b, o+0x10) + w(b, pa+6)) & 0xffff
                if not (x >= 0xff40 or x < 0x140): continue
                zy = zw if zw is not None else ((by(b, pa+10) & 0xf) << 12)
                zx = zw if zw is not None else ((by(b, pa+11) & 0xf) << 12)
                w0 = ((y + sy) & 0x1ff) | zy | (w(b, a4) & 0xff00)
                w1 = ((x + sx) & 0x1ff) | zx | ((w(b, a4) << 8) & 0xff00)
                v = base | (cobj if cobj is not None else (by(b, pa+12) & 0xf))
                if b42 == 0: v |= ((by(b, pa+8) & 1) << 7) | ((by(b, pa+9) & 3) << 6)
                w2 = ((v & 0xff) << 8) | (0x1000 if p1 else 0)
                w3 = w(b, a4+2) | (0x2000 if p1 else 0)
                out.append((w0, w1, w2, w3))
        b43 = by(b, o+0x43)
        if b43 & 0x80: tab(l(b, o+0x44), b43 & 0xf, b43 & 0x10)
        tab(l(b, o+0x1a), by(b, o+4), 0)
        if b43 & 0x40: tab(l(b, o+0x44), b43 & 0xf, b43 & 0x10)
    def lin(a, e, p1):
        while a < e:
            if by(b, O(a)) & 0x80: obj(O(a), p1)
            a += 0x60
    lin(0xff0000, 0xff30c0, 1); lin(0xff30c0, 0xff42c0, 0)
    if w(b, O(0xff90e6)): lin(0xff42c0, 0xff48c0, 0)
    else:
        g = []
        for a in range(0xff42c0, 0xff48c0, 0x60):
            if by(b, O(a)) & 0x80:
                k = (w(b, O(a)+0x10) + 0x8000) & 0xffff
                i = 0
                while i < len(g) and not (g[i][0] >= k): i += 1
                g.insert(i, (k, a))
        for k, a in g: obj(O(a), 0)
    lin(0xff48c0, 0xff60c0, 0)
    return out
LT = [0, 0x800, 0xc00, 0x1800, 0x1c00]
def lists(b):
    s = b[SPR:SPR+0x2000]; km = struct.unpack_from('>H', s, 0x118a)[0]
    ln = struct.unpack_from('>5H', s, 0x1180)
    phys = s[0x1038:0x103d]              # (FX_PHYS: per slot mod 5 its buffer)
    res = {}
    for i in range(5):
        p = phys[i] if phys[i] < 5 else i
        res[i] = [struct.unpack_from('>4H', s, LT[p] + 8*j) for j in range(min(ln[p], 128))]
    return km, res
prev = None; ok = bad = 0; ex = []
for gf, b in c.frames(sys.argv[1]):
    km, L = lists(b)
    if prev is not None and 300 < gf:
        m = [p for p in model(prev) if not ((p[3] & 0x3fc0) == 0x3fc0 and p[2] & 0x1000)]
        got = [p for p in L[km] if not ((p[3] & 0x3fc0) == 0x3fc0 and p[2] & 0x1000)]
        if m == got: ok += 1
        else:
            bad += 1
            if len(ex) < 3: ex.append((gf, len(m), len(got), next((i for i, (x, y) in enumerate(zip(m, got)) if x != y), None)))
    prev = b
print('frames match', ok, 'differ', bad, ex)
