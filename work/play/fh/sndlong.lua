-- sndlong.lua (arcade aerofgt): at frame 600 send 0x02 then CMD; log per 60 frames the FM key-ons, banked
-- reads and the sound CPU reads at 0xf800-0xffff (address range) until frame 600+LEN.  Env: OUT, CMD, LEN
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]; local z=m.devices[":audiocpu"]
local zp=z.spaces["program"]; local zio=z.spaces["io"]
local out=io.open(os.getenv("OUT"),"w"); local CMD=tonumber(os.getenv("CMD")); local LEN=tonumber(os.getenv("LEN") or "6000")
local n=0; local reg={[0]=0,[1]=0}; local kon,rd,tail,lo,hi,game=0,0,0,0xffff,0,{}
local taps={}
local function inst() for _,t in ipairs(taps) do t:remove() end
  taps[1]=zp:install_read_tap(0x8000,0xffff,"rd",function(o) rd=rd+1; if o>=0xf800 then tail=tail+1; if o<lo then lo=o end; if o>hi then hi=o end end end)
  taps[2]=zio:install_write_tap(0x00,0x01,"ym",function(o,d) d=d&0xff; if o==0 then reg[0]=d elseif reg[0]==0x28 and d&0xf0~=0 then kon=kon+1 end end)
  taps[3]=sp:install_write_tap(0xffffc0,0xffffc1,"latch",function(o,d) if not mine then game[#game+1]=string.format("%02x",d&0xff) end end) end
mine=false; inst()
emu.register_frame_done(function() n=n+1; if n%300==0 then inst() end
  if n==600 then mine=true; sp:write_u8(0xffffc1,0x02); mine=false end
  if n==620 then mine=true; sp:write_u8(0xffffc1,CMD); mine=false end
  if n>620 and n%60==0 then out:write(string.format("t %5.1fs kon %3d banked %5d tail %d %s game %s\n",(n-620)/60,kon,rd,tail,tail>0 and string.format("%04x-%04x",lo,hi) or "",table.concat(game,","))); out:flush()
    kon,rd,tail,lo,hi,game=0,0,0,0xffff,0,{} end
  if n>=600+LEN then out:close(); m:exit() end end)
