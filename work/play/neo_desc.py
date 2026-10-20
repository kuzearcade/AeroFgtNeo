"""neo_desc.py: work/catalog/neo_functions.tsv + names/subsystems: game code (< 0x80000) from the original's
descriptions (same addresses; DIRECT patches noted), HAL routines from neo_hal_routines.tsv (file = subsystem)
-> neo_functions_described.tsv"""
import csv, bisect, os
C = os.path.expanduser('~/AeroFgtNeo/work/catalog')
od = {int(r['entry'], 16): r for r in csv.DictReader(open(C + '/orig_functions_described.tsv'), delimiter='\t')}
OE = sorted(od)
hal = {int(r['address'], 16): r for r in csv.DictReader(open(C + '/neo_hal_routines.tsv'), delimiter='\t')}
HE = sorted(hal)
rows = list(csv.DictReader(open(C + '/neo_functions.tsv'), delimiter='\t'))
for r in rows:
    e = int(r['entry'], 16)
    if e < 0x80000:
        j = bisect.bisect_right(OE, e) - 1
        o = od[OE[j]] if j >= 0 else None
        r['subsystem'] = 'game: ' + (o['subsystem'] if o else '?'); r['name'] = (o['name'] if o else r['name']) + ('' if o and OE[j] == e else '')
        r['description'] = o['description'] if o else ''
    else:
        j = bisect.bisect_right(HE, e) - 1
        h = hal[HE[j]] if j >= 0 else None
        r['subsystem'] = 'HAL: ' + (h['file'] if h else '?'); r['name'] = h['label'] if h else r['name']; r['description'] = h['description'] if h else ''
with open(C + '/neo_functions_described.tsv', 'w') as o:
    w = csv.DictWriter(o, list(rows[0].keys()), delimiter='\t'); w.writeheader(); w.writerows(rows)
print(len(rows), 'functions')
