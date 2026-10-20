#!/bin/sh
cd ~/AeroFgtNeo
until grep -q "battery fz16 done" work/play/fh/q_bat.log; do sleep 20; done
F=60000 sh work/play/fp/benchlag.sh $PWD/work/out_fz19 fz19b > work/play/fp/bench_fz19b.txt 2>&1; echo "battery fz19 done"
F=60000 sh work/play/fp/benchlag.sh $PWD/work/out_fz19e0 fz19e0b > work/play/fp/bench_fz19e0b.txt 2>&1; echo "battery fz19e0 done"
