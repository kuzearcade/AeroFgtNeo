dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "1200"); local pcs={}
sp:install_write_tap(0xd0e4d0,0xd0e4df,"w",function(o,d,mk) local pc=cpu.state["PC"].value; local k=string.format("%06x->%06x",pc,o); pcs[k]=(pcs[k] or 0)+1 end)
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f>=N-5 then for k,v in pairs(pcs) do out:write(string.format("%s x%d\n",k,v)) end; out:close(); m:exit() end end)
