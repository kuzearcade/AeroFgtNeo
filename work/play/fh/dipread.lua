dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f==100 then local t={} for i=0,15 do t[#t+1]=string.format("%02x",sp:read_u8(0xd00810+i)) end print("HAL_SOFTDIP",table.concat(t," "))
    local u={} for i=0,15 do u[#u+1]=string.format("%02x",sp:read_u8(0x10fd84+i)) end print("BIOS_GAME_DIP",table.concat(u," ")); m:exit() end end)
