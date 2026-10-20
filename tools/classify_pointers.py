"""Classify ROM data pointer candidates from provenance runs.

Usage: classify_pointers.py main.bin candidates.txt prov1.txt [prov2.txt ...]
Writes analysis/data_pointers.txt.  A candidate is a pointer when it is read by one of
the address-consuming sites below (identified by reading the consuming code):
"""
import bisect
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import analyze68k  # noqa: E402

# reader instruction -> reason
POINTER_READERS = {
    0x017ffe: "palette fade records: destination palette address (move.l (a4)+,(a3)+, later movea.l)",
    0x008552: "attract demo object list (0x8552 movea.l (a6)+,a5 / add.w d1,($a,a5), ends at -1)",
}
# whole tables whose pointer-valued entries are relocated even if not every entry
# was observed being read: (start, end, stride)
POINTER_TABLES = [
]

rom = open(sys.argv[1], "rb").read()
cands = [int(l, 16) for l in open(sys.argv[2]) if l.strip()]
seeds = [int(l, 16) for l in open(os.path.join(HERE, "..", "analysis", "code_seeds.txt"))
         if l.strip() and not l.startswith("#")]
prog = analyze68k.Program(rom, seeds)
starts = sorted(prog.ins)


def reader(pc):
    i = bisect.bisect_left(starts, pc) - 1
    while i >= 0 and starts[i] >= pc - 12:
        a = starts[i]
        if a < pc <= a + prog.ins[a].length + 4:
            return a
        i -= 1
    return None


ptr = {}
for path in sys.argv[3:]:
    for line in open(path):
        c, pc, _ = line.split()
        r = reader(int(pc, 16))
        if r in POINTER_READERS:
            ptr[int(c, 16)] = POINTER_READERS[r]
cset = set(cands)
for start, end, stride, why in POINTER_TABLES:
    for a in range(start, end, stride):
        if a in cset:
            ptr.setdefault(a, why)
out = os.path.join(HERE, "..", "analysis", "data_pointers.txt")
with open(out, "w") as f:
    f.write("# ROM data longs that are RAM/video pointers (tools/classify_pointers.py)\n")
    for a in sorted(ptr):
        f.write("%06x  %08x  # %s\n" % (a, struct.unpack_from(">I", rom, a)[0], ptr[a]))
print(len(ptr), "pointers")
