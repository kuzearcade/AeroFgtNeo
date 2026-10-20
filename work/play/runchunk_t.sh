#!/bin/sh
# runchunk.sh <orig|neo> <from> <to>: trace game frames from..to (state s<from> unless 0) into tr_<t>/c<from>/
t=$1; F=$2; T=$3; P=$HOME/AeroFgtNeo/work/play; D=$P/octest/$NEOGEO_CPU_SCALE; rm -rf $D; mkdir -p $D; cd $D
M="-cfg_directory cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
if [ $t = orig ]; then G="aerofgt -rompath $HOME/AeroFgtNeo/mame_roms"; else G="aerofgtn -rompath $HOME/AeroFgtNeo/work/out_wf;$HOME/AeroFgtNeo/mame_roms"; fi
ST=""; [ $F -gt 0 ] && ST="-state $(printf s%06d $F)"
mkfifo fifo
$P/agg/agg fifo . > agg.log 2>&1 &
MAME_COVERAGE_DIR=$D TR_FIFO=$D/fifo HARNESS_FRAME0=$F HARNESS_TARGET=$t HARNESS_MOVIE=$P/bot200k.txt HARNESS_FRAMES=$T timeout -s KILL 30000 ~/mame/aerofgtneo $G -state_directory $P/st_$( [ $t = neo ] && echo wf || echo $t) $ST -nvram_directory nv $M -debug -debugger none -autoboot_script $P/chunk.lua > log 2>&1
wait
rm -f fifo
echo "$t $F done $(cat summary.txt)"
