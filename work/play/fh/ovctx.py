#!/usr/bin/env python3
"""ovctx.py <ev/out.txt>: the overruns (O events) in fzev.lua's log, each with the run that ended last
before it (tail or slot, how it ended, its phase at the end, lines past KDL) and whether a HUD pass (H)
ran in that run; a summary by kind."""
import sys, collections
E=[l.split() for l in open(sys.argv[1])]
E=[f for f in E if f]
n=0; kinds=collections.Counter(); hud_in_run=0; last_run=None; cur=None; runs_with_hud=0; frames=0
for f in E:
    t=f[0]
    if t=="S": cur={"tail":int(f[5])!=0,"kdl":int(f[9]),"hud":False,"v0":int(f[2])-256,"hf":int(f[8])}
    elif t=="H" and cur is not None: cur["hud"]=True
    elif t=="E" and cur is not None:
        p=int(f[4],16); cur["end"]="done" if 0x853ec<=p<0x853f8 or "fz" in f[4] else "stop"; cur["ph"]=int(f[7]); cur["v1"]=int(f[2])-256; last_run=cur; cur=None
    elif t=="N": frames=int(f[4])
    elif t=="O":
        n+=1
        if last_run:
            k=("tail" if last_run["tail"] else "slot", last_run.get("end"), "hud" if last_run["hud"] else "rec", "ph%d"%last_run.get("ph",-1))
            kinds[k]+=1
            if n<=8: print("O at HF %d: last run %s lines %d..%d kdl %d" % (frames, k, last_run["v0"], last_run.get("v1",-1), last_run["kdl"]))
print("overruns %d in %d HAL frames; by the last run's kind:" % (n, frames), kinds.most_common(10))
