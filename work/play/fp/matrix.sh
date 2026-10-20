#!/bin/sh
# matrix.sh <romdir> <name> [nations] [seeds] [frames]: the profile matrix of AUDIT 39/40 - the nation
# batteries of a build (two players started together, autofire on both, bombs on bosses: botsel.lua), one
# game per nation and seed, F frames each, all in parallel; then matrix_report.py.  The arcade's side
# (bl_n<N>orig_<seed>, the same movies on MAME aerofgt) is made once with ORIG=1 (romdir ignored).
#   sh work/play/fp/matrix.sh work/out_fz64 64L            -> work/play/fp/bl_n{0..3}64L_{7,8,9}, 200k frames
#   ORIG=1 sh work/play/fp/matrix.sh - orig                  -> the arcade's reference runs
#   sh work/play/fp/matrix.sh work/out_X X "1 3" "7" 60000 -> a quick check: nations 1 and 3, seed 7, 60k
# Run from ~/AeroFgtNeo.  ~25 min for 12 x 200k on 16 cores (longer with other runs alongside).
R=$1; N=$2; NAT=${3:-"0 1 2 3"}; S=${4:-"7 8 9"}; F=${5:-200000}; P=$HOME/AeroFgtNeo/work/play; FP=$P/fp
[ -z "$N" ] && { echo "usage: matrix.sh <romdir> <name> [nations] [seeds] [frames]"; exit 1; }
for n in $NAT; do
  for s in $S; do
    m=$P/bot200k_$s.txt; [ $s = 7 ] && m=$P/bot200k.txt
    if [ -n "$ORIG" ]; then
      NATION=$n HARNESS_BOTFILE=$FP/botsel.lua sh $FP/runlag_orig.sh $FP/bl_n${n}${N}_$s $F $m > /dev/null 2>&1 &
    else
      NATION=$n HARNESS_BOTFILE=$FP/botsel.lua sh $FP/runlag.sh $R $FP/bl_n${n}${N}_$s $F $m > /dev/null 2>&1 &
    fi
  done
done
wait
[ -z "$ORIG" ] && python3 -I $FP/matrix_report.py $N orig "$(echo $NAT | tr ' ' ,)" "$(echo $S | tr ' ' ,)"
