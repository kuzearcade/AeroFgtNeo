"""fpana.py <name> [frame_lo frame_hi]: analysis of work/play/fp/<name>/frames.npz (fpmerge.py):
per-frame cycle structure, late-frame anatomy and causes, stages, object census, drops, fixed costs,
headroom model.  Writes <name>/report.txt and prints it."""
import sys, os, numpy as np, collections
R = os.path.expanduser('~/AeroFgtNeo/work/play/fp'); N = sys.argv[1]
z = np.load('%s/%s/frames.npz' % (R, N)); F = z['frames']; A = z['data']; names = list(z['names'])
if len(sys.argv) > 3:
    lo, hi = int(sys.argv[2]), int(sys.argv[3]); m = (F >= lo) & (F <= hi); F, A = F[m], A[m]
ci = {n: i for i, n in enumerate(names)}
m = (F >= 450) & (A[:, ci['cycles']] < 600000)      # (the boot: BIOS, RAM test, HAL takeover)
nboot = (~m).sum(); F, A = F[m], A[m]
def c(n): return A[:, ci[n]]
def d(n):   # per-frame delta of a cumulative counter (0 at the first frame / chunk gaps)
    v = c(n); r = np.zeros_like(v); r[1:] = v[1:] - v[:-1]; r[r < 0] = 0; r[0] = 0
    gap = np.ones(len(F), bool); gap[1:] = (F[1:] - F[:-1]) != 1; r[gap] = 0
    return r
FRAME = 202750
out = []
def P(*a): s = ' '.join(str(x) for x in a); out.append(s); print(s)
def st(v, pct=(50, 90, 99)):
    v = np.asarray(v, float)
    if len(v) == 0: return 'n=0'
    return 'mean %7.0f  p50 %7.0f  p90 %7.0f  p99 %7.0f  max %7.0f' % ((v.mean(),) + tuple(np.percentile(v, pct)) + (v.max(),))
