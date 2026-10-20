-- fzcnt.lua: hal/fz.s counters every 2000 game frames and at the end: FZ_SKIP (builds without a
-- free buffer), FZ_NDUE (due buffers dropped), FZ_BLD (builds), FZ_PASSN (passes), FZ_NDUP
-- (duplicate-round buffers), HAL_SPR_DROP.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "20000"); local FZV=0xd0e300
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f%2000==0 or f>=N-5 then out:write(string.format("gf %d skip %d ndue %d builds %d passes %d ndup %d drops %d\n",f,sp:read_u16(FZV+64),sp:read_u16(FZV+66),sp:read_u32(FZV+68),sp:read_u32(FZV+72),sp:read_u16(FZV+228),sp:read_u32(0xd00ba0))); out:flush() end
  if f>=N-5 then out:close(); m:exit() end end)
