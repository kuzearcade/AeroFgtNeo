"""tiles_cat.py: tilemap tiles in use per stage (census tiles.txt) -> work/catalog/tiles/{tiles.tsv,summary.txt,atlas_<stage>_L<n>.png}"""
import os, sys, glob, hashlib, collections, numpy as np
from PIL import Image
R = os.path.expanduser('~/AeroFgtNeo'); sys.path.insert(0, R + '/tools'); sys.path.insert(0, R + '/tests')
import romset, gfx
from compare_bg import neo_rgb_table
exec(open(R + '/work/play/categories.py').read().split('CAT = {')[0].split('C = ')[0])
C = R + '/work/play/cen'; O = R + '/work/catalog/tiles'
STAGE = eval(open(R + '/work/play/categories.py').read().split('STAGE = ')[1].split('\nCAT')[0])
H = {}
for f in glob.glob(C + '/lut_*.bin'): H[int(f[-7:-4])] = hashlib.md5(open(f, 'rb').read()).hexdigest()[:8]
sc = {}; last = '?'
for l in open(C + '/scenes.txt'):
    s = int(l.split()[0]); sc[s] = STAGE.get(H.get(s, ''), H.get(s, '?'))
use = collections.defaultdict(collections.Counter); colr = collections.defaultdict(collections.Counter); stage_scene = {}
for l in open(C + '/tiles.txt'):
    s, layer, code, col, n = l.split(); s = int(s); st = sc.get(s, '?'); code = int(code, 16)
    use[(st, int(layer))][code] += int(n); colr[(st, int(layer), code)][int(col)] += int(n); stage_scene.setdefault(st, s)
t8 = gfx._unpack_tiles8(romset.load_aerofgt(R + '/mame_roms/aerofgt.zip')['tiles']).astype(int); rgb = neo_rgb_table()
allc = collections.Counter(); per_stage = collections.defaultdict(set)
with open(O + '/tiles.tsv', 'w') as o:
    o.write('stage\tlayer\tcode\tuses\tcolour\n')
    for (st, layer), cnt in sorted(use.items()):
        for code, n in cnt.most_common():
            o.write('%s\t%d\t%05x\t%d\t%d\n' % (st, layer, code, n, colr[(st, layer, code)].most_common(1)[0][0]))
            allc[(layer, code)] += n; per_stage[(layer, code)].add(st)
with open(O + '/summary.txt', 'w') as o:
    o.write('unique tilemap tiles in the playthrough: layer 0 %d, layer 1 %d (of 32768 in the ROM)\n' % (
        sum(1 for k in allc if k[0] == 0), sum(1 for k in allc if k[0] == 1)))
    o.write('tiles used by more than one stage: %d\n\n' % sum(1 for v in per_stage.values() if len(v) > 1))
    o.write('%-26s %8s %8s\n' % ('stage', 'L0 tiles', 'L1 tiles'))
    for st in sorted(set(k[0] for k in use)):
        o.write('%-26s %8d %8d\n' % (st, len(use[(st, 0)]), len(use[(st, 1)])))
for (st, layer), cnt in use.items():
    s = stage_scene[st]; pf = C + '/pal_%03d.bin' % s
    pal = np.frombuffer(open(pf, 'rb').read(), '>u2').astype(int) if os.path.exists(pf) else np.arange(1024)
    codes = sorted(cnt); n = len(codes); cols = 64; rows = (n + cols - 1) // cols
    img = np.zeros((rows * 9, cols * 9, 3), np.uint8)
    for i, code in enumerate(codes):
        t = t8[code & 0x7fff]; c = colr[(st, layer, code)].most_common(1)[0][0]
        cc = rgb[pal[layer * 256 + 16 * c + t] & 0x7fff]
        blk = np.stack([(cc >> 16) & 255, (cc >> 8) & 255, cc & 255], -1).astype(np.uint8)
        if layer == 1: blk[t == 15] = (40, 0, 40)
        y, x = (i // cols) * 9, (i % cols) * 9; img[y:y + 8, x:x + 8] = blk
    Image.fromarray(img).resize((cols * 18, rows * 18), Image.NEAREST).save('%s/atlas_%s_L%d.png' % (O, st.replace(' ', '_').replace('/', '-'), layer))
print(open(O + '/summary.txt').read())
