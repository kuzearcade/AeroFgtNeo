-- livescan.lua (arcade): every 30 real frames the work RAM 0xff0000-0xfffeff (not the I/O page at 0xffff00:
-- reading it has side effects) as raw bytes; stops at N real frames, whatever the game frame says.
-- For finding the lives counter.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"wb"); local N=tonumber(os.getenv("N") or "12000"); local n=0
emu.register_frame_done(function() n=n+1
  if n%30==0 then out:write(string.pack("<I4I4",n,HARNESS_GAME_FRAME())..sp:read_range(0xff0000,0xfffeff,8)) end
  if n>=N then out:close(); m:exit() end end)
