"""Cycle model of the original sprite-piece emitter (0x2c0b4 / 0x2c0d2 / 0x2c0ec, loop
0x2c0f8): cycles from the entry instruction to the rts (rts excluded), from the object
fields and the piece tables in ROM.  Validated against MAME debugger logs (work/emit)."""
import struct, sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import romset
ROM = bytes(romset.load_aerofgt(os.path.join(os.path.dirname(__file__), '..', 'mame_roms', 'aerofgt.zip'))["maincpu"])
def rb(a): return ROM[a]
def rw(a): return struct.unpack_from('>H', ROM, a)[0]
def rl(a): return struct.unpack_from('>I', ROM, a)[0]
END_CLEAR, END_FULL = 20, 20        # andi/ori #,sr before the rts

def piece(a3, f, a1):
    """one piece from 0x2c0f8 up to 0x2c202 (excluded): (cycles, a1, buffer full)."""
    c = 12 + 12 + 12 + 8                                    # movea (a3),a4 .. cmpi #$fee0
    y = (f['y'] + rw(a3 + 4)) & 0xffff
    if y >= 0xfee0: c += 10
    else:
        c += 12 + 8
        if y >= 0xe0: return c + 10, a1, False              # off screen (y)
        c += 12
    c += 16 + 8 + 12 + 16                                   # add scroll .. cmpi #$2e
    c += (12 + 12) if f['k2e'] else 10
    c += 22 + 14 + 4 + 8 + 22 + 4 + 8                       # .. move.w d0,(a1)+
    c += 12 + 12 + 8                                        # x .. cmpi #$ff40
    x = (f['x'] + rw(a3 + 6)) & 0xffff
    if x >= 0xff40: c += 10
    else:
        c += 12 + 8
        if x < 0x140: c += 10
        else: return c + 12 + 10 + 10, a1, False           # off screen (x): w0 undone
    c += 16 + 8 + 12 + 16
    c += (12 + 12) if f['k2e'] else 10
    c += 22 + 14 + 4 + 8 + 22 + 4 + 8                       # .. move.w d0,(a1)+
    c += 12 + 12                                            # move.b 12(a3) .. tst.b 5(a0)
    if f['b5'] & 0x80:
        c += 12 + 4
        c += 10 if f['d5'] else (12 + 12)
    else: c += 10
    c += 8 + 12                                             # andi #$f .. tst.b 25(a0)
    c += (12 + 12 + 8 + 16 + 4 + 10) if f['b25'] & 0x80 else (10 + 8)
    c += 12                                                 # move.b 42(a0),d1
    c += 10 if f['b42'] else (12 + 12 + 20 + 4 + 12 + 18)
    c += 4 + 22 + 16 + 8 + 8 + 16 + 8 + 12 + 4 + 4 + 12 + 8 + 8 + 8 + 4 + 8
    a1 += 8
    if a1 & 0x3ff == 0: return c + 10, a1, True             # buffer full: -> 0x2c212
    return c + 12, a1, False

def emitter(entry, f, a1):
    """cycles from entry to the rts (excluded)."""
    if entry == 0x2c0d2:
        c = 12
        if not f['b43'] & 0x80: return c + 10 + END_CLEAR, a1
        c += 12 + 4 + 8 + 8 + 16 + 10
        a3, n, d5 = f['p44'], f['b43'] & 0xf, f['b43'] & 0x10
    elif entry == 0x2c0b4:
        c = 12 + 10
        if not f['b43'] & 0x40: return c + 10 + END_CLEAR, a1
        c += 12 + 4 + 8 + 8 + 16 + 10
        a3, n, d5 = f['p44'], f['b43'] & 0xf, f['b43'] & 0x10
    else:
        c = 4 + 16 + 4 + 12
        a3, n, d5 = f['p1a'], f['b4'], 0
    f = dict(f, d5=d5)
    tot = c
    for i in range(n + 1):
        pc, a1, full = piece(a3, f, a1)
        a3 += 14
        if full: return tot + pc + END_FULL, a1
        tot += pc + 16 + (10 if i < n else 14)              # adda #$e,a3 ; dbf
    return tot + END_CLEAR, a1

def parse(path):
    calls = []; cur = None
    for l in open(path):
        p = l.split()
        if not p: continue
        if p[0] == 'E':
            v = [int(x, 16) for x in p[1:2]] + [int(p[2])] + [int(x, 16) for x in p[3:]]
            pc, tc, a0, a1, b43, p44, p1a, b4, y, x, k16, b5, b25, b42, b1 = v[:15]
            sy, sx = v[15], v[16]
            cur = (pc - 2, tc, a1, dict(b43=b43, p44=p44, p1a=p1a, b4=b4, y=y, x=x, k2e=(k16 == 0x2e), b5=b5, b25=b25, b42=b42))
        elif p[0] == 'X' and cur:
            calls.append((cur, int(p[2]), int(p[3], 16))); cur = None
    return calls

if __name__ == '__main__':
    calls = parse(sys.argv[1]); bad = 0
    for (entry, tc, a1, f), tx, a1x in calls:
        m, a1m = emitter(entry, f, a1)
        if m != tx - tc or a1m != a1x:
            bad += 1
            if bad <= 10: print('mismatch', hex(entry), 'measured', tx - tc, 'model', m, 'a1', hex(a1x), hex(a1m), f)
    print('calls', len(calls), 'mismatches', bad)
