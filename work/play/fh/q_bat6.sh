#!/bin/sh
cd ~/AeroFgtNeo
until grep -q done work/play/fh/pa_fz23.log && grep -q done work/play/fh/ev_fz23c.log; do sleep 20; done
F=60000 sh work/play/fp/benchlag.sh $PWD/work/out_fz23 fz23b > work/play/fp/bench_fz23b.txt 2>&1; echo "battery fz23 done"
