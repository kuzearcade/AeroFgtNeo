"""MC68000 instruction decoder (68000 only, no 68010+ forms).

Decodes one instruction at a time from a big-endian byte buffer and reports
everything the translator needs:
  - total length
  - mnemonic / size
  - effective-address operands, including where their extension words sit in
    the instruction (so absolute addresses and immediates can be patched in place)
  - control flow (branch / jump / call targets, terminators)

The decoder is deliberately strict: any encoding that is not a valid 68000
instruction raises DecodeError, so data mis-identified as code is caught early.
"""

import struct


class DecodeError(Exception):
    pass


# EA mode identifiers
DN, AN, IND, POSTINC, PREDEC, DISP, INDEX, ABSW, ABSL, PCDISP, PCINDEX, IMM = range(12)
EA_NAMES = ["Dn", "An", "(An)", "(An)+", "-(An)", "d16(An)", "d8(An,Xn)",
            "abs.w", "abs.l", "d16(PC)", "d8(PC,Xn)", "#imm"]

COND = ["t", "f", "hi", "ls", "cc", "cs", "ne", "eq", "vc", "vs", "pl", "mi", "ge", "lt", "gt", "le"]

# EA category masks (bitmask over EA kinds)
def _m(*kinds):
    v = 0
    for k in kinds:
        v |= 1 << k
    return v

ALL = _m(*range(12))
DATA = ALL & ~_m(AN)
MEMORY = ALL & ~_m(DN, AN)
CONTROL = _m(IND, DISP, INDEX, ABSW, ABSL, PCDISP, PCINDEX)
ALTERABLE = _m(DN, AN, IND, POSTINC, PREDEC, DISP, INDEX, ABSW, ABSL)
DATA_ALT = DATA & ALTERABLE
MEM_ALT = MEMORY & ALTERABLE
CTRL_ALT = CONTROL & ALTERABLE


class Operand:
    __slots__ = ("kind", "reg", "size", "ext_off", "ext_len", "value", "index")

    def __init__(self, kind, reg=0, size=None, ext_off=None, ext_len=0, value=None, index=None):
        self.kind = kind          # one of the EA identifiers above
        self.reg = reg            # register number for register-based modes
        self.size = size          # operand data size in bytes (1/2/4) when known
        self.ext_off = ext_off    # byte offset of the extension word(s) from instruction start
        self.ext_len = ext_len    # number of extension bytes
        self.value = value        # absolute address / displacement / immediate value
        self.index = index        # (is_an, reg, long, disp) for indexed modes

    def text(self, pc=None):
        k = self.kind
        if k == DN:
            return "d%d" % self.reg
        if k == AN:
            return "a%d" % self.reg if self.reg != 7 else "sp"
        a = "a%d" % self.reg if self.reg != 7 else "sp"
        if k == IND:
            return "(%s)" % a
        if k == POSTINC:
            return "(%s)+" % a
        if k == PREDEC:
            return "-(%s)" % a
        if k == DISP:
            return "%d(%s)" % (self.value, a)
        if k == INDEX:
            is_an, r, lng, d = self.index
            return "%d(%s,%s%d.%s)" % (d, a, "a" if is_an else "d", r, "l" if lng else "w")
        if k == ABSW:
            return "($%04x).w" % (self.value & 0xffff)
        if k == ABSL:
            return "($%x).l" % self.value
        if k == PCDISP:
            return "$%x(pc)" % self.value
        if k == PCINDEX:
            is_an, r, lng, d = self.index
            return "$%x(pc,%s%d.%s)" % (self.value, "a" if is_an else "d", r, "l" if lng else "w")
        if k == IMM:
            if isinstance(self.value, str):
                return self.value
            return "#$%x" % (self.value & 0xffffffff)
        return "?"


class Instr:
    __slots__ = ("addr", "length", "op", "size", "operands", "flow", "targets", "raw", "special")

    def __init__(self, addr):
        self.addr = addr
        self.length = 2
        self.op = ""
        self.size = None
        self.operands = []
        # flow: None (falls through), 'branch' (cond, falls through + target),
        # 'jump' (unconditional, no fall-through), 'call' (falls through + target),
        # 'ret' (rts/rte/rtr), 'stop' (illegal/trap-like terminator), 'indirect_jump',
        # 'indirect_call'
        self.flow = None
        self.targets = []
        self.raw = b""
        self.special = None

    def text(self):
        sz = {1: ".b", 2: ".w", 4: ".l"}.get(self.size, "")
        ops = ",".join(o.text(self.addr) for o in self.operands)
        return "%s%s %s" % (self.op, sz, ops)


