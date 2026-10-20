"""Frames whose picture differs although no slip was logged (conversion errors):
unlogged.py npal.bin full_report.txt [offset]"""
import ast, struct, sys
d = open(sys.argv[1], 'rb').read(); R = 24 + 0x2000
slip = {}
for i in range(len(d) // R):
    gf = struct.unpack_from('<I', d, i * R)[0]
    slip[gf] = struct.unpack_from('<H', d, i * R + 12)[0]
bad = ast.literal_eval(open(sys.argv[2]).read().strip().split('\n')[-1])
off = int(sys.argv[3]) if len(sys.argv) > 3 else 1
# the picture of game frame k is shown in slot k + off: slips logged there (or the slot before)
un = [(k, px) for k, px in bad if not any(slip.get(k + o, 0) for o in (off - 1, off, off + 1))]
print('differing frames %d, with no slip logged nearby %d' % (len(bad), len(un)))
print(un[:30])
