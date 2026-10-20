-- slotdump.lua (HARNESS_TARGET=neo, botsel.lua): the state bytes of the main loop's 255 object slots
-- (0x1010c0..0x107000, stride 0x60) at every frame end of F0..F1, one 255-byte record a frame after
-- the frame number (u32 LE) - for simulating slot-scan variants offline.  Env: OUT, F0, F1
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"wb"); local F0=tonumber(os.getenv("F0")); local F1=tonumber(os.getenv("F1"))
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>=F0 and f<F1 then local t={}
    for a=0x1010c0,0x107000,0x60 do t[#t+1]=string.char(sp:read_u8(a)) end
    out:write(string.pack("<I4",f)..table.concat(t)) end
  if f>=F1 then out:close(); m:exit() end end)
