#!/bin/sh
# bench.sh <romdir> <name>: three whole bot playthroughs (movies seed 7, 8, 9) in parallel -> full/<name>_{7,8,9}, totals
R=$1; N=$2; P=$HOME/AeroFgtNeo/work/play
for s in 7 8 9; do
  m=$P/bot200k_$s.txt; [ $s = 7 ] && m=$P/bot200k.txt
  MOVIE=$m sh $P/runfull.sh $R $P/full/${N}_$s > /dev/null &
done
wait
python3 $P/statsum.py $P/full/${N}_7 $P/full/${N}_8 $P/full/${N}_9
python3 - $P/full/${N} <<'PY'
import sys, glob
t=[0]*4; nf=0
for s in (7,8,9):
    L=[l.split() for l in open('%s_%d/c0.txt'%(sys.argv[1],s))]; L=[l for l in L if len(l)==6]
    a,b=L[0],L[-1]; nf+=int(b[0])-int(a[0])
    for i in range(4): t[i]+=int(b[i+1])-int(a[i+1])
print('%-28s frames %6d late %5d (%.2f%%) dropped %5d frames-with-drops %5d (%.2f%%) overruns %d'%(sys.argv[1].split('/')[-1]+' ALL',nf,t[0],100*t[0]/nf,t[1],t[2],100*t[2]/nf,t[3]))
PY
