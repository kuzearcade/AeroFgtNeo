dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local cpu=manager.machine.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("V_OUT"),"w"); local f=0; local taps={}
local F0=tonumber(os.getenv("F0")); local F1=tonumber(os.getenv("F1"))
local function on(o,d,m) if f>=F0 and f<=F1 then out:write(string.format("f%d w %06x = %d pc %06x shon %d\n",f,o,d,cpu.state["PC"].value,sp:read_u8(0xd0f6f2))) out:flush() end end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd00fac,0xd00fad,"g",on),sp:install_write_tap(0xd00fce,0xd00fcf,"e",on)} end
inst()
emu.register_frame_done(function() f=f+1; if f%300==0 or f==F0-1 then inst() end end)
