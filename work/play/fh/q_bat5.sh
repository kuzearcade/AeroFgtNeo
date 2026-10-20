#!/bin/sh
cd ~/AeroFgtNeo
for n in fz21 fz21e0; do F=60000 sh work/play/fp/benchlag.sh $PWD/work/out_$n ${n}b > work/play/fp/bench_${n}b.txt 2>&1; echo "battery $n done"; done
