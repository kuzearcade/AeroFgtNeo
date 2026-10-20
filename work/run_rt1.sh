#!/bin/sh
# run_rt1.sh <romdir> <outdir>: movie1 with HAL log + pixels, RAM check, HAL counters, picture check
cd ~/AeroFgtNeo; R=$1; D=$2; rm -rf $D; mkdir -p $D; ln -sf ~/AeroFgtNeo/work/eq/orig.bin $D/orig.bin
M="-cfg_directory cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
HARNESS_TARGET=neo HARNESS_MOVIE=work/movie1.txt HARNESS_DUMP=$D/neo.bin HARNESS_FRAMES=1500 HARNESS_SLIPLOG=$D/slip.bin HARNESS_HALLOG=$D/hal.bin HARNESS_NEOPAL=$D/npal.bin HARNESS_PRE=$D/pre.bin HARNESS_PIXELS=$D/pix_neo.bin timeout -s KILL 2400 ~/mame/aerofgtneo aerofgtn -rompath "$R;mame_roms" -nvram_directory $D/nv1 $M -autoboot_script tests/harness.lua > $D/mame.log 2>&1
python3 tests/compare_state.py work/eq/orig.bin $D/neo.bin | tail -1
python3 - $D <<'PY'
import sys; sys.path.insert(0,'tests'); import hallog
names=[('HAL_SPR_LATE',4),('HAL_SPR_MIXN',4),('HAL_SPR_DROP',4),('HAL_SPR_DROPN',4),('HAL_SPR_CARRY',4),('HAL_SPR_VZN',4),('HAL_OVERRUN',4),('HAL_SPR_DBGI',2)]
log=hallog.load(sys.argv[1]+'/hal.bin'); last=max(log); g=log[last]
print(last,{n:g(n,s) for n,s in names})
PY
FULL_ALL=1 python3 tests/compare_full.py $D/orig.bin $D/pre.bin $D/pix_neo.bin 1 > $D/full_report.txt 2>&1; head -c 200 $D/full_report.txt; echo
