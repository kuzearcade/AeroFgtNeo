-- dlstat.lua: per game frame in DL_FROM..DL_TO: updates in place (HAL_SPR_DELTAN), dl failure reasons (DL_WHYN), late
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local last=-1
local A,B=tonumber(os.getenv("DL_FROM")),tonumber(os.getenv("DL_TO"))
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME(); if f==last or f<A then return end; last=f
  local w={}; for i=1,15 do w[#w+1]=tostring(sp:read_u16(0xd0e5e2+2*(i-1))) end
  out:write(string.format("%d %d %d %d %s\n",f,sp:read_u32(0xd0087c),sp:read_u32(0xd00ba4),sp:read_u32(0xd00ba0),table.concat(w,",")))
  if f>=B then out:close(); manager.machine:exit() end
end)
