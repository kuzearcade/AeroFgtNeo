-- hudlog3.lua: at each flip: game frame, FX_HOK, FZ_LUTGEN, FZ_HCOK, FX_HSEEN, FX_HSAME, the live
-- lookup entries of the 1P score strip (0x3fc0-0x3fc7), slot 0's shadow (cells count, lookup copy)
-- and slot 0's cache key.  Env: OUT, N, HSHD, LUT
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3000")
local HSHD=tonumber(os.getenv("HSHD")); local LUT=tonumber(os.getenv("LUT")); local FXS=0xd0f000
local tap
local function h(a,n) local w={}; for i=0,n-1 do w[#w+1]=string.format("%04x",sp:read_u16(a+2*i)) end; return table.concat(w) end
local function onflip(o,d,mk)
  out:write(string.format("%d %d %d %04x %04x %04x live %s shd %04x %s key %s\n",HARNESS_GAME_FRAME(),sp:read_u8(FXS+21),sp:read_u16(0xd0fdf2),sp:read_u16(0xd0fdf0),sp:read_u16(FXS+0x18c),sp:read_u16(FXS+0x18e),h(LUT+2*0x3fc0,8),sp:read_u16(HSHD+12),h(HSHD+16,8),h(0xd0fd20,8)))
end
local function inst() if tap then tap:remove() end; tap=sp:install_write_tap(0xd00b9c,0xd00b9d,"flip",onflip) end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%200==0 then out:flush(); inst() end; if f>=N-5 then out:close(); m:exit() end end)
