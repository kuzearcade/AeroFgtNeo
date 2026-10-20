#!/bin/sh
# rundr.sh <romdir> <out> <movie> [frames]: dumpl.lua over a whole playthrough
R=$1; O=$2; P=$HOME/AeroFgtNeo/work/play; mkdir -p $O.nv
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
OUT=$O HARNESS_TARGET=neo HARNESS_MOVIE=$3 HARNESS_FRAMES=${4:-200000} timeout -s KILL 20000 ~/mame/aerofgtneo aerofgtn -rompath "$R;$HOME/AeroFgtNeo/mame_roms" -nvram_directory $O.nv $M -autoboot_script $P/dumpl.lua > $O.log 2>&1
