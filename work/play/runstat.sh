#!/bin/sh
# runstat.sh <romdir> <outdir> <from> <to> [cpu scale]: HAL late/drop/overrun counters per game frame
# (neostat.lua) for game frames from..to, started from st_wf state s<from>, -> <outdir>/c<from>.txt
R=$1; O=$2; F=$3; T=$4; P=$HOME/AeroFgtNeo/work/play; mkdir -p $O/nv$F
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
ST=""; [ $F -gt 0 ] && ST="-state $(printf s%06d $F)"
[ -n "$5" ] && export NEOGEO_CPU_SCALE=$5
OUT=$O/c$F.txt HARNESS_FRAME0=$F HARNESS_TARGET=neo HARNESS_MOVIE=$P/bot200k.txt HARNESS_FRAMES=$T timeout -s KILL 20000 ~/mame/aerofgtneo aerofgtn -rompath "$R;$HOME/AeroFgtNeo/mame_roms" -state_directory $P/st_wf $ST -nvram_directory $O/nv$F $M -autoboot_script $P/neostat.lua > $O/log$F 2>&1
echo "$O $F done"
