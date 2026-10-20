-- per game frame (converted game): HAL late/drop/overrun counters and a lookup-RAM fingerprint (stage)
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local last=-1
local POS={0x0100,0x0800,0x1234,0x2000,0x2800,0x3000,0x3456,0x3800}
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME(); if f==last then return end; last=f
  local h=0; for _,p in ipairs(POS) do h=(h*31+sp:read_u16(0xd06000+2*p))%4294967296 end
  out:write(string.format("%d %d %d %d %d %08x\n",f,sp:read_u32(0xd00ba4),sp:read_u32(0xd00ba0),sp:read_u32(0xd00bf8),sp:read_u32(0xd00be0),h))
end)
