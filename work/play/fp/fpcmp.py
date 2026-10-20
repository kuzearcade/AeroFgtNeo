#!/usr/bin/env python3
"""fpcmp.py <A> <B> lo hi: per-frame cycle means of two profiles (work/play/fp/<name>/frames.npz)
over game frames lo..hi, side by side: the walk's categories, conversion, dl, ring control,
flip, reclaim, HUD, pool, bg, pal, fixed, game, HAL, and the counters' deltas (late, carried,
holds, busy)."""
import sys, os, numpy as np
R = os.path.expanduser('~/AeroFgtNeo/work/play/fp')
lo, hi = int(sys.argv[3]), int(sys.argv[4])

def load(n):
    z = np.load('%s/%s/frames.npz' % (R, n)); F = z['frames']; A = z['data']; names = list(z['names'])
    m = (F >= lo) & (F <= hi) & (F >= 450) & (A[:, names.index('cycles')] < 600000)
    return F[m], A[m], {k: i for i, k in enumerate(names)}

FA, A, ia = load(sys.argv[1]); FB, B, ib = load(sys.argv[2])
def mean(A, i, n): return A[:, i[n]].mean() if n in i else float('nan')
def dsum(A, i, n):
    if n not in i: return float('nan')
    v = A[:, i[n]]; d = np.diff(v); d = d[d >= 0]; return d.sum()
rows = ['c_walk_scan', 'c_walk_emit', 'c_walk_sort', 'c_walk_ctl', 'c_hud', 'c_bpool', 'c_fx_other', 'c_conv', 'c_dl', 'c_spr_ctl',
        'c_flip', 'c_reclaim', 'c_bg_conv', 'c_bg_blast', 'c_bg_place', 'c_tx', 'c_tm', 'c_bg_scrub', 'c_pal', 'c_sched', 'c_vid',
        'c_tcheck', 'c_inputs', 'c_hal_other', 'c_gx_col', 'c_gx_upd', 'c_idle', 'c_ram', 'cycles']
print('%-14s %10s %10s %8s   (frames A %d, B %d)' % ('mean cycles', sys.argv[1], sys.argv[2], 'B-A', len(FA), len(FB)))
for r in rows:
    a, b = mean(A, ia, r), mean(B, ib, r)
    print('%-14s %10.0f %10.0f %8.0f' % (r[2:], a, b, b - a))
ga = sum(A[:, ia[n]] for n in ia if n.startswith('c_g_')).mean(); gb = sum(B[:, ib[n]] for n in ib if n.startswith('c_g_')).mean()
print('%-14s %10.0f %10.0f %8.0f' % ('game logic', ga, gb, gb - ga))
wa = sum(mean(A, ia, n) for n in rows[:7]); wb = sum(mean(B, ib, n) for n in rows[:7])
print('%-14s %10.0f %10.0f %8.0f' % ('walk+hud+pool', wa, wb, wb - wa))
sa = wa + mean(A, ia, 'c_conv') + mean(A, ia, 'c_dl') + mean(A, ia, 'c_spr_ctl'); sb = wb + mean(B, ib, 'c_conv') + mean(B, ib, 'c_dl') + mean(B, ib, 'c_spr_ctl')
print('%-14s %10.0f %10.0f %8.0f' % ('sprite path', sa, sb, sb - sa))
print()
for n in ('LATE', 'CARRY', 'SLOWB', 'TIMN', 'OVERRUN', 'DROP', 'MIXN', 'IDLES'):
    print('%-14s %10.0f %10.0f' % (n + ' (sum)', dsum(A, ia, n), dsum(B, ib, n)))
for n in ('BUSY',):
    if n in ia and n in ib: print('%-14s %10.0f %10.0f' % (n + ' frames', (A[:, ia[n]] != 0).sum(), (B[:, ib[n]] != 0).sum()))
