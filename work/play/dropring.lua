-- per drop event (first per game frame): the writer's PC and the column ring's state
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local cpu=manager.machine.devices[":maincpu"]
local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local last=-1; local cur=-2; local tap; local n=0
local LT={0xd0e000,0xd0e800,0xd0ec00,0xd0f800,0xd0fc00}
local function vis(w0,w1)
  local y=w0&0x1ff; if y>=224 and y+((w0&0xe00)>>5)<=512-16 then return false end
  local x=w1&0x1ff; if x>=320 and x+((w1&0xe00)>>5)<=512-16 then return false end
  return true end
local function need(b)
  if b<0 or b>4 then return -1,-1 end
  local n=sp:read_u16(0xd0f180+2*b); local a=LT[b+1]; local c,e=0,0
  for i=0,n-1 do local w0=sp:read_u16(a+8*i); local w1=sp:read_u16(a+8*i+2)
    if vis(w0,w1) then c=c+((w1>>9)&7)+1; e=e+1 end end
  return c,e end
local VR=emu.item(manager.machine.devices[":spritegen"].items["0/m_videoram"])
local function vram(a0,a1)
  -- columns a1..a0-1 (a0 the start): live (chained to a head of height > 0) and idle
  ZR=""; local live,idle,hh,hz=0,0,0,0; local cur=false
  for n=a1,a0-1 do end
  -- heads are below their chains? no: a column chains to the one BELOW (lower number)
  local h=false
  for n=a1,a0-1 do
    local v=VR:read(0x8200+n)
    if v&0x40==0 then h=(v&0x3f)>0; if h then hh=hh+1 else hz=hz+1; ZR=ZR..n.."(" end end
    if not h and v&0x40~=0 and (n==a0-1 or VR:read(0x8200+n+1)&0x40==0) then ZR=ZR..n..")" end
    if h then live=live+1 else idle=idle+1 end
  end
  return live,idle,hh,hz end
local function snap()
  local f=HARNESS_GAME_FRAME and HARNESS_GAME_FRAME() or -1
  if f==cur then return end; cur=f
  local t={string.format("%d pc=%06x W=%d dl=%d ordn=%d ord=%d,%d,%d shown=%d gnext=%d sps=%d top=%d pt=%d why=%d",
    f,cpu.state["PC"].value,sp:read_i16(0xd00b98),sp:read_u8(0xd0f620),sp:read_u8(0xd00fae),
    sp:read_u8(0xd00faf),sp:read_u8(0xd00fb0),sp:read_u8(0xd00fb1),sp:read_i16(0xd00b9c),
    sp:read_u16(0xd00fac),sp:read_i8(0xd00fde),sp:read_u16(0xd00fe4),sp:read_u16(0xd00fe6),sp:read_u16(0xd0e5e0))}
  for i=0,2 do
    local g=0x10a280+510*i
    t[#t+1]=string.format("s%d:st=%d %d..%d next=%d heads=%d dead=%d",i,sp:read_u8(0xd00b68+i),
      sp:read_u16(0xd00fba+2*i),sp:read_u16(0xd00fcc+2*i),sp:read_u16(g+4),sp:read_u16(g+10)//2,sp:read_u8(0xd0e510+64*i+3))
  end
  local c1,e1=need(sp:read_i16(0xd0f018)); local c2,e2=need(sp:read_i16(0xd0f660))
  t[#t+1]=string.format("needc=%d ne=%d needs=%d nse=%d",c1,e1,c2,e2)
  local sh=sp:read_i16(0xd00b9c)
  if sh>=0 and sh<=2 then local l,i,hh,hz=vram(sp:read_u16(0xd00fba+2*sh),sp:read_u16(0x10a280+510*sh+4))
    t[#t+1]=string.format("live=%d idle=%d hv=%d hz=%d zr=%s",l,i,hh,hz,ZR) end
  out:write(table.concat(t," ").."\n")
end
local function inst()
  tap=sp:install_write_tap(0xd00ba0,0xd00ba3,"drop",function(o,d,m) snap() end)
end
inst()
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME(); if f==last then return end; last=f
  n=n+1; if n%300==0 then if tap then tap:remove() end; inst() end
end)
