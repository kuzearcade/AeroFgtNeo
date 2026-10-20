#!/bin/sh
# runfh.sh <romdir> <outdir> <frames> <lua> [movie]: a bot playthrough with a probe script
# (work/play/fh/*.lua), output in <outdir>/out.txt
R=$1; O=$2; N=$3; L=$4; P=$HOME/AeroFgtNeo/work/play; MOV=${5:-$P/bot200k.txt}
rm -rf $O; mkdir -p $O/nv; cd $O
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
OUT=$O/out.txt N=$N HARNESS_TARGET=neo HARNESS_MOVIE=$MOV HARNESS_FRAMES=$N timeout -s KILL 20000 ~/mame/aerofgtneo aerofgtn -rompath "$R;$HOME/AeroFgtNeo/mame_roms" -nvram_directory $O/nv $M -autoboot_script $P/fh/$L > log 2>&1
echo "$O done $(wc -l < out.txt)"
