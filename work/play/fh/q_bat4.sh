#!/bin/sh
# the 9-seed lag batteries at 60k frames: fz19, fz19e0, fz20 (one after the other)
cd ~/AeroFgtNeo
for n in fz19 fz19e0 fz20; do F=60000 sh work/play/fp/benchlag.sh $PWD/work/out_$n ${n}b > work/play/fp/bench_${n}b.txt 2>&1; echo "battery $n done"; done
