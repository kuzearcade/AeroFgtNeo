# topng.py DIR: pix.bin (pick.lua) -> DIR/f<frame>.png
import sys, struct, numpy as np
from PIL import Image
d = sys.argv[1]; b = open(d + "/pix.bin", "rb").read(); o = 0
while o < len(b):
    k, w, h = struct.unpack_from("<III", b, o); o += 12
    a = np.frombuffer(b, np.uint8, w * h * 4, o).reshape(h, w, 4); o += w * h * 4
    Image.fromarray(a[:, :, [2, 1, 0]]).save("%s/f%05d.png" % (d, k))
