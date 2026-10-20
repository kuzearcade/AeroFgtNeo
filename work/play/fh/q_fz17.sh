#!/bin/sh
# queued measurements of fz17 after the fz16 runs
cd ~/AeroFgtNeo
until grep -q done work/play/fh/ov_fz16o.log && grep -q done work/play/fh/pa_fz16.log && grep -q done work/play/fh/ev_fz16c.log && grep -q done work/play/fh/dw_fz16.log; do sleep 20; done
N=20000 TGT=fz sh work/play/fh/runfh.sh $PWD/work/out_fz17 $PWD/work/play/fh/pa_fz17 20000 parity.lua > work/play/fh/pa_fz17.log 2>&1 &
N=20000 sh work/play/fh/runfh.sh $PWD/work/out_fz17o $PWD/work/play/fh/ov_fz17o 20000 ovd.lua > work/play/fh/ov_fz17o.log 2>&1 &
sh work/play/fp/runlag.sh $PWD/work/out_fz17 $PWD/work/play/fp/bl_fz17_7 20000 $PWD/work/play/bot200k.txt > /dev/null 2>&1 &
wait
echo q_fz17 done
