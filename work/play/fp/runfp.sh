#!/bin/sh
# runfp.sh <romdir> <outdir> <from> <to> [movie]: power-on bot playthrough, untraced to game frame
# <from>, then traced to <to> (fprof.c per-frame categories -> prof.txt) with the per-frame HAL
# state (fprof.lua -> stat.txt).  Rows of prof.txt are labelled from <from>: the first is partial.
R=$1; O=$2; F=$3; T=$4; P=$HOME/AeroFgtNeo/work/play; FP=$P/fp
MOV=${5:-$P/bot200k.txt}
rm -rf $O; mkdir -p $O/nv; cd $O
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
mkfifo fifo
$FP/fprof fifo prof.txt ${MAP:-$FP/map.txt} 9e8 $((F+1)) > fprof.log 2>&1 &
OUT=$O/stat.txt TR_FIFO=$O/fifo FL_FROM=$F FL_TO=$T HARNESS_TARGET=neo HARNESS_MOVIE=$MOV HARNESS_FRAMES=$((T+5)) \
  timeout -s KILL 30000 ~/mame/aerofgtneo aerofgtn -rompath "$R;$HOME/AeroFgtNeo/mame_roms" -nvram_directory $O/nv $M -debug -debugger none -autoboot_script $FP/fprof.lua > log 2>&1
wait
rm -f fifo
echo "$O done: $(wc -l < prof.txt) prof rows, $(wc -l < stat.txt) stat rows"
