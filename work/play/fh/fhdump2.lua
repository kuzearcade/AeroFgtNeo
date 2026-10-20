-- fhdump2.lua: at the first sprite-set flip once the game's logic round AT_ROUND is reached
-- (rounds: builder-point writes at 0x2bfaa), the shown set's heads: column, SCB3 value,
-- SCB4, and the head column's first 4 SCB1 words.  Env: OUT, AT_ROUND
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local vi=nil
for name, idx in pairs(m.devices[":spritegen"].items) do
  if name:find("m_videoram") then vi=emu.item(idx) end
end
local out=io.open(os.getenv("OUT"),"w")
local AT=tonumber(os.getenv("AT_ROUND") or "195")
local SETS=0x10a280; local SSZ=510; local HOFF=10; local HADR=62; local HVAL=286
local round=0; local done=false
local taps={}
local function onr(o,d,mk)
  if (o&~1)~=0x10a236 then return end
  local pc=cpu.state["PC"].value
  if pc>=0x2bfaa and pc<=0x2bfb6 then round=round+1 end
end
local function onw(o,d,mk)
  if (o&~1)~=0xd00b9c or done or round<AT then return end
  local s=d & 0xffff; if s>2 then return end
  done=true
  local ss=SETS+SSZ*s; local nh=sp:read_u16(ss+HOFF)//2
  out:write(string.format("gf %d HF %d round %d set %d heads %d\n",HARNESS_GAME_FRAME(),sp:read_u32(0xd0085c),round,s,nh))
  for i=0,nh-1 do
    local a=sp:read_u16(ss+HADR+2*i); local v=sp:read_u16(ss+HVAL+2*i); local col=a-0x8200
    local t={} for r=0,3 do t[#t+1]=string.format("%04x/%04x",vi:read(64*col+2*r),vi:read(64*col+2*r+1)) end
    out:write(string.format(" head %2d col %3d scb3 %04x scb4 %04x : %s\n",i,col,v,vi:read(0x8400+col),table.concat(t," ")))
  end
  out:close(); m:exit()
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd00b9c,0xd00b9d,"fh",onw),sp:install_write_tap(0x10a236,0x10a237,"rd",onr)} end
inst()
local f=0
emu.register_frame_done(function() f=f+1; if f%300==0 then inst() end end)
