#!/bin/sh
# runfp_all.sh <romdir> <name> [chunks]: the whole bot playthrough (bot200k.txt, 200k game frames)
# profiled per frame in 10k-frame chunks run in parallel (each from power-on, traced only in
# its window), into work/play/fp/<name>/c<from>/.  Then: python3 fpmerge.py <name>
R=$1; N=$2; C=${3:-20}; FP=$HOME/AeroFgtNeo/work/play/fp
mkdir -p $FP/$N
i=0
while [ $i -lt $C ]; do
  F=$((i*10000-2)); [ $F -lt 0 ] && F=0
  T=$((i*10000+10000+1))
  sh $FP/runfp.sh $R $FP/$N/c$((i*10000)) $F $T > $FP/$N/c$((i*10000)).log 2>&1 &
  i=$((i+1))
done
wait
echo "all chunks done"
