#!/bin/sh
# peaks.sh <suffix>...: late/drop counts in the dense windows (port frame numbers)
cd ~/AeroFgtNeo; python3 - "$@" <<'PY'
import sys; sys.path.insert(0,'tests'); import hallog
for b in sys.argv[1:]:
    for t,(lo,hi) in (('att',(4800,5400)),('att',(300,5900)),('m7',(7000,7600)),('m7',(300,9900))):
        log=hallog.load('work/c3_%s/%s/hal.bin'%(b,t))
        ks=sorted(log); a=min(k for k in ks if k>=lo); z=max(k for k in ks if k<=hi)
        d={n:log[z](n,4)-log[a](n,4) for n in ('HAL_SPR_LATE','HAL_SPR_DROP','HAL_SPR_DROPN','HAL_OVERRUN')}
        print('%-5s %-3s %4d-%4d late %4d (%2d%%) drop %5d dropframes %4d ovr %d'%(b,t,lo,hi,d['HAL_SPR_LATE'],100*d['HAL_SPR_LATE']//(z-a),d['HAL_SPR_DROP'],d['HAL_SPR_DROPN'],d['HAL_OVERRUN']))
PY
