-- sndtest.lua (arcade aerofgt): a sound test - from frame F0, every STEP frames: command 0x02 (stop), then
-- command X (FIRST..LAST) via the latch at 0xffffc1; per command: FM key-ons, ADPCM-A/B starts, the banks
-- read, the sound CPU reads at 0xf800-0xffff (the bank tail the Neo Geo cannot map), and any command the
-- game itself sent meanwhile.  Env: OUT
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]; local z=m.devices[":audiocpu"]
local zp=z.spaces["program"]; local zio=z.spaces["io"]
local out=io.open(os.getenv("OUT"),"w")
local F0,STEP,FIRST,LAST=600,1200,tonumber(os.getenv("FIRST") or "1"),tonumber(os.getenv("LAST") or "63")
local n=0; local cur=nil; local bank=-1; local reg={[0]=0,[1]=0}
local c
local function reset() c={kon=0,aa=0,ab=0,tail=0,tlo=0xffff,thi=0,banks={},game={}} end
reset()
local taps={}
local function inst()
  for _,t in ipairs(taps) do t:remove() end; taps={}
  taps[1]=zp:install_read_tap(0x8000,0xffff,"rd",function(o,d,mk) c.banks[bank]=(c.banks[bank] or 0)+1
    if o>=0xf800 then c.tail=c.tail+1; if o<c.tlo then c.tlo=o end; if o>c.thi then c.thi=o end end end)
  taps[2]=zio:install_write_tap(0x00,0x04,"io",function(o,d,mk) d=d&0xff
    if o==4 then bank=d&3; return end
    local side=o>>1
    if o&1==0 then reg[side]=d; return end
    local r=reg[side]
    if side==0 and r==0x28 and d&0xf0~=0 then c.kon=c.kon+1
    elseif side==1 and r==0 and d&0x80==0 and d~=0 then c.aa=c.aa+1
    elseif side==0 and r==0x10 and d&0x80~=0 then c.ab=c.ab+1 end end)
  taps[3]=sp:install_write_tap(0xffffc0,0xffffc1,"latch",function(o,d,mk) if not mine then c.game[#c.game+1]=string.format("%02x",d&0xff) end end)
end
mine=false
inst()
local function flush()
  local b={} for k,v in pairs(c.banks) do b[#b+1]=string.format("%d:%d",k,v) end; table.sort(b)
  out:write(string.format("cmd %02x kon %d aa %d ab %d banks %s tail %d %s game %s\n",cur,c.kon,c.aa,c.ab,table.concat(b,","),c.tail,
    c.tail>0 and string.format("%04x-%04x",c.tlo,c.thi) or "-",table.concat(c.game,","))); out:flush()
end
emu.register_frame_done(function() n=n+1
  if n%300==0 then inst() end
  if n>=F0 and (n-F0)%STEP==0 then
    if cur then flush() end
    local x=FIRST+(n-F0)//STEP
    if x>LAST then out:close(); m:exit(); return end
    reset(); cur=x
    mine=true; sp:write_u8(0xffffc1,0x02); mine=false
  elseif cur and (n-F0)%STEP==20 then
    mine=true; sp:write_u8(0xffffc1,cur); mine=false
  end
end)
