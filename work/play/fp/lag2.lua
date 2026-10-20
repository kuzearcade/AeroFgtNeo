-- lag2.lua: per game frame: f, vblank flag at the handler (>=1: a lost logic frame), LATE, SLOWB, TIMN,
-- vpos, BUSY, stage hash, DROP, DROPN, OVERRUN, PALDEFER, FX_WIDLE, FX_UNFIN, CARRY.  Env: OUT
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]; local cpu=m.devices[":maincpu"]
local out=io.open(os.getenv("OUT"),"w")
local POS={0x0100,0x0800,0x1234,0x2000,0x2800,0x3000,0x3456,0x3800}
local tap=sp:install_write_tap(0x109a8e,0x109a8f,"lag_fc",function(off,data,mask)
  local pc=cpu.state["PC"].value
  if pc>=0x9e2 and pc<=0x9ec then
    local h=0; for _,p in ipairs(POS) do h=(h*31+sp:read_u16(0xd06000+2*p))%4294967296 end
    out:write(string.format("%d %d %d %d %d %d %d %08x %d %d %d %d %d %d %d %d\n",HARNESS_GAME_FRAME()+1,sp:read_u8(0x109055),sp:read_u32(0xd00ba4),sp:read_u32(0xd00878),sp:read_u32(0xd0086c),sp:read_u16(0x3c0006)>>7,sp:read_u8(0xd00f44),h,sp:read_u32(0xd00ba0),sp:read_u32(0xd00bf8),sp:read_u32(0xd00be0),sp:read_u32(0xd0042c),sp:read_u32(0xd00f3c),sp:read_u16(0xd0f036),sp:read_u32(0xd00570),sp:read_u32(0xd00f98)))
  end
end)
emu.register_frame_done(function() tap:reinstall() end)
