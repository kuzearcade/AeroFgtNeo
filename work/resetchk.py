"""resetchk.py pix.bin...: game frames (sampled every 10 from 1000) showing the game's
boot MEMORY CHECK screen (mostly pure red): the game was reset (e.g. an address error)."""
import struct, sys, numpy as np
for p in sys.argv[1:]:
    hits = []
    with open(p, 'rb') as f:
        while True:
            h = f.read(12)
            if len(h) < 12: break
            gf, w, hh = struct.unpack('<III', h)
            if gf % 10 or gf < 1000: f.seek(w*hh*4, 1); continue
            a = np.frombuffer(f.read(w*hh*4), np.uint8).reshape(hh, w, 4)
            if ((a[:, :, 2] > 180) & (a[:, :, 1] < 80) & (a[:, :, 0] < 80)).mean() > 0.15: hits.append(gf)
    print(p, 'resets at', hits[:5], len(hits))
