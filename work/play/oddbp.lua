dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local cpu=manager.machine.devices[":maincpu"]; local dbg=manager.machine.debugger
local PCS={0xC09E8,0xC0AAE,0xC0BB8,0xC0C96,0xC0DB8,0xC0E74,0xC0F74,0xC1048,0xC16BC,0xC1786,0xC1894,0xC1976,0xC1A9C,0xC1B5C,0xC1C60,0xC1D38,0xC1E54,0xC1F0A,0xC2004,0xC20D2,0xC21E4,0xC2290,0xC2380,0xC2444}
local G0,G1=tonumber(os.getenv("G0")),tonumber(os.getenv("G1")); local on=false; local started=false
emu.register_frame_done(function()
  if not started then started=true; dbg:command("go") end
  local g=HARNESS_GAME_FRAME and HARNESS_GAME_FRAME() or -1
  if g>=G0 and g<=G1 and not on then on=true
    for _,p in ipairs(PCS) do cpu.debug:bpset(p,"(b@(a3+3)&1)!=0",string.format('printf "odd g=%d pc=%%x a0=%%x a3=%%x d4=%%x",pc,a0,a3,d4; g',g)) end
    cpu.debug:bpset(0xC05FE,"1",'printf "obj a0=%x act=%x pass=%x seen=%x wseq=%d",a0,b@a0,w@d0f006,w@d0f18c,w@d0f694; g')
    cpu.debug:bpset(0xC0602,"(sr&1)!=0",'printf "  bail a0=%x",a0; g')
    cpu.debug:bpset(0xC03FC,"1",'printf "WALK START wseq=%d seen=%x obj0=%x fxobj=%x line=%d",w@d0f694,w@d0f18c,b@101300,d@d0f008,beamy; g')
    cpu.debug:wpset(cpu.spaces["program"],"w",0x101300,2,"1",'printf "  OBJ0 write pc=%x val=%x line=%d wseq=%d type16=%x obj360=%x type376=%x",pc,wpdata,beamy,w@d0f694,w@101316,b@101360,w@101376; g')
    dbg:command("printf \"bps set at g="..g.."\"")
  elseif g>G1 and on then on=false; cpu.debug:bpclear(); dbg:command("printf \"bps cleared\"") end
end)
