-- efford.lua (HARNESS_TARGET=neo, botsel.lua): where the effects (AUDIT 48's load-shedding types)
-- sit in the sprite pass's order (fz_build: 0x101000.., 0x1040c0.., the x-sorted group 0x1052c0..
-- (taken here in slot order), 0x1058c0..0x1070c0; the first drawn in front), in frames with at least
-- CMIN columns: per effect type, how many effects there are, and how many of them have a non-effect
-- object AFTER them in the order (drawn behind them) whose box overlaps theirs (a store below the
-- ring, behind every ring sprite, would put such an effect behind it: a priority slip), and how many
-- have a non-effect object BEFORE them overlapping (a store above the ring would slip those).
-- Boxes from the pieces' offsets and sizes (16 px tiles).  Env: OUT, F0, F1, CMIN
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local F0=tonumber(os.getenv("F0")); local F1=tonumber(os.getenv("F1"))
local CMIN=tonumber(os.getenv("CMIN") or "150")
local EFF={[0x09]=1,[0x33]=1,[0x60]=1,[0x6c]=1,[0x99]=1,[0x9b]=1,[0x0e]=1,[0x16]=1,[0xa3]=1,[0x20]=1,[0x2f]=1,[0x34]=1,[0x88]=1}
local T={}; local nf=0
local function box(a)
  local tab=sp:read_u32(a+0x1a)&0xfffffe; local n=sp:read_u8(a+4)+1; local c=0
  if tab==0 or tab>=0x80000 then return nil,0 end
  local oy,ox=sp:read_i16(a+0xe),sp:read_i16(a+0x10); local y0,x0,y1,x1=1e9,1e9,-1e9,-1e9
  for i=0,n-1 do local e=tab+14*i; local w0=sp:read_u16(e); local h,w
    if (w0&0x4000)~=0 then h=((sp:read_u8(e+9)&0xe)>>1)+1; w=((sp:read_u8(e+11)&0xe)>>1)+1
    else if w0>=8 then break end; local g=sp:read_u32(e)&0xffffff; if g==0 or g>=0x80000 then break end
      h=((sp:read_u8(g)&0xe)>>1)+1; w=((sp:read_u8(g+1)&0xe)>>1)+1 end
    local y,x=oy+sp:read_i16(e+4),ox+sp:read_i16(e+6); c=c+w
    y0=math.min(y0,y); x0=math.min(x0,x); y1=math.max(y1,y+16*h); x1=math.max(x1,x+16*w) end
  if y0>y1 then return nil,0 end
  return {y0,x0,y1,x1},c
end
local function ov(a,b) return a and b and a[1]<b[3] and b[1]<a[3] and a[2]<b[4] and b[2]<a[4] end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>=F0 and f<F1 then
    local L={}; local c=0
    for a=0x1010c0,0x1070c0-0x60,0x60 do if sp:read_u8(a)>=0x80 then local ty=sp:read_u16(a+0x16); local b,k=box(a); c=c+k
      L[#L+1]={ty=ty,b=b,e=EFF[ty]~=nil} end end
    if c>=CMIN then nf=nf+1
      for i,o in ipairs(L) do if o.e then local k=string.format("%02x",o.ty); T[k]=T[k] or {n=0,after=0,before=0}; local t=T[k]; t.n=t.n+1
        local af,bf=false,false
        for j,p in ipairs(L) do if not p.e and ov(o.b,p.b) then if j>i then af=true else bf=true end end end
        if af then t.after=t.after+1 end; if bf then t.before=t.before+1 end end end end end
  if f>=F1 then out:write(string.format("frames with >= %d columns: %d\n",CMIN,nf))
    local ks={} for k in pairs(T) do ks[#ks+1]=k end; table.sort(ks,function(a,b) return T[a].n>T[b].n end)
    for _,k in ipairs(ks) do local t=T[k]; out:write(string.format("type %s  %.2f a frame; overlapping a non-effect drawn behind it %.0f%%, in front of it %.0f%%\n",k,t.n/nf,100*t.after/t.n,100*t.before/t.n)) end
    out:close(); m:exit() end end)
