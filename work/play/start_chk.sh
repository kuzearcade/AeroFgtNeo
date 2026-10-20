#!/bin/sh
# start_chk.sh <build>: 3-movie drop probe + commit check (bot 8) + chain check (bot 9)
P=$HOME/AeroFgtNeo/work/play; cd $P; B=$1
rm -rf dr_$B; mkdir -p dr_$B
for m in bot200k bot200k_8 bot200k_9; do sh rundr.sh ../out_$B dr_$B/$m.txt $m.txt > /dev/null 2>&1 & done
M="-cfg_directory ../cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
run() { rm -rf $1; mkdir -p $1; (cd $1; V_OUT=$PWD/$5 HARNESS_TARGET=neo HARNESS_MOVIE=$2 HARNESS_FRAMES=$3 timeout -s KILL 8000 ~/mame/aerofgtneo aerofgtn -rompath "../../out_$B;$HOME/AeroFgtNeo/mame_roms" -nvram_directory nv $M -autoboot_script ../$4 > log 2>&1 &) ; }
run cc_${B}_k8 $P/bot200k_8.txt 100000 kschk4.lua ks.txt
run cc_${B}_b9 $P/bot200k_9.txt 100000 chainchk_z.lua z.txt
wait
