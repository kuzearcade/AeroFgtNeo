# sheet.py th.npz out.png from to step [cols] : contact sheet of thumbnails labelled with frame numbers
import sys, numpy as np
from PIL import Image, ImageDraw
d = np.load(sys.argv[1]); th = d['th']; fr = d['fr']
a, b, s = map(int, sys.argv[3:6]); cols = int(sys.argv[6]) if len(sys.argv) > 6 else 12
idx = list(range(a, min(b, len(th)), s)); rows = (len(idx)+cols-1)//cols
im = Image.new('RGB', (cols*82, rows*68), (40, 40, 40)); dr = ImageDraw.Draw(im)
for k, i in enumerate(idx):
    x, y = k % cols*82, k//cols*68
    im.paste(Image.fromarray(th[i]), (x+1, y+1)); dr.text((x+2, y+57), str(fr[i]), fill=(255, 255, 0))
im = im.resize((im.width*2, im.height*2), Image.NEAREST); im.save(sys.argv[2])
