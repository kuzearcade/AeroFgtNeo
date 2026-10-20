#!/bin/sh
cd ~/AeroFgtNeo
until grep -q "q_fz17 done" work/play/fh/q_fz17.log; do sleep 20; done
N=20000 sh work/play/fh/runfh.sh $PWD/work/out_fz17 $PWD/work/play/fh/dw_fz17 20000 dropwhy.lua > work/play/fh/dw_fz17.log 2>&1 &
N=20000 sh work/play/fh/runfh.sh $PWD/work/out_fz17c $PWD/work/play/fh/ev_fz17c 20000 fzev.lua > work/play/fh/ev_fz17c.log 2>&1 &
wait; echo q_fz17b done
