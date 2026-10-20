"""Where the virtual vblank interrupts the game: irqpc.py hal.bin neo.bin
Histogram of interrupted PCs (from the IRQ frame at HAL_SAVED_SP in the harness dump),
for harvested (idle entry) and probe frames."""
import collections, struct, sys
sys.path.insert(0, '/home/vboxuser/AeroFgtNeo/tests')
import hallog
import compare_state as cs
L = hallog.load(sys.argv[1])
h = {'idle': collections.Counter(), 'probe': collections.Counter()}
prev = None
for fa, d in cs.frames(sys.argv[2]):
    if fa not in L or fa - 1 not in L:
        continue
    g = L[fa]
    kind = 'idle' if g('HAL_IDLES', 4) != L[fa - 1]('HAL_IDLES', 4) else 'probe'
    sp = g('HAL_SAVED_SP', 4)
    off = sp - 0x100000
    if not 0 <= off < 0x10000 - 6:
        h[kind]['sp?%06x' % sp] += 1
        continue
    pc = struct.unpack_from('>I', d, off + 2)[0]
    h[kind][pc] += 1
for k, c in h.items():
    print(k, sum(c.values()))
    for pc, n in c.most_common(15):
        print('   %s %d' % (pc if isinstance(pc, str) else '%06x' % pc, n))
