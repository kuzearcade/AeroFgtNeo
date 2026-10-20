dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local cpu=manager.machine.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local cg=-1; local n=0; local t
local function f(o,d,m) n=n+1; if cg>=tonumber(os.getenv("G0")) and cg<=tonumber(os.getenv("G1")) then out:write(string.format("  cg=%d pc=%06x o=%x d=%04x m=%04x\n",cg,cpu.state["PC"].value,o,d,m)) end end
emu.register_frame_done(function()
  if t then t:remove() end; t=sp:install_write_tap(0xd0f18c,0xd0f18f,"hs",f)
  cg=HARNESS_GAME_FRAME and HARNESS_GAME_FRAME() or -1
  if cg%500==0 or (cg>=tonumber(os.getenv("G0")) and cg<=tonumber(os.getenv("G1"))) then out:write(string.format("-- g=%d hits=%d\n",cg,n)); out:flush() end end)
