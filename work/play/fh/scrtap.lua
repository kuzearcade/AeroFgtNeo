-- scrtap.lua: writes of the game's G_DX_SCRY/X (0xff8b4c/4a -> 0x109b4c/4a) with HAL_FRAMES
-- and the PC: how often the sprite scroll offsets change.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3000")
local last={}
local t=sp:install_write_tap(0x109b4a,0x109b4d,"scr",function(o,d,mk)
  if last[o]~=d then last[o]=d; out:write(string.format("gf %d HF %d %06x <- %04x pc %06x\n",HARNESS_GAME_FRAME(),sp:read_u16(0xd0085e),o,d&0xffff,cpu.state["PC"].value)) end
end)
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%500==0 then out:flush() end; if f>=N then out:close(); m:exit() end end)
