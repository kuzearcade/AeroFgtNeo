dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local cpu=manager.machine.devices[":maincpu"]; local sp=cpu.spaces["program"]; local scr=manager.machine.screens[":screen"]
local out=io.open(os.getenv("OUT"),"w"); local G0,G1=tonumber(os.getenv("G0")),tonumber(os.getenv("G1"))
local t; local cg=-1
local function f(o,d,m)
  if cg>=G0 and cg<=G1 then out:write(string.format("  after g=%d line=%d pc=%06x %s<-%04x m=%04x wseq=%d pass=%d\n",cg,scr:vpos(),cpu.state["PC"].value,(o&~1)==0xd0f18c and "SEEN" or "SAME",d,m,sp:read_u16(0xd0f694),sp:read_u16(0xd0f006))) end end
t=sp:install_write_tap(0xd0f18c,0xd0f18f,"hs",f)
emu.register_frame_done(function() if t then t:remove() end; t=sp:install_write_tap(0xd0f18c,0xd0f18f,"hs",f)
  cg=HARNESS_GAME_FRAME and HARNESS_GAME_FRAME() or -1
  if cg>=G0 and cg<=G1 then out:write(string.format("--- frame end g=%d seen=%04x same=%04x wseq=%d\n",cg,sp:read_u16(0xd0f18c),sp:read_u16(0xd0f18e),sp:read_u16(0xd0f694))) end end)
