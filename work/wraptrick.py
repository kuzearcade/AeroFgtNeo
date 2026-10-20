"""wraptrick.py neo.bin hal.bin: attract per-line overflow (> 96) with tilemap-1 columns
full height / trimmed / trimmed with the wrap trick (fused builds: lists in sprite RAM)."""
import sys,struct,numpy as np
sys.path.insert(0,'tools'); sys.path.insert(0,'tests')
import gfx, romset, compare_state as c, hallog
NEO,HAL=sys.argv[1],sys.argv[2]
r=romset.load_aerofgt('mame_roms/aerofgt.zip')
t8=gfx._unpack_tiles8(r['tiles'])
blk=gfx.blocks(t8); shb=gfx.shifted_blocks(t8)
tr=np.zeros(0x20000,bool)
tr[gfx.BLK1_BASE:gfx.BLK1_BASE+len(blk)]=(blk==15).reshape(len(blk),-1).all(1)
tr[gfx.BLKS1_BASE:gfx.BLKS1_BASE+len(shb)]=(shb==15).reshape(len(shb),-1).all(1)
tr[gfx.C_TILES_USED]=True
uni=np.tile(t8[::0x800],(1,2,2)); tr[gfx.UNI1_BASE:gfx.UNI1_BASE+len(uni)]=(uni==15).reshape(len(uni),-1).all(1)
sys.argv=['x',NEO]
exec(open('work/walkmodel.py').read().split('prev = None; ok')[0])
hl=hallog.load(HAL)
BUF=0xff9900-0xfef000
def sprite_lines(P):
    line=np.zeros(224,np.int32)
    for w0,w1,w2,w3 in P:
        rows=((w0>>9)&7)+1; n=((w1>>9)&7)+1; oy=w0&0x1ff; y=oy-512 if oy>=224 else oy
        a=max(0,y); b=min(224,y+16*rows)
        if b>a: line[a:b]+=n
    return line
K=('full','hide','trim','wrap'); res=dict.fromkeys(K,0); worst=dict.fromkeys(K,0); frames=0; hidden=0; cols=0
for gf,b in c.frames(NEO):
    if gf<300 or gf not in hl: continue
    frames+=1
    km,Ls=lists(b); spr=sprite_lines(Ls[km])+21
    sy=hl[gf]('HAL_BG_SY',4)&0xffff
    rowlines={}
    for y in range(224):
        rowlines.setdefault(((y+sy)&511)>>4,[]).append(y)
    vis=sorted(rowlines,key=lambda rr: rowlines[rr][0])
    cov={k:np.zeros(224,np.int32) for k in K}
    for s in range(21):
        words=struct.unpack_from('>64H',b,BUF+(32+s)*128)
        content=[not tr[words[2*rr]] for rr in range(32)]
        cov['full']+=1; cols+=1
        crow=[i for i,rr in enumerate(vis) if content[rr]]
        if not crow: hidden+=1; continue
        cov['hide']+=1
        i0,i1=crow[0],crow[-1]
        for rr in vis[i0:i1+1]: cov['trim'][rowlines[rr]]+=1
        best=None; i=i0
        while i<=i1:
            if not content[vis[i]]:
                j=i
                while j<=i1 and not content[vis[j]]: j+=1
                if best is None or j-i>best[1]-best[0]: best=(i,j)
                i=j
            else: i+=1
        for k2 in range(i0,i1+1):
            if best and best[0]<=k2<best[1]: continue
            cov['wrap'][rowlines[vis[k2]]]+=1
    for k in K:
        m=int((spr+cov[k]).max()); worst[k]=max(worst[k],m); res[k]+=m>96
print('frames',frames,'over 96:',res,'worst line:',worst,'| front columns fully empty in view: %.0f%%'%(100*hidden/cols))
