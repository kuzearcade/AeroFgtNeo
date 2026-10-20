-- oc.lua: try the CPU clock scale from Lua (an A/B with no lag in either build)
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w")
out:write("clock "..tostring(cpu.clock).."\n")
local ok,err=pcall(function() cpu:set_clock_scale(tonumber(os.getenv("SCALE") or "3")) end)
out:write("set_clock_scale ok "..tostring(ok).." "..tostring(err).."\n")
out:write("clock now "..tostring(cpu.clock).."\n")
local N=tonumber(os.getenv("N") or "1500")
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  if f%500==0 then out:write(string.format("gf %d LATE %d SLOWB %d TIMN %d OVERRUN %d busy %d\n",f,sp:read_u32(0xd00ba4),sp:read_u32(0xd00878),sp:read_u32(0xd0086c),sp:read_u32(0xd00be0),sp:read_u8(0xd00f44))); out:flush() end
  if f>=N then out:close(); m:exit() end
end)
