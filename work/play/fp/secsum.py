#!/usr/bin/env python3
"""secsum.py <conv> <orig> [nations] [seeds] [bin]: the conversion's and the arcade's lost-logic share
by SECTION - a stage id and a stretch of it: the frames since the stage began in bins of <bin>
(600 = 10 s) or the boss fight (the bot's flag) - from the nation batteries work/play/fp/bl_n<N><name>_<seed>
(lag.txt + botsel.lua's bot.txt).  Per section: frames (conv / arcade), lost% both, the conversion's late%,
drop frames, overruns, and the mean active objects and player shots (both).  Then the sections where the
conversion is behind the arcade (both sides >= MINF frames), worst first.  Env: STAGES="id:name,..", MINF."""
import sys, os, collections
conv, orig = sys.argv[1], sys.argv[2]
nations = [int(x) for x in (sys.argv[3] if len(sys.argv) > 3 else "0,1,2,3").split(",")]
seeds = [int(x) for x in (sys.argv[4] if len(sys.argv) > 4 else "7,8,9").split(",")]
BIN = int(sys.argv[5]) if len(sys.argv) > 5 else 600
MINF = int(os.environ.get("MINF", "1500"))
STAGE = {}
for a in os.environ.get("STAGES", "0:night fleet,1:cities,2:coast/river,3:bases,4:desert,5:ocean,6:runway,7:final").split(","):
    if ":" in a: k, v = a.split(":"); STAGE[int(k)] = v

def load(d):
    lag = {}
    try:
        for l in open(d + "/lag.txt"):
            f = l.split()
            if len(f) >= 8 and f[0].isdigit(): lag[int(f[0])] = f
    except FileNotFoundError: return None, None
    bot = {}
    for l in open(d + "/bot.txt"):
        f = l.split()
        if len(f) >= 19 and f[0].isdigit(): bot[int(f[0])] = f
    return lag, bot

def run(d):
    lag, bot = load(d)
    if lag is None: return None
    r = collections.defaultdict(collections.Counter)
    prev = None; stage_start = None; cur_idx = None
    for f in sorted(lag):
        L = lag[f]; B = bot.get(f)
        if f < 450 or B is None: prev = L; continue
        idx = int(B[7]); sid = int(B[8]); boss = B[1] == "1"
        if idx != cur_idx: cur_idx = idx; stage_start = f
        if sid == 255: prev = L; continue
        sec = "boss" if boss else "t%03d" % ((f - stage_start) // BIN)
        c = r[(sid, sec)]
        c["frames"] += 1
        c["lost"] += 1 if int(L[1]) >= 1 else 0
        c["nact"] += int(B[4]); c["shots"] += int(B[12])
        if prev is not None and len(L) >= 11:
            c["late"] += int(L[2]) - int(prev[2]); c["drop"] += int(L[9]) - int(prev[9]); c["ovr"] += int(L[10]) - int(prev[10])
        prev = L
    return r

tot = {}
for n in nations:
    for tag, name in (("c", conv), ("o", orig)):
        T = collections.defaultdict(collections.Counter)
        for s in seeds:
            r = run("work/play/fp/bl_n%d%s_%d" % (n, name, s))
            if r is None: print("missing: nation %d seed %d %s" % (n, s, name)); continue
            for k, c in r.items():
                for kk, v in c.items(): T[k][kk] += v
        tot[(n, tag)] = T
def pct(c, k): return 100.0 * c[k] / max(1, c["frames"])
behind = []
for n in nations + ["all"]:
    if n == "all":
        C = collections.defaultdict(collections.Counter); O = collections.defaultdict(collections.Counter)
        for m in nations:
            for k, c in tot[(m, "c")].items():
                for kk, v in c.items(): C[k][kk] += v
            for k, c in tot[(m, "o")].items():
                for kk, v in c.items(): O[k][kk] += v
    else:
        C, O = tot[(n, "c")], tot[(n, "o")]
    print("== nation %s" % n)
    print("   %-14s %-6s %7s %7s %6s %6s %6s | %6s %5s %5s | %5s %5s %5s %5s" % ("stage", "sect", "cframes", "aframes", "conv%", "arc%", "delta", "late%", "drop", "ovr", "cobj", "aobj", "cshot", "ashot"))
    keys = sorted(set(C) | set(O), key=lambda k: (k[0], k[1] == "boss", k[1]))
    for k in keys:
        c, o = C[k], O[k]
        if c["frames"] + o["frames"] < 200: continue
        d = pct(c, "lost") - pct(o, "lost")
        print("   %-14s %-6s %7d %7d %5.2f%% %5.2f%% %+5.2f | %5.2f%% %5d %5d | %5.1f %5.1f %5.1f %5.1f" % (
            STAGE.get(k[0], str(k[0])), k[1], c["frames"], o["frames"], pct(c, "lost"), pct(o, "lost"), d, pct(c, "late"), c["drop"], c["ovr"],
            c["nact"] / max(1, c["frames"]), o["nact"] / max(1, o["frames"]), c["shots"] / max(1, c["frames"]), o["shots"] / max(1, o["frames"])))
        if n != "all" and d > 0 and c["frames"] >= MINF and o["frames"] >= MINF:
            behind.append((d, n, k, c, o))
print("== sections where the conversion is behind the arcade (>= %d frames each side), worst first" % MINF)
for d, n, k, c, o in sorted(behind, reverse=True):
    print("   nation %d %-14s %-6s conv %5.2f%% arcade %5.2f%% (%+.2f) frames %d/%d late %.2f%% drop %d ovr %d obj %.1f/%.1f shots %.1f/%.1f" % (
        n, STAGE.get(k[0], str(k[0])), k[1], pct(c, "lost"), pct(o, "lost"), d, c["frames"], o["frames"], pct(c, "late"), c["drop"], c["ovr"],
        c["nact"] / max(1, c["frames"]), o["nact"] / max(1, o["frames"]), c["shots"] / max(1, c["frames"]), o["shots"] / max(1, o["frames"])))
