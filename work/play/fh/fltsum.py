import sys, numpy as np
for b in sys.argv[1:]:
    rows=[l.split() for l in open('/home/vboxuser/AeroFgtNeo/work/play/fh/flt_%s/out.txt'%b)]
    rows=[r for r in rows if len(r)>=21 and '32767' not in r[1:4]]
    t=np.array([[int(x) for x in r[1:10]] for r in rows]); sh=np.array([int(r[13]) for r in rows]); pbn=np.array([[int(r[15]),int(r[16]),int(r[17])] for r in rows]); bp=np.array([[int(r[19]),int(r[20]),int(r[21])] for r in rows])
    flip=t[:,1]-t[:,0]; hud=bp[:,1]-bp[:,0]; pool=bp[:,2]-bp[:,1]; pre=bp[:,0]-t[:,0]; post=t[:,1]-bp[:,2]
    print(b,len(rows),'frames: flip %.2f lines = before hud %.2f + hud %.2f + pool %.2f + after %.2f; pool p90 %d max %d; hud p90 %d max %d'%(flip.mean(),pre.mean(),hud.mean(),pool.mean(),post.mean(),np.percentile(pool,90),pool.max(),np.percentile(hud,90),hud.max()))
    for lo,hi in ((0,1),(1,8),(8,16),(16,24),(24,33)):
        s=(sh>=lo)&(sh<hi)
        if s.sum(): print('   shown %2d-%2d: %5d frames, pool lines mean %.2f p90 %d, hud %.2f, pre %.2f'%(lo,hi-1,s.sum(),pool[s].mean(),np.percentile(pool[s],90),hud[s].mean(),pre[s].mean()))