cat = lambda pre: sum(c(n) for n in names if n.startswith('c_' + pre))
G = {}
G['game_logic'] = sum(c(n) for n in names if n.startswith('c_g_'))
G['gx'] = c('c_gx_col') + c('c_gx_upd')
G['idle'] = c('c_idle') + c('c_ram')
G['walk'] = c('c_walk_scan') + c('c_walk_emit') + c('c_walk_sort') + c('c_walk_ctl') + c('c_fx_other') + c('c_hud') + c('c_bpool')
G['conv'] = c('c_conv'); G['flip'] = c('c_flip'); G['reclaim'] = c('c_reclaim'); G['spr_ctl'] = c('c_spr_ctl'); G['dl'] = c('c_dl')
G['bg'] = c('c_bg_conv') + c('c_bg_blast') + c('c_bg_place') + c('c_tm') + c('c_tx'); G['bg_scrub'] = c('c_bg_scrub')
G['pal'] = c('c_pal'); G['fixed'] = c('c_sched') + c('c_vid') + c('c_tcheck') + c('c_inputs') + c('c_sound') + c('c_diag') + c('c_hal_other')
game = G['game_logic'] + G['gx']
hal = sum(G[k] for k in G if k not in ('game_logic', 'gx', 'idle'))
filler = G['bg_scrub']
cyc = c('cycles')
late = d('LATE') > 0; dropn = d('DROPN'); drop = d('DROP'); ovr = d('OVERRUN'); paldef = d('PALDEFER'); bgdef = d('BGDEFER')
slowb = d('SLOWB'); timn = d('TIMN'); yn = d('YN'); deltan = d('DELTAN'); carry = d('CARRY'); mixn = d('MIXN'); unfin = d('UNFIN'); blkn = d('BLKN')
busy = c('BUSY') != 0
# timeline: slot start = sch_idle or sch_timer marker; slot end = ORIG_IRQ marker
m0, m1, m2, m6 = c('m_0'), c('m_1'), c('m_2'), c('m_6')
sstart = np.where(m0 >= 0, m0, m1); has_slot = (sstart >= 0) & (m6 >= 0)
slot = np.where(has_slot, m6 - sstart, 0); gametime = np.where(sstart >= 0, sstart, cyc)
vend = c('vpos') - 256
nobj = c('NOBJ'); wp = c('WP'); LN = np.array([c('LN%d' % i) for i in range(5)]).T; pieces = LN[np.arange(len(F)), np.clip(wp, 0, 4)]
STG = {0xa0b4faad: 'intro/map', 0x91b430ec: 'bases/attract', 0xe2f47afa: 'coast/river', 0x634fcf44: 'cities', 0x6da96bff: 'desert', 0x018c6b86: 'ocean', 0xc39339a2: 'runway', 0x786ebae6: 'final'}
stage = np.array([STG.get(h, 'other') for h in c('HASH')])
OC = [n for n in names if n.startswith('O_')]
n = len(F)
pre = np.where((m2 >= 0) & (sstart >= 0), m2 - sstart, 0)     # slot time before the commit (the vblank)
post = np.where((m2 >= 0) & (m6 >= 0), m6 - m2, 0)             # commit + hold
P('=' * 100); P('PER-FRAME PROFILE %s: frames %d (%d..%d), %d boot frames left out' % (N, n, F[0], F[-1], nboot)); P('=' * 100)
P('late frames %d (%.2f%%)  frames with drops %d (%.3f%%)  sprites dropped %d  overruns %d' % (late.sum(), 100 * late.mean(), (dropn > 0).sum(), 100 * (dropn > 0).mean(), drop.sum(), ovr.sum()))
P('palette deferrals %d  tilemap deferrals %d  post-commit holds (SLOWB) %d  timer-started slots (game busy at line 226) %d (%.2f%%)  yields %d' % (paldef.sum(), bgdef.sum(), slowb.sum(), busy.sum(), 100 * busy.mean(), yn.sum()))
P('in-place updates %d  conversions carried over a slot %d  mixed sets shown %d  walks unfinished in their slot %d  column waits %d' % (deltan.sum(), carry.sum(), mixn.sum(), unfin.sum(), blkn.sum()))
P()
P('--- frame cycle structure (all frames; a real frame is %d cycles; holds stretch game frames)' % FRAME)
P('  %-12s %s' % ('frame', st(cyc)))
for k in ['game_logic', 'gx', 'idle', 'walk', 'conv', 'flip', 'reclaim', 'spr_ctl', 'dl', 'bg', 'bg_scrub', 'pal', 'fixed']: P('  %-12s %s' % (k, st(G[k])))
P('  %-12s %s' % ('game', st(game))); P('  %-12s %s' % ('HAL', st(hal))); P('  %-12s %s' % ('HAL-filler', st(hal - filler)))
P('  %-12s %s' % ('gametime', st(gametime))); P('  %-12s %s' % ('slot', st(slot[has_slot])))
P('  walk categories: ' + ', '.join('%s %.0f' % (k[2:], c(k).mean()) for k in ['c_walk_scan', 'c_walk_emit', 'c_walk_sort', 'c_walk_ctl', 'c_hud', 'c_bpool', 'c_fx_other']))
P('  bg categories:   ' + ', '.join('%s %.0f' % (k[2:], c(k).mean()) for k in ['c_bg_conv', 'c_bg_blast', 'c_bg_place', 'c_tm', 'c_tx', 'c_bg_scrub']))
P('  fixed categories:' + ', '.join('%s %.0f' % (k[2:], c(k).mean()) for k in ['c_sched', 'c_vid', 'c_tcheck', 'c_inputs', 'c_hal_other', 'c_diag', 'c_sound']))
P('  game categories: ' + ', '.join('%s %.0f' % (k[4:], c(k).mean()) for k in sorted((k for k in names if k.startswith('c_g_')), key=lambda k: -c(k).mean())))
P()
ok = ~late
P('--- late (%d) vs on-time (%d) frames' % (late.sum(), ok.sum()))
P('  %-12s %-45s | %s' % ('', 'late: mean p50 p90', 'on-time: mean p50 p90'))
def cmp(name, v):
    a, b = v[late], v[ok]
    P('  %-12s %7.0f %7.0f %7.0f %21s | %7.0f %7.0f %7.0f' % (name, a.mean(), np.percentile(a, 50), np.percentile(a, 90), '', b.mean(), np.percentile(b, 50), np.percentile(b, 90)))
