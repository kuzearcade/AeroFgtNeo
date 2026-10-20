-- flipt.lua: cycle stamps at the sprite flip's steps (out_ov5 addresses), logerror -> error.log
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local dbg=manager.machine.debugger
local P={{0x857a0,"E"},{0x858aa,"F"},{0x85a8e,"S"},{0x85c76,"W"},{0x85c9a,"H"},{0x85ca0,"B"},{0x82386,"R"}}
for _,p in ipairs(P) do
  dbg:command(string.format('bpset %x,1,{logerror "%s %%d\\n",totalcycles; g}',p[1],p[2]))
end
