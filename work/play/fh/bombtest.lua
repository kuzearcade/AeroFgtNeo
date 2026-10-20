-- bombtest.lua: from F0 on, P1's object bytes +0x1c..+0x21 whenever they change, and per frame the
-- count of bomb objects (types 0d, 20, 21) when non-zero; exit at N.  Env: OUT, F0, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local F0=tonumber(os.getenv("F0") or "12000"); local N=tonumber(os.getenv("N") or "14000")
local B=0x101000; local PEND=B+0x60c0; local P1=B+0x6c0; local last=""
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>=F0 then
    local t={} for i=0x1c,0x21 do t[#t+1]=string.format("%02x",sp:read_u8(P1+i)) end; local k=table.concat(t," ")
    if k~=last then out:write(string.format("f %d P1+1c.. %s\n",f,k)); last=k end
    local nb=0
    for a=B,PEND-1,0x60 do if sp:read_u8(a)~=0 then local ty=sp:read_u16(a+0x16); if ty==0x0d or ty==0x20 or ty==0x21 then nb=nb+1 end end end
    if nb>0 then out:write(string.format("f %d bomb objects %d\n",f,nb)) end
  end
  if f>=N then out:close(); m:exit() end end)
