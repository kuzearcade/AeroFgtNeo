# thumbs.py pix.bin out.npz : per-frame 80x56 RGB thumbnails (4x4 mean) + full-res fix-layer-region crops kept separately
import sys, numpy as np, os
f = sys.argv[1]; W, H = 320, 224; rec = 12 + W*H*4
n = os.path.getsize(f)//rec
mm = np.memmap(f, dtype=np.uint8, mode='r')
th = np.zeros((n, 56, 80, 3), np.uint8); fr = np.zeros(n, np.int32)
for i in range(n):
    o = i*rec
    fr[i] = int.from_bytes(mm[o:o+4].tobytes(), 'little')
    px = np.asarray(mm[o+12:o+rec]).reshape(H, W, 4)[:, :, 2::-1].astype(np.uint16)  # BGRA -> RGB
    th[i] = (px.reshape(56, 4, 80, 4, 3).mean((1, 3))).astype(np.uint8)
np.savez_compressed(sys.argv[2], th=th, fr=fr)
print(n, fr[0], fr[-1])
