-- ctrs.lua (HARNESS_TARGET=neo): long counters of a check build, every 10000 frames and at the end.
-- Env: OUT, N, ADDRS=<name>:<hex addr>,... (e.g. miss:d00874,frn:d00f30,frbad:d00f34)
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "40000"); local A={}
for n,a in os.getenv("ADDRS"):gmatch("(%w+):(%x+)") do A[#A+1]={n,tonumber(a,16)} end
local function line(f) local t={} for _,x in ipairs(A) do t[#t+1]=string.format("%s %d",x[1],sp:read_u32(x[2])) end
  out:write(string.format("frame %d %s\n",f,table.concat(t," "))); out:flush() end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>0 and f%10000==0 then line(f) end
  if f>=N then line(f); out:close(); m:exit() end end)
