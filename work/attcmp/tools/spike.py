import sys,subprocess,numpy as np
W,H=80,60
p=subprocess.Popen(['ffmpeg','-loglevel','error','-i',sys.argv[1],'-vf',f'crop=1440:1080:240:0,scale={W}:{H}','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
fr=[]
while True:
    b=p.stdout.read(W*H*3)
    if len(b)<W*H*3: break
    fr.append(np.frombuffer(b,np.uint8).reshape(H,W,3).astype(np.int16))
F=np.array(fr); n=len(F); print('frames',n)
d=lambda a,b: np.abs(F[a]-F[b]).mean()
hits=[]
for i in range(1,n-1):
    a,b,c=d(i-1,i),d(i,i+1),d(i-1,i+1)
    if a>12 and b>12 and c<0.35*min(a,b): hits.append((i,round(a,1),round(b,1),round(c,1)))
print(len(hits),'one-frame spikes'); [print(h) for h in hits[:40]]
