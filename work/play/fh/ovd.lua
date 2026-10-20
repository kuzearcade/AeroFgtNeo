-- ovd.lua (OVR_DIAG=1 builds): at each overrun (HAL_OVERRUN grows), the diagnostics
-- hal/hal.s keeps: lines past the deadline (OVD_OAT), the site, the early stage, and the
-- commit steps' times (OVD_OT: lines past HAL_KDL at OVT 0..8; 0x7fff = not reached),
-- plus BUSY and the game frame.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w")
local N=tonumber(os.getenv("N") or "12000")
local last=0
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  local ov=sp:read_u32(0xd00be0)
  if ov~=last then
    last=ov
    local t={} for i=0,8 do t[#t+1]=string.format("%d",sp:read_i16(0xd00f26+2*i)) end
    out:write(string.format("gf %d over %d lines site %d est %d busy %d steps %s\n",f,sp:read_i16(0xd00f0e),sp:read_u16(0xd00f10)&0xff,sp:read_u16(0xd00f12),sp:read_u8(0xd00f44),table.concat(t," ")))
  end
  if f>=N then out:close(); m:exit() end
end)
