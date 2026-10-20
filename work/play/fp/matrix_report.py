#!/usr/bin/env python3
"""matrix_report.py <conv> <orig> [nations] [seeds] [prev]: the report of a profile matrix (matrix.sh):
reboots, the nation/stage table against the arcade (natsum.py), boss fights and lost logic by load
(botsum.py), the sections where the conversion is behind (secsum.py), the night fleet by load bin, the
bursts of 5+ lost frames per game and the per-seed drops/overruns; with [prev] the previous build's totals.
Run from ~/AeroFgtNeo: python3 -I work/play/fp/matrix_report.py 64L orig 0,1,2,3 7,8,9 63L"""
import sys, os, subprocess, collections
conv, orig = sys.argv[1], sys.argv[2]
nations = [int(x) for x in (sys.argv[3] if len(sys.argv) > 3 else "0,1,2,3").split(",")]
seeds = [int(x) for x in (sys.argv[4] if len(sys.argv) > 4 else "7,8,9").split(",")]
prev = sys.argv[5] if len(sys.argv) > 5 else None
FP = "work/play/fp"; STAGES = "0:night fleet,1:cities,2:coast/river,3:bases,4:desert,5:ocean,6:runway,7:final"
env = dict(os.environ, STAGES=STAGES)
def sh(cmd): return subprocess.run(cmd, shell=True, capture_output=True, text=True, env=env).stdout
def lag(d):
    L = []
    for l in open(d + "/lag.txt"):
        f = l.split()
        if len(f) >= 8 and f[0].isdigit() and int(f[0]) >= 450: L.append(f)
    return L
print("== reboots (restart markers after frame 40) and per-seed figures, %s" % conv)
for n in nations:
    for s in seeds:
        d = "%s/bl_n%d%s_%d" % (FP, n, conv, s)
        if not os.path.exists(d + "/lag.txt"): print("  missing", d); continue
        L = lag(d); rb = sum(1 for f in L if f[7] == "9b762e14")
        lost = sum(1 for f in L if int(f[1]) >= 1); r = 0; b = 0
        for f in L:
            if int(f[1]) >= 1: r += 1
            else:
                if r >= 5: b += 1
                r = 0
        print("  n%d seed %d: frames %d reboots %d lost %.2f%% late %s drops %s overruns %s bursts(5+) %d" % (
            n, s, len(L), rb, 100.0 * lost / max(1, len(L)), L[-1][2], L[-1][9] if len(L[-1]) > 10 else "-", L[-1][10] if len(L[-1]) > 10 else "-", b))
print("== nation / stage against the arcade (natsum.py)")
print(sh("python3 -I %s/natsum.py %s %s %s %s" % (FP, conv, orig, ",".join(map(str, nations)), ",".join(map(str, seeds)))).rstrip())
if prev:
    print("== the previous build's totals (%s)" % prev)
    print("\n".join(l for l in sh("python3 -I %s/natsum.py %s %s %s %s" % (FP, prev, orig, ",".join(map(str, nations)), ",".join(map(str, seeds)))).split("\n") if "TOTAL" in l or "boss" in l))
print("== boss fights and lost logic by active-object bin (botsum.py)")
print(sh("python3 -I %s/botsum.py %s" % (FP, " ".join("n%d%s n%d%s" % (n, conv, n, orig) for n in nations))).rstrip())
print("== sections where the conversion is behind the arcade (secsum.py, >= 3000 frames each side)")
print(sh("MINF=3000 python3 -I %s/secsum.py %s %s %s %s" % (FP, conv, orig, ",".join(map(str, nations)), ",".join(map(str, seeds)))).split("== sections where")[-1].rstrip())
print("== the night fleet by load bin, conv / arcade (frames)")
def runs(name, n):
    for s in seeds:
        d = "%s/bl_n%d%s_%d" % (FP, n, name, s)
        if not os.path.exists(d + "/lag.txt"): continue
        lg = {int(f[0]): int(f[1]) >= 1 for f in lag(d)}
        for l in open(d + "/bot.txt"):
            f = l.split()
            if len(f) >= 19 and f[0].isdigit() and int(f[0]) in lg: yield int(f[8]), int(f[4]), lg[int(f[0])]
for n in nations:
    row = []
    for name in (conv, orig):
        b = collections.defaultdict(lambda: [0, 0])
        for sid, na, lost in runs(name, n):
            if sid != 0: continue
            k = min(na // 10 * 10, 80); b[k][0] += 1; b[k][1] += lost
        row.append(b)
    if row[0] or row[1]:
        print("  n%d " % n + " | ".join("%d+: %.1f/%.1f (%d/%d)" % (k, 100.0 * row[0][k][1] / max(1, row[0][k][0]), 100.0 * row[1][k][1] / max(1, row[1][k][0]), row[0][k][0], row[1][k][0]) for k in sorted(set(row[0]) | set(row[1])) if k >= 40))
