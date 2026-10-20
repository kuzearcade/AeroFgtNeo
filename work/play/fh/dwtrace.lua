-- dwtrace.lua: when the pass dispatches an entry whose words match W0/W3 (env, hex), dump the
-- record it came from (FZ_REC - 16), FZ_Y/FZ_X, and every active object (address, state, type,
-- y, x, the C table, b43, the B/A table).  FZ_DIAG build.  Env: OUT, N, W0, W3
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3000"); local FZV=0xd0e300
local W0=tonumber(os.getenv("W0") or "aa",16); local W3=tonumber(os.getenv("W3") or "16",16)
local hits=0; local taps={}
local function ondw(o,d,mk)
  if o~=FZV+108+6 then return end
  if sp:read_u16(FZV+108)~=W0 or (d&0xffff)~=W3 then return end
  hits=hits+1; if hits>3 then return end
  local r=sp:read_u32(FZV)-16
  out:write(string.format("HIT gf %d words %04x %04x %04x %04x record %08x: %s  FZ_Y %d FZ_X %d\n",HARNESS_GAME_FRAME(),sp:read_u16(FZV+108),sp:read_u16(FZV+110),sp:read_u16(FZV+112),d&0xffff,r,
    sp:read_range(r,r+15,8):gsub(".",function(c) return string.format("%02x",c:byte()) end),sp:read_i16(FZV+32),sp:read_i16(FZV+34)))
  for a=0x101000,0x1070c0-1,0x60 do local st=sp:read_u8(a)
    if st~=0 then out:write(string.format("  obj %06x st %02x type %04x y %d x %d C %08x b4 %d b43 %02x BA %08x\n",a,st,sp:read_u16(a+0x16),sp:read_i16(a+0xe),sp:read_i16(a+0x10),sp:read_u32(a+0x1a),sp:read_u8(a+4),sp:read_u8(a+0x43),sp:read_u32(a+0x44))) end end
  out:flush()
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(FZV+108,FZV+115,"dw",ondw)} end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%300==0 then inst() end; if f>=N-5 then out:close(); m:exit() end end)
