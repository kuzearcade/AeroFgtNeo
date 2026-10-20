-- sndpc.lua (arcade): play SONG; every sound CPU I/O access made with PC in 0x0a00-0x0c00 or 0x1500-0x1700, by
-- exact PC, port and direction, for LEN frames.  Env: OUT, SONG, LEN
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]; local z=m.devices[":audiocpu"]; local zio=z.spaces["io"]
local out=io.open(os.getenv("OUT"),"w"); local SONG=tonumber(os.getenv("SONG")); local LEN=tonumber(os.getenv("LEN") or "1800")
local n=0; local F0=600; local cnt={}; local taps={}
local function rng(pc) return (pc>=0x0a00 and pc<0x0c00) or (pc>=0x1500 and pc<0x1700) end
local function inst() for _,t in ipairs(taps) do t:remove() end
  taps[1]=zio:install_write_tap(0x00,0xff,"w",function(o,d) local pc=z.state["PC"].value; if n>=F0 and rng(pc) then local k=string.format("%04x W%d",pc,o&0xff); cnt[k]=(cnt[k] or 0)+1 end end)
  taps[2]=zio:install_read_tap(0x00,0xff,"r",function(o,d) local pc=z.state["PC"].value; if n>=F0 and rng(pc) then local k=string.format("%04x R%d",pc,o&0xff); cnt[k]=(cnt[k] or 0)+1 end end) end
inst()
emu.register_frame_done(function() n=n+1; if n%300==0 then inst() end
  if n==F0 then sp:write_u8(0xffffc1,0x02) end; if n==F0+20 then sp:write_u8(0xffffc1,SONG) end
  if n>=F0+LEN then local l={} for k,v in pairs(cnt) do l[#l+1]=string.format("%s x%d",k,v) end; table.sort(l); out:write(table.concat(l,"\n").."\n"); out:close(); m:exit() end end)
