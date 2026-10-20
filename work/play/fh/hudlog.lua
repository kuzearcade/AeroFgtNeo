-- hudlog.lua: at each flip, per logic round: FX_HSEEN, FX_HSAME and
-- every HUD slot's shown strip (FX_HSHD: words, column, row, cells, palette): two builds on the
-- by-round harness must log the same.  Env: OUT, N, HSHD (FX_HSHD's address)
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3000")
local HSHD=tonumber(os.getenv("HSHD")); local FXS=0xd0f000
local tap
local function onflip(o,d,mk)
  local t={}
  for s=0,12 do local a=HSHD+96*s; t[#t+1]=string.format("%08x%08x/%04x%04x%04x%04x",sp:read_u32(a),sp:read_u32(a+4),sp:read_u16(a+8),sp:read_u16(a+10),sp:read_u16(a+12),sp:read_u16(a+14)) end
  out:write(string.format("%d %d seen %04x same %04x hcok %04x hok %d fixused %d %s\n",HARNESS_GAME_ROUND(),HARNESS_GAME_FRAME(),sp:read_u16(FXS+0x18c),sp:read_u16(FXS+0x18e),sp:read_u16(0xd0fdf0),sp:read_u8(FXS+21),sp:read_u16(0xd00552),table.concat(t," ")))
end
local function inst() if tap then tap:remove() end; tap=sp:install_write_tap(0xd00b9c,0xd00b9d,"flip",onflip) end   -- (taps get lost: reinstalled)
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%200==0 then out:flush(); inst() end; if f>=N-5 then out:close(); m:exit() end end)
