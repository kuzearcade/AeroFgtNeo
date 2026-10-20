"""Visible tilemap changes per frame vs cheap signals: scenechg.py pre.bin [min_blocks]"""
import struct, sys
import numpy as np
sys.path.insert(0, '/home/vboxuser/AeroFgtNeo/tests')
from compare_bg import PRE
MIN = int(sys.argv[2]) if len(sys.argv) > 2 else 40
prev = None
rows = []
with open(sys.argv[1], 'rb') as f:
    while True:
        b = f.read(PRE)
        if len(b) < PRE:
            break
        k = struct.unpack_from('<I', b)[0]
        raster = np.frombuffer(b[4:4 + 0x800], '>u2')
        io = b[4 + 0x800:4 + 0x820]
        vram = np.frombuffer(b[4 + 0x820:4 + 0x820 + 0x4000], '>u2').reshape(2, 64, 64)
        sx = [(int(raster[0]) - 18) & 511, (int(raster[0x200]) - 20) & 511]
        sy = [struct.unpack_from('>H', io, 16 + 2 * l)[0] & 511 for l in range(2)]
        banks = bytes(io[0:8])
        if prev is not None:
            ch = []
            for l in range(2):
                # blocks (16x16) in the 21x15 visible window: compare the top-right cell
                c0, r0 = sx[l] >> 4, sy[l] >> 4
                cols = [(c0 + i) & 31 for i in range(21)]
                rws = [(r0 + j) & 31 for j in range(15)]
                a = vram[l][np.ix_([2 * r for r in rws], [2 * c + 1 for c in cols])]
                p = prev['vram'][l][np.ix_([2 * r for r in rws], [2 * c + 1 for c in cols])]
                ch.append(int((a != p).sum()))
            sig = []
            if banks != prev['banks']:
                sig.append('banks')
            for l in range(2):
                if abs(sx[l] - prev['sx'][l]) > 16 and abs(sx[l] - prev['sx'][l]) < 496:
                    sig.append('sx%d' % l)
                if abs(sy[l] - prev['sy'][l]) > 16 and abs(sy[l] - prev['sy'][l]) < 496:
                    sig.append('sy%d' % l)
            if max(ch) >= MIN or sig:
                rows.append((k, ch, sig))
        prev = {'vram': vram.copy(), 'banks': banks, 'sx': sx, 'sy': sy}
big = [r for r in rows if max(r[1]) >= MIN]
print('frames with >= %d visible blocks changed: %d; with a signal: %d' % (MIN, len(big), sum(1 for r in big if r[2])))
for r in rows[:80]:
    print(r)
