dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local f=0
emu.register_frame_done(function() f=f+1
  if f==500 then print(string.format("SND %04x %04x %04x %04x", sp:read_u16(0xd00f50),sp:read_u16(0xd00f52),sp:read_u16(0xd00f54),sp:read_u16(0xd00f56))) end end)
