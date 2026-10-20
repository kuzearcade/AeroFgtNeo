#!/bin/sh
# the 9-seed lag batteries at 60k frames: fz17, fz14, fz16 (one after the other)
cd ~/AeroFgtNeo
until grep -q "q_fz17b done" work/play/fh/q_fz17b.log; do sleep 30; done
for n in fz17 fz14 fz16; do F=60000 sh work/play/fp/benchlag.sh $PWD/work/out_$n ${n}b > work/play/fp/bench_${n}b.txt 2>&1; echo "battery $n done"; done
