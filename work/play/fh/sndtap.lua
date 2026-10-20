-- sndtap.lua: sound CPU program reads at 0xf800-0xffff (on the arcade: the top 2 KB of the banked
-- window; on the Neo Geo: the relocated driver RAM) - per game frame with reads: the count, the
-- arcade's current bank (OUT ($04)), the distinct reading PCs, the stage index and id.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local z=m.devices[":audiocpu"]; local zp=z.spaces["program"]; local zio=z.spaces["io"]
local sp=m.devices[":maincpu"].spaces["program"]
local neo=os.getenv("HARNESS_TARGET")=="neo"; local C=neo and 0x10d000 or 0xffc000
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "200000")
local bank=-1; local cnt=0; local pcs={}; local lo,hi=0xffff,0
local t1,t2
local function inst()
  if t1 then t1:remove() end; if t2 then t2:remove() end
  t1=zp:install_read_tap(0xf800,0xffff,"hi",function(o,d,mk) local pc=z.state["PC"].value
    if not neo or (pc<0x7800) then cnt=cnt+1; pcs[pc]=true; if o<lo then lo=o end; if o>hi then hi=o end end end)
  if not neo then t2=zio:install_write_tap(0x04,0x04,"bank",function(o,d,mk) bank=d&0xff end) end
end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f%300==0 then inst() end
  if cnt>0 then local idx=sp:read_u16(C+0x110); local sid=255; if idx>=1 and idx<=7 then sid=sp:read_u8(C+0x100+idx-1) end
    local l={} for pc in pairs(pcs) do l[#l+1]=string.format("%04x",pc) end; table.sort(l)
    out:write(string.format("%d n %d bank %d range %04x-%04x idx %d sid %d pcs %s\n",f,cnt,bank,lo,hi,idx,sid,table.concat(l,","))) end
  cnt=0; pcs={}; lo,hi=0xffff,0
  if f>=N-5 then out:close(); m:exit() end end)
