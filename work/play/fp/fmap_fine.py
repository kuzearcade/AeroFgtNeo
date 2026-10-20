"""fmap.py <hal.lst> <out map>: category map for fprof (PC ranges -> category) from the build's
hal.lst global labels (HAL, >= 0x80000) and work/catalog/neo_functions_described.tsv (game code);
markers for the frame timeline."""
import sys, re, csv, os
LST, OUT = sys.argv[1], sys.argv[2]
R = os.path.expanduser('~/AeroFgtNeo')
GAME = ['boot', 'irq/vblank', 'main loop', 'objects (generic)', 'enemies', 'bosses', 'enemy weapons', 'player',
        'player weapons', 'explosions/effects', 'collision', 'scoring/HUD', 'screens', 'stage/scripting', 'palette',
        'tilemap', 'math/util', 'input', 'sound', 'sprites/lookup', 'sprite-list builder']
GSHORT = ['g_boot', 'g_irq', 'g_main', 'g_objgen', 'g_enemies', 'g_bosses', 'g_ewpn', 'g_player', 'g_pwpn', 'g_expl',
          'g_coll', 'g_score', 'g_screens', 'g_stage', 'g_pal', 'g_tilemap', 'g_math', 'g_input', 'g_sound', 'g_lut', 'g_builder']
HAL = ['idle', 'g_other', 'sched', 'vid', 'tcheck', 'inputs', 'walk_scan', 'walk_emit', 'hud', 'walk_sort', 'walk_ctl', 'bpool',
       'fx_other', 'conv', 'flip', 'reclaim', 'spr_ctl', 'dl', 'bg_scrub', 'bg_blast', 'bg_place', 'tx', 'bg_conv', 'tm', 'pal',
       'gx_col', 'gx_upd', 'sound', 'diag', 'hal_other', 'ram']
NAMES = GSHORT + HAL
cid = {n: i for i, n in enumerate(NAMES)}
def hal_cat(n):
    s = lambda *p: n.startswith(p)
    if s('sch_') or n in ('hal_post','hal_idle','hal_timer','hal_vbl','hal_tramp'): return 'sched'
    if n in ('hal_coin_sound',): return 'sound'
    if s('hal_vid_', 'hal_slip'): return 'vid'
    if n in ('hal_late_n', 'hal_late_raw', 'hal_vpos', 'hal_deadline', 'hal_late_rawx'): return 'tcheck'
    if s('hal_inputs'): return 'inputs'
    if s('fx_walk'): return 'walk_scan'
    # hal/fz.s (FUSED): the object half as the walk's scan/sort, the pass's piece code as
    # the emit, its control as walk_ctl; the shape routines stay 'conv'
    # (fine split, work/play/fp/fmap_fine.py: fz_rec -> walk_scan, fz_build/fz_pass -> walk_sort,
    # fz_ntab -> walk_ctl, fz_next -> fx_other, fz_disp -> bpool, fz_bul -> inputs, fz_hud -> hud,
    # fz_go/fz_begin/fz_due/fz_anch/fz_fin -> diag)
    if s('fz_rec'): return 'walk_scan'
    if s('fz_build', 'fz_pass', 'fz_group'): return 'walk_sort'
    if s('fz_em'): return 'walk_emit'
    if s('fz_ntab'): return 'walk_ctl'
    if s('fz_next'): return 'fx_other'
    if s('fz_disp', 'fz_nsl'): return 'bpool'
    if s('fz_bul'): return 'inputs'
    if s('fz_hud'): return 'hud'
    if s('fz_pd_', 'fz_pdh_', 'fz_pdt', 'fz_pdht'): return 'walk_emit'      # (the descriptor piece routines: pass pieces)
    if s('fz_fast', 'fz_bul', 'fz_pshot', 'fz_disp', 'fz_next', 'fz_nsl'): return 'walk_ctl'   # (the record dispatch)
    if s('fz_'): return 'diag'
    if s('fx_obj', 'fx_o1', 'fx_em', 'fxb_', 'fx_piece', 'fx_lin', 'fx_tab'): return 'walk_emit'
    if s('fx_hud', 'fx_q', 'fx_h'): return 'hud'
    if s('fx_sort', 'fx_grp'): return 'walk_sort'
    if s('fx_snap', 'fx_start', 'fx_gen', 'fx_batch'): return 'walk_ctl'
    if s('bp_'): return 'bpool'
    if s('fx_', 'fxu'): return 'fx_other'
    if s('hal_spr_go', 'spv_', 'spz_', 'spr_go', 'spr_lo', 'spr_z', 'spr_fast'): return 'conv'
    if s('hal_spr_flip', 'spr_cut', 'ring_spr_flip'): return 'flip'
    if s('hal_spr_reclaim'): return 'reclaim'
    if s('hal_spr', 'spr_', 'ring_spr'): return 'spr_ctl'
    if s('dl_', 'sh_', 'sh2_', 'dlr_'): return 'dl'
    if s('hal_bg_scrub', 'hal_bg_sample', 'hal_bg_verify'): return 'bg_scrub'
    if s('hal_bg_blast'): return 'bg_blast'
    if s('hal_bg_place', 'hal_bg_window', 'hal_bg_pos'): return 'bg_place'
    if s('hal_bg_mask', 'hal_bg_l1', 'tx_', 'hal_bg_hide'): return 'tx'
    if s('hal_bg', 'hal_fix', 'hal_attr', 'hal_tile'): return 'bg_conv'
    if s('tm_'): return 'tm'
    if s('hal_pal'): return 'pal'
    if s('gx_col'): return 'gx_col'
    if s('gx_'): return 'gx_upd'
    if s('hal_sound', 'hal_z80', 'hal_snd'): return 'sound'
    if s('ovd_', 'hal_diag', 'diag_'): return 'diag'
    return 'hal_other'
