"""Extract per-IRQ timing from MAME cycle traces (tests/trace_window.lua output).

orig: e_k = cycle of the first instruction of 0x888; prints deltas e_k+1 - e_k and the
      interrupted PC.
neo:  virtual-vblank entries are vector starts at 0x08000C whose stacked context is
      game code (< 0x80000); resume = start of 0x888.  Virtual delta between handler
      starts = X_k+1 - resume_k.
"""
import re
import sys


def parse(path):
    ev = []
    pending = None
    for line in open(path):
        m = re.match(r'\s*\(interrupted at ([0-9A-F]+), IRQ (\d)\)', line)
        if m:
            pending = int(m.group(1), 16)
            continue
        m = re.match(r'(\d+) ([0-9A-F]{6}):', line)
        if not m:
            continue
        t, pc = int(m.group(1)), int(m.group(2), 16)
        if pending is not None:
            ev.append(("irq", t, pending))
            pending = None
        if pc == 0x888:
            ev.append(("h", t, None))
    return ev


def orig(path):
    ev = parse(path)
    starts = [(t, ip) for (k, t, ip) in ev if k == "irq"]
    for (t0, _), (t1, ip) in zip(starts, starts[1:]):
        print("delta %d interrupted %06x" % (t1 - t0, ip))


def neo(path):
    ev = parse(path)
    resume = None
    for k, t, ip in ev:
        if k == "h":
            resume = t
        elif k == "irq" and ip < 0x80000 and resume is not None:
            print("delta %d interrupted %06x" % (t - resume, ip))
            resume = None


{"orig": orig, "neo": neo}[sys.argv[1]](sys.argv[2])
