#!/bin/sh
# runov.sh <romdir> <name> [seeds]: bot playthroughs with ovstat.lua (OVR_DIAG builds), 200k frames each
R=$1; N=$2; P=$HOME/AeroFgtNeo/work/play; L=${LUA:-ovstat.lua}; S=${3:-"7 8 9 10 11 12 13 14 15"}
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
for s in $S; do
  m=$P/bot200k_$s.txt; [ $s = 7 ] && m=$P/bot200k.txt
  O=$P/ov/${N}_$s; rm -rf $O; mkdir -p $O/nv
  OUT=$O/c0.txt HARNESS_TARGET=neo HARNESS_MOVIE=$m HARNESS_FRAMES=${FR:-200000} timeout -s KILL 20000 ~/mame/aerofgtneo aerofgtn -rompath "$R;$HOME/AeroFgtNeo/mame_roms" -nvram_directory $O/nv $M -autoboot_script $P/$L > $O/log 2>&1 &
done
wait
