-- cuttap.lua: per game frame F0..F1: writes to TM_ALL (0xd0e500-1), TM_DIRTY (0xd0e400-0xd0e4ff),
-- HAL_BG_HID (0xd00556-7), G_GFXBANK? no; the tilemap clear 0x1254/0x125e hit counts via PC taps are
-- not available: write taps only.  Also HAL_BG_HID and HAL_BG_POS values at frame end.  Env: OUT, N, F0, F1
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "2500")
local F0=tonumber(os.getenv("F0") or "2380"); local F1=tonumber(os.getenv("F1") or "2420")
local c={all=0,dirty=0,hid=0,vram0=0,vram1=0}; local taps={}
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={}
  taps[#taps+1]=sp:install_write_tap(0xd0e500,0xd0e501,"all",function() c.all=c.all+1 end)
  taps[#taps+1]=sp:install_write_tap(0xd0e400,0xd0e4ff,"dirty",function() c.dirty=c.dirty+1 end)
  taps[#taps+1]=sp:install_write_tap(0xd00556,0xd00557,"hid",function() c.hid=c.hid+1 end)
  taps[#taps+1]=sp:install_write_tap(0xd02000,0xd03fff,"v0",function() c.vram0=c.vram0+1 end)
  taps[#taps+1]=sp:install_write_tap(0xd04000,0xd05fff,"v1",function() c.vram1=c.vram1+1 end)
end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); inst()
  if f>=F0 and f<=F1 then
    out:write(string.format("f %d all %d dirty %d hid %d v0 %d v1 %d | HID %04x POS %04x pend0 %d\n",f,c.all,c.dirty,c.hid,c.vram0,c.vram1,sp:read_u16(0xd00556),sp:read_u16(0xd0054c),0)) out:flush() end
  c={all=0,dirty=0,hid=0,vram0=0,vram1=0}
  if f>=N-5 then out:close(); m:exit() end end)
