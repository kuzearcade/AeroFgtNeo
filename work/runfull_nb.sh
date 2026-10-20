#!/bin/sh
cd ~/AeroFgtNeo
rm -rf nvram/aerofgtn
HARNESS_SLIPLOG=work/eq/slip.bin HARNESS_HALLOG=work/eq/hal.bin HARNESS_NEOPAL=work/eq/npal.bin HARNESS_PRE=work/eq/pre.bin HARNESS_PIXELS=work/eq/pix_neo.bin timeout 2400 tests/run_eq.sh aerofgtn 1500 2>&1 | tail -1
FULL_ALL=1 python3 tests/compare_full.py work/eq/orig.bin work/eq/pre.bin work/eq/pix_neo.bin 1 > work/eq/full_report.txt 2>&1
head -c 300 work/eq/full_report.txt; echo
python3 - <<'PY'
import struct, collections
d=open('/home/vboxuser/AeroFgtNeo/work/eq/npal.bin','rb').read(); R=24+0x2000
c=collections.Counter()
for i in range(len(d)//R):
    slip=struct.unpack('<H',d[i*R+12:i*R+14])[0]
    for b,n in ((1,'pal'),(2,'bg'),(4,'spr')):
        if slip&b: c[n]+=1
print(dict(c))
PY
python3 tests/slipcheck.py work/eq 1
