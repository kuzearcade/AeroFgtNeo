-- ordtap.lua: the order within a frame of the game's builder point (0x2bfaa clr.w
-- 0xff9236, every frame in DIRECT builds), the HAL slot's start (HAL_FRAMES bumped) and
-- the game's writes into the object tables (0xff0000..0xff60c0).  One line per event:
-- B/S, game frame, vpos, [S: busy flag], object-table writes since the last event.
-- Env: OUT, N (frames)
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w")
local N=tonumber(os.getenv("N") or "3000")
local ow=0
local function vpos() return ((sp:read_u16(0x3c0006)>>7)-248)%264 end
local taps={}
local function onobj(o,d,mk) ow=ow+1 end
local function onb(o,d,mk)
  if (o&~1)~=0x10a236 then return end
  out:write(string.format("B %d %d %d pc %06x\n",HARNESS_GAME_FRAME(),vpos(),ow,cpu.state["PC"].value)); ow=0
end
local function ons(o,d,mk)
  if o~=0xd0085c then return end
  out:write(string.format("S %d %d busy %d %d\n",HARNESS_GAME_FRAME(),vpos(),sp:read_u8(0xd00f44),ow)); ow=0
end
local function inst()
  for _,t in ipairs(taps) do t:remove() end
  taps={sp:install_write_tap(0x101000,0x1070bf,"obj",onobj),
        sp:install_write_tap(0x10a236,0x10a237,"bld",onb),
        sp:install_write_tap(0xd0085c,0xd0085f,"slot",ons)}
end
inst()
local f=0
emu.register_frame_done(function() f=f+1; if f%300==0 then inst(); out:flush() end; if f>=N then out:close(); m:exit() end end)