class Decoder:
    def __init__(self, data, base=0):
        self.data = data
        self.base = base

    def w(self, addr):
        off = addr - self.base
        if off < 0 or off + 2 > len(self.data):
            raise DecodeError("read outside image at %x" % addr)
        return struct.unpack_from(">H", self.data, off)[0]

    def l(self, addr):
        return (self.w(addr) << 16) | self.w(addr + 2)

    # ------------------------------------------------------------------
    def ea(self, ins, mode, reg, size, allowed):
        """Decode an EA field; consumes extension words from ins.length."""
        if mode == 0:
            kind = DN
        elif mode == 1:
            kind = AN
        elif mode == 2:
            kind = IND
        elif mode == 3:
            kind = POSTINC
        elif mode == 4:
            kind = PREDEC
        elif mode == 5:
            kind = DISP
        elif mode == 6:
            kind = INDEX
        else:
            kind = {0: ABSW, 1: ABSL, 2: PCDISP, 3: PCINDEX, 4: IMM}.get(reg)
            if kind is None:
                raise DecodeError("bad EA 7.%d" % reg)
        if not (allowed >> kind) & 1:
            raise DecodeError("EA %s not allowed" % EA_NAMES[kind])
        if kind == AN and size == 1:
            raise DecodeError("byte An")
        off = ins.length
        a = ins.addr + off
        op = Operand(kind, reg if mode < 7 else 0, size)
        if kind in (DISP, PCDISP):
            d = self.w(a)
            d = d - 0x10000 if d & 0x8000 else d
            op.ext_off, op.ext_len = off, 2
            op.value = d if kind == DISP else (a + d) & 0xffffffff
            ins.length += 2
        elif kind in (INDEX, PCINDEX):
            e = self.w(a)
            if e & 0x0700:
                raise DecodeError("68020 index form")
            d = e & 0xff
            d = d - 0x100 if d & 0x80 else d
            op.index = ((e >> 15) & 1, (e >> 12) & 7, (e >> 11) & 1, d)
            op.ext_off, op.ext_len = off, 2
            if kind == PCINDEX:
                op.value = (a + d) & 0xffffffff
            ins.length += 2
        elif kind == ABSW:
            v = self.w(a)
            op.value = (v | 0xffff0000) & 0xffffffff if v & 0x8000 else v
            op.ext_off, op.ext_len = off, 2
            ins.length += 2
        elif kind == ABSL:
            op.value = self.l(a)
            op.ext_off, op.ext_len = off, 4
            ins.length += 4
        elif kind == IMM:
            if size == 4:
                op.value = self.l(a)
                op.ext_off, op.ext_len = off, 4
                ins.length += 4
            else:
                v = self.w(a)
                if size == 1:
                    if v & 0xff00 and (v & 0xff00) != 0xff00:
                        raise DecodeError("bad byte immediate")
                    v &= 0xff
                op.value = v
                op.ext_off, op.ext_len = off, 2
                ins.length += 2
        return op

    def decode(self, addr):
        ins = Instr(addr)
        if addr & 1:
            raise DecodeError("odd address")
        op = self.w(addr)
        top = op >> 12
        h = getattr(self, "_g%x" % top)
        h(ins, op)
        off = addr - self.base
        ins.raw = bytes(self.data[off:off + ins.length])
        return ins

    # ------------------------------------------------------------------
    @staticmethod
    def _size2(bits):
        # 00 byte, 01 word, 10 long
        return {0: 1, 1: 2, 2: 4}.get(bits)

    def _g0(self, ins, op):
        mode, reg = (op >> 3) & 7, op & 7
        if op & 0x0100:
            if mode == 1:
                # MOVEP
                opm = (op >> 6) & 3
                ins.op = "movep"
                ins.size = 2 if opm in (0, 2) else 4
                d = self.w(ins.addr + 2)
                d = d - 0x10000 if d & 0x8000 else d
                o = Operand(DISP, reg, ins.size, 2, 2, d)
                ins.length = 4
                dn = Operand(DN, (op >> 9) & 7)
                ins.operands = [o, dn] if opm < 2 else [dn, o]
                return
            # dynamic bit ops
            t = (op >> 6) & 3
            ins.op = ["btst", "bchg", "bclr", "bset"][t]
            allowed = DATA if t == 0 else DATA_ALT
            dst = self.ea(ins, mode, reg, 1 if mode != 0 else 4, allowed)
            ins.size = 4 if mode == 0 else 1
            ins.operands = [Operand(DN, (op >> 9) & 7), dst]
            return
        sel = (op >> 9) & 7
        if sel == 4:
            # static bit ops
            t = (op >> 6) & 3
            ins.op = ["btst", "bchg", "bclr", "bset"][t]
            imm = self.w(ins.addr + 2)
            if imm & 0xff00:
                raise DecodeError("bad bit number")
            ins.length = 4
            immop = Operand(IMM, 0, 1, 2, 2, imm & 0xff)
            allowed = (DATA & ~_m(IMM)) if t == 0 else DATA_ALT
            dst = self.ea(ins, mode, reg, 1 if mode != 0 else 4, allowed)
            ins.size = 4 if mode == 0 else 1
            ins.operands = [immop, dst]
            return
        if sel == 7:
            raise DecodeError("bad op 0")
        names = {0: "ori", 1: "andi", 2: "subi", 3: "addi", 5: "eori", 6: "cmpi"}
        name = names.get(sel)
        if name is None:
            raise DecodeError("bad op 0")
        sz = self._size2((op >> 6) & 3)
        if sz is None:
            raise DecodeError("bad size")
        if mode == 7 and reg == 4 and name in ("ori", "andi", "eori"):
            # to CCR / SR
            if sz == 4:
                raise DecodeError("bad ccr/sr op")
            ins.op = name
            ins.size = sz
            imm = self.w(ins.addr + 2)
            ins.length = 4
            ins.operands = [Operand(IMM, 0, sz, 2, 2, imm & (0xff if sz == 1 else 0xffff)),
                            Operand(IMM, 0, None, None, 0, "ccr" if sz == 1 else "sr")]
            ins.special = "ccr" if sz == 1 else "sr"
            return
        ins.op = name
        ins.size = sz
        ins.length = 2
        immop = self.ea(ins, 7, 4, sz, ALL)
        allowed = DATA_ALT if name != "cmpi" else (DATA_ALT)
        dst = self.ea(ins, mode, reg, sz, allowed)
        ins.operands = [immop, dst]

    def _move(self, ins, op, sz):
        smode, sreg = (op >> 3) & 7, op & 7
        dmode, dreg = (op >> 6) & 7, (op >> 9) & 7
        src = self.ea(ins, smode, sreg, sz, ALL if sz != 1 else (ALL & ~_m(AN)))
        if dmode == 1:
            if sz == 1:
                raise DecodeError("movea.b")
            ins.op = "movea"
            dst = Operand(AN, dreg, sz)
        else:
            ins.op = "move"
            dst = self.ea(ins, dmode, dreg, sz, DATA_ALT)
        ins.size = sz
        ins.operands = [src, dst]

    def _g1(self, ins, op):
        self._move(ins, op, 1)

    def _g2(self, ins, op):
        self._move(ins, op, 4)

    def _g3(self, ins, op):
        self._move(ins, op, 2)

    def _g4(self, ins, op):
        mode, reg = (op >> 3) & 7, op & 7
        if op & 0x0100:
            if (op >> 6) & 7 == 7:
                ins.op = "lea"
                ins.size = 4
                src = self.ea(ins, mode, reg, 4, CONTROL)
                ins.operands = [src, Operand(AN, (op >> 9) & 7, 4)]
                return
            if (op >> 6) & 7 == 6:
                ins.op = "chk"
                ins.size = 2
                src = self.ea(ins, mode, reg, 2, DATA)
                ins.operands = [src, Operand(DN, (op >> 9) & 7, 2)]
                return
            raise DecodeError("bad 4xxx")
        sub = (op >> 8) & 0xf
        szb = (op >> 6) & 3
        if op == 0x4afc:
            ins.op = "illegal"
            ins.flow = "stop"
            return
        if op & 0xfff0 == 0x4e40:
            ins.op = "trap"
            ins.operands = [Operand(IMM, 0, 1, None, 0, op & 0xf)]
            ins.flow = "trap"
            return
        if op & 0xfff8 == 0x4e50:
            ins.op = "link"
            d = self.w(ins.addr + 2)
            d = d - 0x10000 if d & 0x8000 else d
            ins.length = 4
            ins.operands = [Operand(AN, reg), Operand(IMM, 0, 2, 2, 2, d)]
            return
        if op & 0xfff8 == 0x4e58:
            ins.op = "unlk"
            ins.operands = [Operand(AN, reg)]
            return
        if op & 0xfff0 == 0x4e60:
            ins.op = "move"
            ins.size = 4
            ins.special = "usp"
            ins.operands = [Operand(AN, reg)]
            return
        fixed = {0x4e70: ("reset", None), 0x4e71: ("nop", None), 0x4e72: ("stop", "stopi"),
                 0x4e73: ("rte", "ret"), 0x4e75: ("rts", "ret"), 0x4e76: ("trapv", None),
                 0x4e77: ("rtr", "ret")}
        if op in fixed:
            name, fl = fixed[op]
            ins.op = name
            if fl == "stopi":
                ins.length = 4
                ins.operands = [Operand(IMM, 0, 2, 2, 2, self.w(ins.addr + 2))]
                ins.special = "sr"
            else:
                ins.flow = fl
            return
        if op & 0xffc0 == 0x4e80 or op & 0xffc0 == 0x4ec0:
            call = op & 0xffc0 == 0x4e80
            ins.op = "jsr" if call else "jmp"
            dst = self.ea(ins, mode, reg, None, CONTROL)
            ins.operands = [dst]
            if dst.kind in (ABSW, ABSL, PCDISP):
                ins.targets = [dst.value & 0xffffff]
                ins.flow = "call" if call else "jump"
            else:
                ins.flow = "indirect_call" if call else "indirect_jump"
            return
        if sub == 0x0 and szb != 3:
            ins.op = "negx"
            ins.size = self._size2(szb)
            ins.operands = [self.ea(ins, mode, reg, ins.size, DATA_ALT)]
            return
        if sub == 0x0 and szb == 3:
            ins.op = "move"
            ins.size = 2
            ins.special = "fromsr"
            ins.operands = [Operand(IMM, 0, None, None, 0, "sr"), self.ea(ins, mode, reg, 2, DATA_ALT)]
            return
        if sub == 0x2 and szb != 3:
            ins.op = "clr"
            ins.size = self._size2(szb)
            ins.operands = [self.ea(ins, mode, reg, ins.size, DATA_ALT)]
            return
        if sub == 0x4 and szb != 3:
            ins.op = "neg"
            ins.size = self._size2(szb)
            ins.operands = [self.ea(ins, mode, reg, ins.size, DATA_ALT)]
            return
        if sub == 0x4 and szb == 3:
            ins.op = "move"
            ins.size = 2
            ins.special = "ccr"
            ins.operands = [self.ea(ins, mode, reg, 2, DATA), Operand(IMM, 0, None, None, 0, "ccr")]
            return
        if sub == 0x6 and szb != 3:
            ins.op = "not"
            ins.size = self._size2(szb)
            ins.operands = [self.ea(ins, mode, reg, ins.size, DATA_ALT)]
            return
        if sub == 0x6 and szb == 3:
            ins.op = "move"
            ins.size = 2
            ins.special = "sr"
            ins.operands = [self.ea(ins, mode, reg, 2, DATA), Operand(IMM, 0, None, None, 0, "sr")]
            return
        if sub == 0x8:
            if szb == 0:
                ins.op = "nbcd"
                ins.size = 1
                ins.operands = [self.ea(ins, mode, reg, 1, DATA_ALT)]
                return
            if szb == 1:
                if mode == 0:
                    ins.op = "swap"
                    ins.operands = [Operand(DN, reg)]
                    return
                ins.op = "pea"
                ins.size = 4
                ins.operands = [self.ea(ins, mode, reg, 4, CONTROL)]
                return
            if mode == 0:
                ins.op = "ext"
                ins.size = 2 if szb == 2 else 4
                ins.operands = [Operand(DN, reg)]
                return
            # movem reg->mem
            ins.op = "movem"
            ins.size = 2 if szb == 2 else 4
            mask = self.w(ins.addr + 2)
            ins.length = 4
            m = Operand(IMM, 0, 2, 2, 2, mask)
            ins.operands = [m, self.ea(ins, mode, reg, ins.size, CTRL_ALT | _m(PREDEC))]
            ins.special = "movem_store"
            return
        if sub == 0xa:
            if szb == 3:
                ins.op = "tas"
                ins.size = 1
                ins.operands = [self.ea(ins, mode, reg, 1, DATA_ALT)]
                return
            ins.op = "tst"
            ins.size = self._size2(szb)
            ins.operands = [self.ea(ins, mode, reg, ins.size, DATA_ALT)]
            return
        if sub == 0xc and szb >= 2:
            ins.op = "movem"
            ins.size = 2 if szb == 2 else 4
            mask = self.w(ins.addr + 2)
            ins.length = 4
            m = Operand(IMM, 0, 2, 2, 2, mask)
            ins.operands = [self.ea(ins, mode, reg, ins.size, CONTROL | _m(POSTINC)), m]
            ins.special = "movem_load"
            return
        raise DecodeError("bad 4xxx %04x" % op)

    def _g5(self, ins, op):
        mode, reg = (op >> 3) & 7, op & 7
        szb = (op >> 6) & 3
        if szb == 3:
            cond = (op >> 8) & 0xf
            if mode == 1:
                ins.op = "db" + COND[cond]
                d = self.w(ins.addr + 2)
                d = d - 0x10000 if d & 0x8000 else d
                ins.length = 4
                t = (ins.addr + 2 + d) & 0xffffff
                ins.operands = [Operand(DN, reg), Operand(PCDISP, 0, None, 2, 2, t)]
                ins.targets = [t]
                ins.flow = "branch"
                return
            ins.op = "s" + COND[cond]
            ins.size = 1
            ins.operands = [self.ea(ins, mode, reg, 1, DATA_ALT)]
            return
        q = (op >> 9) & 7
        q = 8 if q == 0 else q
        ins.op = "subq" if op & 0x0100 else "addq"
        ins.size = self._size2(szb)
        dst = self.ea(ins, mode, reg, ins.size, ALTERABLE)
        ins.operands = [Operand(IMM, 0, ins.size, None, 0, q), dst]

    def _g6(self, ins, op):
        cond = (op >> 8) & 0xf
        d = op & 0xff
        if d == 0:
            d = self.w(ins.addr + 2)
            d = d - 0x10000 if d & 0x8000 else d
            ins.length = 4
            ext = (2, 2)
        else:
            d = d - 0x100 if d & 0x80 else d
            ext = (None, 0)
        t = (ins.addr + 2 + d) & 0xffffff
        if t & 1:
            raise DecodeError("odd branch target")
        ins.op = {0: "bra", 1: "bsr"}.get(cond, "b" + COND[cond])
        ins.operands = [Operand(PCDISP, 0, None, ext[0], ext[1], t)]
        ins.targets = [t]
        ins.flow = {0: "jump", 1: "call"}.get(cond, "branch")

    def _g7(self, ins, op):
        if op & 0x0100:
            raise DecodeError("bad moveq")
        v = op & 0xff
        v = v - 0x100 if v & 0x80 else v
        ins.op = "moveq"
        ins.size = 4
        ins.operands = [Operand(IMM, 0, 1, None, 0, v), Operand(DN, (op >> 9) & 7)]

    def _arith(self, ins, op, name, allow_an_src=True):
        mode, reg = (op >> 3) & 7, op & 7
        rn = (op >> 9) & 7
        opm = (op >> 6) & 7
        if opm in (3, 7):
            # address-register form (adda/suba/cmpa)
            sz = 2 if opm == 3 else 4
            ins.op = name + "a"
            ins.size = sz
            ins.operands = [self.ea(ins, mode, reg, sz, ALL), Operand(AN, rn, sz)]
            return
        sz = self._size2(opm & 3)
        ins.size = sz
        if opm < 3:
            ins.op = name
            allowed = ALL if allow_an_src else DATA
            if sz == 1:
                allowed &= ~_m(AN)
            ins.operands = [self.ea(ins, mode, reg, sz, allowed), Operand(DN, rn, sz)]
        else:
            ins.op = name
            ins.operands = [Operand(DN, rn, sz), self.ea(ins, mode, reg, sz, MEM_ALT)]

    def _g8(self, ins, op):
        mode, reg = (op >> 3) & 7, op & 7
        opm = (op >> 6) & 7
        rn = (op >> 9) & 7
        if opm == 3 or opm == 7:
            ins.op = "divu" if opm == 3 else "divs"
            ins.size = 2
            ins.operands = [self.ea(ins, mode, reg, 2, DATA), Operand(DN, rn)]
            return
        if opm == 4 and mode in (0, 1):
            ins.op = "sbcd"
            ins.size = 1
            k = DN if mode == 0 else PREDEC
            ins.operands = [Operand(k, reg), Operand(k, rn)]
            return
        self._arith(ins, op, "or", allow_an_src=False)

    def _g9(self, ins, op):
        self._addsub(ins, op, "sub")

    def _gd(self, ins, op):
        self._addsub(ins, op, "add")

    def _addsub(self, ins, op, name):
        mode, reg = (op >> 3) & 7, op & 7
        opm = (op >> 6) & 7
        rn = (op >> 9) & 7
        if opm in (4, 5, 6) and mode in (0, 1):
            ins.op = name + "x"
            ins.size = self._size2(opm & 3)
            k = DN if mode == 0 else PREDEC
            ins.operands = [Operand(k, reg), Operand(k, rn)]
            return
        self._arith(ins, op, name)

    def _ga(self, ins, op):
        ins.op = "linea"
        ins.flow = "trap"
        ins.operands = [Operand(IMM, 0, 2, None, 0, op)]

    def _gf(self, ins, op):
        ins.op = "linef"
        ins.flow = "trap"
        ins.operands = [Operand(IMM, 0, 2, None, 0, op)]

    def _gb(self, ins, op):
        mode, reg = (op >> 3) & 7, op & 7
        opm = (op >> 6) & 7
        rn = (op >> 9) & 7
        if opm in (3, 7):
            sz = 2 if opm == 3 else 4
            ins.op = "cmpa"
            ins.size = sz
            ins.operands = [self.ea(ins, mode, reg, sz, ALL), Operand(AN, rn, sz)]
            return
        sz = self._size2(opm & 3)
        ins.size = sz
        if opm < 3:
            ins.op = "cmp"
            allowed = ALL if sz != 1 else ALL & ~_m(AN)
            ins.operands = [self.ea(ins, mode, reg, sz, allowed), Operand(DN, rn, sz)]
            return
        if mode == 1:
            ins.op = "cmpm"
            ins.operands = [Operand(POSTINC, reg, sz), Operand(POSTINC, rn, sz)]
            return
        ins.op = "eor"
        ins.operands = [Operand(DN, rn, sz), self.ea(ins, mode, reg, sz, DATA_ALT)]

    def _gc(self, ins, op):
        mode, reg = (op >> 3) & 7, op & 7
        opm = (op >> 6) & 7
        rn = (op >> 9) & 7
        if opm == 3 or opm == 7:
            ins.op = "mulu" if opm == 3 else "muls"
            ins.size = 2
            ins.operands = [self.ea(ins, mode, reg, 2, DATA), Operand(DN, rn)]
            return
        if opm == 4 and mode in (0, 1):
            ins.op = "abcd"
            ins.size = 1
            k = DN if mode == 0 else PREDEC
            ins.operands = [Operand(k, reg), Operand(k, rn)]
            return
        if opm == 5 and mode in (0, 1):
            ins.op = "exg"
            ins.size = 4
            k = DN if mode == 0 else AN
            ins.operands = [Operand(k, rn), Operand(k, reg)]
            return
        if opm == 6 and mode == 1:
            ins.op = "exg"
            ins.size = 4
            ins.operands = [Operand(DN, rn), Operand(AN, reg)]
            return
        self._arith(ins, op, "and", allow_an_src=False)

    def _ge(self, ins, op):
        szb = (op >> 6) & 3
        mode, reg = (op >> 3) & 7, op & 7
        if szb == 3:
            if op & 0x0800:
                raise DecodeError("bad memory shift")
            t = (op >> 9) & 3
            ins.op = ["as", "ls", "rox", "ro"][t] + ("l" if op & 0x0100 else "r")
            ins.size = 2
            ins.operands = [self.ea(ins, mode, reg, 2, MEM_ALT)]
            return
        t = (op >> 3) & 3
        ins.op = ["as", "ls", "rox", "ro"][t] + ("l" if op & 0x0100 else "r")
        ins.size = self._size2(szb)
        cnt = (op >> 9) & 7
        if op & 0x20:
            src = Operand(DN, cnt)
        else:
            src = Operand(IMM, 0, 1, None, 0, 8 if cnt == 0 else cnt)
        ins.operands = [src, Operand(DN, reg)]


def decode(data, addr, base=0):
    return Decoder(data, base).decode(addr)
