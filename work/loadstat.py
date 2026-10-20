"""Harvested vs probe frames: sprite entries in the list, HAL budget (lines).
loadstat.py hal.bin neo.bin"""
import collections, statistics, struct, sys
sys.path.insert(0, '/home/vboxuser/AeroFgtNeo/tests')
import hallog
import compare_state as cs
L = hallog.load(sys.argv[1])
SPR = 0x1d000                           # sprram offset in a record body
st = collections.defaultdict(lambda: collections.defaultdict(list))
for fa, d in cs.frames(sys.argv[2]):
    if fa not in L or fa - 1 not in L or fa < 200:
        continue
    g = L[fa]
    kind = 'idle' if g('HAL_IDLES', 4) != L[fa - 1]('HAL_IDLES', 4) else 'probe'
    ram = struct.unpack_from('>512H', d, SPR)
    n = 0
    for w in ram:
        if w & 0x4000:
            break
        if not w & 0x8000:
            n += 1
    st[kind]['entries'].append(n)
    st[kind]['deadline'].append(g('HAL_DEADLINE', 2))
for k, v in st.items():
    print('%-5s frames %5d  entries mean %5.1f  deadline lines mean %5.1f min %d' % (
        k, len(v['entries']), statistics.mean(v['entries']), statistics.mean(v['deadline']), min(v['deadline'])))
