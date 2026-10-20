#!/usr/bin/env python3
"""audcmp.py <reference.wav> <capture.(mkv|wav)> [ref_start_s] [length_s]: align a capture's audio to a reference
(MAME -wavwrite) by cross-correlating 10 Hz loudness envelopes, then compare 5-second windows: loudness of each,
the correlation of their band spectra, and the music-band share (100-2000 Hz without the noisy upper bands).
A window where the capture keeps its loudness peaks (effects) but loses the reference's spectral match marks the
music going wrong."""
import sys, subprocess, numpy as np, wave, tempfile, os
def load(p):
    if not p.endswith('.wav'):
        t = tempfile.mktemp(suffix='.wav'); subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-i', p, '-vn', '-ac', '1', '-ar', '24000', t], check=True); p2 = t
    else:
        t = tempfile.mktemp(suffix='.wav'); subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-i', p, '-ac', '1', '-ar', '24000', t], check=True); p2 = t
    w = wave.open(p2); a = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768; os.unlink(p2); return a
R, C = load(sys.argv[1]), load(sys.argv[2]); SR = 24000; H = SR // 10
def feats(a):
    n = len(a) // H; x = a[:n * H].reshape(n, H) * np.hanning(H)
    s = np.abs(np.fft.rfft(x, axis=1)) ** 2; f = np.fft.rfftfreq(H, 1 / SR)
    edges = [60, 120, 250, 500, 1000, 2000, 4000, 8000, 12000]
    b = np.stack([s[:, (f >= lo) & (f < hi)].sum(1) for lo, hi in zip(edges, edges[1:])], 1)
    return np.log10(b + 1e-9), np.log10(s.sum(1) + 1e-9)
RB, RE = feats(R); CB, CE = feats(C)
r0 = int(float(sys.argv[3]) * 10) if len(sys.argv) > 3 else 0; L = int(float(sys.argv[4]) * 10) if len(sys.argv) > 4 else len(RE) - r0
seg = RE[r0:r0 + 600] - RE[r0:r0 + 600].mean()
best = max(range(0, len(CE) - 600), key=lambda k: float(np.dot(seg, CE[k:k + 600] - CE[k:k + 600].mean())))
off = best - r0
print('capture offset: %.1f s (reference %.1f s = capture %.1f s)' % (off / 10, r0 / 10, best / 10))
print('%8s %8s | %7s %7s | %6s | %s' % ('ref s', 'cap s', 'ref dB', 'cap dB', 'corr', 'band dB difference (cap - ref), 60..12k Hz'))
for k in range(r0, min(r0 + L, len(RE), len(CE) - off) - 50, 50):
    rb, cb = RB[k:k + 50], CB[k + off:k + off + 50]
    c = np.corrcoef(rb.ravel(), cb.ravel())[0, 1]
    d = (cb.mean(0) - rb.mean(0)) * 10
    print('%8.1f %8.1f | %7.1f %7.1f | %6.2f | %s' % (k / 10, (k + off) / 10, RE[k:k + 50].mean() * 10, CE[k + off:k + off + 50].mean() * 10, c, ' '.join('%+5.1f' % v for v in d)))
