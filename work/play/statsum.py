"""statsum.py <outdir>...: totals of the per-chunk HAL counter deltas (runstat.sh output)"""
import sys, glob
for O in sys.argv[1:]:
    t = [0] * 4; nf = 0
    for f in glob.glob(O + '/c*.txt'):
        L = [l.split() for l in open(f)]
        L = [l for l in L if len(l) == 6]
        if len(L) < 2: continue
        a, b = L[0], L[-1]; nf += int(b[0]) - int(a[0])
        for i in range(4): t[i] += int(b[i + 1]) - int(a[i + 1])
    print('%-28s frames %6d late %5d (%.2f%%) dropped %5d frames-with-drops %5d (%.2f%%) overruns %d' % (
        O.split('/')[-1], nf, t[0], 100 * t[0] / max(nf, 1), t[1], t[2], 100 * t[2] / max(nf, 1), t[3]))
