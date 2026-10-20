#!/bin/sh
cd ~/AeroFgtNeo/work/play/fp
for n in fz24 fz25; do rm -rf ${n}p_tmp; sh runfp.sh $HOME/AeroFgtNeo/work/out_$n $HOME/AeroFgtNeo/work/play/fp/${n}p_tmp 2700 7700 > ${n}p_run.log 2>&1 && mkdir -p ${n}p && rm -rf ${n}p/c2700 && mv ${n}p_tmp ${n}p/c2700 && python3 fpmerge.py ${n}p >> ${n}p_run.log 2>&1; echo "prof $n done" & done; wait; echo "profiles done"
