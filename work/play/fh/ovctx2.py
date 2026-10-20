#!/usr/bin/env python3
"""ovctx2.py <ev/out.txt> [max]: each overrun (O) with the pass that ended before it: the HAL frame,
the refreshes (U) in the last two HAL frames, every run of that pass (slot/tail, lines v0..v1, KDL,
records, refills F/G (short -> credit), the HUD pass (H) with its units, the end kind/phase), and
the HUD draw cost (the cycles from H to E).  Then a summary: overruns with/without a refresh in the
frame, and the same for all passes (the base rate)."""
import sys, collections
E=[l.split() for l in open(sys.argv[1])]; E=[f for f in E if f]
mx=int(sys.argv[2]) if len(sys.argv)>2 else 10
LINE=768
hf=0; hf_c=0; lastU=[]; runs=[]; cur=None; passes=[]; curpass=None
n_ov=0; ov_ref=0; shown=0
pass_ref=collections.Counter()
for i,f in enumerate(E):
    t=f[0]; c=int(f[3]) if len(f)>3 and f[3].lstrip('-').isdigit() else 0
    if t=="N": hf=int(f[4]); hf_c=c
    elif t=="U": lastU.append((hf,c))
    elif t=="Q":
        curpass={"q":int(f[5]),"runs":[],"hfq":hf}
        passes.append(curpass)
    elif t=="S":
        cur={"tail":int(f[5])!=0,"v0":int(f[2])-256,"c0":c,"kdl":int(f[9]),"hf":int(f[8]),"nrec":0,"ref":[],"H":None,"hud_units":None}
        if curpass is not None: curpass["runs"].append(cur)
    elif cur is not None:
        if t=="R": cur["nrec"]+=1
        elif t=="F": cur["ref"].append([int(f[4]),None])
        elif t=="G":
            if cur["ref"] and cur["ref"][-1][1] is None: cur["ref"][-1][1]=int(f[4])
            if cur["H"] is not None and cur["hud_units"] is None: cur["hud_units"]=int(f[4])
        elif t=="H": cur["H"]=c
        elif t=="E":
            p=int(f[4],16); cur["end"]="done" if 0x853ec<=p<0x853f8 else "stop"; cur["ph"]=int(f[7]); cur["v1"]=int(f[2])-256; cur["c1"]=c
            cur=None
    if t=="O":
        n_ov+=1
        recentU=[u for u in lastU if u[0]>=hf-2]
        if recentU: ov_ref+=1
        if shown<mx and curpass is not None:
            shown+=1
            print("O at HF %d: refreshes in HF-2..HF: %s; pass q %d (Q at HF %d)" % (hf,[u[0] for u in recentU],curpass["q"],curpass["hfq"]))
            for r in curpass["runs"]:
                if "c1" not in r: continue
                hud=""
                if r["H"] is not None: hud=" HUD units %s actual %.1f lines" % (r["hud_units"],(r["c1"]-r["H"])/LINE)
                print("   %s HF %d lines %d..%d (%.1f) kdl %d recs %d refills %s -> %s ph %d%s" % ("TAIL" if r["tail"] else "slot",r["hf"],r["v0"],r["v1"],(r["c1"]-r["c0"])/LINE,r["kdl"],r["nrec"],[(a,b) for a,b in r["ref"]],r["end"],r["ph"],hud))
# base rate: passes whose frame had a refresh
Us=set(u[0] for u in lastU)
for p in passes:
    k=any((p["hfq"]-d) in Us for d in range(0,3)); pass_ref[k]+=1
print("overruns %d, with a refresh in the two frames before %d; passes %d, with a refresh %d (%.1f%%)" % (n_ov,ov_ref,len(passes),pass_ref[True],100.0*pass_ref[True]/max(1,len(passes))))
