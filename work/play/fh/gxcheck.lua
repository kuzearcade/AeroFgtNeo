-- gxcheck.lua: GX_VERIFY counters at the end of a run: HAL_GX_MISS (pre-test / table
-- disagreements), GXV_OUT (speeds outside the table), GXV_BIG (the largest |speed|).  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "20000")
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  if f%2000==0 or f>=N-10 then out:write(string.format("gf %d XPRE_MISS %d VEL: calls %d out %d miss %d big %d\n",f,sp:read_u32(0xd00874),sp:read_u32(0xd00f0c),sp:read_u32(0xd00f00),sp:read_u32(0xd00f08),sp:read_u16(0xd00f04))); out:flush() end
  if f>=N-10 then out:close(); m:exit() end
end)
