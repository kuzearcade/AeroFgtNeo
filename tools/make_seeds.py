"""Merge MAME coverage bitmaps (MAME_COVERAGE_DIR) into analysis/code_seeds.txt.

The seed list holds only executed instruction addresses (no ROM content); the
converter uses it to find code reached through indirect jumps.
"""
import os
import sys

size = 0x80000
cov = bytearray(size // 8)
for p in sys.argv[2:]:
    c = open(p, 'rb').read()
    for i in range(len(cov)):
        cov[i] |= c[i]
old = set()
if os.path.exists(sys.argv[1]):
    for line in open(sys.argv[1]):
        line = line.strip()
        if line and not line.startswith('#'):
            old.add(int(line, 16))
pcs = sorted(old | {a for a in range(size) if cov[a >> 3] >> (a & 7) & 1})
with open(sys.argv[1], 'w') as f:
    f.write('# executed 68K instruction starts observed in MAME (aerofgt), merged\n')
    for a in pcs:
        f.write('%06x\n' % a)
print(len(old), '->', len(pcs))
