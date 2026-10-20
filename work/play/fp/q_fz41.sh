#!/bin/sh
cd ~/AeroFgtNeo/work/play/fp
until ! pgrep -f "ev_n[0-3]40c" > /dev/null; do sleep 30; done
F=60000 sh benchlag.sh $HOME/AeroFgtNeo/work/out_fz41 fz41 > bench_fz41.txt 2>&1; echo "battery fz41 done" >> q_fz41.log
