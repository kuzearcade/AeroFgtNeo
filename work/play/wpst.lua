dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local dbg=manager.machine.debugger; local st=0
emu.register_frame_done(function()
  local g=HARNESS_GAME_FRAME()
  if st==0 and g>=32764 then st=1
    dbg:command('wpset d00b68,3,w,1,{logerror "WP g=%d pc=%x addr=%x data=%x fr=%x\\n",w@d0f000,pc,wpaddr,wpdata,w@d0085e; g}')
    dbg:command('wpset d00fae,2,w,1,{logerror "WO pc=%x addr=%x data=%x fr=%x\\n",pc,wpaddr,wpdata,w@d0085e; g}')
  end
  if g>=32770 then manager.machine:exit() end
end)
