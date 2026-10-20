#!/bin/sh
# benchlag_orig.sh <name> [seeds]: the original game's 9 bot playthroughs (F frames each) in parallel
N=$1; P=$HOME/AeroFgtNeo/work/play; FP=$P/fp; S=${2:-"7 8 9 10 11 12 13 14 15"}; F=${F:-200000}
for s in $S; do m=$P/bot200k_$s.txt; [ $s = 7 ] && m=$P/bot200k.txt; sh $FP/runlag_orig.sh $FP/bl_${N}_$s $F $m > /dev/null 2>&1 & done
wait