for k, v in [('frame', cyc), ('game', game), ('gametime', gametime), ('slot', slot), ('pre-commit', pre), ('post-commit', post), ('HAL', hal), ('HAL-filler', hal - filler), ('walk', G['walk']), ('conv', G['conv']), ('dl', G['dl']), ('bg', G['bg']), ('pal', G['pal']), ('fixed', G['fixed']), ('flip', G['flip']), ('gx', G['gx']), ('objects', nobj), ('pieces', pieces), ('columns', c('PREV')), ('paldirty', c('PALDIRTY')), ('bgpend', c('BGPEND'))]: cmp(k, v)
P('  game categories, late vs on-time mean: ' + ', '.join('%s %.0f/%.0f' % (k[4:], c(k)[late].mean(), c(k)[ok].mean()) for k in sorted((k for k in names if k.startswith('c_g_') or k.startswith('c_gx')), key=lambda k: -c(k)[late].mean())[:12]))
P('  walk categories, late vs on-time mean: ' + ', '.join('%s %.0f/%.0f' % (k[2:], c(k)[late].mean(), c(k)[ok].mean()) for k in ['c_walk_scan', 'c_walk_emit', 'c_walk_sort', 'c_walk_ctl', 'c_hud', 'c_bpool']))
P('  fixed categories, late vs on-time mean: ' + ', '.join('%s %.0f/%.0f' % (k[2:], c(k)[late].mean(), c(k)[ok].mean()) for k in ['c_sched', 'c_vid', 'c_tcheck', 'c_spr_ctl', 'c_reclaim', 'c_bg_place', 'c_bg_blast', 'c_tm', 'c_tx', 'c_bg_conv']))
sw = G['walk'] + G['conv'] + G['dl']
P('  sprite work (walk+conv+dl) done in timer-started slots: %.1f%% of all sprite work (%.1f%% of frames); mean per busy frame %.0f vs idle-started %.0f' % (100 * sw[busy].sum() / sw.sum(), 100 * busy.mean(), sw[busy].mean(), sw[~busy].mean()))
P('  busy (timer) share: late %.1f%%  on-time %.1f%%;  hold share: late %.1f%% on-time %.1f%%;  walk unfinished: late %.1f%% on-time %.1f%%;  carried: late %.1f%% on-time %.1f%%' % (
    100 * busy[late].mean(), 100 * busy[ok].mean(), 100 * (slowb[late] > 0).mean(), 100 * (slowb[ok] > 0).mean(), 100 * (unfin[late] > 0).mean(), 100 * (unfin[ok] > 0).mean(), 100 * (carry[late] > 0).mean(), 100 * (carry[ok] > 0).mean()))
P()
P('--- late-frame cause tags (not exclusive)')
demand = game + hal - filler
med = {k: np.median(G[k][ok]) for k in G}
tags = collections.OrderedDict()
tags['game busy at 226 (timer slot)'] = busy
tags['post-commit hold'] = slowb > 0
tags['walk unfinished'] = unfin > 0
tags['conversion carried'] = carry > 0
tags['tilemap conversion > 15k (scene load)'] = G['bg'] > 15000
tags['palette > 10k (fade)'] = G['pal'] > 10000
tags['dl > 10k'] = G['dl'] > 10000
tags['game > 90k'] = game > 90000
tags['walk > 60k'] = G['walk'] > 60000
tags['conv > 35k'] = G['conv'] > 35000
tags['demand > frame (work-limited)'] = demand > FRAME
tags['demand < 0.93 frame (scheduling-limited)'] = demand < 0.93 * FRAME
for k, v in tags.items(): P('  %-45s late %6d (%.1f%% of late)   on-time %6d (%.1f%%)' % (k, (v & late).sum(), 100 * (v & late).sum() / max(1, late.sum()), (v & ok).sum(), 100 * (v & ok).sum() / max(1, ok.sum())))
none = late & ~np.any(np.array([tags[k] for k in tags]), axis=0); P('  %-45s %d' % ('late with no tag', none.sum()))
# primary cause: the group with the largest excess over the on-time median
groups = ['walk', 'conv', 'dl', 'bg', 'pal', 'flip', 'reclaim', 'spr_ctl', 'fixed', 'game_logic', 'gx']
ex = np.array([G[k] - med[k] for k in groups]).T
prim = collections.Counter()
for i in np.nonzero(late)[0]:
    j = int(np.argmax(ex[i])); prim[groups[j] if ex[i][j] > 5000 else 'none > 5k'] += 1
