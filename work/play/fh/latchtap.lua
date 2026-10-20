-- latchtap.lua (Neo build): every 68000 write to REG_SOUND (0x320000) and every sound CPU read of port $00,
-- with the machine time in microseconds; the stage id; the port G mirror byte (0xd00ead) at each write.
-- Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local z=m.devices[":audiocpu"]; local zio=z.spaces["io"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "200000")
local function us() return m.time:as_double()*1e6 end
local t1,t2
local function inst()
  if t1 then t1:remove() end; if t2 then t2:remove() end
  t1=sp:install_write_tap(0x320000,0x320001,"snd",function(o,d,mk) if mk&0xff00~=0 or o==0x320000 then
    local v=(o==0x320000) and ((mk&0xff00)~=0 and (d>>8)&0xff or d&0xff) or d&0xff
    out:write(string.format("W %d %.1f %02x pc %06x g %02x\n",HARNESS_GAME_FRAME(),us(),v,cpu.state["PC"].value,sp:read_u8(0xd00ead))) end end)
  t2=zio:install_read_tap(0x0000,0xffff,"zr",function(o,d,mk) if o&0xff==0 then
    out:write(string.format("R %d %.1f %02x zpc %04x\n",HARNESS_GAME_FRAME(),us(),d&0xff,z.state["PC"].value)) end end)
end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%300==0 then inst() end
  if f>=N-5 then out:close(); m:exit() end end)
