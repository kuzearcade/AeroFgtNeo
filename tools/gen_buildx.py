"""Generate the exact replica of the game's sprite-list builder (hal/buildx: included when
AEROFGT_BUILDX=1; the builder's first instruction at 0x2bee0, movea.l #$ff6800,a6, 12
cycles, becomes jmp bx_entry, also 12 cycles).

The replica does what the original builder (0x2bee0..0x2bf9a with the pass loop 0x2bfd0,
the sort 0x2bffa and the emitters 0x2c0b4/0x2c0d2/0x2c0ec) does to RAM and to every
register, and takes exactly as long: everything but the emitter calls is copied
instruction for instruction; the three calls per object are one inline routine
(bx_obj) whose piece loops are specialised by the per-call flags (24 variants).  A cycle
debt in d2 (the original's cycles from the emitter model, tools/../work/emitmodel.py,
less the replica's own) is burnt off exactly before returning to 0x2bf9a.  Debt adds
sit where a later instruction of the same piece sets X the way the original does, so X
at the end is the original's; d2/d3 (untouched by the original) are saved and restored.

No vblank may land inside the replica (no fallback yet): the experiment build only.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import memmap  # noqa: E402


def R(a):
    """relocated game RAM address"""
    v = memmap.map_addr(a)
    assert v is not None, hex(a)
    return v


# ---------------------------------------------------------------- code with cycles
class Prog:
    def __init__(self):
        self.items = []          # (label or None, text, cyc, branch)

    def lab(self, name):
        self.items.append((name, None, 0, None))

    def i(self, text, cyc):
        self.items.append((None, text, cyc, None))

    def b(self, text, target, taken, nt):
        """conditional branch"""
        self.items.append((None, text, 0, ("c", target, taken, nt)))

    def j(self, text, target, cyc):
        """unconditional branch / jump"""
        self.items.append((None, text, 0, ("u", target, cyc, cyc)))

    def index(self):
        return {it[0]: k for k, it in enumerate(self.items) if it[0]}

    def walk(self, start, end, decisions):
        """cycles from label start up to label end (excluded), taking conditional
        branches by the decisions (True = taken), in order."""
        idx = self.index()
        k = idx[start]
        dec = list(decisions)
        cyc = 0
        steps = 0
        while True:
            steps += 1
            assert steps < 10000
            lab, text, c, br = self.items[k]
            if lab == end:
                assert not dec, (start, end, dec)
                return cyc
            if br is None:
                cyc += c
                k += 1
            elif br[0] == "u":
                cyc += br[2]
                k = idx[br[1]]
            else:
                assert dec, ("out of decisions at", text, start, end)
                t = dec.pop(0)
                cyc += br[2] if t else br[3]
                k = idx[br[1]] if t else k + 1

    def text(self, subst):
        out = []
        for lab, text, c, br in self.items:
            if lab:
                out.append("%s:" % lab)
                continue
            t = text.format(**subst) if "{" in text else text
            out.append("\t%-36s ; %s" % (t, ("%d" % c) if br is None else
                                        ("%d/%d" % (br[2], br[3]) if br[0] == "c" else "%d" % br[2])))
        return "\n".join(out) + "\n"


# ---------------------------------------------------------------- the original's costs
END_CLEAR = END_FULL = 20       # andi/ori #,sr
BSR, RTS, BCSW_NT, BCSW_T = 18, 16, 12, 10

O_Y = {"Y1": 54, "Y2": 76, "OFFY": 74 + 16}            # offy: + adda #$e,a3


def kk(k2e):
    return 24 if k2e else 10


def O_x(k2e, x):
    base = 52 + kk(k2e) + 82 + 32
    return base + {"X1": 10, "X2": 30, "OFFX": 52 + 16}[x]


CO = {0: 10, 1: 26, 2: 40}


def O_tail(k2e, co, b25, b42, full):
    c = 52 + kk(k2e) + 82 + 24 + CO[co] + 20 + (62 if b25 else 18) + 12 + (10 if b42 else 78) + 150
    return c + (10 if full else 12 + 16)


# call overheads in the original (entry .. rts excluded, from emitmodel), + bsr, rts, bcs
O_B_FAIL = 42 + BSR + RTS + BCSW_NT
O_A_FAIL = 52 + BSR + RTS + BCSW_NT
O_B_PASS = 70 + END_CLEAR + BSR + RTS + BCSW_NT        # + pieces
O_A_PASS = 80 + END_CLEAR + BSR + RTS + BCSW_NT
O_C = 36 + END_CLEAR + BSR + RTS + BCSW_NT


# ---------------------------------------------------------------- variants
VARIANTS = [(k2e, co, b25, b42) for k2e in (0, 1) for co in (0, 1, 2) for b25 in (0, 1) for b42 in (0, 1)]


def vname(v):
    return "bxv_%d%d%d%d" % v


def piece_loop(p, v):
    """the piece loop of variant v; K placeholders named per variant"""
    k2e, co, b25, b42 = v
    cobj = co == 2
    n = vname(v)
    L = lambda s: n + "_" + s      # noqa: E731
    p.lab(n)
    p.lab(L("p"))
    p.i("addi.w  #{%s},d2" % L("ka"), 8)
    p.i("movea.l (a3),a4", 12)
    p.i("move.w  $e(a0),d0", 12)
    p.i("add.w   4(a3),d0", 12)
    p.i("cmpi.w  #$fee0,d0", 8)
    p.b("bcc.s   %s" % L("y1"), L("y1"), 10, 8)
    p.i("cmpi.w  #$e0,d0", 8)
    p.b("bcc.w   %s" % L("offy"), L("offy"), 10, 12)
    p.i("addi.w  #{%s},d2" % L("kb2"), 8)
    p.j("bra.s   %s" % L("yv"), L("yv"), 10)
    p.lab(L("y1"))
    p.i("addi.w  #{%s},d2" % L("kb1"), 8)
    p.lab(L("yv"))
    p.i("add.w   d3,d0", 4)
    p.i("andi.w  #$1ff,d0", 8)
    if k2e:
        p.i("or.w    (EX_ZB).l,d0", 16)
    else:
        p.i("move.b  10(a3),d1", 12)
        p.i("ror.w   #4,d1", 14)
        p.i("andi.w  #$f000,d1", 8)
        p.i("or.w    d1,d0", 4)
    p.i("move.w  (a4),d1", 8)
    p.i("andi.w  #$ff00,d1", 8)
    p.i("or.w    d1,d0", 4)
    p.i("move.w  d0,(a1)+", 8)
    p.i("move.w  $10(a0),d0", 12)
    p.i("add.w   6(a3),d0", 12)
    p.i("cmpi.w  #$ff40,d0", 8)
    p.b("bcc.s   %s" % L("x1"), L("x1"), 10, 8)
    p.i("cmpi.w  #$140,d0", 8)
    p.b("bcc.w   %s" % L("offx"), L("offx"), 10, 12)
    p.i("addi.w  #{%s},d2" % L("kc2"), 8)
    p.j("bra.s   %s" % L("xv"), L("xv"), 10)
    p.lab(L("x1"))
    p.i("addi.w  #{%s},d2" % L("kc1"), 8)
    p.lab(L("xv"))
    p.i("swap    d3", 4)
    p.i("add.w   d3,d0", 4)
    p.i("swap    d3", 4)
    p.i("andi.w  #$1ff,d0", 8)
    if k2e:
        p.i("or.w    (EX_ZB).l,d0", 16)
    else:
        p.i("move.b  11(a3),d1", 12)
        p.i("ror.w   #4,d1", 14)
        p.i("andi.w  #$f000,d1", 8)
        p.i("or.w    d1,d0", 4)
    p.i("move.w  (a4),d1", 8)
    p.i("lsl.w   #8,d1", 22)
    p.i("or.w    d1,d0", 4)
    p.i("move.w  d0,(a1)+", 8)
    if cobj and b42:
        p.i("move.b  (EX_B42).l,d1", 16)
        p.i("move.w  (EX_W2).l,(a1)+", 20)
    else:
        if cobj:
            p.i("move.b  (EX_OB).l,d0", 16)
        else:
            p.i("move.b  12(a3),d0", 12)
            p.i("andi.w  #$f,d0", 8)
            p.i("or.b    (EX_OB).l,d0", 16)
        if b42:
            p.i("move.b  (EX_B42).l,d1", 16)
        else:
            p.i("move.b  8(a3),d1", 12)
            p.i("lsl.w   #7,d1", 20)
            p.i("or.b    d1,d0", 4)
            p.i("move.b  9(a3),d1", 12)
            p.i("lsl.w   #6,d1", 18)
            p.i("or.b    d1,d0", 4)
        p.i("lsl.w   #8,d0", 22)
        p.i("or.w    (G_BX923E).l,d0", 16)
        p.i("move.w  d0,(a1)+", 8)
    p.i("move.w  2(a4),d0", 12)
    p.i("or.w    (G_BX9240).l,d0", 16)
    p.i("move.w  d0,(a1)+", 8)
    p.i("addq.w  #1,(a2)", 12)
    p.i("move.w  a1,d0", 4)
    p.i("subq.w  #4,d0", 4)
    p.i("lsr.w   #3,d0", 12)
    p.i("andi.w  #$ff,d0", 8)
    p.i("addi.w  #$100,d0", 8)
    p.i("move.w  d0,(a6)+", 8)
    p.i("addq.l  #4,a4", 8)
    p.i("move.w  a1,d0", 4)
    p.i("andi.w  #$3ff,d0", 8)
    p.b("beq.w   %s" % L("full"), L("full"), 10, 12)
    p.lab(L("nx"))
    p.i("lea     14(a3),a3", 8)
    p.lab(L("dbf"))
    p.b("dbf     d6,%s" % L("p"), L("p"), 10, 14)
    p.i("rts", 16)
    p.lab(L("offy"))
    p.i("lea     14(a3),a3", 8)
    p.j("bra.w   %s" % L("dbf"), L("dbf"), 10)
    p.lab(L("offx"))
    p.i("move.w  -(a1),d0", 10)
    p.i("addq.l  #1,a4", 8)
    p.i("lea     14(a3),a3", 8)
    p.j("bra.w   %s" % L("dbf"), L("dbf"), 10)
    p.lab(L("full"))
    p.i("addi.w  #{%s},d2" % L("kf"), 8)
    p.i("move    #$05,ccr", 16)
    p.i("rts", 16)
    p.lab(L("end"))


def solve_piece(p, v, K):
    """debt adds of variant v's piece loop: every path's adds = O - R"""
    k2e, co, b25, b42 = v
    n = vname(v)
    L = lambda s: n + "_" + s      # noqa: E731
    # path segments (dbf excluded on both sides; the offy/offx bra.w to the dbf is the
    # replica's own cost)
    r_offy = p.walk(L("p"), L("dbf"), [False, True])
    r_y = {"Y1": p.walk(L("p"), L("yv"), [True]), "Y2": p.walk(L("p"), L("yv"), [False, False])}
    r_offx = p.walk(L("yv"), L("dbf"), [False, True])
    r_x = {"X1": p.walk(L("yv"), L("xv"), [True]), "X2": p.walk(L("yv"), L("xv"), [False, False])}
    r_tail_nf = p.walk(L("xv"), L("dbf"), [False])
    r_tail_full = p.walk(L("xv"), L("full"), [True]) + 8 + 16      # .full's addi, ccr
    o_offx = O_x(k2e, "OFFX")
    K[L("ka")] = O_Y["OFFY"] - r_offy
    for y, s in (("Y1", "kb1"), ("Y2", "kb2")):
        K[L(s)] = O_Y[y] - r_y[y] + (o_offx - r_offx) - K[L("ka")]
    o_tnf = O_tail(k2e, co, b25, b42, False)
    for x, s in (("X1", "kc1"), ("X2", "kc2")):
        K[L(s)] = O_x(k2e, x) - r_x[x] + o_tnf - r_tail_nf - (o_offx - r_offx)
    # full: the original's tail then END_FULL + rts; the replica's .full ends in rts:
    # (O_full - R_full) - (O_nf - R_nf), with the loop-end rts (16) of the normal case
    # counted at the call level, and the original's END_CLEAR there too
    # full: the original's END_FULL + rts = its END_CLEAR + rts of the normal end (both
    # counted per call); the replica's .full rts = its loop-end rts (counted per call)
    K[L("kf")] = (O_tail(k2e, co, b25, b42, True) - r_tail_full) - (o_tnf - r_tail_nf)
    return dict(r_offy=r_offy, r_y=r_y, r_offx=r_offx, r_x=r_x, r_tail_nf=r_tail_nf)


def tree(p):
    """variant choice per call: a0 object, d5 (0 for C); scratch d0 only (the first
    piece writes d0 before reading it; d1 must survive: an offscreen piece keeps it)"""
    leaves = {}

    def leaf(path, v):
        n = "bxt_" + "".join(str(x) for x in v)
        leaves[v] = (n, path)
        return n

    # decision order: k2e, colour, b25, b42; generated as nested blocks
    p.lab("bx_tree")
    for k2e in (1, 0):
        lab_k = "bxt_k%d" % k2e
        if k2e == 1:
            p.i("cmpi.w  #$2e,$16(a0)", 16)
            p.b("bne.w   bxt_k0", "bxt_k0", 10, 12)
            p.i("move.b  1(a0),d0", 12)
            p.i("ror.w   #4,d0", 14)
            p.i("andi.w  #$f000,d0", 8)
            p.i("move.w  d0,(EX_ZB).l", 16)
            p.j("bra.w   bxt_c1", "bxt_c1", 10)
        else:
            p.lab(lab_k)
            p.j("bra.w   bxt_c0", "bxt_c0", 10)
        # colour
    for k2e in (1, 0):
        p.lab("bxt_c%d" % k2e)
        p.i("tst.b   5(a0)", 12)
        p.b("bpl.w   bxt_k%d_co0" % k2e, "bxt_k%d_co0" % k2e, 10, 12)
        p.i("tst.w   d5", 4)
        p.b("bne.w   bxt_k%d_co1" % k2e, "bxt_k%d_co1" % k2e, 10, 12)
        p.i("move.b  5(a0),d0", 12)
        p.i("andi.b  #$f,d0", 8)
        p.j("bra.w   bxt_k%d_co2b" % k2e, "bxt_k%d_co2b" % k2e, 10)
        for co in (0, 1):
            p.lab("bxt_k%d_co%d" % (k2e, co))
            p.i("moveq   #0,d0", 4)
            p.j("bra.w   bxt_k%d_co%db" % (k2e, co), "bxt_k%d_co%db" % (k2e, co), 10)
        for co in (0, 1, 2):
            pre = "bxt_k%d_co%d" % (k2e, co)
            p.lab(pre + "b")
            # b25
            p.i("tst.b   $19(a0)", 12)
            p.b("bpl.w   %s_p0" % pre, pre + "_p0", 10, 12)
            p.i("btst    #0,$19(a0)", 16)
            p.b("beq.w   %s_p1z" % pre, pre + "_p1z", 10, 12)
            p.i("ori.b   #$20,d0", 8)
            p.j("bra.w   %s_q1" % pre, pre + "_q1", 10)
            p.lab(pre + "_p1z")              # (as long as the bit-set path)
            p.i("nop", 4)
            p.i("exg     d0,d0", 6)
            p.j("bra.w   %s_q1" % pre, pre + "_q1", 10)
            p.lab(pre + "_p0")
            p.i("ori.b   #$20,d0", 8)
            p.j("bra.w   %s_q0" % pre, pre + "_q0", 10)
            for b25 in (0, 1):
                q = "%s_q%d" % (pre, b25)
                p.lab(q)
                p.i("tst.b   $2a(a0)", 12)
                p.b("beq.w   %s_n42" % q, q + "_n42", 10, 12)
                p.i("or.b    $2a(a0),d0", 12)
                p.i("move.b  $2a(a0),(EX_B42).l", 24)
                p.i("move.b  d0,(EX_OB).l", 16)
                p.i("lsl.w   #8,d0", 22)
                p.i("or.w    (G_BX923E).l,d0", 16)
                p.i("move.w  d0,(EX_W2).l", 16)
                v = (k2e, co, b25, 1)
                p.i("addi.w  #{%s},d2" % ("lk_" + vname(v)), 8)
                p.j("bra.w   %s" % vname(v), vname(v), 10)
                p.lab(q + "_n42")
                p.i("move.b  d0,(EX_OB).l", 16)
                v = (k2e, co, b25, 0)
                p.i("addi.w  #{%s},d2" % ("lk_" + vname(v)), 8)
                p.j("bra.w   %s" % vname(v), vname(v), 10)


def tree_path(v):
    """decisions through bx_tree to variant v's branch"""
    k2e, co, b25, b42 = v
    d = [k2e == 0]                   # bne.w bxt_k0 taken when not k2e
    if co == 0:
        d += [True]
    elif co == 1:
        d += [False, True]
    else:
        d += [False, False]
    if b25 == 0:
        d += [True]
    else:
        d += [False, False]          # b25 bit 7 set; btst #0 -> (either) the ori path: cost below
    d += [b42 == 0]
    return d


