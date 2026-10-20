"""Sprite/slot statistics from a HARNESS_HALLOG dump: sprstat.py hal.bin [first last]"""
import sys
sys.path.insert(0, '/home/vboxuser/AeroFgtNeo/tests')
import hallog
L = hallog.load(sys.argv[1])
ks = sorted(L)
lo = int(sys.argv[2]) if len(sys.argv) > 2 else ks[0]
hi = int(sys.argv[3]) if len(sys.argv) > 3 else ks[-1]
names = ['HAL_SPR_CARRY', 'HAL_SPR_LATE', 'HAL_SPR_MIXN', 'HAL_SPR_DROP', 'HAL_SPR_DROPN', 'HAL_SPR_VZN', 'HAL_OVERRUN', 'HAL_LATEWAKE', 'HAL_IDLES']
a, b = L[max(k for k in ks if k <= lo)], L[min(k for k in ks if k >= hi)]
print('frames %d..%d: ' % (lo, hi) + ' '.join('%s=%d' % (n[4:], b(n, 4) - a(n, 4)) for n in names))
