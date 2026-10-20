"""cmpwchk.py a.txt b.txt: walks done in their own slot in both runs: same list?"""
import sys
def ld(f):
    d = {}
    for l in open(f):
        p = l.split()
        if len(p) >= 4: d[int(p[0])] = p[1:]
    return d
a, b = ld(sys.argv[1]), ld(sys.argv[2])
com = sorted(set(a) & set(b)); bad = [k for k in com if a[k][:3] != b[k][:3]]
print('walks a %d b %d both %d differ %d' % (len(a), len(b), len(com), len(bad)), bad[:10])
for k in bad[:3]:
    x, y = a[k], b[k]
    if len(x) > 3 and len(y) > 3:
        for e in range(0, max(len(x[3]), len(y[3])), 16):
            u, v = x[3][e:e + 16], y[3][e:e + 16]
            print(k, e // 16, u, v, '' if u == v else '<--')
