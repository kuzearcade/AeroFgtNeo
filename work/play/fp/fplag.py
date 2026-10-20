"""fplag.py <name> <lag.txt>: game-logic lag (the vblank flag already set when the handler bumps
it: that logic frame spans two vblanks and one is lost) joined with the per-frame profile."""
import sys, os, numpy as np, collections
R = os.path.expanduser('~/AeroFgtNeo/work/play/fp'); N = sys.argv[1]
z = np.load('%s/%s/frames.npz' % (R, N)); F = z['frames']; A = z['data']; names = list(z['names']); ci = {n: i for i, n in enumerate(names)}
lagf = {}; late_l = {}; hashes = {}
for l in open(sys.argv[2]):
    p = l.split()
    if len(p) < 8: continue
    lagf[int(p[0])] = int(p[1]) >= 1; hashes[int(p[0])] = int(p[7], 16)
STG = {0xa0b4faad: 'intro/map', 0x91b430ec: 'bases/attract', 0xe2f47afa: 'coast/river', 0x634fcf44: 'cities', 0x6da96bff: 'desert', 0x018c6b86: 'ocean', 0xc39339a2: 'runway', 0x786ebae6: 'final'}
n = len(lagf); lag = sum(lagf.values())
print('lag run: %d vblank frames, %d lost logic frames (%.2f%%)' % (n, lag, 100 * lag / n))
per = collections.Counter(); perl = collections.Counter()
for f, v in lagf.items():
    s = STG.get(hashes[f], 'other'); per[s] += 1; perl[s] += v
print('  by stage: ' + ', '.join('%s %.1f%% (%d)' % (s, 100 * perl[s] / per[s], per[s]) for s in sorted(per, key=lambda s: -per[s])))
w = collections.Counter(); wl = collections.Counter()
for f, v in lagf.items(): w[f // 10000] += 1; wl[f // 10000] += v
print('  per 10k frames: ' + ' '.join('%d:%.0f%%' % (k * 10, 100 * wl[k] / w[k]) for k in sorted(w)))
# join with the profile
idx = {f: i for i, f in enumerate(F)}
both = [f for f in lagf if f in idx and f >= 450]
if both:
    I = np.array([idx[f] for f in both]); L = np.array([lagf[f] for f in both])
    c = lambda nm: A[I, ci[nm]]
    d = lambda nm: np.r_[0, np.diff(A[:, ci[nm]])][I] > 0
    late = d('LATE'); busy = c('BUSY') != 0
    hal = sum(c(k) for k in names if k.startswith('c_') and k not in ('c_idle', 'c_ram', 'c_bg_scrub') and not k.startswith('c_g_') and not k.startswith('c_gx'))
    walk = c('c_walk_scan') + c('c_walk_emit') + c('c_walk_sort') + c('c_walk_ctl') + c('c_hud') + c('c_fx_other') + c('c_bpool'); conv = c('c_conv')
    print('  joined %d frames: lag %.2f%%; late among lag frames %.1f%%, among others %.1f%%; busy among lag %.1f%%' % (len(both), 100 * L.mean(), 100 * late[L].mean(), 100 * late[~L].mean(), 100 * busy[L].mean()))
    print('  HAL work per frame: lag frames walk %.0f conv %.0f HAL-f %.0f | other frames walk %.0f conv %.0f HAL-f %.0f' % (walk[L].mean(), conv[L].mean(), hal[L].mean(), walk[~L].mean(), conv[~L].mean(), hal[~L].mean()))
    print('  share of all walk+conversion cycles spent in lag frames: %.1f%%; in timer-started (busy) frames: %.1f%%' % (100 * (walk + conv)[L].sum() / (walk + conv).sum(), 100 * (walk + conv)[busy].sum() / (walk + conv).sum()))
    nobj = c('NOBJ'); dn = nobj >= 45
    print('  dense frames (>=45 objects): lag %.1f%%  late %.1f%%' % (100 * L[dn].mean(), 100 * late[dn].mean()))
