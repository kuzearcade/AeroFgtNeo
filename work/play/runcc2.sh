#!/bin/sh
# runcc2.sh <romdir> <outdir> <movie> <frames> [lua]: chain check (chainchk2.lua) over a bot movie
R=$1; D=$2; P=$HOME/AeroFgtNeo/work/play; rm -rf $D; mkdir -p $D/nv; cd $D
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
V_OUT=$D/z.txt HARNESS_TARGET=neo HARNESS_MOVIE=$3 HARNESS_FRAMES=$4 timeout -s KILL 20000 ~/mame/aerofgtneo aerofgtn -rompath "$R;$HOME/AeroFgtNeo/mame_roms" -nvram_directory nv $M -autoboot_script $P/${5:-chainchk2.lua} > log 2>&1
