-- chainchk.lua: per screen frame, each shown sprite (the shown set's list entries with a
-- head slot) must have its columns right of the head chained (SCB3 bit 6)
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local vi=nil
for name, idx in pairs(manager.machine.devices[":spritegen"].items) do
  if name:find("m_videoram") then vi=emu.item(idx) end
end
local LT={0xd0e000,0xd0e800,0xd0ec00,0xd0f800,0xd0fc00}
local out=io.open(os.getenv("V_OUT"),"w")
local f=0; local bad=0; local chk=0
emu.register_frame_done(function()
  f=f+1
  local s=sp:read_i16(0xd00b9c); if s<0 or s>2 then return end
  local ss=0x10a280+510*s; local nh=sp:read_u16(ss+10)//2
  local ti=sp:read_u8(0xd0e510+64*s+1); local ta=0x1084e0+132*ti
  if sp:read_u8(ta+130)==0 then return end
  local b=sp:read_u16(0xd0e510+192+2*s); if b>4 then return end
  local n=sp:read_u16(0xd0f180+2*b); local a=LT[b+1]
  local tfin=sp:read_u8(ta+128); local nxt=sp:read_u8(ta+129)
  local nb=0
  for i=0,math.min(n,128)-1 do
    local v=sp:read_u8(ta+i)
    if i>=tfin and v==0xff then v=nxt; nxt=nxt+1 end
    if v<nh then
      local col=sp:read_u16(ss+62+2*v)-0x8200
      local h=vi:read(0x8200+col)
      if (h & 0x3f)~=0 then
        chk=chk+1
        local w=((sp:read_u16(a+8*i+2)>>9)&7)+1
        for k=1,w-1 do
          if (vi:read(0x8200+col+k) & 0x40)==0 then nb=nb+1; if f<800 then local t={} for q=0,w do t[#t+1]=string.format("%04x",vi:read(0x8200+col+q)) end out:write(string.format("  e%d slot%d col%d w%d ent %04x%04x%04x%04x scb3 %s scb4 %04x\n",i,v,col,w,sp:read_u16(a+8*i),sp:read_u16(a+8*i+2),sp:read_u16(a+8*i+4),sp:read_u16(a+8*i+6),table.concat(t," "),vi:read(0x8400+col))) end; break end
        end
      end
    end
  end
  if nb>0 then bad=bad+1; out:write(string.format("%d gf %d broken %d shown %d heads %d dead %d\n",f,sp:read_u16(0xd0085e),nb,s,nh,sp:read_u8(0xd0e510+64*s+3))); out:flush() end
  if f%2000==0 then out:write(string.format("F %d bad %d checked %d\n",f,bad,chk)); out:flush() end
end)
