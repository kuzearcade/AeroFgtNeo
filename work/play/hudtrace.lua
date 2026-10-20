-- fix-layer writes to the 1P HUD (columns 36-39, rows 0-9) and the HUD queue / dl state, in game-frame windows
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local cpu=manager.machine.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w")
local W={}; for c in string.gmatch(os.getenv("WIN"),"%d+") do W[#W+1]=tonumber(c) end
local function inwin() local g=HARNESS_GAME_FRAME and HARNESS_GAME_FRAME() or -1
  for _,c in ipairs(W) do if g>=c-5 and g<=c then return g end end return nil end
local addr,mod=0,1; local sf=0
local t1; local t2; local t3
local function tapf(o,d,m)
  local g0=inwin(); if g0 and os.getenv("ALL") and not (o==0x3c0002 and (addr<0x7000 or addr>=0x7800)) then out:write(string.format("  r sf=%d g=%d pc=%06x o=%x d=%04x m=%x addr=%04x\n",sf,g0,cpu.state["PC"].value,o,d,m,addr)) end
  if o==0x3c0000 then addr=d elseif o==0x3c0004 then mod=d elseif o==0x3c0002 then
    local g=inwin()
    if g and addr>=0x7480 and addr<0x7500 and (addr&31)<10 then
      out:write(string.format("  w sf=%d g=%d pc=%06x a=%04x c%d r%d v=%04x\n",sf,g,cpu.state["PC"].value,addr,(addr-0x7000)>>5,addr&31,d)) end
    addr=(addr+mod)&0xffff end end
t1=sp:install_write_tap(0x3c0000,0x3c0005,"vr",tapf)
emu.register_frame_done(function()
  sf=sf+1; if t1 then t1:remove() end; t1=sp:install_write_tap(0x3c0000,0x3c0005,"vr",tapf)
  if t2 then t2:remove() end
  t2=sp:install_write_tap(0xd00552,0xd00553,"fu",function(o,d,m) local g=inwin(); if g then out:write(string.format("  fixused<-%04x pc=%06x g=%d\n",d,cpu.state["PC"].value,g)) end end)
  local g=inwin(); if not g then return end
  out:write(string.format("LN fixused=%04x hok=%d %d %d %d %d %d\n",sp:read_u16(0xd00552),sp:read_u8(0xd0f015),sp:read_u16(0xd0f180),sp:read_u16(0xd0f182),sp:read_u16(0xd0f184),sp:read_u16(0xd0f186),sp:read_u16(0xd0f188)))
  local qh,qn=sp:read_u16(0xd0f690),sp:read_u16(0xd0f692); local q={}
  for i=0,qn-1 do local a=0x107c00+80*((qh+i)%12); q[#q+1]=string.format("[%d t%d c%d r%d n%d]",sp:read_u16(a),sp:read_u16(a+2),sp:read_u16(a+4),sp:read_u16(a+6),sp:read_u16(a+8)) end
  out:write("Q "..table.concat(q," ").."\n")
  local VR=emu.item(manager.machine.devices[":spritegen"].items["0/m_videoram"]); local n=0
  for c=36,39 do for r=0,9 do if VR:read(0x7000+c*32+r)~=0 then n=n+1 end end end
  out:write(string.format("F sf=%d g=%d hud=%d qh=%d qn=%d wseq=%d lseq=%d,%d,%d,%d,%d upto=%d due=%d fnoh=%d delta=%d pon=%d idn=%d shown=%d sbuf=%d\n",
   sf,g,n,sp:read_u16(0xd0f690),sp:read_u16(0xd0f692),sp:read_u16(0xd0f694),sp:read_u16(0xd0f696),sp:read_u16(0xd0f698),sp:read_u16(0xd0f69a),sp:read_u16(0xd0f69c),sp:read_u16(0xd0f69e),
   sp:read_u16(0xd0f6a0),sp:read_u8(0xd0f6a2),sp:read_u8(0xd0f68f),sp:read_u8(0xd0f620),sp:read_u8(0xd0f640),sp:read_u16(0xd0f6dc),sp:read_i16(0xd00b9c),sp:read_i16(0xd0f660)))
end)
