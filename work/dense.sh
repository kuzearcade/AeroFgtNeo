#!/bin/sh
# dense.sh <suffix> <romdir>: late/drops over the frames that are dense in that build's own run
# (attract: >= 20 pair bullets; gameplay: >= 55 active objects), from its run_cmp3 hal logs
cd ~/AeroFgtNeo; b=$1; R=$2; S=/tmp/claude-1000/-home-vboxuser-AeroFgtNeo/560dbddd-2c54-4bd4-b6db-4e3d9472357d/scratchpad
M="-cfg_directory cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
[ -s work/cen/bul_${b}_att.txt ] || CEN_OUT=work/cen/bul_${b}_att.txt CEN_TO=6000 HARNESS_TARGET=neo HARNESS_MOVIE=work/movie_idle.txt HARNESS_FRAMES=6100 timeout 1500 ~/mame/aerofgtneo aerofgtn -rompath "$R;mame_roms" -nvram_directory work/cen/nvd_${b}a $M -autoboot_script $S/bulcount.lua > /dev/null 2>&1 &
[ -s work/cen/bul_${b}_m7.txt ] || CEN_OUT=work/cen/bul_${b}_m7.txt CEN_TO=10000 HARNESS_TARGET=neo HARNESS_MOVIE=work/movie7.txt HARNESS_FRAMES=10100 timeout 2500 ~/mame/aerofgtneo aerofgtn -rompath "$R;mame_roms" -nvram_directory work/cen/nvd_${b}m $M -autoboot_script $S/bulcount.lua > /dev/null 2>&1 &
wait
python3 - $b <<'PY'
import sys; sys.path.insert(0,'tests'); import hallog
b=sys.argv[1]
for t,col,thr in (('att',1,20),('m7',2,55)):
    dense=set()
    for l in open('work/cen/bul_%s_%s.txt'%(b,t)):
        p=l.split()
        if int(p[col])>=thr: dense.add(int(p[0]))
    log=hallog.load('work/c3_%s/%s/hal.bin'%(b,t)); ks=sorted(log)
    tot={n:0 for n in ('HAL_SPR_LATE','HAL_SPR_DROP','HAL_SPR_DROPN')}; nf=0
    for i in range(1,len(ks)):
        if ks[i] in dense and ks[i]-ks[i-1]==1:
            nf+=1
            for n in tot: tot[n]+=log[ks[i]](n,4)-log[ks[i-1]](n,4)
    print('%-5s %-3s dense frames %4d  late %4d (%2d%%)  dropped sprites %5d  frames with drops %4d (%2d%%)'%(b,t,nf,tot['HAL_SPR_LATE'],100*tot['HAL_SPR_LATE']//max(nf,1),tot['HAL_SPR_DROP'],tot['HAL_SPR_DROPN'],100*tot['HAL_SPR_DROPN']//max(nf,1)))
PY
