"""hudcheck.py <rundir>...: movie7 runs (work/run_m7pix.sh) - frames around each set shown with
dropped sprites (HAL_SPR_DROPN steps): pixels of the HUD strips (x 288-319; x 0-15 at the bomb
stocks) that differ from the original's render.  A frame counts as 'HUD hit' above 150."""
import os,struct,sys,numpy as np
sys.path.insert(0,'tests'); sys.path.insert(0,'tools')
import compare_full as cf, romset, gfx, hallog
from compare_bg import REC,POFF,PRE,neo_rgb_table
r=romset.load_aerofgt('mame_roms/aerofgt.zip'); t8=gfx._unpack_tiles8(r["tiles"]); spr=gfx._unpack_sprites(r["sprites"]); rgb=neo_rgb_table()
pals={}
with open('work/eq7/orig.bin','rb') as f:
    while True:
        b=f.read(REC)
        if len(b)<REC: break
        pals[struct.unpack_from('<I',b)[0]]=np.frombuffer(b[POFF:POFF+0x800],'>u2').astype(np.int32)
mask=np.zeros((224,320),bool); mask[:,288:]=True; mask[0:56,0:16]=True; mask[112:168,0:16]=True
for d in sys.argv[1:]:
    log=hallog.load(d+'/hal.bin'); prev=0; ev=[]
    for gf in sorted(log):
        v=log[gf]('HAL_SPR_DROPN',4)
        if v!=prev: ev.append(gf); prev=v
    want=set()
    for g in ev:
        for k in range(g-3,g+4): want.add(k)
    pres={}
    with open(d+'/pre.bin','rb') as f:
        while True:
            b=f.read(PRE)
            if len(b)<PRE: break
            g=struct.unpack_from('<I',b)[0]
            if g in want or g+1 in want: pres[g]=b
    pix={}
    with open(d+'/pix.bin','rb') as f:
        while True:
            h=f.read(12)
            if len(h)<12: break
            gf,w,hh=struct.unpack('<III',h)
            if gf-1 in want: pix[gf]=np.frombuffer(f.read(w*hh*4),np.uint32).reshape(hh,w)&0xffffff
            else: f.seek(w*hh*4,1)
    hit=0; tot=0
    for k in sorted(want):
        if k not in pres or k-1 not in pres or k not in pals or k+1 not in pix: continue
        ref=cf.render_full(pres[k],pres[k-1],pals[k],t8,spr,rgb); got=pix[k+1]
        n=int(((ref!=got)&mask).sum()); tot+=1
        if n>150: hit+=1
    print(d,'sets with drops',len(ev),'| frames checked',tot,'HUD hit',hit)
