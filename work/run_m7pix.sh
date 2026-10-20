#!/bin/sh
# run_m7pix.sh <romdir> <outdir>: movie7 with HAL log, PRE and pixel capture
cd ~/AeroFgtNeo; R=$1; D=$2; mkdir -p $D
M="-cfg_directory cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
rm -rf $D/nv; HARNESS_TARGET=neo HARNESS_MOVIE=work/movie7.txt HARNESS_DUMP=$D/neo.bin HARNESS_HALLOG=$D/hal.bin HARNESS_PRE=$D/pre.bin HARNESS_PIXELS=$D/pix.bin HARNESS_FRAMES=10000 timeout -s KILL 5000 ~/mame/aerofgtneo aerofgtn -rompath "$R;mame_roms" -nvram_directory $D/nv $M -autoboot_script tests/harness.lua >/dev/null 2>&1
python3 tests/compare_state.py work/eq7/orig.bin $D/neo.bin | tail -1
