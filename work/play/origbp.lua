dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local cpu=manager.machine.devices[":maincpu"]; local dbg=manager.machine.debugger
local G0,G1=tonumber(os.getenv("G0")),tonumber(os.getenv("G1")); local on=false; local started=false
emu.register_frame_done(function()
  if not started then started=true; dbg:command("go") end
  local g=HARNESS_GAME_FRAME and HARNESS_GAME_FRAME() or -1
  if g>=G0 and g<=G1 and not on then on=true
    cpu.debug:bpset(0x2bee0,"1",'printf "BUILDER start obj=%x line=%d",b@ff0300,beamy; g')
    cpu.debug:bpset(0x2bf08,"1",'printf "  builder pass1 obj=%x line=%d",b@ff0300,beamy; g')
    cpu.debug:wpset(cpu.spaces["program"],"w",0xff0300,1,"1",'printf "  OBJ write pc=%x val=%x line=%d",pc,wpdata,beamy; g')
    dbg:command("printf \"on g="..g.."\"")
  elseif g>G1 and on then on=false; cpu.debug:bpclear(); cpu.debug:wpclear(); dbg:command("printf \"off g="..g.."\"") end
  if on then dbg:command("printf \"--- frame end g="..g.."\"") end
end)
