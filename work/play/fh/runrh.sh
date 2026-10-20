#!/bin/sh
# runrh.sh <nation> <outdir> <frames>: the original arcade with botsel.lua and romhits.lua
R=$HOME/AeroFgtNeo; P=$R/work/play; O=$2; rm -rf $O; mkdir -p $O/nv; cd $O
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
OUT=$O/out.txt N=$3 PDLIST=$P/fh/pdlist_fz46.txt NATION=$1 HARNESS_BOTFILE=$P/fp/botsel.lua HARNESS_TARGET=orig HARNESS_MOVIE=$P/bot200k.txt HARNESS_FRAMES=$3 timeout -s KILL 20000 ~/mame/aerofgtneo aerofgt -rompath "$R/mame_roms" -nvram_directory $O/nv $M -autoboot_script $P/fh/romhits.lua > log 2>&1
echo "$O done"
