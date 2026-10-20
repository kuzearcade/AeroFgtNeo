"""catalog.py <orig|neo>: merge the playthrough chunks (work/play/tr_<t>/c*/) and build
work/catalog/<t>_disasm.txt (annotated disassembly) + <t>_functions.tsv + <t>_profile.json.
orig: aerofgt main ROM; neo: the converted P ROM (game code 0..0x7ffff + HAL, hal.lst labels)."""
import sys, os, re, glob, json, struct, collections, bisect
sys.path.insert(0, os.path.expanduser('~/AeroFgtNeo/tools'))
import m68k
T = sys.argv[1]; P = os.path.expanduser('~/AeroFgtNeo/work/play'); OUT = os.path.expanduser('~/AeroFgtNeo/work/catalog')
S = '/tmp/claude-1000/-home-vboxuser-AeroFgtNeo/560dbddd-2c54-4bd4-b6db-4e3d9472357d/scratchpad'
chunks = sorted(glob.glob('%s/tr_%s/c*/' % (P, T)), key=lambda d: int(re.search(r'c(\d+)/$', d).group(1)))
chunks = [d for d in chunks if os.path.exists(d + 'summary.txt')]
print(len(chunks), 'chunks')
# ---------------------------------------------------------------- merge
cnt = collections.Counter(); cyc = collections.Counter(); calls = collections.Counter(); incl = collections.Counter()
edges = collections.Counter(); cov = None; total = 0; lines = 0; tl = []
for d in chunks:
    for l in open(d + 'pc.txt'):
        a, n, c = l.split(); a = int(a, 16); cnt[a] += int(n); cyc[a] += int(c)
    for l in open(d + 'incl.txt'):
        a, n, c = l.split(); a = int(a, 16); calls[a] += int(n); incl[a] += int(c)
    for l in open(d + 'edges.txt'):
        f, t, k, n = l.split(); edges[(int(f, 16), int(t, 16), k)] += int(n)
    s = dict(zip(*[iter(open(d + 'summary.txt').read().split())] * 2)); total += int(s['cycles']); lines += int(s['lines'])
    c = open(d + 'cov_maincpu.bin', 'rb').read()
    cov = bytearray(c) if cov is None else bytearray(x | y for x, y in zip(cov, c))
    tlb = open(d + 'timeline.bin', 'rb').read(); tl.append((int(re.search(r'c(\d+)/$', d).group(1)), len(tlb) // 4 // 8192))
print('instructions traced', lines, 'cycles', total)
# ---------------------------------------------------------------- code
if T == 'orig':
    rom = open(S + '/orig_main.bin', 'rb').read(); size = 0x80000; labels = {}
else:
    raw = open(os.path.expanduser('~/AeroFgtNeo/work/out_ow/aerofgtn/538-p1.p1'), 'rb').read()
    rom = bytes(b for i in range(0, len(raw), 2) for b in (raw[i + 1], raw[i]))   # (word-swapped file)
    size = len(rom); labels = {}
    for m in re.finditer(r'^([0-9A-F]{8}) ([A-Za-z_]\w*)$', open(os.path.expanduser('~/AeroFgtNeo/work/out_ow/build/hal.lst')).read(), re.M):
        a = int(m.group(1), 16)
        if a < size: labels.setdefault(a, m.group(1 + 1))
covered = [a for a in range(size) if cov[a >> 3] >> (a & 7) & 1]
dec = m68k.Decoder(rom); ins = {}; errs = 0
vec = struct.unpack('>64I', rom[:256]); seeds = set(v for v in vec[1:64] if v < size)
seeds |= set(covered)
for f in ('code_seeds.txt', 'code_seeds_static.txt'):
    p = os.path.expanduser('~/AeroFgtNeo/analysis/' + f)
    if T == 'orig' and os.path.exists(p):
        seeds |= set(int(l, 16) for l in open(p) if l.strip() and not l.startswith('#'))
work = sorted(seeds)
while work:
    a = work.pop()
    while a < size and not a & 1 and a not in ins:
        try: i = dec.decode(a)
        except m68k.DecodeError: errs += 1; break
        ins[a] = i
        for t in i.targets:
            if t < size: work.append(t)
        if i.flow in ('jump', 'ret', 'indirect_jump', 'stop'): break
        a += i.length
print('instructions', len(ins), 'covered', len(covered), 'decode errors', errs)
# ---------------------------------------------------------------- functions
entries = set(v for v in vec[1:64] if v in ins)
for i in ins.values():
    if i.flow == 'call': entries.update(t for t in i.targets if t in ins)
for (f, t, k), n in edges.items():
    if k in 'CI' and t in ins: entries.add(t)
    if k == 'J' and t in ins and f in ins and ins[f].flow == 'indirect_jump': entries.add(t)
entries |= set(a for a in labels if a in ins)
# the object handler table (0x199ba: 4-byte pointers per type) and any other pointer
# table entries reached only through it: function entries even when never executed
for t in range(0x100):
    h = struct.unpack_from('>I', rom, 0x199ba + 4 * t)[0]
    if h in ins: entries.add(h)
# code after an unconditional jump / return that runs (a task started through the
# scheduler, a table target): a block of its own
prevend = {}
for a, i in ins.items(): prevend[a + i.length] = i
for a in ins:
    p_ = prevend.get(a)
    if p_ is not None and p_.flow in ('jump', 'ret', 'indirect_jump', 'stop') and (cov[a >> 3] >> (a & 7) & 1): entries.add(a)
E = sorted(entries)
def fn_of(a):
    j = bisect.bisect_right(E, a) - 1
    return E[j] if j >= 0 else None
REG = [('rom', 0, 0x7ffff), ('palette', 0x1a0000, 0x1a07ff), ('raster', 0x1b0000, 0x1b0fff), ('vram0', 0x1b2000, 0x1b3fff),
       ('vram1', 0x1b4000, 0x1b5fff), ('sprlut', 0x1c0000, 0x1c7fff), ('sprram', 0x1d0000, 0x1d1fff), ('wram', 0xfef000, 0xffefff),
       ('io', 0xffff80, 0xffffff)] if T == 'orig' else \
      [('prom', 0, 0xfffff), ('wram', 0x100000, 0x10ffff), ('palette', 0x400000, 0x401fff), ('lspc', 0x3c0000, 0x3c000f),
       ('ioreg', 0x300000, 0x3fffff), ('bios', 0xc00000, 0xc1ffff), ('backup', 0xd00000, 0xd0ffff)]
def region(v):
    v &= 0xffffff
    for n, lo, hi in REG:
        if lo <= v <= hi: return n
    return None
F = {}
for a in sorted(ins):
    e = fn_of(a)
    if e is None: continue
    f = F.setdefault(e, dict(n=0, cov=0, exe=0, cyc=0, refs=collections.Counter(), ops=collections.Counter(), end=a))
    i = ins[a]; f['n'] += 1; f['end'] = a + i.length; f['exe'] += cnt[a]; f['cyc'] += cyc[a]
    f['ops'][i.op] += 1
    for o in i.operands:
        if o.kind in (m68k.ABSL, m68k.ABSW) or (o.kind == m68k.IMM and o.ext_len == 4):
            r = region(o.value if o.kind != m68k.ABSW else (o.value | 0xffff0000 if o.value & 0x8000 else o.value))
            if r and r not in ('rom', 'prom'): f['refs'][r] += 1
covset = set(covered)
for a in ins:
    e = fn_of(a)
    if e in F and a in covset: F[e]['cov'] += 1
callers = collections.defaultdict(collections.Counter); callees = collections.defaultdict(collections.Counter)
for (f, t, k), n in edges.items():
    if k in 'CI':
        cf = fn_of(f); callers[t][cf] += n; callees[cf][t] += n
for i in ins.values():
    if i.flow == 'call':
        for t in i.targets:
            cf = fn_of(i.addr); callers[t].setdefault(cf, 0); callees[cf].setdefault(t, 0)
# ---------------------------------------------------------------- outputs
os.makedirs(OUT, exist_ok=True)
with open('%s/%s_functions.tsv' % (OUT, T), 'w') as o:
    o.write('entry\tend\tname\tinstr\tcovered\tcalls\texec\tcycles_excl\tcycles_incl\tpct_excl\tregions\tcallers\tcallees\n')
    for e in E:
        f = F.get(e)
        if not f: continue
        o.write('%06x\t%06x\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%.3f\t%s\t%s\t%s\n' % (
            e, f['end'], labels.get(e, 'f_%06x' % e), f['n'], f['cov'], calls[e], f['exe'], f['cyc'], incl[e], 100.0 * f['cyc'] / max(total, 1),
            ','.join('%s:%d' % kv for kv in f['refs'].most_common()), ','.join('%06x' % c for c, _ in callers[e].most_common(8) if c is not None),
            ','.join('%06x' % c for c, _ in callees[e].most_common(12))))
with open('%s/%s_disasm.txt' % (OUT, T), 'w') as o:
    o.write('; %s: %d instructions (%d executed in the playthrough), %d functions; %d instructions / %d cycles traced\n' % (T, len(ins), len(covset & set(ins)), len(F), lines, total))
    o.write('; columns: address, executions, cycles, bytes, instruction\n')
    prev = None
    for a in sorted(ins):
        if a in entries:
            f = F.get(a, {})
            o.write('\n; ======== %s (%06x)  calls %d  cycles excl %d incl %d\n' % (labels.get(a, 'f_%06x' % a), a, calls[a], f.get('cyc', 0), incl[a]))
            cl = ', '.join('%06x' % c for c in callers[a] if c is not None)
            if cl: o.write(';   called from: %s\n' % cl[:300])
        elif prev is not None and prev != a:
            o.write('        ; (gap)\n')
        i = ins[a]
        o.write('%06x %10d %11d  %-20s %s\n' % (a, cnt[a], cyc[a], i.raw.hex() if i.raw else '', i.text()))
        prev = a + i.length
json.dump(dict(total=total, lines=lines, chunks=[c for c, _ in tl]), open('%s/%s_profile.json' % (OUT, T), 'w'))
print('functions', len(F))
