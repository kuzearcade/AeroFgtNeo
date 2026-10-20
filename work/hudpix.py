"""hudpix.py pix.bin...: per frame, white pixels at the HUD's 1P label (Neo picture
x 294..319, y 0..23) and score; lists short runs where the label is missing."""
import struct
import sys

import numpy as np


def scan(p):
    out = {}
    with open(p, 'rb') as f:
        while True:
            h = f.read(12)
            if len(h) < 12:
                break
            gf, w, hh = struct.unpack('<III', h)
            a = np.frombuffer(f.read(w * hh * 4), np.uint32).reshape(hh, w) & 0xffffff
            r = (a >> 16) & 255
            g = (a >> 8) & 255
            b = a & 255
            wh = (r > 200) & (g > 200) & (b > 200)
            out[gf] = (int(wh[0:24, 294:320].sum()), int(wh[30:70, 294:320].sum()), w, hh)
    return out


for p in sys.argv[1:]:
    o = scan(p)
    ks = sorted(o)
    lab = np.array([o[k][0] for k in ks])
    sc = np.array([o[k][1] for k in ks])
    print(p, 'frames', len(ks), 'size', o[ks[0]][2:], 'label px median', np.median(lab),
          'score px median', np.median(sc))
    ref = np.median(lab[lab > 0]) if (lab > 0).any() else 0
    good = lab > 0.6 * ref
    runs = []
    i, n = 0, len(ks)
    while i < n:
        if not good[i]:
            j = i
            while j < n and not good[j]:
                j += 1
            if good[max(0, i - 60):i].sum() > 50 and good[j:j + 60].sum() > 50 and j - i < 60:
                runs.append((ks[i], j - i))
            i = j
        else:
            i += 1
    print('  dropouts', len(runs), runs[:60])
