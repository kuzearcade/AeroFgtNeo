#!/usr/bin/env python3
"""tabmerge.py <tab_*/out.txt>...: the piece tables the per-nation census (tabcen.lua) saw that the
catalogue (work/catalog/sprites/objects.json) lacks, added to it under the key "nations" (table,
pieces, kind, the first type seen) so that tools/aerofgt2neo.py's fz_pd_prepare rewrites their
entries as descriptors too.  Prints what was added.  The catalogue is backed up as objects.json.bak once."""
import sys, json, os, shutil
P = 'work/catalog/sprites/objects.json'
if not os.path.exists(P + '.bak'): shutil.copy(P, P + '.bak')
d = json.load(open(P))
have = {}
for lst in d.values():
    for e in lst: have[e['table']] = max(have.get(e['table'], 0), e['pieces'])
new = {}
for fn in sys.argv[1:]:
    for l in open(fn):
        f = l.split()
        if len(f) < 5: continue
        t, p, k, ty = int(f[0], 16), int(f[1]), f[2], f[3]
        if t >= 0x80000 or t & 1: continue
        if have.get(t, 0) >= p: continue
        if new.get(t, (0,))[0] >= p: continue
        new[t] = (p, k, ty)
old = {e['table']: e for e in d.get('nations', [])}
for t, (p, k, ty) in new.items():
    old[t] = dict(table=t, kind=k, frames=0, first=0, pieces=max(p, old.get(t, {}).get('pieces', 0)), scenes=[], defs=[], type=ty)
d['nations'] = sorted(old.values(), key=lambda e: e['table'])
json.dump(d, open(P, 'w'))
print("catalogue tables %d; added/updated %d (now %d under nations)" % (len(have), len(new), len(d['nations'])))
for t, (p, k, ty) in sorted(new.items())[:20]: print("  %06x pieces %d %s type %s" % (t, p, k, ty))
