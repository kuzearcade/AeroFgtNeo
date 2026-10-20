#!/usr/bin/env python3
"""batsum.py <name>...: a battery's totals over its seeds (work/play/fp/bl_<name>_*/lag.txt, lagsum.py's
per-file lines summed): lost logic, late, drop frames, overruns, holds; then per stage."""
import sys, glob, re, subprocess, collections
for name in sys.argv[1:]:
    files = sorted(glob.glob('work/play/fp/bl_%s_*/lag.txt' % name))
    out = subprocess.run([sys.executable, 'work/play/fp/lagsum.py'] + files, capture_output=True, text=True).stdout.split('\n')
    tot = collections.Counter(); st = collections.defaultdict(lambda: [0, 0.0, 0.0])
    for l in out:
        m = re.match(r'\S+\s+frames\s+(\d+) lost-logic\s+(\d+) .*? late\s+(\d+) .*? holds (\d+) busy (\d+)(?: drops (\d+) dropframes (\d+) overruns (\d+))?', l)
        if m:
            f, lag, late, holds, busy, drops, df, ov = (int(x or 0) for x in m.groups())
            tot['frames'] += f; tot['lag'] += lag; tot['late'] += late; tot['holds'] += holds; tot['busy'] += busy; tot['drops'] += drops; tot['df'] += df; tot['ov'] += ov
        elif 'by stage' in l:
            for s, a, b, n in re.findall(r'([\w/ ]+?) ([\d.]+)/([\d.]+) \((\d+)\)', l.split(':', 1)[1]):
                s = s.strip(); n = int(n); st[s][0] += n; st[s][1] += float(a) * n / 100; st[s][2] += float(b) * n / 100
    f = tot['frames']
    print("%-8s seeds %d frames %d: lost logic %.2f%%  late %.2f%%  drop frames %d (%.3f%%)  overruns %d  holds %d  busy %.1f%%" % (
        name, len(files), f, 100.0 * tot['lag'] / f, 100.0 * tot['late'] / f, tot['df'], 100.0 * tot['df'] / f, tot['ov'], tot['holds'], 100.0 * tot['busy'] / f))
    print("   by stage lag%/late% (frames): " + ", ".join("%s %.1f/%.1f (%d)" % (s, 100 * v[1] / v[0], 100 * v[2] / v[0], v[0]) for s, v in sorted(st.items(), key=lambda x: -x[1][0])))
