dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local last=-1; local every=tonumber(os.getenv("SAVE_EVERY") or "10000")
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME(); if f==last then return end; last=f
  if f>0 and f%every==0 then manager.machine:save(string.format("s%06d",f)) end
end)
