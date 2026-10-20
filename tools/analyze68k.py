"""Static code discovery + memory-reference classification for the aerofgt 68K program.

Code discovery = recursive descent from the vectors, seeded additionally with every
instruction start that MAME's coverage bitmap saw executed (covers indirect jumps).

Usage: python3 -I tools/analyze68k.py main.bin cov1.bin [cov2.bin ...] > report.txt
"""

import os
import struct
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import m68k  # noqa: E402

# original memory map (aerofgt.cpp main_map)
REGIONS = [
    ("rom",     0x000000, 0x07ffff),
    ("palette", 0x1a0000, 0x1a07ff),
    ("raster",  0x1b0000, 0x1b0fff),
    ("vram0",   0x1b2000, 0x1b3fff),
    ("vram1",   0x1b4000, 0x1b5fff),
    ("sprlut",  0x1c0000, 0x1c7fff),
    ("sprram",  0x1d0000, 0x1d1fff),
    ("wram",    0xfef000, 0xffefff),
    ("io",      0xffff80, 0xffffff),
]


def region_of(addr):
    addr &= 0xffffff
    for name, lo, hi in REGIONS:
        if lo <= addr <= hi:
            return name
    return None


def load_cov(paths, size):
    cov = bytearray(size // 8)
    for p in paths:
        c = open(p, "rb").read()
        for i in range(len(cov)):
            cov[i] |= c[i]
    return [a for a in range(size) if cov[a >> 3] >> (a & 7) & 1]


class Program:
    def __init__(self, rom, covered):
        self.rom = rom
        self.dec = m68k.Decoder(rom)
        self.ins = {}
        self.covered = set(covered)
        self.errors = []
        self.indirect = []
        vec = struct.unpack(">64I", rom[:256])
        seeds = [vec[1]] + [v for v in vec[2:64] if v < len(rom) and v != 0xffffffff]
        self.vectors = sorted(set(seeds))
        self.walk(self.vectors + sorted(covered))

    def walk(self, seeds):
        work = list(seeds)
        while work:
            a = work.pop()
            while True:
                if a in self.ins or a >= len(self.rom) or a & 1:
                    break
                try:
                    i = self.dec.decode(a)
                except m68k.DecodeError as e:
                    self.errors.append((a, str(e)))
                    break
                self.ins[a] = i
                for t in i.targets:
                    if t < len(self.rom):
                        work.append(t)
                if i.flow in ("indirect_jump", "indirect_call"):
                    self.indirect.append(a)
                if i.flow in ("jump", "ret", "indirect_jump", "stop"):
                    break
                a += i.length


def main():
    rom = open(sys.argv[1], "rb").read()
    covered = load_cov(sys.argv[2:], len(rom))
    p = Program(rom, covered)
    print("instructions: %d (covered %d, static-only %d)" % (
        len(p.ins), len(p.covered), len(set(p.ins) - p.covered)))
    print("decode errors during walk: %d" % len(p.errors))
    for a, e in p.errors[:30]:
        print("  err %06x %s" % (a, e))
    # overlapping instruction check
    owner = {}
    overlaps = 0
    for a, i in p.ins.items():
        for b in range(a, a + i.length, 2):
            if b in owner and owner[b] != a:
                overlaps += 1
            owner[b] = a
    print("overlapping instruction bytes: %d" % overlaps)

    stats = Counter()
    absw = []
    imm_ptr = defaultdict(list)
    sr_writes = []
    abs_by_region = defaultdict(Counter)
    for a in sorted(p.ins):
        i = p.ins[a]
        if i.special in ("sr",) and i.op in ("move", "ori", "andi", "eori", "stop"):
            sr_writes.append(a)
        for o in i.operands:
            if o.kind == m68k.ABSW:
                r = region_of(o.value)
                absw.append((a, i.text(), r))
            if o.kind == m68k.ABSL:
                r = region_of(o.value)
                abs_by_region[r][i.op] += 1
                stats["absl_" + str(r)] += 1
            if o.kind == m68k.IMM and isinstance(o.value, int) and o.ext_len:
                v = o.value & 0xffffffff
                r = region_of(v) if o.ext_len == 4 else None
                if r and r != "rom":
                    imm_ptr[r].append((a, i.text()))
                if o.ext_len == 2 and i.op in ("movea", "cmpa", "adda", "suba") and o.value & 0x8000:
                    imm_ptr["word_sext:" + str(region_of(o.value | 0xffff0000))].append((a, i.text()))
    print("\nabs.l references by region:")
    for r, c in sorted(abs_by_region.items(), key=lambda x: str(x[0])):
        print("  %-8s %5d  %s" % (r, sum(c.values()), dict(c.most_common(8))))
    print("\nabs.w references: %d" % len(absw))
    for a, t, r in absw[:40]:
        print("  %06x %-40s %s" % (a, t, r))
    print("\nimmediates that look like non-ROM pointers:")
    for r, lst in sorted(imm_ptr.items()):
        print("  %s: %d" % (r, len(lst)))
        for a, t in lst[:6]:
            print("     %06x %s" % (a, t))
    print("\nSR writes: %d" % len(sr_writes))
    for a in sr_writes[:60]:
        print("  %06x %s" % (a, p.ins[a].text()))
    print("\nindirect jumps/calls: %d" % len(p.indirect))
    for a in p.indirect[:40]:
        print("  %06x %s" % (a, p.ins[a].text()))
    ops = Counter(i.op for i in p.ins.values())
    print("\nopcode histogram:", dict(ops.most_common()))


if __name__ == "__main__":
    main()
