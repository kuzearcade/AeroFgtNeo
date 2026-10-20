"""hal_cat.py: every global HAL routine (hal/*.s, the build's hal.lst addresses) with the comment block
above it -> work/catalog/neo_hal_routines.tsv (file, label, address, size, description)"""
import re, glob, os
R = os.path.expanduser('~/AeroFgtNeo')
addr = {m.group(2): int(m.group(1), 16) for m in re.finditer(r'^([0-9A-F]{8}) ([A-Za-z_]\w*)$', open(R + '/work/out_ow/build/hal.lst').read(), re.M)}
rows = []
for f in sorted(glob.glob(R + '/hal/*.s')):
    lines = open(f, errors='ignore').read().split('\n'); com = []
    for i, l in enumerate(lines):
        m = re.match(r'^([A-Za-z_]\w*):', l)
        if l.startswith(';'):
            com.append(l.lstrip('; ').rstrip())
        elif m:
            name = m.group(1)
            if name in addr:
                desc = ' '.join(c for c in com if c and not set(c) <= set('=-'))
                rows.append((os.path.basename(f), name, addr[name], desc))
            com = []
        elif l.strip() and not l.strip().startswith(('if', 'else', 'endif', 'include', 'even')) and not re.match(r'^\w+\s+equ', l):
            com = []
rows.sort(key=lambda r: r[2]); A = [r[2] for r in rows]
with open(R + '/work/catalog/neo_hal_routines.tsv', 'w') as o:
    o.write('file\tlabel\taddress\tsize\tdescription\n')
    for k, (f, n, a, d) in enumerate(rows):
        size = (A[k + 1] - a) if k + 1 < len(A) else 0
        o.write('%s\t%s\t%06x\t%d\t%s\n' % (f, n, a, size, d))
print(len(rows), 'HAL routines;', sum(1 for r in rows if r[3]), 'with descriptions')
