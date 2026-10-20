"""Compare two harness dumps frame by frame (original vs conversion)."""
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import memmap  # noqa: E402

REGIONS = [("wram", 0xfef000, 0x10000), ("palette", 0x1a0000, 0x800), ("raster", 0x1b0000, 0x800),
           ("vram", 0x1b2000, 0x4000), ("sprlut", 0x1c0000, 0x8000), ("sprram", 0x1d0000, 0x2000)]
REC = 4 + sum(r[2] for r in REGIONS)


def frames(path):
    with open(path, "rb") as f:
        while True:
            b = f.read(REC)
            if len(b) < REC:
                return
            yield struct.unpack_from("<I", b)[0], b[4:]


def where(off):
    for name, base, size in REGIONS:
        if off < size:
            return name, base + off
        off -= size


# Task stacks (8 x 0x400 below 0xfff000, plus slack): only here are word-level
# relocation residues accepted -- stale halves of relocated pointers, pointer low words
# moved into data registers, and stacked CCRs that differ only in N because a pointer
# low word was moved (move.w An,Dn) just before the interrupt.
STACK_LO, STACK_HI = 0xffd000, 0xffefff
HIGH_WORDS = {(0x00ff, 0x0010), (0x00fe, 0x0010), (0x001a, 0x00d0), (0x001b, 0x00d0),
              (0x001c, 0x00d0), (0x001d, 0x00d0)}
# low-word deltas of the linear region maps (neo - orig) mod 0x10000
LOW_DELTAS = {(m[2] - m[0]) & 0xffff for m in memmap.LINEAR}
# 0x2c1e8: move.w A1,D0 / subq.w #4,D0 / lsr.w #3,D0 / andi.w #$ff,D0 (A1 in work RAM):
# a vblank between the shift and the mask stacks D0 with the work-RAM delta >> 3
LOW_DELTAS.add(0x1000 >> 3)


def residue_ok(da, db, off):
    """off: even offset of a differing word inside the wram block of the record."""
    addr = 0xfef000 + off
    if not (STACK_LO <= addr <= STACK_HI):
        return False
    wa = struct.unpack_from(">H", da, off)[0]
    wb = struct.unpack_from(">H", db, off)[0]
    if (wa, wb) in HIGH_WORDS:
        return True
    if (wb - wa) & 0xffff in LOW_DELTAS:
        return True
    if wa & 0xf800 == 0x2000 and wb & 0xf800 == 0x2000 and (wa | 0x0100) ^ wb in (0, 0x08):
        return True
    return False


def equivalent(da, db, diffs):
    """Drop differences explained by relocation: RAM-resident pointers (orig value maps to
    the neo value) and stacked SR words whose interrupt level was remapped 0 -> 1."""
    ok = set()
    for i in diffs:
        if i in ok:
            continue
        for start in range(i - 3, i + 1):
            if start < 0 or start & 1 or start + 4 > len(da):
                continue
            va = struct.unpack_from(">I", da, start)[0]
            vb = struct.unpack_from(">I", db, start)[0]
            if va != vb and memmap.is_pointer_value(va) and memmap.map_addr(va) == vb:
                ok.update(range(start, start + 4))
                break
        else:
            start = i & ~1
            wa = struct.unpack_from(">H", da, start)[0]
            wb = struct.unpack_from(">H", db, start)[0]
            if wa & 0xf800 == 0x2000 and wb == wa | 0x0100 and (wa >> 8) & 7 == 0:
                ok.update((start, start + 1))
    rest = [i for i in diffs if i not in ok]
    return [i for i in rest if i >= 0x10000 or not residue_ok(da, db, i & ~1)]


# HAL palette canary (hal/video.s PAL_CANARY): entries 128-129 of the never-displayed
# palette range hold 0x80018001 on the conversion; the game never reads them
CANARY = {0x1a0100: 0x80, 0x1a0101: 0x01, 0x1a0102: 0x80, 0x1a0103: 0x01}


# HAL scratch (hal/bg.s BG_SHADOW): original work RAM 0xfef000-0xfeffff, which the game
# only uses in its boot RAM test/clear (before the first game frame)
HAL_SCRATCH = (0xfef000, 0xfeffff)
# idle-loop trampoline (hal/idle.s G_TRAMP): the deepest part of the idle/handler stack,
# which the game only reaches in its boot RAM test/clear
HAL_TRAMP = (0xffec00, 0xffec2f)
# converted sprite sets (hal/spr.s G_SPRBUF): a gap in the game's RAM map it never touches
HAL_SPRBUF = (0xff9280, 0xffbfff)
# retained-sprite tables and state (hal/sprr.s): sprite RAM the game writes only in its
# boot RAM test and clear
HAL_SPRTAB = ((0x1d0400, 0x1d07ff), (0x1d1000, 0x1d1fff))


def canary_ok(db, i):
    name, addr = where(i)
    if name == "wram" and any(lo <= addr <= hi for lo, hi in (HAL_SCRATCH, HAL_TRAMP, HAL_SPRBUF)):
        return True
    if name == "sprram" and any(lo <= addr <= hi for lo, hi in HAL_SPRTAB):
        return True
    return CANARY.get(addr) == db[i]


def main():
    a, b = sys.argv[1], sys.argv[2]
    ignore = set()
    for spec in sys.argv[3:]:
        lo, hi = (int(x, 16) for x in spec.split("-"))
        ignore.update(range(lo, hi + 1))
    n = bad = 0
    first = None
    for (fa, da), (fb, db) in zip(frames(a), frames(b)):
        n += 1
        if da == db:
            continue
        diffs = [i for i in range(len(da)) if da[i] != db[i] and where(i)[1] not in ignore
                 and not canary_ok(db, i)]
        diffs = equivalent(da, db, diffs)
        if not diffs:
            continue
        bad += 1
        if first is None:
            first = fa
            print("first mismatch at game frame %d: %d bytes" % (fa, len(diffs)))
            for i in diffs[:40]:
                name, addr = where(i)
                print("   %-8s %06x  orig %02x  neo %02x" % (name, addr, da[i], db[i]))
    print("frames compared %d, mismatching %d" % (n, bad))
    sys.exit(1 if bad else 0)



def histogram(a, b, limit=40):
    from collections import Counter
    c = Counter()
    first = {}
    for (fa, da), (fb, db) in zip(frames(a), frames(b)):
        if da == db:
            continue
        d = equivalent(da, db, [i for i in range(len(da)) if da[i] != db[i]])
        for i in d:
            k = where(i)
            c[k] += 1
            first.setdefault(k, (fa, da[i], db[i]))
    for k in sorted(c, key=lambda k: first[k][0])[:limit]:
        f, x, y = first[k]
        print("%-8s %06x frames=%-6d first=%d orig %02x neo %02x" % (k[0], k[1], c[k], f, x, y))
    print("distinct differing addresses: %d" % len(c))


if __name__ == "__main__":
    if sys.argv[1] == "--hist":
        histogram(sys.argv[2], sys.argv[3])
    else:
        main()
