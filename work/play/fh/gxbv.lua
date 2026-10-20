-- gxbv.lua (HARNESS_TARGET=neo, a GX_BAND build with AEROFGT_GXCHECK=1): the collision
-- index's check, AUDIT 43 - HAL_GX_MISS (the indexed calls unlike the reference scan, and
-- gx_scan's own checks), the indexed calls, builds, calls scanned for a full list, entries in
-- range (tested again); every 10000 frames and at the end.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "60000")
local function line(f) out:write(string.format("frame %d miss %d indexed %d builds %d full %d inrange %d\n",f,
  sp:read_u32(0xd00874),sp:read_u32(0xd00f08),sp:read_u32(0xd00f0c),sp:read_u32(0xd00f14),sp:read_u32(0xd00f18))); out:flush() end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>0 and f%10000==0 then line(f) end
  if f>=N then line(f); out:close(); m:exit() end end)
