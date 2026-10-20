#!/bin/sh
# run_cmp3.sh <romdir> <outdir>: movie7 (10000) + attract (6000): HAL counters, RAM check, pixels for the HUD check
cd ~/AeroFgtNeo; R=$1; D=$2; rm -rf $D; mkdir -p $D/m7 $D/att
M="-cfg_directory cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
(HARNESS_MARK=1 HARNESS_TARGET=neo HARNESS_MOVIE=work/movie7.txt HARNESS_DUMP=$D/m7/neo.bin HARNESS_HALLOG=$D/m7/hal.bin HARNESS_PRE=$D/m7/pre.bin HARNESS_PIXELS=$D/m7/pix.bin HARNESS_FRAMES=10000 timeout -s KILL 5000 ~/mame/aerofgtneo aerofgtn -rompath "$R;mame_roms" -nvram_directory $D/m7/nv $M -autoboot_script tests/harness.lua > $D/m7/mark.txt 2>&1) &
(HARNESS_MARK=1 HARNESS_TARGET=neo HARNESS_MOVIE=work/movie_idle.txt HARNESS_DUMP=$D/att/neo.bin HARNESS_HALLOG=$D/att/hal.bin HARNESS_PRE=$D/att/pre.bin HARNESS_PIXELS=$D/att/pix.bin HARNESS_FRAMES=6000 timeout -s KILL 5000 ~/mame/aerofgtneo aerofgtn -rompath "$R;mame_roms" -nvram_directory $D/att/nv $M -autoboot_script tests/harness.lua > $D/att/mark.txt 2>&1) &
wait
python3 tests/compare_state.py work/eq7/orig.bin $D/m7/neo.bin | tail -1
python3 tests/compare_state.py work/eqa/orig.bin $D/att/neo.bin | tail -1
python3 - $D <<'PY'
import sys; sys.path.insert(0,'tests'); import hallog
names=[('HAL_SPR_LATE',4),('HAL_SPR_MIXN',4),('HAL_SPR_DROP',4),('HAL_SPR_DROPN',4),('HAL_SPR_CARRY',4),('HAL_OVERRUN',4)]
for p in ('m7','att'):
    log=hallog.load(sys.argv[1]+'/'+p+'/hal.bin'); last=max(log); g=log[last]
    print(p,last,{n:g(n,s) for n,s in names})
PY
python3 work/hudpix.py $D/m7/pix.bin $D/att/pix.bin
