#!/bin/sh
# runptr.sh <romdir> <outdir> <from> <to> [movie]: profile game frames from..to of a run from power-on (agg)
R=$1; D=$2; P=$HOME/AeroFgtNeo/work/play; rm -rf $D; mkdir -p $D/nv; cd $D
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
mkfifo fifo; $P/agg/agg fifo . > agg.log 2>&1 &
FL_FROM=$3 FL_TO=$4 TR_FIFO=$D/fifo HARNESS_TARGET=neo HARNESS_MOVIE=${5:-$P/bot200k.txt} HARNESS_FRAMES=$(($4+10)) timeout -s KILL 20000 ~/mame/aerofgtneo aerofgtn -rompath "$R;$HOME/AeroFgtNeo/mame_roms" -nvram_directory nv $M -debug -debugger none -autoboot_script $P/ptr.lua > log 2>&1
wait; rm -f fifo; cat summary.txt
