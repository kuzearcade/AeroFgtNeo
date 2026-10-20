#!/bin/sh
cd ~/AeroFgtNeo
until grep -q "battery fz24 done" work/play/fh/q_bat7.log; do sleep 20; done
F=60000 sh work/play/fp/benchlag.sh $PWD/work/out_fz24e0 fz24e0b > work/play/fp/bench_fz24e0b.txt 2>&1; echo "battery fz24e0 done"
