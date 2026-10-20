"""fpbudget.py: per-logic-frame cycle budget of the ov10 profile (work/play/fp/ov10/frames.npz) joined with
its lag run (lag/lag.txt): what one walk + one conversion + the game would need per logic frame, by object
count and stage, and the lost-vblank share modelled after a cut of X cycles per frame (AUDIT.md 23)."""
import numpy as np, collections, sys
R='/home/vboxuser/AeroFgtNeo/work/play/fp'
z=np.load(R+'/ov10/frames.npz'); F=z['frames']; A=z['data']; names=list(z['names']); ci={n:i for i,n in enumerate(names)}
print('cols:', ' '.join(names))
lag={}; hsh={}
for l in open(R+'/lag/lag.txt'):
    p=l.split()
    if len(p)>=8: lag[int(p[0])]=int(p[1])>=1; hsh[int(p[0])]=int(p[7],16)
idx={f:i for i,f in enumerate(F)}
fr=[f for f in F if f in lag and f>=450]
I=np.array([idx[f] for f in fr]); L=np.array([lag[f] for f in fr])
c=lambda n: A[I,ci[n]].astype(float)
d=lambda n: np.r_[0,np.diff(A[:,ci[n]])][I]
G=sum(c(k) for k in names if k.startswith('c_g_'))+c('c_gx_col')+c('c_gx_upd')
walk=c('c_walk_scan')+c('c_walk_emit')+c('c_walk_sort')+c('c_walk_ctl')+c('c_hud')+c('c_fx_other')+c('c_bpool')
conv=c('c_conv'); dl=c('c_dl'); bg=c('c_bg_blast')+c('c_bg_place')+c('c_tx')+c('c_bg_conv')+c('c_tm'); pal=c('c_pal')
fixed=c('c_sched')+c('c_vid')+c('c_tcheck')+c('c_inputs')+c('c_flip')+c('c_reclaim')+c('c_spr_ctl')+c('c_hal_other')+c('c_sound')+c('c_diag')
idle=c('c_idle'); scrub=c('c_bg_scrub'); ram=c('c_ram')
tot=G+walk+conv+dl+bg+pal+fixed+idle+scrub+ram
print('frames %d, mean total %.0f (G %.0f walk %.0f conv %.0f dl %.0f bg %.0f pal %.0f fixed %.0f idle %.0f scrub %.0f ram %.0f)'%(len(fr),tot.mean(),G.mean(),walk.mean(),conv.mean(),dl.mean(),bg.mean(),pal.mean(),fixed.mean(),idle.mean(),scrub.mean(),ram.mean()))
nobj=c('NOBJ'); busy=c('BUSY')!=0
# logic-frame groups: a non-lag frame followed by its lag frames
groups=[]; cur=None
for k in range(len(fr)):
    if not L[k] or cur is None:
        if cur: groups.append(cur)
        cur=[k]
    else: cur.append(k)
if cur: groups.append(cur)
BUD=202750
rows=[]
for g in groups:
    g=np.array(g)
    need=G[g].sum()+walk[g].max()+conv[g].max()+dl[g].sum()+bg[g].sum()+pal[g].sum()+fixed[g].mean()*1.0
    rows.append((len(g), nobj[g].max(), need, G[g].sum(), walk[g].max(), conv[g].max(), dl[g].sum(), bg[g].sum(), pal[g].sum(), fixed[g].mean(), walk[g].sum()-walk[g].max(), conv[g].sum()-conv[g].max(), hsh.get(fr[g[0]],0)))
r=np.array([x[:12] for x in rows]); st=[x[12] for x in rows]
STG={0xa0b4faad:'intro/map',0x91b430ec:'bases/attract',0xe2f47afa:'coast/river',0x634fcf44:'cities',0x6da96bff:'desert',0x018c6b86:'ocean',0xc39339a2:'runway',0x786ebae6:'final'}
print('logic frames %d; spanning 1 vblank %d, 2: %d, 3+: %d'%(len(rows),(r[:,0]==1).sum(),(r[:,0]==2).sum(),(r[:,0]>=3).sum()))
ex=r[:,2]-BUD
print('needed - budget (one walk, one conversion, no waste): >0 in %.1f%% of logic frames; p50 %.0f p90 %.0f p95 %.0f p99 %.0f max %.0f'%(100*(ex>0).mean(),*np.percentile(ex,[50,90,95,99]),ex.max()))
over=ex>0
print('over-budget logic frames: mean need %.0f = G %.0f walk %.0f conv %.0f dl %.0f bg %.0f pal %.0f fixed %.0f | extra walks %.0f extra conv %.0f (waste now)'%tuple(r[over,2:12].mean(0)[[0,1,2,3,4,5,6,7,8,9]]))
print('  objects p50 %.0f; by stage: '%np.median(r[over,1])+', '.join('%s %d'%(STG.get(s,'other'),n) for s,n in collections.Counter(st[i] for i in np.where(over)[0]).most_common()))
for cut in (10000,20000,30000,40000,50000,60000):
    print('  a cut of %dk per frame fits %.1f%% of all logic frames (now %.1f%%)'%(cut//1000,100*(ex<=cut).mean(),100*(ex<=0).mean()))
dn=r[:,1]>=45
print('dense logic frames (>=45 objects) %d: need p50 %.0f p90 %.0f p99 %.0f; over budget %.1f%%; mean G %.0f walk %.0f conv %.0f dl %.0f bg %.0f pal %.0f fixed %.0f'%(dn.sum(),*np.percentile(r[dn,2],[50,90,99]),100*(ex[dn]>0).mean(),*r[dn,3:10].mean(0)))
for lo,hi in ((0,20),(20,30),(30,40),(40,50),(50,60),(60,200)):
    m=(r[:,1]>=lo)&(r[:,1]<hi)
    if m.sum(): print('  objects %2d-%3d: %6d logic frames, over budget %5.1f%%, need p50 %6.0f p90 %6.0f; G %5.0f walk %5.0f conv %5.0f dl %5.0f'%(lo,hi,m.sum(),100*(ex[m]>0).mean(),*np.percentile(r[m,2],[50,90]),*r[m,3:7].mean(0)))
# per stage over-budget share and the wasted cycles
print('waste per vblank frame now: extra walks %.0f extra conversions %.0f (mean over all logic frames, per logic frame)'%(r[:,10].mean(),r[:,11].mean()))
# game logic per logic frame distribution
print('G per logic frame: p50 %.0f p90 %.0f p99 %.0f max %.0f; > 163k (original frame) in %.2f%%'%(*np.percentile(r[:,3],[50,90,99]),r[:,3].max(),100*(r[:,3]>163000).mean()))
