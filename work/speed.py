"""speed.py dir...: screen frames per stretch of game frames (harness marks) for m7/att."""
import sys, re
for d in sys.argv[1:]:
    for run, spans in (('att', [(1000, 2000), (4400, 5200), (300, 5900)]), ('m7', [(300, 9900)])):
        m = {}
        try:
            for l in open(f'{d}/{run}/mark.txt'):
                r = re.search(r'game frame (\d+) at screen frame (\d+)', l)
                if r: m[int(r.group(1))] = int(r.group(2))
        except FileNotFoundError: continue
        print(d, run, ' '.join(f'{a}-{b}: {m[b]-m[a]} ({(m[b]-m[a])/(b-a):.3f})' for a, b in spans if a in m and b in m))
