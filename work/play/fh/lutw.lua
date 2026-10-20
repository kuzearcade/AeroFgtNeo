-- lutw.lua: writes into the HUD's lookup entries (G_SPRLUT + 2*0x3fc0 .. 0x4000) by PC
-- (a histogram), with the first 40 writes listed (frame, line, pc, offset, value).  Env OUT, N, LUT
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]; local scr=m.screens[":screen"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "13000")
local LUT=tonumber(os.getenv("LUT")); local lo=LUT+2*0x3fc0; local hi=LUT+2*0x4000-1
local hist={}; local nlist=0; local tap
local function inst()
  if tap then tap:remove() end
  tap=sp:install_write_tap(lo,hi,"lut",function(o,d,mk)
    local pc=cpu.state["PC"].value; hist[pc]=(hist[pc] or 0)+1
    if nlist<60 then nlist=nlist+1; out:write(string.format("W %d %d %06x %04x %04x\n",scr:frame_number(),sp:read_u16(0x3c0006)>>7,pc,(o-LUT)>>1,d&0xffff)) end
  end)
end
inst()
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  if f>0 and f%1000==0 then inst() end
  if f>=N-5 then for pc,n in pairs(hist) do out:write(string.format("H %06x %d\n",pc,n)) end; out:close(); m:exit() end
end)