P('  primary excess (largest group over its on-time median, > 5k): ' + ', '.join('%s %d' % kv for kv in prim.most_common()))
exc = demand[late] - FRAME
P('  work-limited late frames: excess over the frame  %s' % st(exc[exc > 0]))
P('  late frames by excess: <=0 %d  0-10k %d  10-20k %d  20-40k %d  >40k %d' % ((exc <= 0).sum(), ((exc > 0) & (exc <= 10000)).sum(), ((exc > 10000) & (exc <= 20000)).sum(), ((exc > 20000) & (exc <= 40000)).sum(), (exc > 40000).sum()))
# 3-frame window (holds move game-frame boundaries): work over frames k-2..k against 3 real frames
w = game + hal - filler
W3 = w.copy(); W3[1:] += w[:-1]; W3[2:] += w[:-2]
def3 = W3 - 3 * FRAME
lag = d('IDLES') == 0          # the game never reached its idle loop in this game frame: a true lag frame
P('  3-frame window deficit (work - 3 real frames), late frames: %s' % st(def3[late]))
P('  3-frame window deficit, on-time frames: %s' % st(def3[ok]))
P('  late frames by 3-frame deficit: <=0 %d  0-15k %d  15-30k %d  30-60k %d  >60k %d   (per frame: /3)' % ((def3[late] <= 0).sum(), ((def3[late] > 0) & (def3[late] <= 15000)).sum(), ((def3[late] > 15000) & (def3[late] <= 30000)).sum(), ((def3[late] > 30000) & (def3[late] <= 60000)).sum(), (def3[late] > 60000).sum()))
P('  late frames fitting 3 real frames after cutting X per frame: ' + ', '.join('%dk: %d%%' % (x // 1000, 100 * ((def3[late] - 3 * x) <= 0).sum() // max(1, late.sum())) for x in (0, 5000, 10000, 15000, 20000, 30000, 40000, 60000)))
P('  game lag frames (game busy for the whole game frame, no idle entry): %d (%.2f%%); late among them %.1f%%; lag share in late frames %.1f%%' % (lag.sum(), 100 * lag.mean(), 100 * late[lag].mean() if lag.any() else 0, 100 * lag[late].mean()))
# what-if: late frames whose demand would fit after cutting X cycles (the simplest shedding model)
P('  late frames with demand <= frame after cutting: ' + ', '.join('%dk: %d%%' % (x // 1000, 100 * ((demand[late] - x) <= FRAME).sum() // max(1, late.sum())) for x in (0, 5000, 10000, 15000, 20000, 30000, 40000, 60000)))
sl = late & (demand < 0.93 * FRAME)
P('  scheduling-limited late frames (%d): busy %.0f%%  hold %.0f%%  carried %.0f%%  unfinished walk %.0f%%  column wait %.0f%%  pre-commit slot < 20k %.0f%%  conv in frame %.0f  walk %.0f  bg %.0f  pal %.0f' % (
    sl.sum(), 100 * busy[sl].mean(), 100 * (slowb[sl] > 0).mean(), 100 * (carry[sl] > 0).mean(), 100 * (unfin[sl] > 0).mean(), 100 * (blkn[sl] > 0).mean(), 100 * (pre[sl] < 20000).mean(), G['conv'][sl].mean(), G['walk'][sl].mean(), G['bg'][sl].mean(), G['pal'][sl].mean()) if sl.any() else '  none')
P('  late frames: pre-commit slot time %s' % st(pre[late])); P('  on-time:     pre-commit slot time %s' % st(pre[ok]))
# runs of late frames
runs = []; i = 0; L = late.astype(int)
while i < n:
    if L[i]:
        j = i
        while j < n and L[j]: j += 1
        runs.append(j - i); i = j
    else: i += 1
rc = collections.Counter(runs); P('  late runs (consecutive late frames): ' + ', '.join('%d:%d' % kv for kv in sorted(rc.items())[:12]))
P()
P('--- stages')
P('  %-14s %7s %6s %6s %6s %7s %6s %7s %7s %7s %7s %6s %6s' % ('stage', 'frames', 'late%', 'drop%', 'lag%', 'busy%', 'holds', 'game', 'HAL-f', 'walk', 'conv', 'nobj', 'cols'))
for s in sorted(set(stage), key=lambda s: -(stage == s).sum()):
    m = stage == s
    P('  %-14s %7d %6.2f %6.3f %6.2f %7.1f %6d %7.0f %7.0f %7.0f %7.0f %6.1f %6.1f' % (s, m.sum(), 100 * late[m].mean(), 100 * (dropn[m] > 0).mean(), 100 * lag[m].mean(), 100 * busy[m].mean(), slowb[m].sum(), game[m].mean(), (hal - filler)[m].mean(), G['walk'][m].mean(), G['conv'][m].mean(), nobj[m].mean(), c('PREV')[m].mean()))
# dense windows: frames with >= 45 objects
dn = nobj >= 45
P('  dense frames (>= 45 objects): %d (%.1f%%), late %.1f%%, lag %.1f%%, drop frames %.2f%%; mean game %.0f HAL-f %.0f walk %.0f conv %.0f dl %.0f bg %.0f fixed %.0f' % (dn.sum(), 100 * dn.mean(), 100 * late[dn].mean(), 100 * lag[dn].mean(), 100 * (dropn[dn] > 0).mean(), game[dn].mean(), (hal - filler)[dn].mean(), G['walk'][dn].mean(), G['conv'][dn].mean(), G['dl'][dn].mean(), G['bg'][dn].mean(), G['fixed'][dn].mean()) if dn.any() else '  no dense frames')
P()
P('--- object census (mean objects per frame by category): late vs on-time vs drop frames')
P('  %-10s %7s %7s %7s' % ('category', 'late', 'ontime', 'drops'))
dm = dropn > 0
for k in OC: P('  %-10s %7.1f %7.1f %7.1f' % (k[2:], c(k)[late].mean(), c(k)[ok].mean(), c(k)[dm].mean() if dm.any() else 0))
P('  %-10s %7.1f %7.1f %7.1f' % ('all', nobj[late].mean(), nobj[ok].mean(), nobj[dm].mean() if dm.any() else 0))
msk = nobj > 0
P('  walk cycles per object (walk / objects): %s' % st((G['walk'][msk] / nobj[msk])))
P('  conversion cycles per column (conv / PREV columns): %s' % st((G['conv'][c('PREV') > 0] / c('PREV')[c('PREV') > 0])))
P()
P('--- drop frames (%d): ring and lists' % dm.sum())
if dm.any():
    for k, v in [('columns(PREV)', c('PREV')), ('pieces', pieces), ('objects', nobj), ('sets in ring', c('ORDN')), ('split (SPS>=0)', (c('SPS') >= 0).astype(int)), ('column waits', blkn), ('sprites dropped', drop), ('late', late.astype(int))]: P('  %-16s %s' % (k, st(v[dm])))
P()
P('--- fixed per-frame costs (frames with <= 6 objects, no deferrals, no palette work): median cycles')
q = (nobj <= 6) & (paldef == 0) & (bgdef == 0) & (c('PALDIRTY') == 0) & ok
if q.sum() > 10:
    P('  n=%d: ' % q.sum() + ', '.join('%s %.0f' % (k[2:], np.median(c(k)[q])) for k in ['c_sched', 'c_vid', 'c_tcheck', 'c_inputs', 'c_pal', 'c_tm', 'c_bg_place', 'c_bg_blast', 'c_bg_conv', 'c_tx', 'c_dl', 'c_spr_ctl', 'c_reclaim', 'c_flip', 'c_walk_ctl', 'c_walk_scan', 'c_hud', 'c_walk_sort', 'c_g_irq', 'c_hal_other']))
    P('  total HAL-filler median %.0f, game %.0f' % (np.median((hal - filler)[q]), np.median(game[q])))
P()
P('--- timeline (slot start = game idle entry or timer; vpos at the slot end from the handler)')
P('  gametime (handler start -> slot start) %s' % st(gametime[has_slot]))
P('  slot length %s' % st(slot[has_slot]))
P('  vpos at the frame end (slot end): ' + ', '.join('%d:%d' % (b, ((vend >= b) & (vend < b + 20)).sum()) for b in range(0, 264, 20)))
P('  frames longer than a real frame (held/stretched): %d (%.2f%%); shorter than 0.9 frame: %d' % ((cyc > FRAME * 1.02).sum(), 100 * (cyc > FRAME * 1.02).mean(), (cyc < FRAME * 0.9).sum()))
P()
P('--- spare time: frames whose slot had filler (the scrub ran, > 5k) = the HAL was not saturated')
sp_ = filler > 5000
P('  frames with filler %d (%.1f%%), late among them %.2f%%; frames without %d, late among them %.2f%%' % (sp_.sum(), 100 * sp_.mean(), 100 * late[sp_].mean(), (~sp_).sum(), 100 * late[~sp_].mean()))
P('  dl cycles: in filler frames mean %.0f (%.0f%% of all dl), in saturated frames mean %.0f' % (G['dl'][sp_].mean(), 100 * G['dl'][sp_].sum() / max(1, G['dl'].sum()), G['dl'][~sp_].mean()))
P('  in saturated frames: mean walk %.0f conv %.0f dl %.0f bg %.0f pal %.0f fixed %.0f spr_ctl %.0f flip %.0f reclaim %.0f game %.0f gx %.0f | HAL-f %.0f' % (G['walk'][~sp_].mean(), G['conv'][~sp_].mean(), G['dl'][~sp_].mean(), G['bg'][~sp_].mean(), G['pal'][~sp_].mean(), G['fixed'][~sp_].mean(), G['spr_ctl'][~sp_].mean(), G['flip'][~sp_].mean(), G['reclaim'][~sp_].mean(), G['game_logic'][~sp_].mean(), G['gx'][~sp_].mean(), (hal - filler)[~sp_].mean()))
P('  fixed categories in saturated frames: ' + ', '.join('%s %.0f' % (k[2:], c(k)[~sp_].mean()) for k in ['c_sched', 'c_vid', 'c_tcheck', 'c_inputs', 'c_spr_ctl', 'c_reclaim', 'c_flip', 'c_bg_place', 'c_bg_blast', 'c_tm', 'c_tx', 'c_walk_ctl', 'c_walk_scan', 'c_walk_sort', 'c_hud', 'c_pal', 'c_g_irq']))
P()
P('--- heavy frames')
for k, thr in [('bg', 15000), ('pal', 10000), ('dl', 10000), ('walk', 60000), ('conv', 35000), ('game_logic', 70000), ('gx', 25000)]:
    v = G[k] > thr; P('  %-11s > %6d: %6d frames (%.2f%%), late among them %.1f%%' % (k, thr, v.sum(), 100 * v.mean(), 100 * late[v].mean() if v.any() else 0))
P()
P('--- overrun frames')
for i in np.nonzero(ovr > 0)[0][:40]:
    P('  frame %d stage %s: cycles %d game %d walk %d conv %d dl %d bg %d pal %d flip %d objects %d cols %d vend %d busy %d' % (F[i], stage[i], cyc[i], game[i], G['walk'][i], G['conv'][i], G['dl'][i], G['bg'][i], G['pal'][i], G['flip'][i], nobj[i], c('PREV')[i], vend[i], busy[i]))
open('%s/%s/report.txt' % (R, N), 'w').write('\n'.join(out) + '\n')