def loop_copy(p, name, store):
    """the pass loop 0x2bfd0 (bsr'ed; a0 = first object, d4 = end): adda.l #$60 (16) ->
    lea (8), each one credited at the end from the pointer it leaves (store)"""
    p.lab(name)
    p.i("move.b  (a0),d0", 8)
    p.b("bpl.w   %s_n" % name, name + "_n", 10, 12)
    p.i("bsr.w   bx_obj", 18)
    p.b("bcs.w   %s_x" % name, name + "_x", 10, 12)
    p.lab(name + "_n")
    p.i("lea     $60(a0),a0", 8)
    p.i("cmpa.l  d4,a0", 6)
    p.b("bcs.s   %s" % name, name, 10, 8)
    p.lab(name + "_x")
    p.i("move.l  a0,(%s).l" % store, 20)
    p.i("rts", 16)


P1_START, P1_END = 0xff0000, 0xff30c0
P2_START, P3_START, PA_START = 0xff30c0, 0xff48c0, 0xff42c0


def build():
    p = Prog()
    K = {}
    # entry: jmp here (12) replaced movea.l #$ff6800,a6 (12)
    p.lab("bx_entry")
    p.i("movea.l #$%06x,a6" % R(0xff6800), 12)
    p.i("move.w  #$c000,(a6)+", 12)
    p.i("move.w  #$1000,($%06x).l" % R(0xff923e), 20)
    p.i("move.w  #$2000,($%06x).l" % R(0xff9240), 20)
    p.i("move.w  #1,($%06x).l" % R(0xff9236), 20)
    p.i("movem.l d2-d3,(EX_SV).l", 32)
    p.i("move.w  ($%06x).l,d3" % R(0xff8b4a), 16)
    p.i("swap    d3", 4)
    p.i("move.w  ($%06x).l,d3" % R(0xff8b4c), 16)
    p.i("move.w  #{k0},d2", 8)
    p.i("move.l  #$%06x,d4" % R(P1_END), 12)
    p.i("movea.l #$%06x,a1" % R(0xff7400), 12)
    p.i("movea.l #$%06x,a0" % R(0xff0000), 12)
    p.i("clr.w   ($%06x).l" % R(0xff8d08), 20)
    p.i("movea.l #$%06x,a2" % R(0xff8d08), 12)
    # pass 1 (inline in the original; cmpa.l #imm (14) -> cmpa.l d4 (6), adda -> lea)
    p.lab("bx_p1")
    p.i("move.b  (a0),d0", 8)
    p.b("bpl.w   bx_p1n", "bx_p1n", 10, 12)
    p.i("bsr.w   bx_obj", 18)
    p.b("bcs.w   bx_p1x", "bx_p1x", 10, 12)
    p.lab("bx_p1n")
    p.i("lea     $60(a0),a0", 8)
    p.i("cmpa.l  d4,a0", 6)
    p.b("bcs.s   bx_p1", "bx_p1", 10, 8)
    p.lab("bx_p1x")
    p.i("move.l  a0,(EX_A1).l", 20)
    p.i("move.l  a1,($%06x).l" % R(0xff8d0e), 20)
    p.i("clr.w   ($%06x).l" % R(0xff923e), 20)
    p.i("clr.w   ($%06x).l" % R(0xff9240), 20)
    p.i("movea.l #$%06x,a1" % R(0xff7000), 12)
    p.i("clr.w   ($%06x).l" % R(0xff8d06), 20)
    p.i("movea.l #$%06x,a2" % R(0xff8d06), 12)
    p.i("movea.l #$%06x,a0" % R(P2_START), 12)
    p.i("move.l  #$%06x,d4" % R(0xff42c0), 12)
    p.i("bsr.w   bx_loop2", 18)
    p.i("bsr.w   bx_sort", 18)
    p.i("movea.l #$%06x,a0" % R(P3_START), 12)
    p.i("move.l  #$%06x,d4" % R(0xff60c0), 12)
    p.i("bsr.w   bx_loop3", 18)
    p.i("move.l  a1,($%06x).l" % R(0xff8d0a), 20)
    p.i("move.l  a6,($%06x).l" % R(0xff9242), 20)
    # end (SR saved: X stays the original's): the slot credits, the burn, back
    p.lab("bx_end")
    p.i("move.w  sr,(EX_SR).l", 20)
    p.i("move.l  (EX_A1).l,d3", 20)
    p.i("subi.l  #$%06x,d3" % R(P1_START), 16)
    p.i("mulu    #10923,d3", 42 + 2 * bin(10923).count("1"))     # 16 per pass-1 slot
    p.i("swap    d3", 4)
    p.i("add.w   d3,d2", 4)
    for st, start in (("EX_A2", P2_START), ("EX_A3", P3_START), ("EX_AA", PA_START)):
        p.i("move.l  (%s).l,d3" % st, 20)
        p.i("subi.l  #$%06x,d3" % R(start), 16)
        p.i("mulu    #5462,d3", 42 + 2 * bin(5462).count("1"))     # 8 per slot
        p.i("swap    d3", 4)
        p.i("add.w   d3,d2", 4)
    # burn d2 (>= 66, even) cycles exactly: 172 a loop round while >= 252, then the rest
    # (< 252) in two shifts of c1 = c/2 and c - c1 counts (c = rest/2 <= 125)
    p.i("subi.w  #66,d2", 8)
    p.lab("bx_bl")
    p.i("cmpi.w  #252,d2", 8)
    p.b("bcs.s   bx_br", "bx_br", 10, 8)
    p.i("moveq   #63,d3", 4)
    p.i("lsl.l   d3,d3", 134)
    p.i("subi.w  #172,d2", 8)
    p.j("bra.s   bx_bl", "bx_bl", 10)
    p.lab("bx_br")
    p.i("lsr.w   #1,d2", 8)
    p.i("move.w  d2,d3", 4)
    p.i("lsr.w   #1,d3", 8)
    p.i("sub.w   d3,d2", 4)
    p.i("lsl.l   d3,d3", 8)          # + 2 per count
    p.i("lsl.l   d2,d3", 8)          # + 2 per count
    p.i("move.w  (EX_SR).l,sr", 24)
    p.i("movem.l (EX_SV).l,d2-d3", 36)
    p.i("jmp     $2bf9a", 12)
    p.lab("bx_end_x")
    loop_copy(p, "bx_loop2", "EX_A2")
    loop_copy(p, "bx_loop3", "EX_A3")
    loop_copy(p, "bx_loopa", "EX_AA")
    # sort (0x2bffa), verbatim but the emitter calls
    p.lab("bx_sort")
    p.i("tst.w   ($%06x).l" % R(0xff90e6), 16)
    p.b("bne.w   bx_s_alt", "bx_s_alt", 10, 12)
    p.i("movea.l #$%06x,a5" % R(0xff9026), 12)
    p.i("move.w  #$1f,d7", 8)
    p.lab("bx_s_clr")
    p.i("move.w  #$ffff,(a5)+", 12)
    p.i("move.l  #$ffffffff,(a5)+", 20)
    p.b("dbra    d7,bx_s_clr", "bx_s_clr", 10, 14)
    p.i("movea.l #$%06x,a0" % R(0xff42c0), 12)
    p.i("move.w  #$f,d7", 8)
    p.lab("bx_s_o")
    p.i("move.b  (a0),d0", 8)
    p.b("bpl.w   bx_s_on", "bx_s_on", 10, 12)
    p.i("movea.l #$%06x,a5" % R(0xff9026), 12)
    p.i("move.w  $10(a0),d0", 12)
    p.i("addi.w  #$8000,d0", 8)
    p.lab("bx_s_f")
    p.i("cmp.w   (a5),d0", 8)
    p.b("bcs.w   bx_s_ins", "bx_s_ins", 10, 12)
    p.b("beq.w   bx_s_ins", "bx_s_ins", 10, 12)
    p.i("adda.l  #6,a5", 16)
    p.j("bra.s   bx_s_f", "bx_s_f", 10)
    p.lab("bx_s_ins")
    p.i("move.l  a0,d1", 4)
    p.lab("bx_s_sh")
    p.i("move.w  d0,($%06x).l" % R(0xff80d0), 16)
    p.i("move.l  d1,($%06x).l" % R(0xff80d2), 20)
    p.i("move.w  (a5),d0", 8)
    p.i("move.l  2(a5),d1", 16)
    p.i("move.w  ($%06x).l,(a5)+" % R(0xff80d0), 20)
    p.i("move.l  ($%06x).l,(a5)+" % R(0xff80d2), 28)
    p.b("bpl.s   bx_s_sh", "bx_s_sh", 10, 8)
    p.lab("bx_s_on")
    p.i("adda.l  #$60,a0", 16)
    p.b("dbra    d7,bx_s_o", "bx_s_o", 10, 14)
    p.i("movea.l #$%06x,a5" % R(0xff9026), 12)
    p.lab("bx_s_e")
    p.i("move.w  (a5)+,d0", 8)
    p.i("tst.w   (a5)", 8)
    p.b("bmi.w   bx_s_x", "bx_s_x", 10, 12)
    p.i("movea.l (a5)+,a0", 12)
    p.i("bsr.w   bx_obj", 18)
    p.b("bcs.w   bx_s_x", "bx_s_x", 10, 12)
    p.j("bra.s   bx_s_e", "bx_s_e", 10)
    p.lab("bx_s_x")
    p.i("move.l  d4,(EX_AA).l", 20)      # (d4 = the alt pass's start: no slots credited)
    p.i("rts", 16)
    p.lab("bx_s_alt")
    p.i("movea.l #$%06x,a0" % R(0xff42c0), 12)
    p.i("move.l  #$%06x,d4" % R(0xff48c0), 12)
    p.j("bra.w   bx_loopa", "bx_loopa", 10)
    # one object: the original's bsr B / bcs / bsr C / bcs / bsr A / bcs
    p.lab("bx_obj")
    p.i("addi.w  #{k_obj},d2", 8)
    p.i("move.b  $43(a0),d6", 12)
    p.b("bmi.w   bx_o_bp", "bx_o_bp", 10, 12)
    p.lab("bx_o_c")
    p.i("clr.w   d5", 4)
    p.i("movea.l $1a(a0),a3", 16)
    p.i("clr.w   d6", 4)
    p.i("move.b  4(a0),d6", 12)
    p.i("bsr.w   bx_tree", 18)
    p.b("bcs.w   bx_o_cf", "bx_o_cf", 10, 12)
    p.lab("bx_o_a")
    p.i("move.b  $43(a0),d6", 12)
    p.i("btst    #6,d6", 10)
    p.b("bne.w   bx_o_ap", "bx_o_ap", 10, 12)
    p.i("rts", 16)
    p.lab("bx_o_bp")
    p.i("addi.w  #{k_bp},d2", 8)
    p.i("move.w  d6,d5", 4)
    p.i("andi.w  #$10,d5", 8)
    p.i("andi.w  #$f,d6", 8)
    p.i("movea.l $44(a0),a3", 16)
    p.i("bsr.w   bx_tree", 18)
    p.b("bcs.w   bx_o_bf", "bx_o_bf", 10, 12)
    p.j("bra.w   bx_o_c", "bx_o_c", 10)
    p.lab("bx_o_ap")
    p.i("addi.w  #{k_ap},d2", 8)
    p.i("move.w  d6,d5", 4)
    p.i("andi.w  #$10,d5", 8)
    p.i("andi.w  #$f,d6", 8)
    p.i("movea.l $44(a0),a3", 16)
    p.i("bsr.w   bx_tree", 18)
    p.i("rts", 16)
    p.lab("bx_o_cf")
    p.i("addi.w  #{k_cf},d2", 8)
    p.i("move    #$05,ccr", 16)
    p.i("rts", 16)
    p.lab("bx_o_bf")
    p.i("addi.w  #{k_bf},d2", 8)
    p.i("move    #$05,ccr", 16)
    p.i("rts", 16)
    tree(p)
    for v in VARIANTS:
        piece_loop(p, v)

    # ---- debt constants (sums of the adds on every path = original - replica)
    for v in VARIANTS:
        solve_piece(p, v, K)
        K["lk_" + vname(v)] = -p.walk("bx_tree", vname(v), tree_path(v))
    # object, assumed B fails, C, A fails.  Replica: caller's bsr 18, bx_obj up to C
    # (addi 8, move.b 12, bmi.w nt 12), C's set-up 36, bsr bx_tree 18 (the tree: its
    # leaf), the piece loop's closing rts 16, bcs.w nt 12, A's test (12+10+12) and rts
    # 16, the caller's bcs.w nt 12
    r_obj = 18 + 32 + 36 + 18 + 16 + 12 + 50 + 12
    assert p.walk("bx_obj", "bx_o_c", [False]) == 32 and p.walk("bx_o_a", "bx_o_bp", [False]) == 50
    K["k_obj"] = (O_B_FAIL + O_C + O_A_FAIL) - r_obj
    # B passes: bmi taken (-2), its set-up 44 (addi incl.), bsr bx_tree 18, loop rts 16,
    # bcs.w nt 12, bra.w bx_o_c 10
    K["k_bp"] = (O_B_PASS - O_B_FAIL) - (-2 + 44 + 18 + 16 + 12 + 10)
    # A passes: bne.w taken instead of (nt 12 + rts 16): -18; set-up 44, bsr 18, loop
    # rts 16, rts 16
    K["k_ap"] = (O_A_PASS - O_A_FAIL) - (-18 + 44 + 18 + 16 + 16)
    # C full: original: C's caller bcs taken (-2), A skipped; replica: bcs.w taken (-2),
    # A's part skipped (-50), bx_o_cf (8 + 16 + 16), the caller's bcs taken (-2)
    K["k_cf"] = (-2 - O_A_FAIL) - (-2 - 50 + 40 - 2)
    # B full (after k_bp): original: B's bcs taken (-2), C and A skipped; replica: bcs.w
    # taken (-2), bra.w skipped (-10), C's fixed part (36 + 18 + 16 + 12) and A's (50)
    # skipped, bx_o_bf 40, the caller's bcs taken (-2)
    K["k_bf"] = (-2 - O_C - O_A_FAIL) - (-2 - 10 - 82 - 50 + 40 - 2)
    # entry/end fixed costs of the replica (the original has none of them)
    entry = 12 + 32 + 16 + 4 + 16 + 8 + 12
    end = p.walk("bx_end", "bx_bl", []) - 8 + 24 + 36 + 12      # less the burn's own subi
    stores = 20                       # pass 1's move.l a0,(EX_A1).l (the loops' stores: per copy, below)
    loops = 3 * 20                    # bx_loop2/3 stores, and bx_loopa's or the sort's
    K["k0"] = -(entry + end + stores + loops)
    # (bx_loopa's store and the alt path: the original's bra.w 2bfd0 is ours too)
    return p, K


def check_alt(p, K):
    pass
def main():
    p, K = build()
    out = sys.argv[1]
    for k, val in K.items():
        assert -32768 <= val <= 32767, (k, val)
    with open(out, "w") as f:
        f.write("; generated by tools/gen_buildx.py: exact replica of the sprite-list builder\n")
        f.write(p.text(K))
    if len(sys.argv) > 2:
        import json
        json.dump({k: v for k, v in K.items()}, open(sys.argv[2], "w"), indent=0)


if __name__ == "__main__":
    main()
