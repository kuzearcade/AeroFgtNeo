#!/usr/bin/env python3
"""sana.py <name> [sid]: the stage profile of work/play/fp/<name>/frames.npz (fpmerge.py) joined with
botsel.lua's log (<name>/c*/bot.txt: ... stage id at column 9, active objects at 5, shots at 13):
for the stage <sid> (or every stage seen), mean cycles per frame by category, the object census
(fprof.lua's O_* columns), and the frames binned by active objects with the lost-logic share
(stat LATE/.. from lag is not here: the budget is 200,000 cycles a frame, 163,000 the arcade's)."""
import sys, os, glob, numpy as np, collections
R = os.path.expanduser('~/AeroFgtNeo/work/play/fp'); N = sys.argv[1]; SID = int(sys.argv[2]) if len(sys.argv) > 2 else None
z = np.load('%s/%s/frames.npz' % (R, N)); F = z['frames']; A = z['data']; names = list(z['names']); ci = {n: i for i, n in enumerate(names)}
bot = {}
for fn in glob.glob('%s/%s/c*/bot.txt' % (R, N)):
    for l in open(fn):
        p = l.split()
        if len(p) >= 19 and p[0].isdigit(): bot[int(p[0])] = (int(p[8]), int(p[4]), int(p[12]), int(p[1]))
sid = np.array([bot.get(f, (255, 0, 0, 0))[0] for f in F]); nact = np.array([bot.get(f, (255, 0, 0, 0))[1] for f in F])
boss = np.array([bot.get(f, (255, 0, 0, 0))[3] for f in F])
ok = (A[:, ci['cycles']] < 600000) & (A[:, ci['cycles']] > 0)
F, A, sid, nact, boss = F[ok], A[ok], sid[ok], nact[ok], boss[ok]
game = sum(A[:, ci[n]] for n in names if n.startswith('c_g_'))
def col(n): return A[:, ci[n]] if n in ci else np.zeros(len(F))
groups = [('game logic', game), ('records (build)', col('c_walk_scan') + col('c_walk_sort')), ('pass pieces', col('c_walk_emit')),
          ('pass control', col('c_walk_ctl') + col('c_spr_ctl')), ('shapes', col('c_conv')), ('HUD', col('c_hud')), ('bullet pool', col('c_bpool')),
          ('flip+reclaim', col('c_flip') + col('c_reclaim')), ('bg conv', col('c_bg_conv')), ('bg blast+place', col('c_bg_blast') + col('c_bg_place')),
          ('bg scrub', col('c_bg_scrub')), ('tx+tm', col('c_tx') + col('c_tm')), ('palette', col('c_pal')),
          ('sched+vid+other', col('c_sched') + col('c_vid') + col('c_tcheck') + col('c_inputs') + col('c_hal_other') + col('c_fx_other')),
          ('gx (collision)', col('c_gx_col') + col('c_gx_upd')), ('idle', col('c_idle')), ('total', A[:, ci['cycles']])]
gcats = sorted([n for n in names if n.startswith('c_g_')], key=lambda n: -A[:, ci[n]].mean())
ocats = [n for n in names if n.startswith('O_')]
def table(sel, label):
    m = int(sel.sum())
    if not m: return
    print("== %s: %d frames; over 200k: %.1f%%, over 163k (the arcade's frame): %.1f%%" % (label, m, 100.0 * (A[sel][:, ci['cycles']] > 200000).mean(), 100.0 * (A[sel][:, ci['cycles']] > 163000).mean()))
    print("   " + "  ".join("%s %.0f" % (g, v[sel].mean()) for g, v in groups))
    print("   game: " + ", ".join("%s %.0f" % (n[4:], A[sel][:, ci[n]].mean()) for n in gcats[:8]))
    print("   census: " + ", ".join("%s %.1f" % (n[2:], A[sel][:, ci[n]].mean()) for n in ocats if A[sel][:, ci[n]].mean() >= 0.3))
busy = A[:, ci['BUSY']] if 'BUSY' in ci else np.zeros(len(F))
sids = [SID] if SID is not None else sorted(set(sid) - {255})
for s in sids:
    sel = sid == s
    table(sel, "stage %d" % s)
    for lo, hi in ((0, 30), (30, 45), (45, 60), (60, 200)):
        table(sel & (nact >= lo) & (nact < hi), "stage %d, %d-%d objects" % (s, lo, hi))
    table(sel & (boss == 1), "stage %d, boss frames" % s)
    table(sel & (busy != 0), "stage %d, BUSY frames (the game still in its round at the slot)" % s)
    table(sel & (busy == 0), "stage %d, idle frames" % s)
