-- per frame: the 1P HUD object's active byte and the 1P label's white pixels; logged around changes of the byte
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]; local A=tonumber(os.getenv("OBJ"))
local out=io.open(os.getenv("OUT"),"w"); local pv=-1; local ring={}; local after=0; local n=0
emu.register_frame_done(function() n=n+1
  local v=sp:read_u8(A); local g=HARNESS_GAME_FRAME and HARNESS_GAME_FRAME() or -1
  local px,w,h=manager.machine.screens[":screen"]:pixels(); local lab=0
  for y=0,23 do for x=294,319 do local c=string.unpack("<I4",px,4*(y*w+x)+1)
    if (c>>16)&255>200 and (c>>8)&255>200 and c&255>200 then lab=lab+1 end end end
  local line=string.format("sf=%d g=%d obj=%02x lab=%d",n,g,v,lab)
  if v~=pv and n>1 then for _,l in ipairs(ring) do out:write(l.."\n") end; ring={}; out:write(line.." *\n"); after=4
  elseif after>0 then out:write(line.."\n"); after=after-1; if after==0 then out:write("--\n") end
  else ring[#ring+1]=line; if #ring>3 then table.remove(ring,1) end end
  pv=v end)
