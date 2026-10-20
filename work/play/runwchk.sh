#!/bin/sh
# runwchk.sh <romdir> <out file> [frames]: walk list checksums over the bot playthrough (FX_WCHK=1 builds)
R=$1; P=$HOME/AeroFgtNeo/work/play; D=$(mktemp -d -p $HOME/AeroFgtNeo/work)
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
OUT=$2 HARNESS_TARGET=neo HARNESS_MOVIE=$P/bot200k.txt HARNESS_FRAMES=${3:-20000} timeout -s KILL 20000 ~/mame/aerofgtneo aerofgtn -rompath "$R;$HOME/AeroFgtNeo/mame_roms" -nvram_directory $D $M -autoboot_script $P/wchk.lua > $D.log 2>&1
rm -rf $D
