#!/bin/sh
# the fz19 profile at c2700 (10k frames traced), then merged
cd ~/AeroFgtNeo/work/play/fp
rm -rf fz19p_tmp; sh runfp.sh $HOME/AeroFgtNeo/work/out_fz19 $HOME/AeroFgtNeo/work/play/fp/fz19p_tmp 2700 12700 > fz19p_run.log 2>&1
mkdir -p fz19p; rm -rf fz19p/c2700; mv fz19p_tmp fz19p/c2700; python3 fpmerge.py fz19p >> fz19p_run.log 2>&1; echo "prof fz19 done"
