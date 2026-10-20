-- gtdiag.lua (FUSED=2): every 500 game frames: builds, skipped (no free set), begun late,
-- LATE, the set states, HAL_FRAMES, drops.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3000"); local FZV=0xd0e300
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  if f>0 and f%500==0 then
    out:write(string.format("gf %d HF %d builds %d skipped %d late %d LATE %d st %d%d%d shown %d DROP %d gtset %d\n",f,sp:read_u32(0xd0085c),sp:read_u32(FZV+192),sp:read_u32(FZV+188),sp:read_u32(FZV+196),sp:read_u32(0xd00ba4),sp:read_u8(0xd00b68),sp:read_u8(0xd00b69),sp:read_u8(0xd00b6a),sp:read_i16(0xd00b9c),sp:read_u32(0xd00ba0),sp:read_i16(FZV+170))); out:write(string.format("   waits %d stale %d\n",sp:read_u32(FZV+212),sp:read_u32(FZV+216))); out:flush()
  end
  if f>=N then out:close(); m:exit() end
end)
