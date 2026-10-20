"""Check the idle-harvest cycle constants (hal/idle.s) on an instruction trace.

usage: idle_trace.py <trace.log> <hal.lst>
The trace (tests/trace_window.lua, debugger "trace" with totalcycles) must cover the
calibration probe and some harvested idle entries.  Reports, per occurrence:
  ENTRY_E   idle loop cmpi (E) -> hal_vernier entry
  V_A       hal_vernier entry -> first polling sample
  F_U       last vernier sample -> counter load instruction, minus (2 - 2*seen)
  PREFIX_P  probe vector start (HAL_BASE+0x0c after the probe IRQ) -> hal_vernier entry
  steps     spacing of the vernier samples (768 + b/2 - seen*b)
"""
import re
import sys


def symbols(lst):
    sym = {}
    insn = {}
    for line in open(lst):
        m = re.match(r'([0-9A-F]{8}) (\w+)$', line.strip())
        if m:
            sym[m.group(2)] = int(m.group(1), 16)
        m = re.match(r'\d\d:([0-9A-F]{8}) [0-9A-F]+\s+\d+: (.*)', line)
        if m:
            insn[int(m.group(1), 16)] = m.group(2)
    return sym, insn


def parse(path):
    recs = []
    for l in open(path):
        if re.match(r'\s*\(interrupted at', l):
            recs.append(("irq", 0, ""))
            continue
        m = re.match(r'(\d+) ([0-9A-F]{6}): (.*)', l)
        if m:
            recs.append((int(m.group(1)), int(m.group(2), 16), m.group(3)))
    return recs


def main():
    recs = parse(sys.argv[1])
    sym, insn = symbols(sys.argv[2])
    vern = sym["hal_vernier"]
    idle = sym["hal_idle"]
    hal_base = 0x80000
    # addresses of interest from the listing comments
    u_at = [a for a, t in insn.items() if "U: counter load" in t][0]
    t4_at = [a for a, t in insn.items() if "last sample (t_4)" in t][0]
    poll_at = [a for a, t in insn.items() if "polling sample" in t][0]
    step_at = sorted(a for a, t in insn.items() if vern <= a < t4_at and "(a0),d5" in t)
    print("hal_vernier %06x hal_idle %06x poll %06x t4 %06x U %06x steps %s" %
          (vern, idle, poll_at, t4_at, u_at, " ".join("%06x" % a for a in step_at)))
    for i, r in enumerate(recs):
        if r[0] == "irq":
            continue
        if r[1] == vern:
            entry = r[0]
            # what led here: idle entry or probe
            back = [x for x in recs[max(0, i - 3000):i] if x[0] != "irq"]
            kind, anchor = "?", None
            for j in range(len(back) - 1, -1, -1):
                if back[j][1] == idle:
                    # E: the cmpi at 0xb84 before the trampoline
                    for k in range(j - 1, -1, -1):
                        if back[k][1] == 0xb84:
                            kind, anchor = "ENTRY_E", back[k][0]
                            break
                    break
                if back[j][1] == hal_base + 0x0c:
                    kind, anchor = "PREFIX_P", back[j][0]
                    break
            # inside the vernier
            samples, polls, last, u = [], [], None, None
            for x in recs[i:i + 4000]:
                if x[0] == "irq":
                    continue
                if x[1] == poll_at:
                    polls.append(x[0])
                if x[1] in step_at:
                    samples.append(x[0])
                if x[1] == t4_at and last is None:
                    last = x[0]
                if x[1] == u_at:
                    u = x[0]
                    break
                if x[1] == vern + 2 and x[0] > entry + 100:
                    break
            print("%s %s  V_A %s  polls %d  steps %s  t4-step3 %s  U-t4 %s" % (
                kind, anchor and entry - anchor, polls and polls[0] - entry, len(polls),
                [b - a for a, b in zip(samples, samples[1:])] + ([last - samples[-1]] if samples and last else []),
                "", u and last and u - last))


if __name__ == "__main__":
    main()
