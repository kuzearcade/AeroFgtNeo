#!/bin/sh
# runfull.sh <romdir> <outdir> [frames]: whole bot playthrough from power-on, HAL counters per game frame
R=$1; O=$2; N=${3:-200000}; P=$HOME/AeroFgtNeo/work/play; rm -rf $O; mkdir -p $O/nv
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
OUT=$O/c0.txt HARNESS_TARGET=neo HARNESS_MOVIE=${MOVIE:-$P/bot200k.txt} HARNESS_FRAMES=$N timeout -s KILL 20000 ~/mame/aerofgtneo aerofgtn -rompath "$R;$HOME/AeroFgtNeo/mame_roms" -nvram_directory $O/nv $M -autoboot_script $P/neostat.lua > $O/log 2>&1
python3 $P/statsum.py $O
