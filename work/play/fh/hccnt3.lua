-- hccnt3.lua (FZ_DIAG builds): the HUD cache's counters (entries/shown/hits/renewed at $d0fdf6/8/a/c),
-- FZ_LUTGEN and the prologue's exits FZ_HX (FZ_V+144, 8 w: HOK, HSEEN, HCOK, cells, key y/x, w2,
-- table, entries differ) every 250 game frames.  Env OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3000")
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f%250==0 then local x={}; for i=0,7 do x[#x+1]=tostring(sp:read_u16(0xd0e300+144+2*i)) end
    out:write(string.format("%d entries %d shown %d hits %d renewed %d lutgen %d exits %s\n",f,sp:read_u16(0xd0fdf6),sp:read_u16(0xd0fdf8),sp:read_u16(0xd0fdfa),sp:read_u16(0xd0fdfc),sp:read_u16(0xd0fdf2),table.concat(x," "))); out:flush() end
  if f>=N-5 then out:close(); m:exit() end end)
