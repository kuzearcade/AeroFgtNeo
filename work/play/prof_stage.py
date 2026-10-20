"""prof_stage.py <orig|neo> [idle_lo idle_hi ...]: per stage (census scenes) the CPU load from the chunk timelines
(10M-cycle buckets): busy = not in the idle ranges; plus per-stage subsystem shares (by 256-byte page ->
function -> subsystem) -> work/catalog/<t>_stages.tsv"""
import sys, os, glob, re, csv, bisect, collections, hashlib, numpy as np
T = sys.argv[1]; R = os.path.expanduser('~/AeroFgtNeo'); P = R + '/work/play'
idle = [(int(sys.argv[i], 16), int(sys.argv[i + 1], 16)) for i in range(2, len(sys.argv), 2)]
STAGE = eval(open(R + '/work/play/categories.py').read().split('STAGE = ')[1].split('\nCAT')[0])
H = {}
for f in glob.glob(P + '/cen/lut_*.bin'): H[int(f[-7:-4])] = hashlib.md5(open(f, 'rb').read()).hexdigest()[:8]
sc = []
for l in open(P + '/cen/scenes.txt'):
    p = l.split(); sc.append((int(p[1]), int(p[2]), STAGE.get(H.get(int(p[0]), ''), 'other')))
starts = [s[0] for s in sc]
def stage_of(f):
    j = bisect.bisect_right(starts, f) - 1
    return sc[j][2] if j >= 0 else 'boot'
fn = list(csv.DictReader(open(R + '/work/catalog/%s_functions_described.tsv' % T), delimiter='\t'))
FE = [int(r['entry'], 16) for r in fn]; FS = [r.get('subsystem') or r.get('name', '') for r in fn]
def page_sub(pg):
    j = bisect.bisect_right(FE, pg * 256 + 128) - 1
    return FS[j] if j >= 0 else '?'
NP = 8192
acc = collections.defaultdict(lambda: dict(b=[], sub=collections.Counter()))
for d in sorted(glob.glob(P + '/tr_%s/c*/' % T), key=lambda d: int(re.search(r'c(\d+)/$', d).group(1))):
    if not os.path.exists(d + 'summary.txt'): continue
    c0 = int(re.search(r'c(\d+)/$', d).group(1))
    s = dict(zip(*[iter(open(d + 'summary.txt').read().split())] * 2)); nb = int(s['buckets']); B = int(s['bucket_cycles'])
    fpb = 10000 / max(1, int(s['cycles']) / B)       # frames per bucket
    tl = np.fromfile(d + 'timeline.bin', dtype=np.uint32).reshape(-1, NP)
    for b in range(tl.shape[0] - 1):
        row = tl[b].astype(np.int64); tot = row.sum()
        if tot < B * 0.9: continue
        idl = sum(row[lo >> 8:(hi >> 8) + 1].sum() for lo, hi in idle)
        st = stage_of(int(c0 + b * fpb)); a = acc[st]; a['b'].append(1 - idl / tot)
        for pg in np.nonzero(row)[0]:
            if not any(lo >> 8 <= pg <= hi >> 8 for lo, hi in idle): a['sub'][page_sub(pg)] += int(row[pg])
with open(R + '/work/catalog/%s_stages.tsv' % T, 'w') as o:
    o.write('stage\tseconds\tbusy_avg\tbusy_p95\tbusy_max\ttop_subsystems\n')
    for st, a in sorted(acc.items(), key=lambda x: -np.mean(x[1]['b'])):
        b = np.array(a['b']); t = sum(a['sub'].values())
        top = ', '.join('%s %.0f%%' % (k, 100 * v / t) for k, v in a['sub'].most_common(5))
        o.write('%s\t%d\t%.1f\t%.1f\t%.1f\t%s\n' % (st, len(b), 100 * b.mean(), 100 * np.percentile(b, 95), 100 * b.max(), top))
print(open(R + '/work/catalog/%s_stages.tsv' % T).read())
