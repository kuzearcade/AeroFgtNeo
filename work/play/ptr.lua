-- ptr.lua: trace game frames FL_FROM..FL_TO into TR_FIFO (agg), then exit
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local dbg=manager.machine.debugger; local st=0
emu.register_frame_done(function()
  local g=HARNESS_GAME_FRAME()
  if st==0 and g>=tonumber(os.getenv("FL_FROM")) then st=1; dbg:command('trace '..os.getenv("TR_FIFO")..',maincpu,noloop,{tracelog "%d ",totalcycles}') end
  if st==1 and g>=tonumber(os.getenv("FL_TO")) then st=2; dbg:command('trace off,maincpu'); manager.machine:exit() end
end)
