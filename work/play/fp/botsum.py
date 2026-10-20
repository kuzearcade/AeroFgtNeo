#!/usr/bin/env python3
"""botsum.py <name>...: a battery run with botfire.lua (work/play/fp/bl_<name>_*/lag.txt + bot.txt):
the totals overall and during boss fights (the bot's boss flag), plus lost logic by the active-object
count (load bins).  Columns as lagsum.py: lost logic = vbf >= 1 at the handler, late = LATE's growth,
overruns/drop frames = the HAL counters' growth (the conversion only)."""
import sys, glob, collections
def load(fn):
    L=[l.split() for l in open(fn)]; return [l for l in L if len(l)>=8 and l[0].isdigit() and int(l[0])>=450]
for name in sys.argv[1:]:
    T=collections.Counter(); B=collections.Counter(); bins=collections.defaultdict(lambda:[0,0]); binsB=collections.defaultdict(lambda:[0,0])
    seeds=0; bossframes=0; presses=0
    for fn in sorted(glob.glob('work/play/fp/bl_%s_*/lag.txt'%name)):
        L=load(fn); bot={}
        try:
            for l in open(fn.replace('lag.txt','bot.txt')):
                f=l.split()
                if len(f)>=6: bot[int(f[0])]=(int(f[1]),int(f[4]),int(f[5]))
        except FileNotFoundError: pass
        if not L: continue
        seeds+=1; presses+=max((b[2] for b in bot.values()),default=0)
        prev=None
        for l in L:
            f=int(l[0]); lost=int(l[1])>=1; late=int(l[2]); ov=int(l[10]) if len(l)>=13 else 0; df=int(l[9]) if len(l)>=13 else 0
            b=bot.get(f) or bot.get(f-1) or (0,0,0)
            d_late=(late-prev[0]) if prev else 0; d_ov=(ov-prev[1]) if prev else 0; d_df=(df-prev[2]) if prev else 0
            prev=(late,ov,df)
            for C,sel in ((T,True),(B,b[0]==1)):
                if not sel: continue
                C['frames']+=1; C['lost']+=lost; C['late']+=d_late; C['ov']+=d_ov; C['df']+=d_df
            k=min(b[1]//10*10,90); bins[k][0]+=1; bins[k][1]+=lost
            if b[0]: binsB[k][0]+=1; binsB[k][1]+=lost
        bossframes+=sum(1 for v in bot.values() if v[0])
    def line(C):
        f=max(1,C['frames']); return "frames %6d  lost logic %.2f%%  late %.2f%%  drop frames %d (%.3f%%)  overruns %d" % (C['frames'],100.0*C['lost']/f,100.0*C['late']/f,C['df'],100.0*C['df']/f,C['ov'])
    print("%-10s seeds %d, bomb presses %d" % (name,seeds,presses))
    print("   all:   "+line(T)); print("   boss:  "+line(B))
    print("   lost logic by active objects (all / boss fights): "+", ".join("%d+: %.1f%% (%d) / %s" % (k,100.0*v[1]/v[0],v[0],("%.1f%% (%d)"%(100.0*binsB[k][1]/binsB[k][0],binsB[k][0])) if binsB[k][0] else "-") for k,v in sorted(bins.items())))
