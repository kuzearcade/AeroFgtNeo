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
          if (vi:read(0x8200+col+k) & 0x40)==0 then nb=nb+1; break end
        end
      end
    end
  end
  if f>=6617 and f<=6621 then
    out:write(string.format("FRAME %d pon %d delta %d dlron %d deltan %d shown %d nh %d tfin %d tnxt %d buf %d n %d dead %d\n",f,sp:read_u8(0xd0f640),sp:read_u8(0xd0f620),sp:read_u8(0xd0f667),0,s,nh,tfin,sp:read_u8(ta+129),b,n,sp:read_u8(0xd0e510+64*s+3)))
    local nx=sp:read_u8(ta+129)
    for i=0,n-1 do local v=sp:read_u8(ta+i); local vv=v; if i>=tfin and v==0xff then vv=nx; nx=nx+1 end
      local col=-1; if vv<nh then col=sp:read_u16(ss+62+2*vv)-0x8200 end
      out:write(string.format("  e%d t%02x slot%d col%d w%d ent %04x%04x%04x%04x\n",i,v,vv,col,((sp:read_u16(a+8*i+2)>>9)&7)+1,sp:read_u16(a+8*i),sp:read_u16(a+8*i+2),sp:read_u16(a+8*i+4),sp:read_u16(a+8*i+6))) end
    do local ks={} for k=0,23 do ks[#ks+1]=string.format("%d",sp:read_u8(0xd0e600+k)) end
      local ti2=sp:read_u16(0xd0f632); local ct={} for k=0,23 do ct[#ct+1]=string.format("%02x",sp:read_u8(0x1084e0+132*ti2+k)) end
      local bs={} for k=0,23 do bs[#bs+1]=string.format("%02x",sp:read_u8(0x108774+k)) end
      out:write(string.format("  KS %s\n  CT(tab %d) %s\n  BSL %s\n  HASH %s NEXT %s A2 %06x A3 %06x CL %06x\n  H %d PERM %d OOO %d ID %d HOLE %d R %d why %d\n",table.concat(ks,","),ti2,table.concat(ct,","),table.concat(bs,","),(function() local h={} for k=0,31 do h[#h+1]=string.format("%02x",sp:read_u8(0xd0e6b2+k)) end return table.concat(h,"") end)(),(function() local h={} for k=0,23 do h[#h+1]=string.format("%02x",sp:read_u8(0xd0e7a0+k)) end return table.concat(h,",") end)(),sp:read_u32(0xd0f676),sp:read_u32(0xd0f67a),sp:read_u32(0xd0f000+0x1c),sp:read_u16(0xd0f672),sp:read_u8(0xd0f6d6),sp:read_u8(0xd0f6e2),sp:read_u8(0xd0f6b6),sp:read_u8(0xd0f6e0),sp:read_u16(0xd0f6a4),sp:read_u16(0xd0e5e0))) end
    local hh={} for k=0,nh-1 do hh[#hh+1]=string.format("%d",sp:read_u16(ss+62+2*k)-0x8200) end
    out:write("  heads "..table.concat(hh,",").."\n")
    local cc={} for c=320,381 do cc[#cc+1]=string.format("%d:%04x",c,vi:read(0x8200+c)) end
    out:write("  scb3 "..table.concat(cc," ").."\n")
  end
  if sp:read_u8(0xd0f640)~=0 or sp:read_u8(0xd0f620)~=0 then return end  -- (an update matched: the base's slots permuted until its flip)
  if nb>0 then bad=bad+1; out:write(string.format("%d gf %d broken %d shown %d heads %d dead %d\n",f,sp:read_u16(0xd0085e),nb,s,nh,sp:read_u8(0xd0e510+64*s+3))); out:flush() end
  if f%2000==0 then out:write(string.format("F %d bad %d checked %d\n",f,bad,chk)); out:flush() end
end)
