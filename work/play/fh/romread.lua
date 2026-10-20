-- romread.lua (orig target): do read taps see the game's data reads from its ROM?  Counts reads
-- in LO..HI (env, hex) for N frames; prints the count and a few PCs.  Env: OUT, N, LO, HI
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "600")
local LO=tonumber(os.getenv("LO") or "50000",16); local HI=tonumber(os.getenv("HI") or "5ffff",16)
local n=0; local pcs={}
local tap=sp:install_read_tap(LO,HI,"rr",function(o,d,mk) n=n+1; if n<=20 then pcs[#pcs+1]=string.format("%06x@%06x",o,cpu.state["PC"].value) end end)
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%100==0 then tap:reinstall() end
  if f>=N-5 then out:write(string.format("reads %d: %s\n",n,table.concat(pcs," "))); out:close(); m:exit() end end)
