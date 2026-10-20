#!/bin/sh
# the oo3 test set: drop probe (3 movies), regression, chain/commit checks
P=$HOME/AeroFgtNeo/work/play; cd $P
rm -rf dr7; mkdir -p dr7
for m in bot200k bot200k_8 bot200k_9; do sh rundr.sh ../out_oo3 dr7/$m.txt $m.txt > /dev/null 2>&1 & done
(cd $HOME/AeroFgtNeo; sh work/runall.sh oo3 > work/runall_oo3.txt 2>&1 &)
M="-cfg_directory ../cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
run() { # run <dir> <movie> <frames> <lua> <out>
  rm -rf $1; mkdir -p $1; (cd $1; V_OUT=$PWD/$5 HARNESS_TARGET=neo HARNESS_MOVIE=$2 HARNESS_FRAMES=$3 timeout -s KILL 5000 ~/mame/aerofgtneo aerofgtn -rompath "../../out_oo3;$HOME/AeroFgtNeo/mame_roms" -nvram_directory nv $M -autoboot_script ../$4 > log 2>&1 &) ; }
run cc_oo3_b8 $P/bot200k_8.txt 60000 chainchk_z.lua z.txt
run cc_oo3_k8 $P/bot200k_8.txt 60000 kschk4.lua ks.txt
run cc_oo3_m7 $HOME/AeroFgtNeo/work/movie7.txt 10000 chainchk_z.lua z.txt
