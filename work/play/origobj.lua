dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local pv=-1; local n=0
emu.register_frame_done(function() n=n+1
  local v=sp:read_u8(0xff0300); local g=HARNESS_GAME_FRAME and HARNESS_GAME_FRAME() or -1
  if v~=pv then out:write(string.format("sf=%d g=%d obj=%02x\n",n,g,v)); pv=v end end)
