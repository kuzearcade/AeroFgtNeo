#!/bin/sh
# runlag_orig.sh <outdir> <frames> [movie]: the ORIGINAL arcade game (MAME aerofgt) on a bot movie
# with lag_orig.lua (the same per-frame lost-logic record as lag2.lua's): lagsum.py reads it
O=$1; N=$2; P=$HOME/AeroFgtNeo/work/play; MOV=${3:-$P/bot200k.txt}
rm -rf $O; mkdir -p $O/nv; cd $O
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
OUT=$O/lag.txt HARNESS_TARGET=orig HARNESS_MOVIE=$MOV HARNESS_FRAMES=$N timeout -s KILL 20000 ~/mame/aerofgtneo aerofgt -rompath "$HOME/AeroFgtNeo/mame_roms" -nvram_directory $O/nv $M -autoboot_script $P/fp/lag_orig.lua > log 2>&1
echo "$O done $(wc -l < lag.txt)"
