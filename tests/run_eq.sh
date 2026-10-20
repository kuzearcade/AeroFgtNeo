#!/bin/sh
# run_eq.sh <set> [frames] - run the harness on a conversion set with movie1 and
# compare against the original dump (work/eq/orig.bin).  Extra env passes through.
set -e
cd "$(dirname "$0")/.."
SET=${1:-aerofgtn}; N=${2:-1500}
HARNESS_TARGET=neo HARNESS_MOVIE=work/movie1.txt HARNESS_DUMP=work/eq/neo.bin HARNESS_FRAMES=$N \
timeout -s KILL 1800 ~/mame/aerofgtneo $SET -rompath "out;mame_roms" -cfg_directory cfg -nvram_directory nvram \
	-skip_gameinfo -nothrottle -video none -sound none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none -autoboot_script tests/harness.lua 2>&1 \
	| grep -v "CHECKSUM\|EXPECTED\|FOUND\|might not run\|doesn't make" || true
python3 tests/compare_state.py work/eq/orig.bin work/eq/neo.bin | tail -3
