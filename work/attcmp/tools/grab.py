# grab.py out.png src:frame ... : full-res frames side by side (src = orig|neo|s_orig|s_neo pix.bin by frame number, mis = capture index)
import sys, numpy as np, os
from PIL import Image, ImageDraw
W, H = 320, 224; rec = 12 + W*H*4; ims = []
for a in sys.argv[2:]:
    s, f = a.split(':'); f = int(f)
    if s == 'mis':
        m = np.memmap(os.path.expanduser('~/AeroFgtNeo/work/attcmp/mister.rgb'), np.uint8, 'r').reshape(-1, H, W, 3); px = np.array(m[f])
    else:
        p = os.path.expanduser(f'~/AeroFgtNeo/work/attcmp/{s}' + ('' if s.endswith('.bin') else '/pix.bin')); mm = np.memmap(p, np.uint8, 'r')
        n = len(mm)//rec; fr = np.ndarray((n,), '<u4', mm, 0, (rec,)); i = int(np.searchsorted(fr, f)); o = i*rec
        assert fr[i] == f, (a, fr[i])
        px = np.asarray(mm[o+12:o+rec]).reshape(H, W, 4)[:, :, 2::-1]
    ims.append((a, px))
im = Image.new('RGB', (len(ims)*(W+4), H+14), (60, 60, 60)); dr = ImageDraw.Draw(im)
for k, (a, px) in enumerate(ims):
    im.paste(Image.fromarray(np.ascontiguousarray(px)), (k*(W+4), 14)); dr.text((k*(W+4)+2, 1), a, fill=(255, 255, 0))
im = im.resize((im.width*2, im.height*2), Image.NEAREST); im.save(sys.argv[1])
