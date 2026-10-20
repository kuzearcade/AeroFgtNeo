#!/bin/sh
# vischk.sh <romdir> <outdir>: visible ring columns outside the shown set, movie7 10000 + attract 6000
R=$HOME/AeroFgtNeo; M="-cfg_directory cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
for p in m7:movie7.txt:10000 att:movie_idle.txt:6000; do n=${p%%:*}; r=${p#*:}; mv=${r%%:*}; fr=${r#*:}
mkdir -p $2/$n; ( cd $2/$n; rm -rf nv; V_OUT=$PWD/vis.txt HARNESS_TARGET=neo HARNESS_MOVIE=$R/work/$mv HARNESS_FRAMES=$fr timeout -s KILL 6000 ~/mame/aerofgtneo aerofgtn -rompath "$R/$1;$R/mame_roms" -nvram_directory nv $M -autoboot_script /tmp/claude-1000/-home-vboxuser-AeroFgtNeo/560dbddd-2c54-4bd4-b6db-4e3d9472357d/scratchpad/vischk.lua > log 2>&1 ) & done; wait
for n in m7 att; do echo $n vis-violations $(awk '$3>0' $2/$n/vis.txt | wc -l); done
