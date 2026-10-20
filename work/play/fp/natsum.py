#!/usr/bin/env python3
"""natsum.py <conv-name> <orig-name> [nations] [seeds]: the nation batteries (work/play/fp/bl_<name>_<seed>
with lag.txt + botsel.lua's bot.txt): per nation and per stage id, the conversion's and the arcade's
lost-logic share, the conversion's late sets, drop frames and overruns, the boss-fight share; then the
totals.  Names: bl_n<N><conv>_<seed>, bl_n<N><orig>_<seed>.  Frames before 450 are skipped (boot)."""
import sys, glob, collections, os
conv, orig = sys.argv[1], sys.argv[2]
nations = [int(x) for x in (sys.argv[3] if len(sys.argv) > 3 else "0,1,2,3").split(",")]
seeds = [int(x) for x in (sys.argv[4] if len(sys.argv) > 4 else "7,8,9").split(",")]
STAGE = {}   # stage id -> name (filled by the caller's knowledge; unknown ids print as the id)
for a in os.environ.get("STAGES", "").split(","):
    if ":" in a: k, v = a.split(":"); STAGE[int(k)] = v

def load(d):
    lag = {}
    try:
        for l in open(d + "/lag.txt"):
            f = l.split()
            if len(f) >= 8: lag[int(f[0])] = f
    except FileNotFoundError: return None, None
    bot = {}
    try:
        for l in open(d + "/bot.txt"):
            f = l.split()
            if len(f) >= 19 and f[0].isdigit(): bot[int(f[0])] = f
    except FileNotFoundError: pass
    return lag, bot

def stat(name, n, s):
    lag, bot = load("work/play/fp/bl_n%d%s_%d" % (n, name, s))
    if lag is None: return None
    r = collections.defaultdict(lambda: collections.Counter())
    prev = None
    for f in sorted(lag):
        if f < 450: continue
        L = lag[f]; B = bot.get(f)
        sid = int(B[8]) if B else 255
        boss = B and B[1] == "1"
        for key in (("all", sid), ("all", "all")) + ((("boss", "all"),) if boss else ()):
            c = r[key]
            c["frames"] += 1
            c["lost"] += 1 if int(L[1]) >= 1 else 0
            if prev is not None:
                c["late"] += int(L[2]) - int(prev[2])
                if len(L) >= 11:
                    c["drop"] += int(L[9]) - int(prev[9])
                    c["ovr"] += int(L[10]) - int(prev[10])
        prev = L
    return r

tot = collections.defaultdict(lambda: collections.defaultdict(lambda: collections.Counter()))   # nation -> key -> counters (summed over seeds), per target
res = {}
for n in nations:
    for s in seeds:
        for tag, name in (("c", conv), ("o", orig)):
            r = stat(name, n, s)
            if r is None: print("missing: nation %d seed %d %s" % (n, s, name)); continue
            for k, c in r.items():
                for kk, v in c.items(): tot[(n, tag)][k][kk] += v
def pct(c, k): return 100.0 * c[k] / max(1, c["frames"])
for n in nations:
    C, O = tot[(n, "c")], tot[(n, "o")]
    print("== nation %d: conversion %d frames, arcade %d frames" % (n, C[("all", "all")]["frames"], O[("all", "all")]["frames"]))
    print("   %-16s %8s %7s %7s | %7s %7s %7s | %6s" % ("stage", "frames", "conv%", "arc%", "late%", "drop%", "ovr", "arcfr"))
    keys = sorted(set(k for k in C if k[0] == "all") | set(k for k in O if k[0] == "all"), key=lambda k: (k[1] == "all", str(k[1])))
    for k in keys:
        c, o = C[k], O[k]
        nm = STAGE.get(k[1], str(k[1])) if k[1] != "all" else "TOTAL"
        print("   %-16s %8d %6.2f%% %6.2f%% | %6.2f%% %6.2f%% %7d | %6d" % (nm, c["frames"], pct(c, "lost"), pct(o, "lost"), pct(c, "late"), pct(c, "drop"), c["ovr"], o["frames"]))
    c, o = C[("boss", "all")], O[("boss", "all")]
    print("   %-16s %8d %6.2f%% %6.2f%% | %6.2f%% %6.2f%% %7d | %6d" % ("boss fights", c["frames"], pct(c, "lost"), pct(o, "lost"), pct(c, "late"), pct(c, "drop"), c["ovr"], o["frames"]))
