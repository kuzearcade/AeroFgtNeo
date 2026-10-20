#!/usr/bin/env python3
"""fztl.py <ev/out.txt> [late|all] [max]: from fzev.lua's log, each records pass's timeline:
the buffer's completion (fz_fin), the set chosen (fz_begin: Q), its runs (S .. E: slot or
commit tail, lines, cycles, records advanced, how it ended), the flip (L) and the delta
against the arcade (HF at the flip - the pass's number).  Prints the aggregate for
on-time and late passes, then the first <max> passes of the kind asked (late/all)."""
import sys, collections

ev = sys.argv[1]; kind = sys.argv[2] if len(sys.argv) > 2 else "late"; mx = int(sys.argv[3]) if len(sys.argv) > 3 else 25
E = []
for l in open(ev):
    f = l.split()
    if f: E.append(f)
LINE = 768
def c(f): return int(f[3])
def v(f): return int(f[2]) - 256
def endkind(pc):
    p = int(pc, 16)
    if 0x85398 <= p < 0x853a0: return "stop"
    if 0x853ec <= p < 0x853f4: return "done"
    return "o" + pc

passes = []
hf = 0; busy = 0; est = 0
lastfin = {}          # buffer -> (cycle, stamp, n)
open_runs = {}
byset = {}            # set -> current pass (dict)
for i, f in enumerate(E):
    t = f[0]
    if t == "N": hf = int(f[4])
    elif t == "Z": busy = int(f[4])
    elif t == "A": est = int(f[4])
    elif t == "B":
        if len(f) < 9: continue
        b, stt = int(f[4]), int(f[5])
        if stt == 1: lastfin[b] = (c(f), int(f[6]), int(f[7]), hf, v(f))
    elif t == "Q":
        s, q, buf = int(f[4]), int(f[5]), int(f[6], 16)
        b = {0xd0e510: 0, 0xd0ea30: 1, 0xd0ea20: 1, 0xd0f800: 2}.get(buf, -1)
        p = {"set": s, "q": q, "buf": b, "cq": c(f), "hfq": hf, "vq": v(f), "busyq": busy, "estq": est, "fin": lastfin.get(b), "runs": [], "flip": None}
        byset[s] = p; passes.append(p)
    elif t == "S":
        s = int(f[4]); p = byset.get(s)
        if p is None or p["flip"] is not None: continue
        open_runs[s] = {"c0": c(f), "v0": v(f), "tail": int(f[5]) != 0, "rec0": int(f[6], 16), "ph0": int(f[7]), "hf": int(f[8]), "busy": int(f[11]), "est": int(f[12]), "nrec": 0, "refills": 0}
        p["runs"].append(open_runs[s])
    elif t == "R":
        for s, r in open_runs.items(): r["nrec"] += 1
    elif t == "F":
        for s, r in open_runs.items(): r["refills"] += 1
    elif t == "E":
        # the run of the set in work: the only open one (S sets it); close all open
        for s, r in list(open_runs.items()):
            r["c1"] = c(f); r["v1"] = v(f); r["end"] = endkind(f[4]); r["rec1"] = int(f[6], 16); r["ph1"] = int(f[7])
            del open_runs[s]
    elif t == "L":
        s = int(f[4]); p = byset.get(s)
        if p is not None and p["flip"] is None:
            p["flip"] = (int(f[5]), c(f), v(f)); p["delta"] = int(f[5]) - p["q"]

# sets never shown (the pass done, its set freed unseen: superseded by the next set at the flip,
# or a duplicate conversion of the same round) among the real passes
real = [p for p in passes if p["runs"] and 100 < p["q"] < 30000 and p["cq"] > 400 * 768 * 264]
never = [p for p in real[:-3] if p["flip"] is None]
dupq = collections.Counter(p["q"] for p in real); dups = sum(1 for p in never if dupq[p["q"]] > 1)
print("real passes %d: never shown %d (%.1f%%), of which duplicate rounds (same q) %d; on time %d (%.1f%%)" % (
    len(real), len(never), 100.0 * len(never) / max(1, len(real)), dups, sum(1 for p in real if p["flip"] and p["delta"] == 0), 100.0 * sum(1 for p in real if p["flip"] and p["delta"] == 0) / max(1, len(real))))
agg = collections.defaultdict(lambda: collections.defaultdict(float)); cnt = collections.Counter()
for p in passes:
    if p["flip"] is None or not p["runs"]: continue
    d = p["delta"]; cnt[d] += 1; a = agg[d]
    runs = [r for r in p["runs"] if "c1" in r]
    a["runs"] += len(runs)
    a["cycles"] += sum(r["c1"] - r["c0"] for r in runs)
    a["tailruns"] += sum(1 for r in runs if r["tail"])
    a["tailcyc"] += sum(r["c1"] - r["c0"] for r in runs if r["tail"])
    a["wait1"] += runs[0]["c0"] - p["cq"]
    a["busyq"] += 1 if p["busyq"] else 0
    a["q_in_tail"] += 1 if runs and runs[0]["tail"] else 0
    a["refills"] += sum(r["refills"] for r in runs)
    a["stops"] += sum(1 for r in runs if r["end"] == "stop")
    if p["fin"]: a["fin2q"] += p["cq"] - p["fin"][0]
    a["recs"] += sum(r["nrec"] for r in runs)
print("passes by delta (HF at the flip - pass number):", sorted(cnt.items()))
for d in sorted(cnt):
    n = cnt[d]; a = agg[d]
    print("delta %d: n %d  runs/pass %.2f (in tails %.2f)  cycles/pass %.0f (tails %.0f) lines %.1f  records/pass %.1f  stops %.2f refills %.2f  fin->Q %.1f lines  Q->first run %.1f lines  Q busy %.2f  first run in tail %.2f" % (
        d, n, a["runs"] / n, a["tailruns"] / n, a["cycles"] / n, a["tailcyc"] / n, a["cycles"] / n / LINE, a["recs"] / n, a["stops"] / n, a["refills"] / n, a["fin2q"] / n / LINE, a["wait1"] / n / LINE, a["busyq"] / n, a["q_in_tail"] / n))
shown = 0
for p in passes:
    if p["flip"] is None or not p["runs"]: continue
    if kind == "late" and p["delta"] <= 0: continue
    if shown >= mx: break
    shown += 1
    fin = p["fin"]
    print("pass q %d set %d buf %d: fin HF %s line %s n %s | Q at HF %d line %d busy %d est %d | flip HF %d (delta %d)" % (
        p["q"], p["set"], p["buf"], fin[3] if fin else "?", fin[4] if fin else "?", fin[2] if fin else "?", p["hfq"], p["vq"], p["busyq"], p["estq"], p["flip"][0], p["delta"]))
    for r in p["runs"]:
        if "c1" not in r: continue
        print("    run HF %d %s line %d..%d (%.1f lines) recs +%d refills %d busy %d est %d -> %s ph %d" % (
            r["hf"], "TAIL" if r["tail"] else "slot", r["v0"], r["v1"], (r["c1"] - r["c0"]) / LINE, r["nrec"], r["refills"], r["busy"], r["est"], r["end"], r["ph1"]))