labs = sorted((int(m.group(1), 16), m.group(2)) for m in re.finditer(r'^([0-9A-F]{8}) ([A-Za-z_]\w*)$', open(LST, errors='ignore').read(), re.M))
labs = [(a, n) for a, n in labs if 0x80000 <= a < 0x200000]
# one name per address: prefer the first alphabetically-stable global (they alias)
rng = []
seen = set()
for i, (a, n) in enumerate(labs):
    if a in seen: continue
    seen.add(a)
    nxt = next((b for b, _ in labs[i + 1:] if b > a), 0x200000)
    rng.append((a, nxt, hal_cat(n), n))
with open(OUT, 'w') as o:
    for i, n in enumerate(NAMES): o.write('N %d %s\n' % (i, n))
    o.write('R 0 80000 %d\n' % cid['g_other'])
    for r in csv.DictReader(open(R + '/work/catalog/neo_functions_described.tsv'), delimiter='\t'):
        sub = (r.get('subsystem') or '').replace('game: ', '')
        if sub.startswith('screens'): sub = 'screens'
        if sub in GAME:
            o.write('R %s %s %d\n' % (r['entry'], r['end'], cid[GSHORT[GAME.index(sub)]]))
    o.write('R b4a bd4 %d\n' % cid['idle'])
    for a, b, c, n in rng: o.write('R %x %x %d\n' % (a, b, cid[c]))
    o.write('R 100000 200000 %d\n' % cid['ram'])
    o.write('R 10fc00 10fc10 %d\n' % cid['idle'])
    o.write('R 108000 10a000 %d\n' % cid['ram'])
    # markers
    L = {n: a for a, n in labs}
    for i, n in enumerate(['sch_idle', 'sch_timer', 'hal_vid_commit', 'hal_spr_flip', 'fx_snap_begin', 'hal_inputs']):
        o.write('M %x %d\n' % (L[n], i))
    o.write('M 888 6\n')      # ORIG_IRQ: the slot ended, the game's handler
    o.write('M 9ee 7\n')      # the handler's end
cnt = {}
for a, b, c, n in rng: cnt[c] = cnt.get(c, 0) + (b - a)
print({k: v for k, v in sorted(cnt.items(), key=lambda x: -x[1])})
print('hal_other:', ' '.join(n for a, b, c, n in rng if c == 'hal_other')[:1500])
