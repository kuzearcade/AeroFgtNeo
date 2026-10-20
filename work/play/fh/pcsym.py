#!/usr/bin/env python3
"""pcsym.py <hal.lst> <pc>...: the symbol (and offset) each PC falls in, from the listing's
"Symbols by value" section."""
import sys, bisect
lst = sys.argv[1]; syms = []
sec = False
for l in open(lst):
    if l.startswith("Symbols by value"): sec = True; continue
    if sec:
        f = l.split()
        if len(f) == 2 and len(f[0]) == 8:
            try: syms.append((int(f[0], 16), f[1]))
            except ValueError: pass
syms.sort(); keys = [a for a, _ in syms]
for p in sys.argv[2:]:
    pc = int(p, 16); i = bisect.bisect_right(keys, pc) - 1
    print("%06x %s+%x" % (pc, syms[i][1], pc - syms[i][0]) if i >= 0 else "%06x ?" % pc)
