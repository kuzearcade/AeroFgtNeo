-- rcchk.lua: the record cache's shadow-mode counters (FZ_RCCHK builds): hits and mismatches
-- (FZ_RCHIT, FZ_RCBAD at FZ_V+246/+244) every 10,000 game frames and at the end.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "60000"); local FZV=0xd0e300
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f%10000==0 or f>=N-5 then out:write(string.format("gf %d hits %d bad %d builds %d\n",f,sp:read_u16(FZV+246),sp:read_u16(FZV+244),sp:read_u32(FZV+68))); out:flush() end
  if f>=N-5 then out:close(); m:exit() end end)
