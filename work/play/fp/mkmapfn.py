#!/usr/bin/env python3
"""mkmapfn.py <hal.lst> <out map> [ngame]: a function-level category map for fprof (runfp.sh MAP=):
the game's ngame hottest routines (work/catalog/neo_functions_described.tsv, by exclusive cycles) one
category each and the rest of the game one; the HAL's sprite path by routine (builder b_*, pass p_*),
the collision index, scan and object-loop scanner apart; the rest of the HAL in a few groups
(fmap_fine.py's categories folded).  At most 63 categories."""
import re, csv, sys, os
LST, OUT = sys.argv[1], sys.argv[2]; NG = int(sys.argv[3]) if len(sys.argv) > 3 else 28
H = os.path.dirname(os.path.abspath(__file__))
lst = open(LST, errors='ignore').read()
labs = sorted((int(m.group(1), 16), m.group(2)) for m in re.finditer(r'^([0-9A-F]{8}) ([A-Za-z_]\w*)$', lst, re.M))
labs = [(a, n) for a, n in labs if 0x80000 <= a < 0x200000]
src = open(os.path.join(H, 'fmap_fine.py')).read()
ns = {}; exec(src[src.index('def hal_cat'):src.index('labs = sorted')], ns); hal_cat = ns['hal_cat']
names = []; cid = {}
def C(n):
    if n not in cid: cid[n] = len(names); names.append(n)
    return cid[n]
rows = list(csv.DictReader(open(os.path.join(H, '../../catalog/neo_functions_described.tsv')), delimiter='\t'))
grows = sorted((r for r in rows if r['subsystem'].startswith('game')), key=lambda r: -int(r['cycles_excl'] or 0))
R = [(0, 0x80000, C('g_rest'))]
for r in grows[:NG]: R.append((int(r['entry'], 16), int(r['end'], 16), C('g:' + r['name'][:24].replace(' ', '_'))))
special = {'fz_build': 'b_build', 'fz_pass': 'b_pass', 'fz_group': 'b_group', 'fz_rec': 'b_rec', 'fz_ntab': 'p_ntab',
           'fz_fastv': 'p_fastv', 'fz_fast': 'p_fast', 'fz_disp': 'p_disp', 'fz_next': 'p_next', 'fz_go': 'p_go', 'fz_due': 'p_due',
           'fz_fin': 'p_fin', 'fz_anch': 'p_anch', 'fz_split_anch': 'p_split', 'fz_hud': 'p_hud', 'fz_toh': 'p_hud', 'fz_bul': 'p_bul'}
fold = {'conv': 'shapes', 'flip': 'flip+reclaim', 'reclaim': 'flip+reclaim', 'spr_ctl': 'spr_ctl', 'bg_conv': 'bg', 'bg_blast': 'bg',
        'bg_place': 'bg', 'bg_scrub': 'bg', 'tx': 'bg', 'tm': 'bg', 'pal': 'pal', 'sched': 'sched', 'vid': 'sched', 'tcheck': 'sched',
        'idle': 'idle', 'bpool': 'bpool', 'hud': 'hud'}
for i, (a, n) in enumerate(labs):
    b = next((x for x, _ in labs[i + 1:] if x > a), 0x200000)
    if n in special: c = special[n]
    elif n.startswith('fz_em'): c = 'p_em'
    elif n.startswith('fz_pd'): c = 'p_pd'
    elif n.startswith('fz_'): c = 'p_other'
    elif n.startswith('gx_b'): c = 'gx_index'
    elif n.startswith('gx_scan'): c = 'gx_scan'
    elif n.startswith('gx_'): c = 'gx_upd'
    else: c = fold.get(hal_cat(n), 'hal_other')
    R.append((a, b, C(c)))
R += [(0x100000, 0x200000, C('idle')), (0xb4a, 0xbd4, C('idle'))]
assert len(names) <= 63, len(names)
L = {n: a for a, n in labs}
with open(OUT, 'w') as o:
    for i, n in enumerate(names): o.write('N %d %s\n' % (i, n[:31]))
    for a, b, c in R: o.write('R %x %x %d\n' % (a, b, c))
    for i, n in enumerate(['sch_idle', 'sch_timer', 'hal_vid_commit', 'hal_spr_flip', 'fx_snap_begin', 'hal_inputs']): o.write('M %x %d\n' % (L[n], i))
    o.write('M 888 6\nM 9ee 7\n')
print(OUT, len(names), 'categories')
