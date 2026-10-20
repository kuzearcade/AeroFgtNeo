-- ovstat.lua: neostat.lua + one "O" line per overrun (OVR_DIAG build: site, last passing check)
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local last=-1; local ov=0
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  local o=sp:read_u32(0xd00be0)
  if o~=ov then
    local t={}; for i=0,8 do t[#t+1]=tostring(sp:read_i16(0xd00f26+2*i)) end
    out:write(string.format("O %d %d site %d pc %06x ln %d at %d est %d T %s",f,o-ov,sp:read_u16(0xd00f10),sp:read_u32(0xd00f08),sp:read_u16(0xd00f0c),sp:read_i16(0xd00f0e),sp:read_u16(0xd00f12),table.concat(t,",")..string.format(" S %d,%d,%d,%d\n",sp:read_i16(0xd00f38),sp:read_i16(0xd00f3a),sp:read_i16(0xd00f3c),sp:read_i16(0xd00f3e))))
    ov=o
  end
  if f==last then return end; last=f
  out:write(string.format("%d %d %d %d %d\n",f,sp:read_u32(0xd00ba4),sp:read_u32(0xd00ba0),sp:read_u32(0xd00bf8),o))
end)
