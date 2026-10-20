dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local last=-1
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME(); if f==last then return end; last=f
  if f>=32740 and f<=32800 then
    local s=string.format("%d fr %08x W %d SH %d ST %d %d %d RDY %d %d %d late %d ordn %d blk %d sdone %d pass %d pon %d prdy %d",
      f, sp:read_u32(0xd0085c), sp:read_i16(0xd00b98), sp:read_i16(0xd00b9c), sp:read_u8(0xd00b68), sp:read_u8(0xd00b69), sp:read_u8(0xd00b6a),
      sp:read_i16(0xd00b70), sp:read_i16(0xd00b72), sp:read_i16(0xd00b74), sp:read_u32(0xd00ba4), sp:read_u8(0xd00fae), sp:read_u8(0xd00fb2),
      sp:read_u8(0xd0f016), sp:read_u16(0xd0f006), sp:read_u8(0xd0f640), sp:read_i16(0xd0f642))
    print(s)
  end
  if f>32800 then manager.machine:exit() end
end)
