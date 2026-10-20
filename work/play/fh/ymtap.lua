-- ymtap.lua: per game frame, the YM2610 writes by class: FM key-ons (A:0x28 with operator bits),
-- FM key-offs, ADPCM-A key-ons (B:0x00 bit7 clear), ADPCM-B starts (A:0x10 bit7), SSG writes
-- (A:0x00-0x0d), all writes; and the stage index/id.  Same game on both targets (botsel.lua).  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local z=m.devices[":audiocpu"]; local zio=z.spaces["io"]
local sp=m.devices[":maincpu"].spaces["program"]
local neo=os.getenv("HARNESS_TARGET")=="neo"; local C=neo and 0x10d000 or 0xffc000; local base=neo and 4 or 0
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "200000")
local reg={[0]=0,[1]=0}; local c={kon=0,koff=0,aa=0,ab=0,ssg=0,all=0,ach={}}
local t
local function inst() if t then t:remove() end
  t=zio:install_write_tap(0x0000,neo and 0xffff or 0x00ff,"ym",function(o,d,mk) local lo=o&0xff
    if lo<base or lo>base+3 then return end; local port=lo-base; local side=port>>1
    if port&1==0 then reg[side]=d&0xff; return end
    local r=reg[side]; d=d&0xff; c.all=c.all+1
    if side==0 and r==0x28 then if d&0xf0~=0 then c.kon=c.kon+1; c.ach[d&7]=true else c.koff=c.koff+1 end
    elseif side==1 and r==0x00 then if d&0x80==0 and d~=0 then c.aa=c.aa+1 end
    elseif side==0 and r==0x10 then if d&0x80~=0 then c.ab=c.ab+1 end
    elseif side==0 and r<=0x0d then c.ssg=c.ssg+1 end end) end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f%300==0 then inst() end
  local idx=sp:read_u16(C+0x110); local sid=255; if idx>=1 and idx<=7 then sid=sp:read_u8(C+0x100+idx-1) end
  local ch=0 for k in pairs(c.ach) do ch=ch|(1<<k) end
  out:write(string.format("%d %d %d %d %d %d %d %d %d %02x\n",f,idx,sid,c.kon,c.koff,c.aa,c.ab,c.ssg,c.all,ch))
  c={kon=0,koff=0,aa=0,ab=0,ssg=0,all=0,ach={}}
  if f>=N-5 then out:close(); m:exit() end end)
