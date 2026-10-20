-- at the first drop per game frame with a split set: dump the converting and shown lists
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local cur=-2; local tap; local n=0; local last=-1
local LT={0xd0e000,0xd0e800,0xd0ec00,0xd0f800,0xd0fc00}
local function lst(b)
  if b<0 or b>4 then return "" end
  local k=sp:read_u16(0xd0f180+2*b); local a=LT[b+1]; local t={}
  for i=0,k-1 do t[#t+1]=string.format("%04x%04x%04x%04x",sp:read_u16(a+8*i),sp:read_u16(a+8*i+2),sp:read_u16(a+8*i+4),sp:read_u16(a+8*i+6)) end
  return table.concat(t,",") end
local function snap()
  local f=HARNESS_GAME_FRAME and HARNESS_GAME_FRAME() or -1
  if f==cur then return end; cur=f
  if sp:read_i8(0xd00fde)<0 then return end
  local cpu=manager.machine.devices[":maincpu"]; local cb=sp:read_i16(0xd0f018)
  local a5=cpu.state["A5"].value; local idx=-1
  if cb>=0 and cb<=4 then idx=(a5-8-LT[cb+1])//8 end
  out:write(string.format("%d M W=%d sps=%d idx=%d delta=%d\n",f,sp:read_i16(0xd00b98),sp:read_i8(0xd00fde),idx,sp:read_u8(0xd0f620)))
  out:write(string.format("%d C %s\n%d S %s\n",f,lst(cb),f,lst(sp:read_i16(0xd0f660)))); out:flush()
end
local function inst() tap=sp:install_write_tap(0xd00ba0,0xd00ba3,"drop",function(o,d,m) snap() end) end
inst()
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME(); if f==last then return end; last=f
  n=n+1; if n%300==0 then if tap then tap:remove() end; inst() end
end)
