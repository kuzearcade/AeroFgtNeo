#!/usr/bin/env python3
"""fzcost.py <ev/out.txt> <hal.lst>: from fzev.lua's log, the records pass's actual cost
against its charges.  Per record (R to the next R of the same run): actual cycles
(the tap's time difference) against the credit consumed (d7's high word, refills
(F/G) added back); by the record's routine and its pieces.  Per refill segment (G to
the next F, or the run's end E): the same.  Tail runs (HAL_SPR_TAILU set at fz_go)
and slot runs apart.  Env: TAIL=1 only the commit tails."""
import sys, collections, os, re

ev = sys.argv[1]; lst = sys.argv[2] if len(sys.argv) > 2 else None
names = {}
if lst:
    sec = False
    for l in open(lst):
        if l.startswith("Symbols by name"): sec = True; continue
        if l.startswith("Symbols by value"): break
        if sec:
            f = l.split()
            if len(f) == 2 and f[1][:2] == "A:":
                names[int(f[1][2:], 16)] = f[0]
def s16(v): return v - 65536 if v >= 32768 else v
def hi(d7): return s16(int(d7, 16) >> 16)
def lo(d7): return s16(int(d7, 16) & 0xffff)

TAILONLY = os.environ.get("TAIL", "1") == "1"
runs = []          # each: dict(tail, start c, end c, end pc, events list)
cur = None
for l in open(ev):
    f = l.split()
    if not f: continue
    t = f[0]
    if t == "S":
        cur = {"tail": int(f[5]) != 0, "c0": int(f[3]), "v0": int(f[2]) - 256, "set": int(f[4]), "ph": int(f[7]),
               "hf": int(f[8]), "kdl": int(f[9]), "ker": int(f[10]), "busy": int(f[11]), "ev": []}
    elif cur is not None and t in "RFGHE":
        cur["ev"].append(f)
        if t == "E":
            cur["c1"] = int(f[3]); cur["v1"] = int(f[2]) - 256; cur["pc"] = f[4]; cur["d7e"] = f[5]
            runs.append(cur); cur = None

# per record
byrt = collections.defaultdict(lambda: [0, 0, 0])      # routine -> n, actual, charged (cycles)
bypc = collections.defaultdict(lambda: [0, 0, 0])      # pieces -> ...
setup = [0, 0, 0]
seg = [0, 0, 0]       # refill segments: n, actual, charged
segs_over = collections.Counter()
nruns = 0; tot = [0, 0]
for r in runs:
    if TAILONLY and not r["tail"]: continue
    nruns += 1
    ev = r["ev"]
    # records: R f v c d7 routine y x charge w2 pieces-1 zoom
    i = 0
    while i < len(ev):
        e = ev[i]
        if e[0] != "R": i += 1; continue
        # find the next R, with refills between
        j = i + 1; refill = 0; broken = False
        while j < len(ev) and ev[j][0] != "R":
            if ev[j][0] == "F":
                if j + 1 < len(ev) and ev[j + 1][0] == "G":
                    refill += int(ev[j + 1][4]) - int(ev[j][4])   # G - short
                    j += 1
                else:
                    broken = True
            elif ev[j][0] in "HE":
                broken = True
            j += 1
        if j >= len(ev) or broken or ev[j][0] != "R":
            i = j; continue
        n = ev[j]
        actual = int(n[3]) - int(e[3])
        charged = (hi(e[4]) - hi(n[4]) + refill) * 16
        rt = names.get(int(e[5], 16), e[5]); pieces = int(e[10]) + 1
        for d, k in ((byrt, rt), (bypc, min(pieces, 9))):
            d[k][0] += 1; d[k][1] += actual; d[k][2] += charged
        tot[0] += actual; tot[1] += charged
        i = j
    # refill segments: G .. next F (consumed = g - (short + k)) or E (consumed = g - hi(d7 at E))
    g = None
    for e in ev:
        if e[0] == "G":
            g = (int(e[3]), int(e[4]))
        elif e[0] == "F" and g is not None:
            cons = g[1] - (int(e[4]) + (int(e[7]) if int(e[7]) != 240 else 0))   # (the HUD pass's refill: no shortfall)
            act = int(e[3]) - g[0]
            seg[0] += 1; seg[1] += act; seg[2] += cons * 16
            segs_over[(act - cons * 16) // 768] += 1
            g = None
    if g is not None and "d7e" in r:
        cons = g[1] - hi(r["d7e"])
        act = r["c1"] - g[0]
        if 0 < cons < 20000:
            seg[0] += 1; seg[1] += act; seg[2] += cons * 16
            segs_over[(act - cons * 16) // 768] += 1

# the HUD pass: units given (G after H) against its actual cycles to the run's end
hud = [0, 0, 0]; hudover = collections.Counter(); ends = collections.defaultdict(collections.Counter)
for r in runs:
    if TAILONLY and not r["tail"]: continue
    ev = r["ev"]
    if "c1" not in r: continue
    kind = "done" if 0x853ec <= int(r["pc"], 16) < 0x853f8 else ("stop-hud" if int(ev[-1][7]) == 255 and ev[-1][0] == "E" else "stop")
    # (E: f v c pc d7 rec ph left tailu)
    ph = int(ev[-1][7]) if ev[-1][0] == "E" else -1
    kind = "done" if kind == "done" else ("stop-hud" if ph == 255 else "stop-rec")
    ends[kind][r["v1"] - r["kdl"]] += 1
    for i, e in enumerate(ev):
        if e[0] == "H":
            if i + 2 < len(ev) and ev[i + 1][0] == "F" and ev[i + 2][0] == "G":
                d6 = int(ev[i + 2][4]); act = r["c1"] - int(ev[i + 2][3])
                hud[0] += 1; hud[1] += act; hud[2] += d6 * 16
                hudover[(act - d6 * 16) // 768] += 1
            break
print("HUD passes %d: actual %d vs units given %d cycles (%.1f%%); (actual - units) in lines:" % (hud[0], hud[1], hud[2], 100.0 * (hud[1] - hud[2]) / max(1, hud[2])), sorted(hudover.items()))
for k in ends:
    print("tail runs ending by %s: lines past KDL at the end:" % k, sorted(ends[k].items()))
print("runs %d (%s); records: actual %d charged %d cycles: %.1f%% under" % (nruns, "tails" if TAILONLY else "all", tot[0], tot[1], 100.0 * (tot[0] - tot[1]) / max(1, tot[1])))
print("by pieces: pieces n actual/rec charged/rec ratio")
for k in sorted(bypc):
    n, a, c = bypc[k]; print("  %d %6d %7.0f %7.0f %.2f" % (k, n, a / n, c / n, a / max(1, c)))
print("by routine (n >= 50): routine n actual/rec charged/rec ratio")
for k, (n, a, c) in sorted(byrt.items(), key=lambda x: -x[1][1]):
    if n >= 50: print("  %-16s %6d %7.0f %7.0f %.2f" % (k, n, a / n, c / n, a / max(1, c)))
print("refill segments %d: actual %d vs consumed %d cycles: %.1f%% under; (actual - consumed) in lines:" % (seg[0], seg[1], seg[2], 100.0 * (seg[1] - seg[2]) / max(1, seg[2])), sorted(segs_over.items()))
