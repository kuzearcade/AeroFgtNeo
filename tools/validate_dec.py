"""Cross-check tools/m68k.py against MAME's unidasm on all executed instruction starts."""
import subprocess, sys, os, tempfile, re
sys.path.insert(0, os.path.dirname(__file__))
import m68k

rom = open(sys.argv[1], 'rb').read()
cov = bytearray(len(rom) // 8)
for p in sys.argv[2:]:
    c = open(p, 'rb').read()
    for i in range(len(cov)):
        cov[i] |= c[i]
pcs = [a for a in range(len(rom)) if cov[a >> 3] >> (a & 7) & 1]
print("covered instruction starts:", len(pcs))
dec = m68k.Decoder(rom)
mine = {}
bad = 0
for a in pcs:
    try:
        mine[a] = dec.decode(a)
    except m68k.DecodeError as e:
        bad += 1
        print("decode error at %x: %s" % (a, e))
# unidasm linear sweeps from the start of each run of consecutive instructions
runs = []
s = set(pcs)
for a in pcs:
    if a in mine and (not runs or runs[-1][1] != a):
        runs.append([a, a])
    if a in mine:
        runs[-1][1] = a + mine[a].length
tmp = tempfile.NamedTemporaryFile(delete=False)
tmp.write(rom); tmp.close()
mism = 0
batch = []
for start, end in runs:
    out = subprocess.run([os.path.expanduser('~/mame/unidasm'), tmp.name, '-arch', 'm68000',
                          '-basepc', '0', '-skip', str(start), '-count', str(end - start)],
                         capture_output=True, text=True).stdout
    # unidasm prints addresses relative to basepc (0) for the skipped stream
    addrs = []
    for line in out.splitlines():
        m = re.match(r'\s*([0-9a-f]+):', line)
        if m:
            addrs.append(int(m.group(1), 16) + start)
    a = start
    for ua in addrs:
        if ua >= end:
            break
        if ua != a:
            mism += 1
            if mism < 20:
                print("length mismatch near %x (mine next %x, unidasm %x) %s" % (a, a, ua, mine.get(a - 2) and mine[a-2].text()))
            break
        if a not in mine:
            break
        a += mine[a].length
        compared = globals().get("compared", 0) + 1; globals()["compared"] = compared
os.unlink(tmp.name)
print("compared", globals().get("compared"))
print("decode errors", bad, "length mismatches", mism, "runs", len(runs))
