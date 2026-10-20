#!/bin/sh
# bench9.sh <romdir> <name> [seeds]: whole bot playthroughs for movie seeds (default 7-15), 9 in parallel, totals
R=$1; N=$2; P=$HOME/AeroFgtNeo/work/play; S=${3:-"7 8 9 10 11 12 13 14 15"}
for s in $S; do
  m=$P/bot200k_$s.txt; [ $s = 7 ] && m=$P/bot200k.txt
  [ -s $P/full/${N}_$s/c0.txt ] && [ $(wc -l < $P/full/${N}_$s/c0.txt) -ge 199990 ] && continue
  MOVIE=$m sh $P/runfull.sh $R $P/full/${N}_$s > /dev/null &
done
wait
python3 - $P/full/${N} $S <<'PY'
import sys
t=[0]*4; nf=0; per=[]
for s in sys.argv[2:]:
    L=[l.split() for l in open('%s_%s/c0.txt'%(sys.argv[1],s))]; L=[l for l in L if len(l)==6]
    a,b=L[0],L[-1]; n=int(b[0])-int(a[0]); nf+=n; d=[int(b[i+1])-int(a[i+1]) for i in range(4)]
    for i in range(4): t[i]+=d[i]
    per.append('%.1f'%(100*d[0]/n))
print('%-10s frames %7d late %6d (%.2f%%) dropped %6d frames-with-drops %6d (%.2f%%) overruns %d  late%% per movie %s'%(sys.argv[1].split('/')[-1],nf,t[0],100*t[0]/nf,t[1],t[2],100*t[2]/nf,t[3],' '.join(per)))
PY
