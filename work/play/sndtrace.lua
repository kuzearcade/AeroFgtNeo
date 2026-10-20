dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local cpu=manager.machine.devices[":maincpu"]; local sp=cpu.spaces["program"]
local z=manager.machine.devices[":audiocpu"]
local f=0; local taps={}; local n=0
local function on(o,d,m)
  if n>80 then return end; n=n+1
  print(string.format("f%d w %06x %04x m %04x pc68 %06x z80pc %04x", f, o, d, m, cpu.state["PC"].value, z.state["PC"].value))
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0x320000,0x320001,"snd",on),sp:install_write_tap(0x3a0000,0x3a001f,"sys",on)} end
inst()
emu.register_frame_done(function() f=f+1; inst() end)
