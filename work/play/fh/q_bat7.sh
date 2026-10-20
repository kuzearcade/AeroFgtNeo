#!/bin/sh
cd ~/AeroFgtNeo
until grep -q done work/play/fh/pa_fz24.log && grep -q done work/play/fh/ev_fz24c.log; do sleep 20; done
F=60000 sh work/play/fp/benchlag.sh $PWD/work/out_fz24 fz24b > work/play/fp/bench_fz24b.txt 2>&1; echo "battery fz24 done"
