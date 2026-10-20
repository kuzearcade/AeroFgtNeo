dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local dbg=manager.machine.debugger; local st=0
emu.register_frame_done(function()
  if st==0 then st=1; dbg:command('trace '..os.getenv("TR_FIFO")..',maincpu,noloop,{tracelog "%d ",totalcycles}') end
end)
