import sys
# short dropouts: the count falls below half its value and comes back within 30 frames
for fn in sys.argv[1:]:
    L=[tuple(map(int,l.split())) for l in open(fn) if len(l.split())==3]
    runs=[]
    for i in range(1,len(L)-1):
        f,g,n=L[i]; pf,pg,pn=L[i-1]
        if pn>=8 and n<pn/2:
            j=i+1
            while j<len(L) and L[j][2]<pn/2: j+=1
            if j<len(L) and L[j][0]-f<=30: runs.append((g,L[j][0]-f))
    print(fn,len(runs),runs[:20])
