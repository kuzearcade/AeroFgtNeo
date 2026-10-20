-- lutw2.lua: writes into the HUD's lookup entries from code other than the HUD refresh
-- (0x2a63e-0x2a7a6) and the loader (0x2bbca-0x2bbf0): game frame, pc, entry, value (first 3000)
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "13000")
local LUT=tonumber(os.getenv("LUT")); local lo=LUT+2*0x3fc0; local hi=LUT+2*0x4000-1
local n=0; local tap
local function inst()
  if tap then tap:remove() end
  tap=sp:install_write_tap(lo,hi,"lut",function(o,d,mk)
    local pc=cpu.state["PC"].value
    if (pc>=0x2a63e and pc<0x2a7b0) or (pc>=0x2bbca and pc<0x2bbf0) then return end
    if n<3000 then n=n+1; out:write(string.format("%d %06x %04x %04x\n",HARNESS_GAME_FRAME(),pc,(o-LUT)>>1,d&0xffff)) end
  end)
end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%200==0 then out:flush(); inst() end; if f>=N-5 then out:close(); m:exit() end end)
