"""render_objs.py: per object type (census work/play/cen), its animation tables' frames composited
from the ROM piece tables, the scene's lookup RAM and palette -> work/catalog/sprites/type_XXXX.png,
plus sheets of all types (sheet_N.png) and objects.json (per table: size, tiles, scenes)."""
import os, sys, struct, json, collections, numpy as np
from PIL import Image, ImageDraw
R = os.path.expanduser('~/AeroFgtNeo'); sys.path.insert(0, R + '/tools'); sys.path.insert(0, R + '/tests')
import romset, gfx
from compare_bg import neo_rgb_table
C = R + '/work/play/cen'; O = R + '/work/catalog/sprites'
rom = open('/tmp/claude-1000/-home-vboxuser-AeroFgtNeo/560dbddd-2c54-4bd4-b6db-4e3d9472357d/scratchpad/orig_main.bin', 'rb').read()
w = lambda a: struct.unpack_from('>H', rom, a)[0]; l = lambda a: struct.unpack_from('>I', rom, a)[0]
sw = lambda v: v - 0x10000 if v & 0x8000 else v
r = romset.load_aerofgt(R + '/mame_roms/aerofgt.zip'); spr = gfx._unpack_sprites(r['sprites']); rgb = neo_rgb_table()
luts = {}; pals = {}
def lut(s):
    while s > 0 and not os.path.exists('%s/lut_%03d.bin' % (C, s)): s -= 1
    if s not in luts: luts[s] = np.frombuffer(open('%s/lut_%03d.bin' % (C, s), 'rb').read(), '>u2').astype(int)
    return luts[s]
def pal(s):
    while s > 0 and not os.path.exists('%s/pal_%03d.bin' % (C, s)): s -= 1
    if s not in pals: pals[s] = np.frombuffer(open('%s/pal_%03d.bin' % (C, s), 'rb').read(), '>u2').astype(int)
    return pals[s]
def render(t, n, scene):
    L = lut(scene); Pl = pal(scene); pieces = []
    for i in range(min(n, 31) + 1):
        pa = t + 14 * i
        if pa + 14 > len(rom): break
        a4 = l(pa) & 0xfffffe
        if a4 + 4 > len(rom): continue
        sz = w(a4); mp = w(a4 + 2)
        ys = (sz >> 9) & 7; xs = (sz >> 1) & 7
        dy = sw(w(pa + 4)); dx = sw(w(pa + 6)); fy = rom[pa + 8] & 1; fx = (rom[pa + 9] >> 0) & 1; fy |= (rom[pa + 9] >> 1) & 1
        col = rom[pa + 12] & 15
        pieces.append((dy, dx, ys, xs, mp, fy, fx, col))
    if not pieces: return None, 0
    y0 = min(p[0] for p in pieces); x0 = min(p[1] for p in pieces)
    y1 = max(p[0] + 16 * (p[2] + 1) for p in pieces); x1 = max(p[1] + 16 * (p[3] + 1) for p in pieces)
    if y1 - y0 > 512 or x1 - x0 > 512: return None, 0
    img = np.zeros((y1 - y0, x1 - x0, 3), np.uint8) + 24; ntiles = 0
    for dy, dx, ys, xs, mp, fy, fx, col in reversed(pieces):
        base = mp
        k0 = L[base & 0x3fff] & 0x7fff
        if not spr[k0].any() or (spr[k0] == 15).all():
            base = mp | 0x2000                      # (a pass-1 object's half of the lookup)
        k = base
        for yi in range(ys + 1):
            for xi in range(xs + 1):
                code = int(L[k & 0x3fff]) & 0x7fff; k += 1; ntiles += 1
                tl = spr[code].astype(int)
                if fx: tl = tl[:, ::-1]
                if fy: tl = tl[::-1, :]
                yy = (ys - yi if fy else yi) * 16 + dy - y0; xx = (xs - xi if fx else xi) * 16 + dx - x0
                m = tl != 15
                c = rgb[Pl[512 + 16 * col + tl] & 0x7fff]
                rgbv = np.stack([(c >> 16) & 255, (c >> 8) & 255, c & 255], -1).astype(np.uint8)
                sub = img[yy:yy + 16, xx:xx + 16]
                sub[m] = rgbv[m]
    return Image.fromarray(img), ntiles
objs = collections.defaultdict(list)
for line in open(C + '/objects.txt'):
    p = line.split(); ty, t, kind = p[0], int(p[1], 16), p[2]
    d = dict(zip(p[3::2], p[4::2]))
    objs[ty].append(dict(table=t, kind=kind, frames=int(d['frames']), first=int(d['first']), pieces=int(d['pieces']),
                         scenes=[int(x) for x in d['scenes'].split(',') if x], defs=d.get('defs', '').split(',')))
out = {}; thumbs = []
for ty in sorted(objs, key=lambda x: int(x, 16)):
    ims = []
    for e in sorted(objs[ty], key=lambda e: -e['frames']):
        if e['table'] >= 0x80000: e['ram'] = True; continue
        im, nt = render(e['table'], e['pieces'] - 1, e['scenes'][0] if e['scenes'] else 0)
        e['tiles'] = nt
        if im: e['size'] = list(im.size); ims.append((e, im))
    out[ty] = objs[ty]
    if not ims: continue
    W = 1200; x = y = rh = 0; pos = []
    for e, im in ims[:60]:
        if x + im.size[0] + 8 > W: x = 0; y += rh + 14; rh = 0
        pos.append((x, y)); x += im.size[0] + 8; rh = max(rh, im.size[1])
    sh = Image.new('RGB', (W, y + rh + 14), (0, 0, 0)); dr = ImageDraw.Draw(sh)
    for (e, im), (px, py) in zip(ims[:60], pos):
        sh.paste(im, (px, py + 12)); dr.text((px, py), '%05x' % e['table'], fill=(255, 255, 0))
    sh.save('%s/type_%s.png' % (O, ty))
    thumbs.append((ty, ims[0][1], sum(e['frames'] for e in objs[ty]), len(objs[ty])))
# overview sheets: per type its most used frame
per = 16; cell = 150
for s in range(0, len(thumbs), per):
    sh = Image.new('RGB', (4 * cell, ((min(per, len(thumbs) - s) + 3) // 4) * (cell + 28)), (0, 0, 0)); dr = ImageDraw.Draw(sh)
    for i, (ty, im, fr, nt) in enumerate(thumbs[s:s + per]):
        im2 = im.copy(); im2.thumbnail((cell - 6, cell - 6))
        px, py = (i % 4) * cell, (i // 4) * (cell + 28)
        sh.paste(im2, (px, py + 26)); dr.text((px, py), 'type %s  %d tbl' % (ty, nt), fill=(255, 255, 0)); dr.text((px, py + 12), '%d obj-frames' % fr, fill=(200, 200, 200))
    sh.save('%s/overview_%02d.png' % (O, s // per))
json.dump(out, open(O + '/objects.json', 'w'))
print(len(thumbs), 'types rendered')
