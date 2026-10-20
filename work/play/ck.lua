-- (FX_O1CHK builds) fast-path checks: objects compared / different, every 10000 frames
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]; local last=-1
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME(); if f==last then return end; last=f
  if f%10000==0 or f==1000 then print(string.format("CK %d %d %d",f,sp:read_u32(0xd00f08),sp:read_u32(0xd00f0c))) end
end)
