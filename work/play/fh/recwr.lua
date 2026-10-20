-- recwr.lua: writers of a record's bytes (ADDR..ADDR+15, env hex) from game frame F0 on: the
-- frame, PC, offset, the word written, a few registers.  Env: OUT, N, ADDR, F0
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "85300")
local A=tonumber(os.getenv("ADDR") or "d0e6a0",16); local F0=tonumber(os.getenv("F0") or "85100")
local taps={}
local function onw(o,d,mk)
  local f=HARNESS_GAME_FRAME(); if f<F0 then return end
  out:write(string.format("gf %d pc %06x off %d data %08x mask %08x a0 %08x a1 %08x a3 %08x d1 %08x d6 %08x\n",f,cpu.state["PC"].value,o-A,d,mk,cpu.state["A0"].value,cpu.state["A1"].value,cpu.state["A3"].value,cpu.state["D1"].value,cpu.state["D6"].value))
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(A,A+15,"rw",onw)} end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%500==0 then inst() end; if f>=N-5 then out:close(); m:exit() end end)
