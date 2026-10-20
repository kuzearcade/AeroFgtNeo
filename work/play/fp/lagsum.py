"""lagsum.py <lag.txt>...: totals of a lag2.lua run: lost logic frames, late, drops, overruns, holds, busy"""
import sys, collections
STG = {0xa0b4faad: 'intro/map', 0x91b430ec: 'bases/attract', 0xe2f47afa: 'coast/river', 0x634fcf44: 'cities', 0x6da96bff: 'desert', 0x018c6b86: 'ocean', 0xc39339a2: 'runway', 0x786ebae6: 'final'}
import glob
for fn in [f for a in sys.argv[1:] for f in sorted(glob.glob(a))]:
    L = [l.split() for l in open(fn)]; L = [l for l in L if len(l) >= 8 and int(l[0]) >= 450]
    n = len(L); lag = sum(1 for l in L if int(l[1]) >= 1); a, b = L[0], L[-1]
    d = lambda i: int(b[i]) - int(a[i])
    per = collections.Counter(); perl = collections.Counter(); perlate = collections.Counter()
    prev = int(a[2])
    for l in L:
        s = STG.get(int(l[7], 16), 'other'); per[s] += 1; perl[s] += int(l[1]) >= 1; perlate[s] += int(l[2]) - prev; prev = int(l[2])
    ex = ''
    if len(b) >= 13: ex = ' drops %d dropframes %d overruns %d paldefer %d nowalk %d' % (d(8), d(9), d(10), d(11), d(12))
    if len(b) >= 15: ex += ' unfinished-walks %d carried %d' % ((int(b[13]) - int(a[13])) & 0xffff, d(14))
    print('%-40s frames %6d lost-logic %5d (%.2f%%) late %5d (%.2f%%) holds %d busy %d%s' % (fn, n, lag, 100 * lag / n, d(2), 100 * d(2) / n, d(3), sum(1 for l in L if int(l[6])), ex))
    print('   by stage lag%%/late%%: ' + ', '.join('%s %.1f/%.1f (%d)' % (s, 100 * perl[s] / per[s], 100 * perlate[s] / per[s], per[s]) for s in sorted(per, key=lambda s: -per[s])))
