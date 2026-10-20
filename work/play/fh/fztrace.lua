-- fztrace.lua: MAME instruction trace of game frames TR_FROM..TR_TO to TR_FILE (the crash hunt;
-- needs -debug -debugger none).  Env: TR_FROM TR_TO TR_FILE
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local dbg=m.debugger
local A,B=tonumber(os.getenv("TR_FROM")),tonumber(os.getenv("TR_TO")); local st=0
emu.register_frame_done(function()
  local g=HARNESS_GAME_FRAME()
  if st==0 and g>=A then st=1; dbg:command('trace '..os.getenv("TR_FILE")..',maincpu,noloop') end
  if st==1 and g>B then st=2; dbg:command('trace off,maincpu'); m:exit() end
end)
