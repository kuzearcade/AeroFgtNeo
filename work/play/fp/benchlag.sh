#!/bin/sh
# benchlag.sh <romdir> <name> [seeds]: 9 whole bot playthroughs (seeds 7-15) with lag2.lua, in parallel,
# into work/play/fp/bl_<name>_<seed>/lag.txt; then the totals (lagsum.py)
R=$1; N=$2; P=$HOME/AeroFgtNeo/work/play; FP=$P/fp; S=${3:-"7 8 9 10 11 12 13 14 15"}; F=${F:-200000}
for s in $S; do
  m=$P/bot200k_$s.txt; [ $s = 7 ] && m=$P/bot200k.txt
  sh $FP/runlag.sh $R $FP/bl_${N}_$s $F $m > /dev/null 2>&1 &
done
wait
python3 $FP/lagsum.py "$FP/bl_${N}_*/lag.txt"
