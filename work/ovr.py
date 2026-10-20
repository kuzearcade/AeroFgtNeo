import sys,bisect,collections; sys.path.insert(0,'tests')
import hallog
log=hallog.load(sys.argv[1] if len(sys.argv)>1 else "work/eq/hal.bin")
syms=[]; f=False
for l in open('out/build/hal.lst'):
    if 'Symbols by value' in l: f=True; continue
    if f:
        p=l.split()
        if len(p)==2:
            try: syms.append((int(p[0],16),p[1]))
            except: pass
syms.sort(); k=[s[0] for s in syms]
def sym(a):
    i=bisect.bisect_right(k,a)-1; return syms[i][1]
c=collections.Counter(); prev=0; fr=[]
for gf in sorted(log):
    g=log[gf]; o=g('HAL_OVERRUN',4)
    if o!=prev: c[(sym(g('HAL_DBG_OVRPC',4)))]+=1; prev=o; fr.append((gf,g('HAL_DBG_OVRLN'),g('HAL_DEADLINE')))
print(c); print(fr[:20])
