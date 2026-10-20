-- neopath.lua (Neo build): from frame F0 send 0x02 then SONG through REG_SOUND; for LEN frames log every sound
-- CPU I/O access made from the unpatched ranges (0x0ac0-0x0bd0, 0x15b0-0x1680): port, read/write, value,
-- and the YM2610 ADPCM-B starts that do reach the chip (ports 4/5, reg 0x10 bit 7).  Env: OUT, SONG, LEN
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]; local z=m.devices[":audiocpu"]; local zio=z.spaces["io"]
local out=io.open(os.getenv("OUT"),"w"); local SONG=tonumber(os.getenv("SONG")); local LEN=tonumber(os.getenv("LEN") or "1200")
local F0=tonumber(os.getenv("F0") or "1500"); local n=0; local reg=0; local cnt={}; local abs=0; local spins=0
local taps={}
local function inA(pc) return (pc>=0x0ac0 and pc<0x0bd0) or (pc>=0x15b0 and pc<0x1680) end
local function inst() for _,t in ipairs(taps) do t:remove() end
  taps[1]=zio:install_write_tap(0x0000,0xffff,"w",function(o,d) local pc=z.state["PC"].value; local p=o&0xff
    if p==4 then reg=d&0xff elseif p==5 and reg==0x10 and d&0x80~=0 then abs=abs+1 end
    if n>=F0 and inA(pc) then local k=string.format("W%d",p); cnt[k]=(cnt[k] or 0)+1 end end)
  taps[2]=zio:install_read_tap(0x0000,0xffff,"r",function(o,d) local pc=z.state["PC"].value
    if n>=F0 and inA(pc) and (o&0xff)==0 then spins=spins+1; local k=string.format("R0=%02x",d&0xff); cnt[k]=(cnt[k] or 0)+1 end end) end
inst()
emu.register_frame_done(function() n=n+1; if n%300==0 then inst() end
  if n==F0 then sp:write_u8(0x320000,0x02) end
  if n==F0+20 then sp:write_u8(0x320000,SONG) end
  if n>=F0 and (n-F0)%120==119 then local l={} for k,v in pairs(cnt) do l[#l+1]=k..":"..v end; table.sort(l)
    out:write(string.format("t %5.1fs  ADPCM-B starts at the chip %d  unpatched-code I/O: %s\n",(n-F0)/60,abs,table.concat(l," "))); out:flush(); cnt={}; abs=0 end
  if n>=F0+LEN then out:close(); m:exit() end end)
