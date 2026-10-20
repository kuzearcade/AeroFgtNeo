"""Static recovery of code that the coverage seeds never reached -> analysis/code_seeds_static.txt

Code discovery (tools/analyze68k.py) walks from the vectors and from every instruction
MAME's coverage saw executed.  Code reached only through indirect jumps on paths the
coverage runs never took (attract-mode demo events, rarer object handlers) stays
undecoded, so its RAM operands are not relocated: on the Neo they then address
unmapped space (first found: 0x1887c movea.l #$ff8dd0,a3 in the attract demo, which
desynchronised the conversion from the original at game frame 2922).

Here every 32-bit ROM value outside known code that points at an even, undecoded ROM
address is a candidate entry (the game's handler tables are tables of longs).  A
candidate is accepted when the walk from it decodes cleanly, every path ends in a
jump/return, and no instruction overlaps known code.  Rounds repeat until nothing new
is accepted.  Checked against a 30000-frame attract coverage run: every executed
instruction the seed walk missed (1523) lies in the recovered code.

The output holds instruction addresses only (no ROM content).

Usage: python3 tools/recover_code.py [--aerofgt mame_roms/aerofgt.zip]
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze68k   # noqa: E402
import m68k         # noqa: E402
import romset       # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "analysis", "code_seeds_static.txt")
MAX_WALK = 4000                 # instructions per candidate (a runaway walk is data)
# ROM words the HAL rewrites (tools/aerofgt2neo.py patch_idle_loop): never code here
RESERVED = range(0xbd0, 0xbd4)


def coverage_seeds():
    path = os.path.join(ROOT, "analysis", "code_seeds.txt")
    return [int(l, 16) for l in open(path) if l.strip() and not l.startswith("#")]


def recover(rom, seeds):
    prog = analyze68k.Program(rom, seeds)
    dec = m68k.Decoder(rom)
    known = dict(prog.ins)
    cov = bytearray(len(rom))
    for a, i in known.items():
        cov[a:a + i.length] = b"\x01" * i.length

    def walk(seed):
        new, work = {}, [seed]
        while work:
            a = work.pop()
            while a not in known and a not in new:
                if a >= len(rom) or a & 1 or cov[a] or a in RESERVED:
                    return None
                try:
                    i = dec.decode(a)
                except m68k.DecodeError:
                    return None
                if any(cov[a + k] or a + k in RESERVED for k in range(i.length)):
                    return None
                new[a] = i
                if len(new) > MAX_WALK:
                    return None
                work.extend(t for t in i.targets if t < len(rom))
                if i.flow in ("jump", "ret", "indirect_jump", "stop"):
                    break
                a += i.length
        return new

    accepted = []
    while True:
        cands = set()
        for p in range(0, len(rom) - 3, 2):
            if not cov[p]:
                v = struct.unpack_from(">I", rom, p)[0]
                if 0x400 <= v < len(rom) and not v & 1 and not cov[v]:
                    cands.add(v)
        n = 0
        for v in sorted(cands):
            if v in known or cov[v]:
                continue
            w = walk(v)
            if w:
                known.update(w)
                for a, i in w.items():
                    cov[a:a + i.length] = b"\x01" * i.length
                accepted.append(v)
                n += 1
        if not n:
            break
    return sorted(accepted), len(prog.ins), len(known)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--aerofgt", default=os.path.join(ROOT, "mame_roms", "aerofgt.zip"))
    args = ap.parse_args()
    rom = bytes(romset.load_aerofgt(args.aerofgt)["maincpu"])
    seeds, before, after = recover(rom, coverage_seeds())
    with open(OUT, "w") as f:
        f.write("# entry points recovered from ROM pointer tables (tools/recover_code.py)\n")
        for a in seeds:
            f.write("%06x\n" % a)
    print("%d entries: %d -> %d instructions" % (len(seeds), before, after))


if __name__ == "__main__":
    main()
