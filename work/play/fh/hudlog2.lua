-- hudlog2.lua: at each flip, per logic round: FX_HOK and every HUD slot's whole shadow entry
-- (FX_HSHD, 96 bytes: words, column, row, cells, palette, lookup copy, the cells themselves):
-- the cache build and the cache-less one must log the same content.  Env: OUT, N, HSHD
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3000")
local HSHD=tonumber(os.getenv("HSHD")); local FXS=0xd0f000
local tap
local function onflip(o,d,mk)
  local t={}
  for s=0,12 do local a=HSHD+96*s; local w={}; for i=0,23 do w[#w+1]=string.format("%08x",sp:read_u32(a+4*i)) end; t[#t+1]=table.concat(w) end
  out:write(string.format("%d %d %d %s\n",HARNESS_GAME_ROUND(),HARNESS_GAME_FRAME(),sp:read_u8(FXS+21),table.concat(t," ")))
end
local function inst() if tap then tap:remove() end; tap=sp:install_write_tap(0xd00b9c,0xd00b9d,"flip",onflip) end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%200==0 then out:flush(); inst() end; if f>=N-5 then out:close(); m:exit() end end)
