-- hcdiff.lua (FZ_DIAG builds): at the HUD cache prologue's "entries differ" exit (the FZ_HX+14
-- counter's write): the piece (A5), its slot (D6), map, tiles, the live entries and the shadow's copy
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "1500")
local HSHD=0x108000; local LUT=0xd06000; local n=0; local tap
local function h(a,k) local w={}; for i=0,k-1 do w[#w+1]=string.format("%04x",sp:read_u16(a+2*i)) end; return table.concat(w," ") end
local function inst() if tap then tap:remove() end
  tap=sp:install_write_tap(0xd0e300+144+14,0xd0e300+144+15,"hx",function(o,d,mk)
    if n>=200 then return end; n=n+1
    local a5=cpu.state["A5"].value; local d6=cpu.state["D6"].value&0xffff
    local map=sp:read_u16(a5+2)&0x3fff; local t=((sp:read_u8(a5+9)>>1)&7)+1
    out:write(string.format("f %d slot %d map %04x tiles %d live %s | shd %s | raw %s\n",HARNESS_GAME_FRAME(),d6,map,t,h(LUT+2*map,8),h(HSHD+96*d6+16,8),h(HSHD+96*d6,8)))
  end) end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%200==0 then out:flush(); inst() end; if f>=N-5 then out:close(); m:exit() end end)
