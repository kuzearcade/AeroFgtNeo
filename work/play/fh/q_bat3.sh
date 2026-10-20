#!/bin/sh
cd ~/AeroFgtNeo
until grep -q "battery fz19e0 done" work/play/fh/q_bat2.log; do sleep 20; done
F=60000 sh work/play/fp/benchlag.sh $PWD/work/out_fz20 fz20b > work/play/fp/bench_fz20b.txt 2>&1; echo "battery fz20 done"
