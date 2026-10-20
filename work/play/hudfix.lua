-- per screen frame: non-zero fix cells of the 1P HUD (columns 36-39, rows 2-9); written when it changes
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local VR=emu.item(manager.machine.devices[":spritegen"].items["0/m_videoram"])
local out=io.open(os.getenv("OUT"),"w"); local f=0; local pv=-1
emu.register_frame_done(function()
  f=f+1; local n=0
  for c=36,39 do for r=2,9 do if VR:read(0x7000+c*32+r)~=0 then n=n+1 end end end
  if n~=pv then out:write(f.." "..sp:read_u16(0xd0085e).." "..n.."\n"); pv=n end
end)
