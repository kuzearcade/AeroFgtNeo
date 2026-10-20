#!/usr/bin/env python3
"""audalign.py <MAME soak wav> <MiSTer capture mkv> <stream start in the wav, s> <stream length, s>: align the capture
to the MAME recording on the first 200 s after the stream start (10 Hz loudness envelopes), then per 5 s of the
stream: both loudnesses and the envelope correlation (a constant capture gain offset is expected; a drop in
correlation with the capture quieter is the music missing).  Memory: two float32 envelopes only."""
import sys, subprocess, numpy as np, wave, tempfile, os
def env(p):
    t = tempfile.mktemp(suffix='.wav'); subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-i', p, '-vn', '-ac', '1', '-ar', '24000', t], check=True)
    w = wave.open(t); n = w.getnframes() // 2400; out = np.empty(n, np.float32)
    for i in range(n):
        a = np.frombuffer(w.readframes(2400), np.int16).astype(np.float32) / 32768
        out[i] = 20 * np.log10(np.sqrt((a * a).mean()) + 1e-6)
    os.unlink(t); return out
M, C = env(sys.argv[1]), env(sys.argv[2]); S = float(sys.argv[3]); L = float(sys.argv[4])
s0 = int(S * 10); seg = M[s0:s0 + 2000] - M[s0:s0 + 2000].mean()
best = max(range(-300, 900), key=lambda k: float(np.dot(seg, C[s0 + k:s0 + k + 2000] - C[s0 + k:s0 + k + 2000].mean())) if s0 + k >= 0 and s0 + k + 2000 <= len(C) else -1e9)
print('capture = MAME + %.1f s; correlation %.2f over the first 200 s' % (best / 10, np.corrcoef(seg, C[s0 + best:s0 + best + 2000])[0, 1]))
for t in range(0, int(L), 5):
    a = M[s0 + t * 10:s0 + t * 10 + 50]; b = C[s0 + best + t * 10:s0 + best + t * 10 + 50]
    if len(a) < 50 or len(b) < 50: break
    c = np.corrcoef(a, b)[0, 1]
    print('stream %4d s (frame %5d): MAME %6.1f dB  MiSTer %6.1f dB  corr %5.2f%s' % (t, t * 59.185, a.mean(), b.mean(), c, '   <--' if c < 0.6 else ''))
