-- romtap.lua: the ORIGINAL arcade (HARNESS_TARGET=orig): a read tap on the ROM range
-- RT_LO..RT_HI (env, hex; default 7b46e..7ffff - the free tail hal/fz.s FZ_TPL_AT takes),
-- reinstalled every 500 frames (taps get lost); the hits (frame, pc, address) the first 50
-- and a count, to OUT; N frames.
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "40000")
local lo=tonumber(os.getenv("RT_LO") or "7b46e",16); local hi=tonumber(os.getenv("RT_HI") or "7ffff",16)
local hits=0; local late=0; local lastf=-1; local tap; local frame=0
local function inst()
  if tap then tap:remove() end
  tap=sp:install_read_tap(lo,hi,"romtap",function(off,data,mask)
    hits=hits+1; if frame>=300 then late=late+1; lastf=frame end
    if hits<=50 then out:write(string.format("hit gf %d pc %x addr %x data %x\n",frame,cpu.state["PC"].value,off,data)); out:flush() end
  end)
end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); frame=f
  if f%500==0 then inst() end
  if f%10000==0 or f>=N-5 then out:write(string.format("gf %d hits %d late %d last %d\n",f,hits,late,lastf)); out:flush() end
  if f>=N-5 then out:close(); m:exit() end end)
