"""ssan.py dump...: self-split drops (dumpl2.lua): do the converting list's remaining
entries (from the dropped one on) match the shown list's back entries, in order from the
back (each looked for among the next LOOK shown entries, shape/zoom/attrs/tiles equal)?"""
import sys, collections
LOOK = 8
def vis(w0, w1):
    y = w0 & 0x1ff
    if y >= 224 and y + ((w0 & 0xe00) >> 5) <= 512 - 16: return False
    x = w1 & 0x1ff
    if x >= 320 and x + ((w1 & 0xe00) >> 5) <= 512 - 16: return False
    return True
def parse(s):
    return [tuple(int(e[i:i + 4], 16) for i in range(0, 16, 4)) for e in s.split(',') if e]
def key(e): return (e[0] & 0xfe00, e[1] & 0xfe00, e[2], e[3])
cls = collections.Counter(); hist = collections.Counter(); tot = collections.Counter()
for fn in sys.argv[1:]:
    L = open(fn).read().splitlines()
    i = 0
    while i + 2 < len(L):
        if ' M ' not in L[i]: i += 1; continue
        m = dict(kv.split('=') for kv in L[i].split()[2:])
        C = parse(L[i + 1].split(' C ')[1] if ' C ' in L[i + 1] else '')
        S = parse(L[i + 2].split(' S ')[1] if ' S ' in L[i + 2] else '')
        i += 3
        W, sps, idx = int(m['W']), int(m['sps']), int(m['idx'])
        kind = 'self' if sps == W else 'shown'
        if idx < 0 or idx >= len(C): cls[kind, 'badidx'] += 1; continue
        R = [e for e in C[idx:] if vis(e[0], e[1])]
        Sv = [e for e in S if vis(e[0], e[1])]
        # match R from its back against Sv from its back
        j = len(Sv); n = 0
        for e in reversed(R):
            found = False
            for k in range(j - 1, max(-1, j - 1 - LOOK), -1):
                if key(Sv[k]) == key(e): j = k; found = True; break
            if not found: break
            n += 1
        full = n == len(R)
        cls[kind, 'full' if full else ('part' if n else 'none')] += 1
        tot[kind, 'rem'] += len(R); tot[kind, 'matched'] += n
        if kind == 'self': hist[min(len(R) - n, 20)] += 1
print('drop frames by kind/outcome:', dict(cls))
print('entries remaining / matched:', dict(tot))
print('self-split: unmatched remaining entries (0 = all shareable):', sorted(hist.items()))
