#!/bin/sh
# runobj.sh orig|neo <romdir> <out> <movie>: objhud.lua over a whole playthrough
T=$1; R=$2; O=$3; P=$HOME/AeroFgtNeo/work/play; rm -rf $O.nv; mkdir -p $O.nv
M="-cfg_directory $P/cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
if [ $T = orig ]; then D=aerofgt; A=0xff0300; else D=aerofgtn; A=0x101300; fi
OBJ=$A OUT=$O HARNESS_TARGET=$T HARNESS_MOVIE=$4 HARNESS_FRAMES=200000 timeout -s KILL 20000 ~/mame/aerofgtneo $D -rompath "$R;$HOME/AeroFgtNeo/mame_roms" -nvram_directory $O.nv $M -autoboot_script $P/objhud.lua > $O.log 2>&1
