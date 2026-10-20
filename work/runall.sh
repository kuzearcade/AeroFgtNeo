#!/bin/sh
# runall.sh <build suffix>: regression (run_cmp3), visibility check, game-over test, reset check
cd ~/AeroFgtNeo; b=$1
M="-cfg_directory cfg -skip_gameinfo -nothrottle -sound none -video none -keyboardprovider none -mouseprovider none -joystickprovider none -lightgunprovider none"
( sh work/run_cmp3.sh work/out_$b work/c3_$b > work/c3_$b.txt 2>&1 ) &
( sh work/vischk.sh work/out_$b work/vc_$b > work/vc_$b.txt 2>&1 ) &
D=work/go_$b; rm -rf $D; mkdir -p $D
( HARNESS_TARGET=neo HARNESS_MOVIE=work/movie7_go.txt HARNESS_PIXELS=$D/pix.bin HARNESS_FRAMES=2600 timeout -s KILL 2500 ~/mame/aerofgtneo aerofgtn -rompath "work/out_$b;mame_roms" -nvram_directory $D/nv $M -autoboot_script tests/harness.lua > $D/log 2>&1 ) &
wait
cat work/c3_$b.txt work/vc_$b.txt
python3 work/resetchk.py work/c3_$b/m7/pix.bin
python3 work/hp/gofind.py $b
python3 - $b <<'PY'
import sys; sys.path.insert(0,'tests'); import hallog
b=sys.argv[1]
for t in ('m7','att'):
    log=hallog.load('work/c3_%s/%s/hal.bin'%(b,t)); g=max(log); f=log[g]
    print(b,t,{n:f(n,4) for n in ('HAL_SLOWN','HAL_SLOWB','HAL_SPR_LATE','HAL_SPR_DROP','HAL_SPR_DROPN','HAL_OVERRUN','HAL_PALDEFER')})
    pd=pn=0; bk={}
    for k in sorted(log):
        d=log[k]('HAL_SPR_DROP',4); n=log[k]('HAL_SPR_DROPN',4); e=bk.setdefault(k//400*400,[0,0]); e[0]+=d-pd; e[1]+=n-pn; pd,pn=d,n
    print('  drops/400:',' '.join(f'{k}:{v[0]}/{v[1]}' for k,v in sorted(bk.items()) if v[0] or v[1]))
PY
