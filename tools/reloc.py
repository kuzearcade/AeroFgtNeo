"""In-place relocation of the original 68K program onto the Neo Geo memory map.

Every patch keeps the instruction (or data word) the same size and the same opcode,
so the 68000 cycle count of every instruction is unchanged.  That property is what
lets the Neo version reproduce the original's lag frames exactly.

Patch kinds:
  absl   - 32-bit absolute EA operand pointing at original RAM/IO
  imm    - 32-bit immediate that is a pointer (movea.l #, move.l #, cmpa.l #, ...)
  data   - 32-bit pointer stored in a ROM data table
  sr     - immediate SR value (interrupt-level remap, see hal/README)
"""

import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import m68k     # noqa: E402
import memmap   # noqa: E402

# ROM data tables that hold RAM pointers.  Each entry: (start, end_exclusive, stride, desc)
# Entries were identified by reading the code that consumes them (see analysis notes).
DATA_POINTER_TABLES = [
    (0x000792, 0x0007c2, 8, "boot RAM clear table (addr,len) pairs"),
    (0x0007c6, 0x00082e, 8, "boot RAM test table (addr,len) pairs"),
    (0x000bb0, 0x000bd0, 4, "task scheduler initial stack pointers (lea $bb0(pc) at 0xa8a)"),
]

# Pointer-shaped longs in ROM bytes that are not code and that turned out to be
# plain data (found by the equivalence tests); never relocated.
DATA_NOT_POINTERS = {
}

# Immediate operands on these opcodes are treated as pointers when the value is a
# mapped original address with a zero top byte.
POINTER_IMM_OPS = {"movea", "move", "cmpa", "cmpi", "adda", "suba", "addi", "subi"}


class Patch:
    __slots__ = ("addr", "size", "old", "new", "kind", "where")

    def __init__(self, addr, size, old, new, kind, where):
        self.addr, self.size, self.old, self.new, self.kind, self.where = addr, size, old, new, kind, where

    def __repr__(self):
        return "%06x %-4s %08x->%08x  %s" % (self.addr, self.kind, self.old, self.new, self.where)


def collect(rom, instrs, sr_map=None, extra_tables=()):
    """Return (patches, review) for the given decoded instruction dict."""
    patches = []
    review = []
    for a in sorted(instrs):
        ins = instrs[a]
        for o in ins.operands:
            if o.kind == m68k.ABSL:
                v = o.value & 0xffffffff
                if (v & 0xffffff) < memmap.ORIG_ROM_END:
                    continue
                n = memmap.map_addr(v)
                if n is None:
                    review.append("%06x unmapped absolute %08x in %s" % (a, v, ins.text()))
                    continue
                # the 68000 bus is 24-bit, so the top byte is dropped in the relocated value
                patches.append(Patch(a + o.ext_off, 4, v, n, "absl", ins.text()))
            elif o.kind == m68k.ABSW:
                v = o.value & 0xffffff
                if v >= memmap.ORIG_ROM_END:
                    review.append("%06x abs.w into RAM/IO cannot be relocated in place: %s" % (a, ins.text()))
            elif o.kind == m68k.IMM and o.ext_len == 4 and isinstance(o.value, int):
                v = o.value & 0xffffffff
                if memmap.is_pointer_value(v):
                    if ins.op in POINTER_IMM_OPS:
                        patches.append(Patch(a + o.ext_off, 4, v, memmap.map_addr(v), "imm", ins.text()))
                    else:
                        review.append("%06x pointer-like immediate on %s: %s" % (a, ins.op, ins.text()))
        if sr_map is not None and ins.special == "sr" and ins.op in ("move", "stop"):
            src = ins.operands[0]
            if src.kind == m68k.IMM and src.ext_len == 2:
                new = sr_map(src.value)
                if new != src.value:
                    patches.append(Patch(a + src.ext_off, 2, src.value, new, "sr", ins.text()))
    for start, end, stride, desc in list(DATA_POINTER_TABLES) + list(extra_tables):
        for p in range(start, end, stride):
            v = struct.unpack_from(">I", rom, p)[0]
            if not memmap.is_pointer_value(v):
                review.append("%06x table '%s' entry %08x is not a mapped pointer" % (p, desc, v))
                continue
            patches.append(Patch(p, 4, v, memmap.map_addr(v), "data", desc))
    return patches, review


def collect_data_pointers(rom, instrs, explicit, lo=0x400, hi=None, only=None, candidates_only=False):
    """Every pointer-shaped 32-bit value (even address) in non-code ROM bytes.

    The game keeps many RAM/video addresses in ROM tables (palette fade lists,
    object templates, ...).  Candidates already covered by an explicit table, or
    listed in DATA_NOT_POINTERS, are skipped.
    """
    hi = hi or len(rom)
    code = bytearray(len(rom))
    for a, i in instrs.items():
        code[a:a + i.length] = b"\x01" * i.length
    taken = set()
    for p in explicit:
        taken.update(range(p.addr, p.addr + p.size))
    out = []
    a = lo
    while a + 4 <= hi:
        if any(code[a:a + 4]) or a in taken or a in DATA_NOT_POINTERS or \
                (only is not None and not candidates_only and a not in only):
            a += 2
            continue
        v = struct.unpack_from(">I", rom, a)[0]
        if memmap.is_pointer_value(v):
            out.append(Patch(a, 4, v, memmap.map_addr(v), "data", "auto: pointer in ROM data"))
            a += 4
        else:
            a += 2
    return out


def apply(rom, patches):
    out = bytearray(rom)
    seen = {}
    for p in patches:
        for b in range(p.addr, p.addr + p.size):
            if b in seen:
                raise ValueError("overlapping patches at %06x (%r / %r)" % (b, seen[b], p))
            seen[b] = p
        fmt = ">I" if p.size == 4 else ">H"
        cur = struct.unpack_from(fmt, out, p.addr)[0]
        if cur != p.old:
            raise ValueError("patch source mismatch at %06x: %x != %x" % (p.addr, cur, p.old))
        struct.pack_into(fmt, out, p.addr, p.new)
    return out
