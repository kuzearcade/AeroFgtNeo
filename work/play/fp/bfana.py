#!/usr/bin/env python3
"""bfana.py <name>: the boss-fight profile of work/play/fp/<name>/frames.npz (fpmerge.py) joined with the
bot's log (<name>/c*/bot.txt: frame, boss, bombs P1/P2, active objects, presses, boss type): mean cycles
per frame by category for boss-fight frames against the rest, the object census, and the frames binned
by enemy bullets (O_ebul) and by active objects; the per-frame budget is 200,000 cycles (12 MHz / 60)."""
import sys, os, glob, numpy as np, collections
R=os.path.expanduser('~/AeroFgtNeo/work/play/fp'); N=sys.argv[1]
z=np.load('%s/%s/frames.npz'%(R,N)); F=z['frames']; A=z['data']; names=list(z['names']); ci={n:i for i,n in enumerate(names)}
bot={}
for fn in glob.glob('%s/%s/c*/bot.txt'%(R,N)):
    for l in open(fn):
        p=l.split()
        if len(p)>=7: bot[int(p[0])]=(int(p[1]),int(p[4]),int(p[6]))
boss=np.array([bot.get(f,(0,0,0))[0] for f in F]); nact=np.array([bot.get(f,(0,0,0))[1] for f in F])
ok=(A[:,ci['cycles']]<600000)&(A[:,ci['cycles']]>0)
F,A,boss,nact=F[ok],A[ok],boss[ok],nact[ok]
game=sum(A[:,ci[n]] for n in names if n.startswith('c_g_'))
def col(n): return A[:,ci[n]] if n in ci else np.zeros(len(F))
groups=[('game logic',game),('walk (scan+sort)',col('c_walk_scan')+col('c_walk_sort')),('pass pieces (emit)',col('c_walk_emit')),
        ('pass control',col('c_walk_ctl')+col('c_spr_ctl')),('shapes (conv)',col('c_conv')),('HUD',col('c_hud')),('bullet pool',col('c_bpool')),
        ('flip+reclaim',col('c_flip')+col('c_reclaim')),('dl',col('c_dl')),('bg+tm+tx',col('c_bg_conv')+col('c_bg_blast')+col('c_bg_place')+col('c_bg_scrub')+col('c_tx')+col('c_tm')),
        ('palette',col('c_pal')),('sched+vid+other',col('c_sched')+col('c_vid')+col('c_tcheck')+col('c_inputs')+col('c_hal_other')+col('c_fx_other')),
        ('gx (collision)',col('c_gx_col')+col('c_gx_upd')),('idle',col('c_idle')),('total',A[:,ci['cycles']])]
gcats=sorted([n for n in names if n.startswith('c_g_')], key=lambda n:-A[:,ci[n]].mean())
def table(sel,label):
    m=sel.sum()
    if not m: return
    print("== %s: %d frames" % (label,m))
    for g,v in groups: print("   %-20s %8.0f" % (g,v[sel].mean()))
    print("   game by category: "+", ".join("%s %.0f"%(n[4:],A[sel][:,ci[n]].mean()) for n in gcats[:8]))
    oc=[n for n in names if n.startswith('O_')]
    print("   objects: "+", ".join("%s %.1f"%(n[2:],A[sel][:,ci[n]].mean()) for n in oc if A[sel][:,ci[n]].mean()>=0.5)+"; active (bot) %.1f" % nact[sel].mean())
    for n in ('LATE','OVERRUN','DROP','CARRY'):
        if n in ci:
            d=np.diff(A[:,ci[n]]); d=np.where(d<0,0,d); d=np.concatenate([[0],d]); print("   %s +%d" % (n,d[sel].sum()), end="")
    print()
table(boss==1,"boss fights"); table(boss==0,"other frames")
eb=col('O_ebul')
for lo,hi in ((0,10),(10,20),(20,30),(30,45),(45,999)):
    table((eb>=lo)&(eb<hi),"enemy bullets %d-%d"%(lo,hi))
