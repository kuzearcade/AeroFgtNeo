#!/bin/sh
# runlag.sh <romdir> <outdir> <frames> [movie]: bot playthrough with lag2.lua (no trace)
R=$1; O=$2; N=$3; P=$HOME/AeroFgtNeo/work/play; MOV=${4:-$P/bot200k.txt}
rm -rf $O; mkdir -p $O/nv; cd $O
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
OUT=$O/lag.txt HARNESS_TARGET=neo HARNESS_MOVIE=$MOV HARNESS_FRAMES=$N timeout -s KILL 20000 ~/mame/aerofgtneo aerofgtn -rompath "$R;$HOME/AeroFgtNeo/mame_roms" -nvram_directory $O/nv $M -autoboot_script $P/fp/lag2.lua > log 2>&1
echo "$O done $(wc -l < lag.txt)"
