"""Minimal Z80 decoder: instruction length plus the operands the sound-driver port
needs (immediate I/O ports, 16-bit immediates/addresses and their byte offsets).

Returns Ins(addr, length, kind, port, imm16_off, imm16, mnem).
"""

import collections

Ins = collections.namedtuple("Ins", "addr length kind port imm16_off imm16 text targets flow")

# opcodes with a 16-bit immediate (nn) right after the opcode (unprefixed)
NN = {0x01, 0x11, 0x21, 0x31, 0x22, 0x2a, 0x32, 0x3a, 0xc2, 0xc3, 0xc4, 0xca, 0xcc, 0xcd,
      0xd2, 0xd4, 0xda, 0xdc, 0xe2, 0xe4, 0xea, 0xec, 0xf2, 0xf4, 0xfa, 0xfc}
# opcodes with an 8-bit immediate
N8 = {0x06, 0x0e, 0x16, 0x1e, 0x26, 0x2e, 0x36, 0x3e, 0xc6, 0xce, 0xd6, 0xde, 0xe6, 0xee,
      0xf6, 0xfe, 0xd3, 0xdb, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38}
JR = {0x10, 0x18, 0x20, 0x28, 0x30, 0x38}


def decode(mem, addr):
    op = mem[addr]
    if op == 0xcb:
        return Ins(addr, 2, "cb", None, None, None, "cb %02x" % mem[addr + 1], [], None)
    if op == 0xed:
        op2 = mem[addr + 1]
        # ED 43/4B/53/5B/63/6B/73/7B: 16-bit memory operand
        if op2 & 0xc7 == 0x43:
            nn = mem[addr + 2] | mem[addr + 3] << 8
            return Ins(addr, 4, "ed_nn", None, 2, nn, "ed %02x %04x" % (op2, nn), [], None)
        kind = "ed"
        if op2 & 0xc7 in (0x40, 0x41):
            kind = "io_c"                         # IN r,(C) / OUT (C),r
        if op2 in (0xa2, 0xa3, 0xaa, 0xab, 0xb2, 0xb3, 0xba, 0xbb):
            kind = "io_block"
        flow = "ret" if op2 in (0x45, 0x4d) else None
        return Ins(addr, 2, kind, None, None, None, "ed %02x" % op2, [], flow)
    if op in (0xdd, 0xfd):
        op2 = mem[addr + 1]
        if op2 == 0xcb:
            return Ins(addr, 4, "ixcb", None, None, None, "%02x cb" % op, [], None)
        if op2 in (0x21, 0x22, 0x2a):
            nn = mem[addr + 2] | mem[addr + 3] << 8
            return Ins(addr, 4, "ix_nn", None, 2, nn, "%02x %02x %04x" % (op, op2, nn), [], None)
        if op2 == 0x36:
            return Ins(addr, 4, "ix", None, None, None, "%02x 36", [], None)
        ixd = {0x34, 0x35, 0x46, 0x4e, 0x56, 0x5e, 0x66, 0x6e, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75,
               0x77, 0x7e, 0x86, 0x8e, 0x96, 0x9e, 0xa6, 0xae, 0xb6, 0xbe}
        if op2 in ixd:
            return Ins(addr, 3, "ix", None, None, None, "%02x %02x" % (op, op2), [], None)
        flow = "ijump" if op2 == 0xe9 else None
        return Ins(addr, 2, "ix", None, None, None, "%02x %02x" % (op, op2), [], flow)
    if op in NN:
        nn = mem[addr + 1] | mem[addr + 2] << 8
        flow = None
        targets = []
        if op in (0xc3,):
            flow, targets = "jump", [nn]
        elif op == 0xcd or op & 0xc7 == 0xc4:
            flow, targets = "call", [nn]
        elif op & 0xc7 == 0xc2:
            flow, targets = "branch", [nn]
        return Ins(addr, 3, "nn", None, 1, nn, "%02x %04x" % (op, nn), targets, flow)
    if op in N8:
        n = mem[addr + 1]
        if op == 0xd3:
            return Ins(addr, 2, "out", n, None, None, "out (%02x),a" % n, [], None)
        if op == 0xdb:
            return Ins(addr, 2, "in", n, None, None, "in a,(%02x)" % n, [], None)
        if op in JR:
            t = (addr + 2 + (n - 256 if n & 0x80 else n)) & 0xffff
            return Ins(addr, 2, "jr", None, None, None, "jr %04x" % t, [t], "jump" if op == 0x18 else "branch")
        return Ins(addr, 2, "n8", None, None, None, "%02x %02x" % (op, n), [], None)
    flow = None
    if op in (0xc9,):
        flow = "ret"
    elif op == 0xe9:
        flow = "ijump"
    elif op & 0xc7 == 0xc7:
        flow = "call"
    return Ins(addr, 1, "op", None, None, None, "%02x" % op, [], flow)
