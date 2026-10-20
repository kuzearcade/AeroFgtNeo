-- pathtap.lua: sound CPU I/O accesses made from the code the Neo port leaves unpatched (0x0ad7-0x0bcb: the
-- channel-0x0b ADPCM-B notes; 0x15c8-0x1674: commands 0x0a/0x0b), with the game frame, port, value and stage;
-- plus the last 8 sound commands before each first hit.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local z=m.devices[":audiocpu"]; local zio=z.spaces["io"]
local sp=m.devices[":maincpu"].spaces["program"]
local neo=os.getenv("HARNESS_TARGET")=="neo"; local C=neo and 0x10d000 or 0xffc000
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "200000")
local hist={}; local lastf=-100; local taps={}
local function rng(pc) return (pc>=0x0ad7 and pc<=0x0bcb) or (pc>=0x15c8 and pc<=0x1674) end
local function hit(kind,o,d)
  local f=HARNESS_GAME_FRAME(); local idx=sp:read_u16(C+0x110); local sid=255; if idx>=1 and idx<=7 then sid=sp:read_u8(C+0x100+idx-1) end
  if f-lastf>60 then out:write(string.format("HIT frame %d stage %d/%d pc %04x %s port %02x val %02x  recent cmds %s\n",f,idx,sid,z.state["PC"].value,kind,o&0xff,d&0xff,table.concat(hist," "))) end
  lastf=f end
local function inst() for _,t in ipairs(taps) do t:remove() end
  taps[1]=zio:install_write_tap(0x0000,neo and 0xffff or 0xff,"w",function(o,d) if rng(z.state["PC"].value) then hit("W",o,d) end end)
  taps[2]=zio:install_read_tap(0x0000,neo and 0xffff or 0xff,"r",function(o,d) local p=o&0xff
    if (not neo and p==0x0c) or (neo and p==0x00 and z.state["PC"].value<0x7800 and not rng(z.state["PC"].value)) then hist[#hist+1]=string.format("%02x",d&0xff); if #hist>8 then table.remove(hist,1) end end
    if rng(z.state["PC"].value) then hit("R",o,d) end end) end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%300==0 then inst() end
  if f>=N-5 then out:close(); m:exit() end end)
