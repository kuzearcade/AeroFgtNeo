-- begtap.lua: per set begun (HAL_SPR_W := set), with a set split: where, the ring, the list's columns
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local cpu=manager.machine.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("V_OUT"),"w")
local taps={}; local f=0; local n=0
local function onw(o,d,m)
  if (o&~1)~=0xd00b98 or d>2 then return end
  local sps=sp:read_i8(0xd00fde); if sps<0 then return end
  local cl=sp:read_u32(0xd0f01a); local nn=sp:read_u16(0xd0f004)//8
  local s=4; for i=0,nn-1 do s=s+((sp:read_u16(cl+8*i+2)>>9)&7)+1 end
  local ordn=sp:read_u8(0xd00fae); local o2={} for i=0,ordn-1 do local st=sp:read_u8(0xd00faf+i); o2[#o2+1]=string.format("%d[st%d %d..%d]",st,sp:read_u8(0xd00b68+st),sp:read_u16(0xd00fba+2*st),sp:read_u16(0xd00fcc+2*st)) end
  n=n+1
  out:write(string.format("f%d W%d pc %06x sum %d n %d sps %d spj %d spg %d delta %d pon %d skip %d why %d ord %s\n",HARNESS_GAME_FRAME(),d,cpu.state["PC"].value,s,nn,sps,sp:read_u16(0xd00fe0),sp:read_u16(0xd00fe2),sp:read_u8(0xd0f620),sp:read_u8(0xd0f640),sp:read_u8(0xd0f6d9),sp:read_u16(0xd0e5e0),table.concat(o2," "))) out:flush()
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd00b98,0xd00b99,"w",onw)} end
inst()
emu.register_frame_done(function() f=f+1; if f%300==0 then inst() end end)
