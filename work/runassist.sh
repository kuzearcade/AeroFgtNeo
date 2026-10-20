#!/bin/sh
cd ~/AeroFgtNeo
rm -rf nvram/aerofgtna
HARNESS_TARGET=neo HARNESS_MOVIE=work/movie1.txt HARNESS_DUMP=work/eq/neo_a.bin HARNESS_PIXELS=work/eq/pix_neo_a.bin HARNESS_FRAMES=1500 timeout -s KILL 1800 ~/mame/aerofgtneo aerofgtna -rompath "out;mame_roms" -cfg_directory cfg -nvram_directory nvram -skip_gameinfo -nothrottle -video none -sound none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none -autoboot_script tests/harness.lua 2>&1 | grep -v "CHECKSUM\|EXPECTED\|FOUND\|might not\|doesn't make" | tail -1
python3 tests/compare_state.py work/eq/orig.bin work/eq/neo_a.bin | tail -1
python3 tests/compare_pixels.py work/eq/pix_orig.bin work/eq/pix_neo_a.bin 2
