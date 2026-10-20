#!/usr/bin/env python3
"""musicgap.py <capture.mkv|wav> [floor_dB] [min_s]: per second, the 10th-percentile of 50 ms loudness (the floor between
effect bursts: held while music plays) and the peak; lists stretches of min_s+ seconds whose floor stays under floor_dB
while peaks continue (effects without music), and stretches of total silence.  Streams the audio (low memory)."""
import sys, subprocess, numpy as np
p = sys.argv[1]; FL = float(sys.argv[2]) if len(sys.argv) > 2 else -55; MS = int(sys.argv[3]) if len(sys.argv) > 3 else 10
pr = subprocess.Popen(['ffmpeg', '-nostdin', '-loglevel', 'error', '-i', p, '-vn', '-ac', '1', '-ar', '24000', '-f', 's16le', '-'], stdout=subprocess.PIPE)
fl, pk = [], []
while True:
    b = pr.stdout.read(48000)
    if len(b) < 48000: break
    a = np.frombuffer(b, np.int16).astype(np.float32).reshape(20, 1200) / 32768
    db = 20 * np.log10(np.sqrt((a * a).mean(1)) + 1e-6)
    fl.append(np.percentile(db, 10)); pk.append(db.max())
fl, pk = np.array(fl), np.array(pk)
print('%d s; floor median %.1f dB' % (len(fl), np.median(fl)))
def runs(mask):
    out = []; i = 0
    while i < len(mask):
        if mask[i]:
            j = i
            while j < len(mask) and mask[j]: j += 1
            if j - i >= MS: out.append((i, j - i))
            i = j
        else: i += 1
    return out
for s, n in runs((fl < FL) & (pk > FL + 15)): print('  effects without music: %4d s for %3d s (floor %.0f, peaks %.0f)' % (s, n, fl[s:s + n].mean(), pk[s:s + n].mean()))
for s, n in runs(pk < -60): print('  silence: %4d s for %3d s' % (s, n))
print('per 30 s floor:', ' '.join('%d' % v for v in [fl[i:i + 30].mean() for i in range(0, len(fl), 30)]))
