-- cyctap.lua: cycles between the fetch of ENTRY and the fetch of EXIT (two ROM addresses), with
-- BP_SHOWN at the exit; one line per call.  Env: OUT, N, ENTRY, EXIT
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "4000")
local E,X=tonumber(os.getenv("ENTRY")),tonumber(os.getenv("EXIT")); local t0; local f=0; local tap1,tap2
local function cyc() local ok,v=pcall(function() return cpu.totalcycles end); if ok and v then return v end; return cpu:total_cycles() end
local function inst()
  if tap1 then tap1:remove() end; if tap2 then tap2:remove() end
  tap1=sp:install_read_tap(E,E+1,"en",function(off,data,mask) if cpu.state["PC"].value==E then t0=cyc() end end)
  tap2=sp:install_read_tap(X,X+1,"ex",function(off,data,mask) if cpu.state["PC"].value==X and t0 then out:write(string.format("%d %d %d\n",f,cyc()-t0,sp:read_u16(0xd0f20e))); t0=nil end end)
end
inst()
emu.register_frame_done(function() f=HARNESS_GAME_FRAME(); inst(); if f>=N-5 then out:close(); m:exit() end end)
