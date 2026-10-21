#!/bin/sh
# truedrop.sh <name>...: per nation, frames where the sprite-drop counter (lag.txt col 9) rises, and sprites dropped, summed over seeds 7-9
cd $HOME/AeroFgtNeo/work/play/fp
for n in 0 1 2 3; do for N in "$@"; do
  cat bl_n${n}${N}_7/lag.txt bl_n${n}${N}_8/lag.txt bl_n${n}${N}_9/lag.txt 2>/dev/null | awk -v n=$n -v N=$N '$1==1{p=0} {if($9>p){f++; s+=$9-p} p=$9} END{printf "n%d %-6s true drop frames %6d  sprites dropped %7d\n",n,N,f,s}'
done; done
