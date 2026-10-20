# neovram.py vram.bin frame [xmin xmax]: Neo sprite columns on screen (resolved chains) with their tiles
import sys, numpy as np
f = open(sys.argv[1], 'rb').read(); rec = 4 + 0x8800*2; want = int(sys.argv[2])
xmin, xmax = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (0, 320)
for k in range(len(f)//rec):
    if int.from_bytes(f[k*rec:k*rec+4], 'little') == want: v = np.frombuffer(f[k*rec+4:(k+1)*rec], '>u2'); break
y = h = x = 0
for n in range(1, 381):
    s3 = v[0x8200+n]; s4 = v[0x8400+n]; s2 = v[0x8000+n]
    if s3 & 0x40: x = (x + 16) & 0x1ff   # sticky: (ignores shrink width)
    else: y = 496 - (s3 >> 7); h = s3 & 0x3f; x = s4 >> 7
    if h == 0: continue
    sx = x if x < 0x1e0 else x - 0x200
    if not (xmin <= sx < xmax): continue
    tiles = [(int(v[n*64+2*i]) | ((int(v[n*64+2*i+1]) >> 4 & 0xf) << 16), int(v[n*64+2*i+1]) >> 8) for i in range(min(h, 32))]
    nz = [(t, p) for t, p in tiles if t]
    print(f"spr {n:3d} x {sx:4d} y {y:4d} h {h:2d} {'S' if s3 & 0x40 else 'H'} shrink {s2:04x} tiles {len(nz)} first {nz[:3]}")
