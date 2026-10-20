"""lstprof.py <hal.lst> <trdir> <lineA> <lineB>: per-instruction counts/cycles (whole trace) for listing lines A..B"""
import sys, glob, re, collections
lst = open(sys.argv[1], errors='replace').read().split('\n'); A, B = int(sys.argv[3]), int(sys.argv[4])
cnt = collections.Counter(); cyc = collections.Counter()
for f in glob.glob(sys.argv[2] + '/c*/pc.txt'):
    for l in open(f):
        p = l.split(); a = int(p[0], 16); cnt[a] += int(p[1]); cyc[a] += int(p[2])
N = 200000; tot = 0
for i in range(A - 1, B):
    m = re.match(r'00:([0-9A-F]{8}) ', lst[i])
    if m:
        a = int(m.group(1), 16); tot += cyc[a]
        print('%8.2f %9.0f  %s' % (cnt[a] / N, cyc[a] / N, lst[i][28:110]))
    else:
        print('%8s %9s  %s' % ('', '', lst[i][28:110]))
print('total cycles/frame', tot / N)
