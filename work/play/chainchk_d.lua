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
  if sp:read_u8(0xd0f640)~=0 or sp:read_u8(0xd0f620)~=0 then return end  -- (an update matched: the base's slots permuted until its flip)
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
          if (vi:read(0x8200+col+k) & 0x40)==0 then nb=nb+1
            local tt={} for q=0,w do tt[#tt+1]=string.format("%04x",vi:read(0x8200+col+q)) end
            local o={} for q=0,sp:read_u8(0xd00fae)-1 do local st=sp:read_u8(0xd00faf+q) o[#o+1]=string.format("%d[st%d %d..%d]",st,sp:read_u8(0xd00b68+st),sp:read_u16(0xd00fba+2*st),sp:read_u16(0xd00fcc+2*st)) end
            out:write(string.format("  f%d e%d/%d slot%d/%d col%d w%d scb3 %s sps %d spg %d spj %d ord %s tfin %d tnxt %d buf %d\n",f,i,n,v,nh,col,w,table.concat(tt," "),sp:read_i8(0xd00fde),sp:read_u16(0xd00fe2),sp:read_u16(0xd00fe0),table.concat(o," "),tfin,sp:read_u8(ta+129),b))
            break end
        end
      end
    end
  end
  if nb>0 then bad=bad+1; out:write(string.format("%d gf %d broken %d shown %d heads %d dead %d\n",f,sp:read_u16(0xd0085e),nb,s,nh,sp:read_u8(0xd0e510+64*s+3))); out:flush() end
  if f%2000==0 then out:write(string.format("F %d bad %d checked %d\n",f,bad,chk)); out:flush() end
end)
