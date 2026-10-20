-- owntap.lua: writes into the stable pool's state (BP_KEY d0f21a.., BP_SLOT d0f2b0.., BP_OWNR d0f3b0.., BP_SEENM d0f3d0) between frames F0 and F1: pc, address, data
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3400"); local F0,F1=tonumber(os.getenv("F0") or "3300"),tonumber(os.getenv("F1") or "3306")
local f=0; local t1
local function inst()
  if t1 then t1:remove() end
  t1=sp:install_write_tap(0xd0f200,0xd0f3df,"own",function(off,data,mask) if f>=F0 and f<=F1 then out:write(string.format("f %d pc %06x at %06x %04x m %04x\n",f,cpu.state["PC"].value,off,data,mask)) end end)
end
inst()
emu.register_frame_done(function() f=HARNESS_GAME_FRAME(); inst(); out:write(string.format("-- frame %d\n",f)); out:flush()
  if f>=N-5 then out:close(); m:exit() end end)
