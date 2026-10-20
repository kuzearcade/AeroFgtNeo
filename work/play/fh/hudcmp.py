#!/usr/bin/env python3
"""hudcmp.py <a/out.txt> <b/out.txt>: hudlog rows (frame flip seen same hcok hok fixused + 13 strips)
compared by flip number: strips equal / different, the first differences listed."""
import sys
def load(p):
    d={}
    for l in open(p):
        f=l.split()
        if len(f)<13 or not f[1].isdigit(): continue
        d[int(f[1])]=(f[0],f[11],f[13:])
    return d
a=load(sys.argv[1]); b=load(sys.argv[2])
common=sorted(set(a)&set(b)); eq=0; diff=[]
for k in common:
    if a[k][2]==b[k][2]: eq+=1
    else: diff.append(k)
print("flips a %d b %d common %d: strips equal %d different %d" % (len(a),len(b),len(common),eq,len(diff)))
for k in diff[:12]:
    da=[i for i in range(min(len(a[k][2]),len(b[k][2]))) if a[k][2][i]!=b[k][2][i]] or ["len"]
    print(" flip %d (frames %s/%s, hok %s/%s): strips %s" % (k,a[k][0],b[k][0],a[k][1],b[k][1],da))
